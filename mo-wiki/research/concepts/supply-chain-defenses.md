---
title: "Supply-chain defenses: what exists, what it stops, and Q17's options"
created: 2026-09-12
updated: 2026-09-17
type: concept
tags: [research, security, stdlib]
sources: [raw/research-runs/supply-chain-incidents-2024-2026.pplx.md, raw/research-runs/supply-chain-defenses-survey.pplx.md, raw/research-runs/package-security-research-review.pplx.md]
confidence: medium
---

# Supply-chain defenses: what exists, what it stops, and Q17's options

Input for [[q17-package-management-and-supply-chain|Q17]] and [[d30-supply-chain-security|direction 30]]. It synthesizes Robert's three Perplexity runs: the incident catalogue for January 2024 to September 2026 (Q17 prompt 1),[151] the defenses survey (prompt 2),[125] and the academic literature review (prompt 3).[126] It also draws on the [[go]], [[austral]], [[unison]], [[koka]] and [[agent-native-cluster]] comparisons. **No recommendation.** Fable and Robert decide.


## (a) The defenses that exist

**Registry layer: what bytes am I installing?**

- **Go checksum database.** Every public module version's hash goes into a transparency log, which the `go` command checks; this is default-on since Go 1.13. It prevents tampering by proxies and code hosts, retroactive rewriting of a version, and silent downgrades. It explicitly does *not* judge intent: "works without needing to attribute specific archives to specific authors". A 2026 study found 2,289 malicious repackaged Go module versions, every one a valid log entry. The proxy's permanence works against takedown: 99.4% of the malicious artifacts were still retrievable. CVE-2026-56865 showed that a malicious `GOPROXY` could forge log tiles.[125] The BoltDB typosquat is the concrete case: its tag was rewritten after the proxy cached it.[15]
- **npm provenance with Sigstore.** CI signs a SLSA provenance statement with a short-lived key tied to the job's OIDC identity and logs it in Rekor. It prevents post-publish tampering, provenance spoofing and impostor packages. npm says it "does not guarantee the package has no malicious code". It does not stop a hijacked but legitimate pipeline, verification is opt-in, and adoption reached only 3.72% of the top 5,000 high-impact packages.[125]
- **PyPI Trusted Publishing.** OIDC tokens are exchanged for 15-minute upload credentials. This removes long-lived token theft and impersonation of one workflow by another. PyPI's own security model says it "does not assert the safety of the code". It also doesn't protect against a compromised workflow ("treat your Trusted Publishers as if they are API tokens"), identity-provider compromise, or gaps when a maintainer is offboarded. A 2026 audit found two anti-replay bugs, since fixed.[125]

**Build layer: how were the bytes produced?**

- **SLSA.** Signed provenance at L2 and a hardened, isolated builder at L3. It prevents artifact substitution, build injection and cache poisoning. By its own threat model it does not cover malicious source, unsafe CI triggers, or transitive dependencies. It does not require reproducibility. Practitioners report adoption is "not widespread".[125]
- **Reproducible builds.** Independent rebuilders compare bit-for-bit outputs, which detects SolarWinds-style build injection. They cannot catch malicious source, which reproduces identically, or a trusting-trust implant in the toolchain. A 2026 NixOS demonstration infected 3,790 of 3,791 binaries without any check firing. In a study of practitioners, 23 of 24 could not name a security incident that reproducibility caught. Coverage in language registries as they stand: PyPI 12.2%, Maven 2.1%, RubyGems 0%.[125]
- **cargo-vet and cargo-crev.** Shared human audits, with delta audits between versions. They stop unreviewed code and malicious *updates* to vetted crates. They do not stop faithless audits or an over-trusted auditing organization. Exemptions mean a passing CI run is not proof of review. crev covers about 1% of crates.[125]

**Language and runtime layer: what can the code do?**

