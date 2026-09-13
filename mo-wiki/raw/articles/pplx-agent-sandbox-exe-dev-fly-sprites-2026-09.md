---
source_url: https://www.perplexity.ai/computer/tasks/d15bef19-24a1-4713-88ce-b0fb5ac3e303
ingested: 2026-09-13
sha256: 524388404ba83bdbcfce03e1d6f00fecedc35492fa8e915106c0ba4205524ca5
---
# Building Your Own "Orbs": Ampcode's Model, and How to Replicate It on Exe.dev or Fly.io

## TL;DR

Ampcode's "orbs" are just full Linux VMs (Debian 12) that Amp's control plane spins up per coding session, pre-loads with a cloned repo + dev tools + Postgres/Redis, hands to the agent, snapshots for fast reuse, and pauses to zero cost when idle. Amp hasn't published its exact virtualization stack, but the strongest evidence points to Firecracker-style microVMs, possibly built on E2B's infrastructure ([mer.vin analysis](https://mer.vin/2026/08/agent-harnesses-vs-orbs-why-remote-sandboxes-beat-local-agent-loops/)). The good news for you: **you don't need to guess at their exact stack to get the same experience.** Your Exe.dev subscription is already very close to orb-shaped (SSH/HTTPS API, ~2-second boot from container images, real Docker/Postgres support, automatic HTTPS per VM, scoped agent tokens) — you can build a thin control layer on top of it in an afternoon. If you want faster boots, snapshot/checkpoint semantics, and more infra control, Fly.io has now productized this exact use case as **Sprites** (its own product at [sprites.dev](https://fly.io/sprites/)) — full Linux computers with automatic disk-level checkpointing, a real HTTPS URL per sandbox, and "Connectors" for secretless access to GitHub/Slack/OpenRouter/any API, purpose-built for AI-agent sandboxes.

---

## 1. What Ampcode's orbs actually are

An orb is Amp's name for **"a machine in which an agent can run without supervision"** ([Amp manual](https://ampcode.com/manual/orbs)). Concretely:

- Every new Amp thread (conversation) started "in orb mode" gets its own dedicated **Debian 12 VM** with your repo already cloned, plugins installed, and dev tools pre-loaded (git, GitHub CLI, PostgreSQL, Redis, Node, Python, a headless browser, etc.) — no manual setup ([Amp — What Are Orbs?](https://ampcode.com/what-are-orbs), [Amp docs — Customizing Orbs](https://ampcode.app/docs/orbs/customizing)).
- Orbs come in six billed sizes, from `a1.tiny` (1 vCPU/2GB, $0.08/hr) to `a1.3xlarge` (16 vCPU/44GB, $2.13/hr), and **auto-pause after 5 minutes idle** (paused = $0, indefinitely) ([Amp docs — Sizes & Costs](https://ampcode.com/docs/orbs/sizes-and-costs)).
- Two lifecycle hook scripts drive customization: `.agents/setup` (runs once, installs deps/seeds databases, 20-min timeout) and `.agents/resume` (runs on every wake, ≤10s) — this is literally how the agent "spins up any infrastructure it needs," including Postgres ([Amp docs — Customizing Orbs](https://ampcode.app/docs/orbs/customizing)).
- After first setup, Amp **snapshots** the VM and reuses that snapshot for up to 72 hours so future threads on the same project skip the setup cost — this is their main trick for fast cold starts ([Amp docs — Customizing Orbs](https://ampcode.app/docs/orbs/customizing)).
- Long-running services (databases, dev servers) must be registered as `systemd` units or in `.amp/services.yaml` — anything left as a bare background process gets killed when setup exits ([Amp docs — Customizing Orbs](https://ampcode.app/docs/orbs/customizing)).
- **"Portals"** expose any HTTP service inside the orb via a public HTTPS URL with live reload, so you can preview the agent's running app from any device without VPN/port-forwarding ([Amp news — Portals](https://ampcode.com/news/portals)).
- Secrets use short-lived **OIDC workload identity** tokens minted inside the orb (`amp orb id-token`), rather than static credentials baked into the VM — this is how they let orbs touch GCP/AWS/Tailscale safely ([Amp news — Secrets of the Orb](https://ampcode.com/news/secrets-of-the-orb)).
- **Infrastructure**: Amp hasn't named its stack in an engineering post. Confirmed facts: Debian 12 guest OS, snapshot-based fast restarts, and at least a GCP dependency (their own workload-identity docs reference GCP directly) ([Amp news — Secrets of the Orb](https://ampcode.com/news/secrets-of-the-orb)). The most specific (but unconfirmed, third-party) claim is that orb portal preview URLs resolve on `.e2b.app` domains alongside Amp's own `.onamp.dev`, suggesting the hosting layer sits on top of **E2B's Firecracker-microVM sandbox infrastructure** rather than a fully custom system ([mer.vin — Agent Harnesses vs Orbs](https://mer.vin/2026/08/agent-harnesses-vs-orbs-why-remote-sandboxes-beat-local-agent-loops/)). This is plausible but not something Amp has confirmed publicly.

The important takeaway for you: **the "magic" is not exotic virtualization — it's the orchestration layer** (fast provisioning + lifecycle scripts + snapshot reuse + pause-to-zero + tunneled preview URLs + short-lived credentials). That orchestration pattern is copyable on nearly any VM provider with a scriptable API, including Exe.dev.

---

## 2. Exe.dev is a genuinely good fit for this

Exe.dev (built by Bold Software — David Crawshaw, ex-Tailscale CTO, and Josh Bleecher Snyder) is architecturally closer to "orb infrastructure" than a generic VPS host:

- **Real KVM VMs, but boot from container images in ~2 seconds** (Cloud Hypervisor under the hood) rather than a traditional disk-image boot — this is most of Amp's "fast start" advantage, minus formal snapshotting ([How exe.dev works](https://exe.dev/docs/faq/how-exedev-works)).
- **The API is SSH** — `ssh exe.dev new --json`, `rm`, `resize`, `ls`, `cp` (clone), all scriptable with `--json` output, plus a thin HTTPS wrapper (`POST https://exe.dev/exec`) for environments that can't shell out ([Exe.dev API docs](https://exe.dev/docs/api), [AI Sandboxes page](https://exe.dev/sandbox)).
- **Docker/Postgres just work.** Exe.dev has a documented example running the Cal.diy app with Docker Compose + a Postgres container on a single VM ([Cal.diy use case](https://exe.dev/docs/use-case-cal-diy)) — exactly the "spin up whatever infra it needs" pattern you're describing.
- **`--setup-script` on `new`** is a direct equivalent of Amp's `.agents/setup` — first-boot provisioning (clone repo, install deps, start Postgres) ([Customizing VMs docs](https://exe.dev/docs/customization)).
- **Automatic HTTPS per VM** (`https://<vmname>.exe.xyz`) is Exe.dev's version of Amp's "Portals" — no manual proxy/tunnel setup needed to preview a running app ([How exe.dev works](https://exe.dev/docs/faq/how-exedev-works)).
- **Scoped, expiring API tokens** built specifically for agent automation: `ssh-key generate-api-key --cmds='new,rm,ssh-key add,ssh-key remove,ssh' --exp=1d` — this is your equivalent of Amp's OIDC-scoped orb credentials ([AI Sandboxes page](https://exe.dev/sandbox)).
- **A secrets-proxy "Integrations" system** — an HTTP proxy inside the VM attaches auth headers to calls to Stripe/OpenAI/Anthropic/GitHub without the agent ever seeing the raw key. This maps directly to Amp's "never store a static credential in the VM" design ([AI Sandboxes page](https://exe.dev/sandbox)).
- **Pooled pricing already fits your workflow**: on the Personal plan ($20/mo) you get 50 VMs sharing a 2×8 CPU/RAM baseline, 100GB disk, 200GB transfer — you're paying for the pool, not per VM, so spinning up (and tearing down) many project VMs is exactly the intended usage pattern ([Exe.dev pricing](https://exe.dev/pricing)).

**Gaps versus Amp orbs today:**
- No formal VM **snapshot/golden-image** feature yet — there's a `cp` (clone) command, but the team was still building a dedicated sub-second "clone from base image" feature as of the most recent public discussion, so you won't get Amp's "reuse the post-setup snapshot for 72 hours" trick out of the box ([Hacker News thread](https://news.ycombinator.com/item?id=46405579)). Workaround: build your own "golden" VM once (repo cloned, deps installed, Postgres configured), then use `cp` to fork new working VMs from it instead of re-running setup every time.
- No auto-pause/auto-resume/idle-billing model like orbs — Exe.dev bills by pooled resource usage, not per-VM active/paused state, so you'd handle "pause when idle" yourself (e.g., `rm` the VM after your agent session ends, since disks aren't the bottleneck and container-image boot is already ~2s).
- No Terraform provider or official SDK — you'll be writing a thin wrapper around SSH/`--json` yourself (very feasible; see the pattern below).

---

## 3. A concrete build for replicating orbs on Exe.dev

You don't need much: a small control script/service (could literally be a Python CLI, or a tiny FastAPI service Claude Code calls as a tool) that does what Amp's control plane does:

1. **Provision**: `ssh exe.dev new --name=proj-<id> --cpu=2 --memory=4 --disk=20 --image=ubuntu:22.04 --setup-script=./setup.sh --json`
   - `setup.sh` clones the repo, installs `apt` packages, starts Postgres/Redis via `systemd`, seeds test data — this is your `.agents/setup` equivalent.
2. **Hand off to the agent**: SSH into `proj-<id>.exe.xyz` and launch Claude Code (or any CLI agent) inside a `tmux`/`screen` session so it survives your own disconnect, same as Amp's shared-tmux orb terminal.
3. **Expose previews**: the VM's default `EXPOSE`d port is auto-published at `https://proj-<id>.exe.xyz`; use `ssh exe.dev share port <vmname> <port>` if you need a non-default port — your "Portal."
4. **Secrets**: register API keys once via Exe.dev's Integrations proxy so agent sessions never see raw credentials; generate a scoped, expiring token (`ssh-key generate-api-key --cmds='new,rm,ssh' --exp=1d`) for anything that needs to create/destroy VMs autonomously.
5. **Fast reuse**: once you have a VM configured the way you like (deps installed, Postgres primed), use `cp` to clone it as the starting point for the next project instead of re-running the full setup script — your stand-in for Amp's snapshot reuse.
6. **Teardown**: `ssh exe.dev rm proj-<id>` when the project session ends. Because container-image boot is ~2s, there's little cost to just destroying and recreating rather than trying to replicate Amp's pause/resume state-preservation exactly.
7. **Multi-project isolation**: since billing is pooled (not per-VM), you can freely run 5–10 project VMs concurrently under one $20/mo Personal plan (bounded by the shared 2×8 baseline — for heavier concurrent workloads you'd want Team or Enterprise, or the pay-as-you-go usage pricing at $0.05/core-hour + $0.016/GiB-hour for bursty overflow) ([Exe.dev pricing](https://exe.dev/pricing)).

This gets you 80% of the orb experience — dedicated disposable VM per project, agent-driven setup, exposed preview URL, scoped credentials — without leaving your existing subscription.

---

## 4. Fly.io as an alternative — and it's arguably a better fit if you want true orb-grade behavior

You specifically asked about Fly.io, and it turns out Fly has already built the exact product category you're describing:

- **Fly Machines API**: REST API + `flyctl` for creating/starting/stopping/destroying Firecracker microVMs directly, with persistent Volumes and a private WireGuard mesh network (6PN) connecting all your machines by default ([Machines overview](https://fly.io/docs/machines/overview/), [Private Networking](https://fly.io/docs/networking/private-networking/)).
- **Sprites** (Fly's newer, purpose-built product, launched ~January 2026) is explicitly Fly's answer to Amp-style agent sandboxes: each Sprite is a microVM with its own kernel/network namespace, an ext4 filesystem that continuously syncs to durable storage (no manual snapshot step for persistence), **copy-on-write checkpoints** (`sprite checkpoint create` / `sprite restore`), and a **DNS-based egress policy that agent code cannot widen from inside the sandbox** — exactly the "don't let the agent loosen its own leash" pattern security-conscious orb-style products need ([Fly.io Agent Sandboxes](https://fly.io/learn/agent-sandbox/)). Reported performance: **1–2 second creation, ~300ms checkpoint/restore**, billed at $0.07/CPU-hour + $0.04375/GB-hour with zero idle charge — a 4-hour Claude Code session runs about $0.44 ([Better Stack comparison](https://betterstack.com/community/comparisons/best-sandbox-runners/)). There's already a community "Tokenizer" pattern for injecting GitHub/OpenAI credentials via a proxy so secrets never live inside the sandbox, and an official connector wiring Sprites into the OpenAI Agents SDK ([Fly community thread](https://community.fly.io/t/sprites-tokenizer-secret-injecting-proxy-pattern-for-sandboxed-ai-agents/27054), [superfly/sprites-openai-agents](https://github.com/superfly/sprites-openai-agents)).
- **Real-world validation**: Fly's customer **Struct** gives each investigation agent its own dedicated Machine (no shared runtime between tenants), keeps a warm pool of pre-provisioned stopped Machines in Postgres for sub-second starts, and destroys the whole Machine when a session ends rather than trying to "clean" a reused one ([Struct customer story](https://fly.io/customer-stories/struct/)) — this is very close to what you're describing wanting to do per coding project.

### Sprites, straight from the source ([fly.io/sprites](https://fly.io/sprites/))

Fly's own product page confirms Sprites is now a fully separate, dedicated product (its own domain, `sprites.dev`, own CLI/API, own docs) rather than a thin wrapper on Machines, and it maps almost one-to-one onto what Amp's orbs do:

- **Positioning**: "Sandboxes aren't enough — Sprites are full Linux computers designed for agents," explicitly persistent-or-disposable as you choose, with checkpointing/restore and secretless external connections ([fly.io/sprites](https://fly.io/sprites/)).
- **Tooling**: install via `curl https://sprites.dev/install.sh | bash`; then `sprite login`, `sprite create my-sprite`, `sprite exec -s my-sprite -- ls -la`, `sprite console -s my-sprite`. There's also a plain REST API (`PUT`/`POST https://api.sprites.dev/v1/sprites/...`) and official SDKs for **JavaScript (`@fly/sprites`), Go (`superfly/sprites-go`), Elixir (`superfly/sprites-ex`), and Python (`sprites-py`)** — a real SDK ecosystem, unlike Exe.dev's SSH-only surface ([fly.io/sprites](https://fly.io/sprites/)).
- **Persistence**: tiered storage — reads/writes hit a fast local cache while data durably lives in object storage behind it, so a Sprite can sleep, move to a different physical machine, and come back with its filesystem exactly intact. It's a normal POSIX filesystem (no special API needed), the volume is 100GB, and you're billed only on actual usage, not a size you provision upfront. A newer **S3 Block Device** backend (early access, opt-in per org) presents the object bucket as a real block device running ext4, which is what makes checkpoints block-level snapshots instead of file copies ([fly.io/sprites](https://fly.io/sprites/)).
- **Checkpoints**: live (doesn't interrupt the running Sprite), copy-on-write (cheap to take/keep), captures the *entire disk* (every file/package/on-disk database), and happens **automatically** — after a stretch of continuous work, when the Sprite goes idle, and on graceful shutdown — so you don't have to remember to snapshot like you would on Exe.dev today. You can create/list/restore checkpoints from inside the Sprite via the `sprite-env` CLI or the management API ([fly.io/sprites](https://fly.io/sprites/)).
- **Sprite URLs**: every Sprite gets its own HTTPS URL with TLS handled for you; an incoming request auto-wakes a paused Sprite; you just bind your app to port 8080 and the proxy routes traffic there; each URL can be flipped between org-private and fully public with one setting — this is the direct equivalent of Amp's Portals ([fly.io/sprites](https://fly.io/sprites/)).
- **Connectors** (first-class, not just a community pattern): your agent calls out through a named connector (provider + connection ID) — official ones exist for **OpenRouter, Slack, and GitHub** — and the connector makes the outbound call so the credential itself never enters the Sprite. Any HTTP API (including your own internal, authenticated services) can be wired up the same way, and each connection can be tested from the control plane before you trust it. This is a more mature, productized version of the "Tokenizer" pattern the community had been building manually, and it's a closer match to Amp's OIDC-based secrets model than what Exe.dev currently offers out of the box ([fly.io/sprites](https://fly.io/sprites/)).
- **Billing (confirmed, per-hour, nothing charged just for a Sprite existing)**: CPU $0.07/CPU-hour, memory $0.04375/GB-hour, hot storage $0.000683/GB-hour (~$0.50/GB-month), cold storage $0.000027/GB-hour. Three lifecycle states — **running** (billed), **warm** (not billed, seconds after activity stops), **cold** (not billed) — so a Sprite that exists but does nothing costs nothing beyond storage. Official worked examples: a 4-hour Claude Code session (bursting to 8 vCPU/8GB, averaging 30% of 2 CPU/1.5GB) costs **$0.44 total**; a low-traffic web app running 30 hours/month costs **$1.89/month**. Bandwidth/egress is not metered at all for Sprites ([fly.io/sprites](https://fly.io/sprites/)).
- **Idle detection**: four things keep a Sprite awake — an in-flight HTTP/API request, stdout output from a session or exec'd process (redirecting to a file or a detached tmux doesn't count), an open TCP connection, or an active task via `sprite-env tasks create` (max 1 hour, renewable) — worth knowing since a naive background job can accidentally keep billing running ([fly.io/sprites](https://fly.io/sprites/)).
- **Plans**: named tiers from Adventurer/Veteran up through Hero ($100/mo — 1,200 CPU-hours, 4,800 RAM GB-hours, 150GB storage, 100 concurrent running + 100 warm Sprites), Champion, Legend, Epic, to Mythic (~$2,000/mo tier referenced in their own billing FAQ), plus pure pay-as-you-go. Sprite creation rate is tiered too: 10/minute on pay-as-you-go, rising to 240/minute on Mythic. A **$30 trial credit** is available per user/org (create roughly 500 Sprites free to try it) ([fly.io/sprites](https://fly.io/sprites/)).
- **Agent ecosystem**: the page advertises "official plugins for every serious coding agent, plus SDKs and native integrations" — i.e. Sprites is being positioned explicitly as the backend for tools like Claude Code, not just a generic VM product ([fly.io/sprites](https://fly.io/sprites/)).

This changes the practical comparison a bit: Sprites' automatic, disk-level, copy-on-write checkpointing and its productized Connectors system are more turnkey than anything Exe.dev offers today, and arguably closer to (in some ways ahead of) what Amp built for its own orbs.

**Fly vs. Exe.dev, practically:**

| | Exe.dev | Fly.io (Machines/Sprites) |
|---|---|---|
| Boot speed | ~2s (container image → VM) | Sprites: 1–2s create, ~300ms checkpoint/restore |
| Snapshot/checkpoint | Not yet mature (clone via `cp`, formal snapshotting in development) | First-class (Firecracker snapshot suspend/resume; Sprites checkpoints) |
| API shape | SSH + thin HTTPS wrapper, no SDK/Terraform | Full REST API, `flyctl`, official SDKs, growing Terraform support |
| Networking | Auto HTTPS proxy per VM, no private mesh | 6PN private WireGuard mesh between all your machines by default |
| Egress control for agent safety | Not a first-class feature | Connectors: agent calls out via a named connection, credential never enters the sandbox |
| Pricing model | Pooled subscription ($20/mo for 50 VMs, shared 2×8 baseline) — very cheap for many small/idle VMs | Hourly usage ($0.07/CPU-hr + $0.04375/GB-hr + tiny storage fee); a 4-hr Claude Code session ≈ $0.44; nothing charged for an idle/existing Sprite beyond storage |
| Postgres/Docker inside | Confirmed working (Cal.diy example) | Fully supported — normal POSIX filesystem, install anything |
| SDKs | None official (SSH/JSON only) | Official JS, Go, Elixir, Python SDKs plus REST API and CLI |
| You already pay for it | Yes | No (new cost, but $30 trial credit ≈ 500 free Sprites to test) |

**Recommendation**: Since you already have Exe.dev, start there — build the thin control-layer described above, and it'll get you most of what you want with zero new cost. But after seeing Fly's own [sprites.dev](https://fly.io/sprites/) page in detail, Sprites is genuinely the more turnkey option for exactly this use case: it does automatic, disk-level, copy-on-write checkpointing for you (no need to manually clone a "golden" VM the way you'd have to on Exe.dev), ships official SDKs in four languages instead of just SSH, and has productized "Connectors" for secretless GitHub/Slack/OpenRouter/any-HTTP-API access that's a closer match to Amp's own OIDC-based secrets model. If you want to prototype quickly, the $30 trial credit gets you roughly 500 Sprites to test against your actual workflow before deciding whether it's worth paying for alongside Exe.dev.

**Other options worth knowing about, if you want an even higher-level SDK instead of managing raw VMs yourself:**
- **E2B** — Firecracker-based, Apache-2.0 open source, self-hostable, pause/resume/fork built in, $100 free credit ([e2b.dev](https://e2b.dev/)).
- **Daytona** — container/VM/GPU sandbox classes, ~90ms creation, pure usage-based pricing, $200 free credit, agent-agnostic ([daytona.io](https://www.daytona.io/docs/en/architecture/)).
- **Modal Sandboxes** — extremely high concurrency (100k+), per-second billing, good if you need massive parallel fan-out of agent sessions rather than a handful of persistent per-project machines ([modal.com/products/sandboxes](https://modal.com/products/sandboxes)).
- **Coder** — if you want a self-hosted control plane (Terraform-defined workspaces + WireGuard tunnels + a governed "Coder Agents" mode) sitting on top of whatever cloud you choose, rather than writing your own orchestration script from scratch ([coder.com/docs/about](https://coder.com/docs/about)).

---

## Sources

- [Amp — What Are Orbs?](https://ampcode.com/what-are-orbs)
- [Amp — Manual: Orbs](https://ampcode.com/manual/orbs)
- [Amp — Docs: Customizing Orbs](https://ampcode.app/docs/orbs/customizing)
- [Amp — Docs: Sizes & Costs](https://ampcode.com/docs/orbs/sizes-and-costs)
- [Amp — News: Portals](https://ampcode.com/news/portals)
- [Amp — News: Secrets of the Orb](https://ampcode.com/news/secrets-of-the-orb)
- [mer.vin — Agent Harnesses vs Orbs](https://mer.vin/2026/08/agent-harnesses-vs-orbs-why-remote-sandboxes-beat-local-agent-loops/)
- [Exe.dev — How exe.dev works](https://exe.dev/docs/faq/how-exedev-works)
- [Exe.dev — API docs](https://exe.dev/docs/api)
- [Exe.dev — AI Sandboxes page](https://exe.dev/sandbox)
- [Exe.dev — Pricing](https://exe.dev/pricing)
- [Exe.dev — Cal.diy use case](https://exe.dev/docs/use-case-cal-diy)
- [Exe.dev — Customization docs](https://exe.dev/docs/customization)
- [Hacker News — Exe.dev thread](https://news.ycombinator.com/item?id=46405579)
- [Fly.io — Machines overview](https://fly.io/docs/machines/overview/)
- [Fly.io — Machine Suspend and Resume](https://fly.io/docs/reference/suspend-resume/)
- [Fly.io — Agent Sandboxes (Sprites)](https://fly.io/learn/agent-sandbox/)
- [Fly.io — Sprites product page](https://fly.io/sprites/)
- [Fly.io — Private Networking (6PN)](https://fly.io/docs/networking/private-networking/)
- [Fly.io — Struct customer story](https://fly.io/customer-stories/struct/)
- [Better Stack — Sandbox runner comparison](https://betterstack.com/community/comparisons/best-sandbox-runners/)
- [Fly community — Sprites Tokenizer pattern](https://community.fly.io/t/sprites-tokenizer-secret-injecting-proxy-pattern-for-sandboxed-ai-agents/27054)
- [superfly/sprites-openai-agents (GitHub)](https://github.com/superfly/sprites-openai-agents)
- [E2B homepage](https://e2b.dev/)
- [Daytona Architecture docs](https://www.daytona.io/docs/en/architecture/)
- [Modal Sandboxes product page](https://modal.com/products/sandboxes)
- [Coder docs: About](https://coder.com/docs/about)