- **Deno permissions.** No file, network, environment or subprocess access without a flag, and no install scripts. This blocks those accesses and install-time malware. Grants are *process-wide*, so once the app needs network access, every dependency gets it. In the NDSS 2025 study only 53 packages used fine-grained permissions, while 33 told users to run with `--allow-all`. `--allow-read` can read environment variables through `/proc`, and subprocesses and FFI are unsandboxed.[125]
- **Capability-safe languages.**
  - **E** removes ambient authority by construction but not covert channels or confused deputies.
  - **Pony** attenuates authority from `AmbientAuth` down to `TCPConnectAuth`, and can allow-list which packages may use FFI, but its own tutorial says FFI calls can void all of Pony's guarantees.
  - **Wyvern** makes module authority non-transitive; 47% of its I/O library is trusted Java.
  - **Austral** gets capabilities from linear types, but unsafe modules "completely bypass the capability hierarchy".
  - **Roc platforms** keep I/O out of library code, but a permissive platform gives dependencies full authority, and the sandbox platform doesn't exist yet.

  The survey's common thread: every design has a native-code escape, and none addresses resource exhaustion.[125]
- **Per-module permission systems (research).** A 2021 npm design had owners declare network, filesystem and process permissions and made escalation on update visible. It would have fully protected 31.9% of npm packages at under 1% overhead. Mir *inferred* per-module read/write/execute/import permissions, cutting privilege 15.6×–706× at 1.93% runtime overhead.[126][125]
- **Information-flow control for libraries.** Cocoon (Rust `Secret<T, Label>`, leaks fail to compile) and "Static IFC made simpler" (`flow mod network_io ->! mod db_handle`) put policy in types or source. They are designs with no ecosystem-scale evidence yet.[126]
- **AI-era detection.** LLM review of npm packages (SocketAI: 99% precision with GPT-4) and behavioural tracing at install time (DySec). Package-existence checks against hallucinated names.[126]

## (b) The 2024–26 incident record, and what would have stopped it

The incident run catalogues 47 incidents and campaigns; the ones below are 20 of them, at least one per category. Each line gives ecosystem and date, the category *as the reporters classified it*, reach, detection, and the ecosystem-level mitigation adopted ("n.a." where no registry or platform change followed).[151] It uses labelled lines instead of an eight-column table for readability (17 Sep 2026: the phone justification struck; phones are not a criterion in this project). **Stopped by / not stopped by** is *Claude's reading* of each defense's documented scope, not a verdict from the runs.

**Worms (rank 1)**
- **Shai-Hulud wave 1** (npm, 14–16 Sep 2025). Self-propagating credential-stealing worm, "the first ever registry-native worm". 526 packages. Detected by StepSecurity and Socket. Mitigation: GitHub blocked uploads matching known indicators, then planned 7-day tokens, trusted publishing, and FIDO instead of TOTP.[151] *Stopped by:* phishing-resistant 2FA, short-lived tokens. *Not by:* checksums, provenance.
- **Shai-Hulud 2.0** (npm, Nov 2025). Worm spread through CI. Between 492 and 1,000+ packages, about 25,000–28,000 repos, 11,858 secrets leaked (2,298 still valid). Its payload "executes only during the pre-install stage". Detected by PostHog, Postman, Aikido, and npm's own automated warning. Mitigation: classic tokens revoked on 9 Dec, session lifetime cut from 12h to 2h.[151] *Stopped by:* no install scripts, a multi-day release-age gate (Postman's window was about 6 hours). *Not by:* provenance.
- **Mini Shai-Hulud, largest wave** (npm and PyPI, 11–12 May 2026). Worm published "under the legitimate GitHub Actions" OIDC publisher identity: 172 packages, 403 versions. Detected by Mend. Mitigation: `minimumReleaseAge` in npm, pnpm, Yarn and Bun.[151] *Stopped by:* a release-age gate, isolated builders. *Not by:* trusted publishing, provenance.
- **ChainDrop** (npm, 4 Aug 2026). Worm through `keyv` and `flat-cache` that "abuses GHA OIDC trusted publishers so packages carry valid provenance". 400+ packages with 1.3 billion monthly downloads. It struck *after* npm 12 turned install scripts off. Detected by Microsoft and Elastic. Mitigation: n.a.[151] *Stopped by:* per-package capabilities, since a cache library holds no network or environment access. *Not by:* trusted publishing, install-script bans.

**Compromised maintainer accounts (rank 2)**
- **Qix: `debug`, `chalk` and more** (npm, 8 Sep 2025). A phishing email that reset 2FA led to a crypto-clipper in packages with 2–3 billion weekly downloads. Later attributed to North Korea's Sapphire Sleet. Detected by Aikido's feed. Mitigation: GitHub's npm hardening plan.[151] *Stopped by:* FIDO-only 2FA. *Not by:* checksums, provenance.
- **`axios`** (npm, 31 Mar 2026). A long-lived token bypassed OIDC trusted publishing. First infection came 89 seconds after publish, and Socket flagged it about 6 minutes after publish. Mitigation: n.a.[151] *Stopped by:* no token type that can publish on its own, a release-age gate. *Not by:* trusted publishing.
- **Lottie Player** (npm, Oct 2024). An automation token bypassed 2FA, and one victim lost over $723,000. Detected from community reports.[151] *Stopped by:* short-lived tokens. *Not by:* TOTP 2FA.

**CI and build pipelines (rank 3)**
- **tj-actions/changed-files** (GitHub Actions, 14 Mar 2025). Every tag was repointed to a malicious commit, and secrets leaked from repos in "over 23,000 public repositories" for about 24 hours. Detected by StepSecurity's egress monitoring. Mitigation: GitHub policy to block actions and require SHA pinning.[151] *Stopped by:* SHA pinning. *Not by:* any registry control.
- **Ultralytics** (PyPI, Dec 2024). Actions cache poisoning shipped a cryptominer. Detected because the artifacts **did not match** their attestations in the Sigstore log.[151] *Stopped by:* attestations with a transparency log (detection). *Not by:* trusted publishing alone.
- **Nx "s1ngularity"** (npm, 26 Aug 2025). About 6 million weekly installs over a roughly 4-hour window. The first widely reported AI-assisted credential harvester: it abused local AI CLIs. Detected by *missing* provenance. Mitigation: Nx moved to OIDC.[151] *Stopped by:* provenance checks, an age gate. *Not by:* checksums.
- **TeamPCP** (PyPI, npm, Actions, Open VSX, containers; Mar 2026). One operator compromised five distribution channels, including Trivy and Checkmarx actions. Detected by Datadog.[151] *Stopped by:* isolated builders. *Not by:* SHA pinning (the action repos themselves were compromised).

**Lookalikes, nation-states, extensions, scripts (ranks 4–7)**
- **`boltdb-go/bolt`** (Go, found Feb 2025). A typosquat the Go proxy cached for 3+ years. Detected by Socket. Mitigation: n.a.; Socket calls Go's registry "insufficient defense".[151][15] *Stopped by:* name checks, human audit. *Not by:* the checksum database.
- **`Tracer.Fody.NLog`** (NuGet, Dec 2025). A typosquat live for "nearly six years", with a spoofed maintainer name and Cyrillic lookalike characters. Detected by Socket.[151] *Not by:* simple name-similarity checks.
- **`Sharp7Extend`** (NuGet, Nov 2025). A typosquat carrying delayed sabotage of industrial PLCs, with "~80% silent PLC write failures".[151] *Not by:* capabilities, since reaching the PLC is the library's legitimate job.
- **XZ Utils** (Linux distributions, Mar 2024). About two years of social engineering by a planted co-maintainer. Andres Freund caught it from a 500 ms slowdown in sshd.[151] *Not by:* any registry defense surveyed.
- **"Solidity Language" extension** (Open VSX in Cursor, Jul 2025). One victim lost $500K in crypto. Mitigation: the extension was removed.[151] *Not by:* package-registry controls. Extensions are the IDE-side analog of agent tools.
- **crates.io `arrayref` and `internment`** (20 Aug 2026). An account compromise plus a `proc-macro2` typosquat, running code **at build time**; the prior clean release line had ~152M downloads. Detected by Socket's AI scanner at publish. Mitigation: releases removed, account locked.[151] *Stopped by:* no build-time execution. *Not by:* bans on install scripts only.
- **SANDWORM_MODE** (npm, Feb 2026). A worm that "poisons Claude, Cursor, Continue and Windsurf MCP configs" and spreads through a GitHub Action.[151] *Stopped by:* capabilities on agent tools. *Not by:* registry signing.

**Ranks 8–12**
- **Slopsquatting.** 19.7% of recommended packages didn't exist, and GPT-5 hallucinated 27.8% of versions. Ranked on exposure: no specific breach confirmed.[151]
- **Repo-jacking (MavenGate), dependency confusion (33 packages, May 2026), protestware (28 packages), registry spam (IndonesianFoods, 169,538 packages).** Research, reconnaissance, or low-harm campaigns in this window.[151]

### Categories ranked by impact, with trend

Ordered by the run's impact ranking, with its trend column.[151]
1. **Credential-stealing worms:** sharply increasing (none in 2024; continuous in 2026)
2. **Maintainer account compromise:** flat in count, increasing in severity
3. **CI and build pipelines:** increasing; CI now spreads every 2026 worm wave
4. **Lookalikes and typosquatting:** increasing, spreading beyond npm and PyPI
5. **Nation-state campaigns:** increasing
6. **Malicious IDE extensions:** increasing
7. **Install- and build-time scripts:** the execution surface more than the entry point
8. **AI-related risk (slopsquatting, AI-toolchain poisoning):** sharply increasing
9. **Repo-jacking:** research, not confirmed exploitation
10. **Dependency confusion:** one confirmed campaign
11. **Protestware:** flat to decreasing
12. **Registry spam:** distorts every malicious-package count

Overall malicious-package volume is up 75% year over year. Detection latency is improving sharply.[151]

### Which defenses have evidence

- **TOTP 2FA did not stop repeats**: Lottie Player and Qix got through it.[151]
- **Trusted publishing did not stop the 2026 worms** (Mini Shai-Hulud, ChainDrop, `axios`). "OIDC moves the attack from the maintainer's laptop to the maintainer's CI."[151]
- **Attestations** gave the one clean detection signal: Ultralytics and Nx.[151]
- **Release-age gates** are backed by timing evidence (89 seconds to first infection, windows of a few hours), but no measured reduction in incidents.[151]
- **npm 12 turned install scripts off**, but build-time scripts remain, and the run's takeaway is to treat both as one surface.[151]
- **Name-blocking at creation:** no effect demonstrated.[151]
- **Fast triage** is the clearest measured win: PyPI handles 66% of reports in under 4 hours and 92% in under 24.[151]

## (c) What Mo already has, against that shape

- **Capabilities as package permissions** ([[d30-supply-chain-security|direction 30]], [[p13-capabilities-and-logging|pick 13]]). This is the granularity the survey calls "the decisive design variable": per function parameter, not per process like Deno.[125] It stops a JSON library, or a cache library like ChainDrop's `keyv`, from reading tokens or phoning home, and it bounds a poisoned MCP-style tool to what it was handed. It does *not* stop a malicious payload in a package that legitimately holds `Network`. That is where attacks move next.
- **No install scripts, macros, or build-time code execution** ([[d30-supply-chain-security|direction 30]]). This removes the install-time vector that DySec and the PyPI studies measure.[126] This matches the incident run's takeaway to treat install-time and build-time execution as one surface, off by default.[151] It does nothing about CI-pipeline hijacks like TanStack (not in the catalogue above; source not captured). Those are about how Mo's *registry* accepts publishes, not the language.
- **Content hashes per declaration** ([[q10-semantic-ids-and-editing|Q10]], [[unison]]). "What changed" becomes exact, and served-bytes tampering is detectable, as with Go's checksum database.[72] Like the checksum database, hashes authenticate consistency, not intent. The 2,289 Go modules would still verify.[125]
- **`flows(...)`** ([[p09-module-header-and-never|pick 9]]). The closest research relative is "Static IFC made simpler".[126] It could prove that a `Secret` never reaches a dependency's `Network`. The literature has designs but no ecosystem evidence.
- **The platform is the only unsafe layer** ([[q16-escape-hatch|Q16]]). Every surveyed capability language failed at its native boundary.[125] Mo concentrates that boundary in platforms, so **auditing platforms is the whole trusted base**, not a side question. Pony's FFI allow-list and Austral's lockfile audit of unsafe modules are the precedents.[125][57]
- ⚠️ **The closure-capture hole** ([[koka]], [[d15-effects-via-capabilities|direction 15]]). A package that declares "needs: nothing" but takes a callback can do I/O through capabilities the caller captured in that closure.[51] This is E's confused deputy in type form,[125] and it defeats the "visible at install time" guarantee for any higher-order API. The candidate fixes are on [[koka]] and [[bosque]]. Not resolved here.

  Answered since (17 Sep 2026): [[d31-effects-never-hide-in-a-value]], with its cost measured in [[closure-audit-2026-09-14]].
- **Not covered by anything Mo has:** resource exhaustion (deadlines bound waits, not CPU or memory; [[d17-mandatory-deadlines|direction 17]]), covert channels, and publish-pipeline compromise.[125]

## Design options for Q17

Evidence for and against each. No ranking.

1. **Go-style: VCS modules, a proxy, a transparency log, minimal version selection.**
   - *For:* default-on and universal, content-authenticated, no key management, locked builds.[125][19]
   - *Against:* doesn't catch malicious-from-first-publish code, the immutable cache preserves malware, tags can be rewritten (BoltDB), and verification code has had bugs.[125][15]
2. **Central registry with mandatory trusted publishing and provenance.**
   - *For:* ends long-lived token theft; adoption follows registry *policy* (an IEEE S&P 2024 finding).[125]
   - *Against:* TanStack (not in the catalogue above; source not captured) produced valid attestations, few consumers verify, and it authenticates the actor, not intent.[125] ChainDrop and Mini Shai-Hulud shipped under valid OIDC identities, and `axios` got around OIDC with a leftover long-lived token.[151]
   - *Composable additions the incident run supports:* WebAuthn as the only second factor, no token type that can publish without it, and a release-age gate.[151]
3. **A capability manifest as the published interface, derived by the compiler from `pub` signatures; any widening is a breaking change a human approves.**
   - *For:* the npm permission study (31.9% of packages fully protectable), Mir's low overhead, and Deno's process-wide failure showing granularity matters. Mo computes the manifest rather than trusting the author's declaration.[126][125]
   - *Against:* the closure-capture hole, confused deputies, and legitimate `Network` holders. Deno showed permission fatigue.[125]
4. **Audited dependencies: cargo-vet-style shared audits keyed to content hashes, with platforms requiring an audit before use.**
   - *For:* stops malicious updates to vetted code, and delta audits get cheaper as hashes shrink the diff.[125]
   - *Against:* faithless audits, about 1% coverage, and exemptions that turn CI green without review.[125]
5. **Content-addressed vendoring (Unison-style): dependencies by hash in the project, no floating versions, patches from old hash to new.**
   - *For:* exact contents, no version conflicts, reviewable diffs.[72][74]
   - *Against:* tooling has to be built from scratch, and a hash doesn't judge intent.[74][125]
6. **A maximal stdlib plus guarded `mo add`: raise Q11's ceiling, and refuse unknown or brand-new names.**
   - *For:* Go's "a little copying" culture, and the slopsquatting data behind package-existence checks.[19][126]
   - *Against:* stdlib maintenance cost, and a typosquat of a *real* name still passes.[126]

The options compose. The survey's own conclusion is that no single layer closes the problem.[125]

## Related
- [[q17-package-management-and-supply-chain]]
- [[d30-supply-chain-security]]
- [[prompts-q17-supply-chain]]
- [[go]]
- [[austral]]
- [[unison]]
- [[koka]]
- [[agent-native-cluster]]
- [[comparison-synthesis-draft]]
- [[d31-effects-never-hide-in-a-value]]
- [[closure-audit-2026-09-14]]

## Sources

[15] https://socket.dev/blog/malicious-package-exploits-go-module-proxy-caching-for-persistence — Malicious package exploits Go Module Proxy caching (Socket)
[19] https://go.dev/blog/supply-chain — How Go Mitigates Supply Chain Attacks (Go blog)
[51] https://se.informatik.uni-tuebingen.de/publications/brachthaeuser22effects.pdf — Effects, Capabilities, and Boxes (Brachthäuser et al.; OOPSLA 2022)
[57] https://borretti.me/article/how-capabilities-work-austral — How Capabilities Work in Austral (Borretti, 2023)
[72] https://www.unison-lang.org/docs/the-big-idea — Unison: The big idea
[74] https://lwn.net/Articles/978955 — Programming in Unison (LWN.net)
[125] raw/research-runs/supply-chain-defenses-survey.pplx.md — Robert's research run: A Survey of Software Supply-Chain Defenses (Perplexity, Q17 prompt 2, 12 Sep 2026)
[126] raw/research-runs/package-security-research-review.pplx.md — Robert's research run: Language-Based Security for Package Dependencies, literature review 2019–2026 (Perplexity, Q17 prompt 3, 12 Sep 2026)
[151] raw/research-runs/supply-chain-incidents-2024-2026.pplx.md — Robert's research run: software supply-chain incidents Jan 2024–Sep 2026 (Perplexity, Q17 prompt 1)
