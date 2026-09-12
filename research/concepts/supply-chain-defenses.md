---
title: "Supply-chain defenses: what exists, what it stops, and Q17's options"
created: 2026-09-12
updated: 2026-09-12
type: concept
tags: [research, security, stdlib]
sources: [raw/research-runs/supply-chain-defenses-survey.pplx.md, raw/research-runs/package-security-research-review.pplx.md]
confidence: medium
---

# Supply-chain defenses: what exists, what it stops, and Q17's options

Input for [[q17-package-management-and-supply-chain|Q17]] and [[d30-supply-chain-security|direction 30]]. It synthesizes Robert's two Perplexity runs: the defenses survey (Q17 prompt 2)[125] and the academic literature review (prompt 3).[126] It also draws on the [[go]], [[austral]], [[unison]], [[koka]] and [[agent-native-cluster]] comparisons. **No recommendation.** Fable and Robert decide.

*Gap:* Q17 prompt 1 (the incident catalogue for 2024–26) has no run yet. Section (b) uses only the incidents the two runs cite, so it is not a full record.

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

## (b) The 2025–26 incident shape, and what would have stopped it

| Incident (per the runs) | Stopped by | Not stopped by |
|---|---|---|
| Shai-Hulud (Sep 2025), 500+ npm packages removed | Short-lived tokens, 2FA publishing | Provenance, checksums |
| Mini Shai-Hulud / TanStack (May 2026) | Isolated builders (L3), workflow audits | Provenance, trusted publishing |
| 2,289 repackaged Go modules (2026) | Human audits, name checks | Checksum DB (it preserved them) |
| Slopsquatting (hallucinated names) | Existence and age checks at add | Every integrity layer |
| MCP tool poisoning and rug pulls | Declared, re-approved capabilities | Registry signing |

*The "stopped by" and "not stopped by" columns are Claude's reading of each defense's documented scope, not verdicts stated in the runs.*

- **TanStack, the defining 2026 case.** A `pull_request_target` "Pwn Request", GitHub Actions cache poisoning, and an OIDC token read from runner memory produced 84 malicious versions across 42 packages, spreading to 170+. The attestations were "indistinguishable from attestations on legitimate packages". Both publishing runs ended in `status: failure`, and no tooling checked that.[125]
- **Repackaged Go modules.** Valid log entries under attacker-controlled owners; the immutable proxy kept serving them.[125]
- **Slopsquatting.** In a 2024 study, 19.7% of LLM-suggested packages did not exist: 205,474 unique names, often repeated across models, which makes squatting practical. Hallucination rates are inversely correlated with coding-benchmark scores.[126]
- **MCP servers.** Namespace typosquatting, tool poisoning, "rug pulls" (a tool changes after approval), and retrieval-agent deception, demonstrated end to end against Claude Desktop.[126]
- **The shape overall:** attackers moved from forging trust to *operating inside* trusted pipelines and names. Every integrity layer authenticates who and how, never intent.[125] Signing infrastructure outran verification: only 3 of 18 organizations checked third-party signatures.[125]

## (c) What Mo already has, against that shape

- **Capabilities as package permissions** ([[d30-supply-chain-security|direction 30]], [[p13-capabilities-and-logging|pick 13]]). This is the granularity the survey calls "the decisive design variable": per function parameter, not per process like Deno.[125] It stops a JSON library from reading tokens or phoning home, and it bounds a poisoned MCP-style tool to what it was handed. It does *not* stop a malicious payload in a package that legitimately holds `Network`. That is where attacks move next.
- **No install scripts, macros, or build-time code execution** ([[d30-supply-chain-security|direction 30]]). This removes the install-time vector that DySec and the PyPI studies measure.[126] It does nothing about CI-pipeline hijacks like TanStack. Those are about how Mo's *registry* accepts publishes, not the language.
- **Content hashes per declaration** ([[q10-semantic-ids-and-editing|Q10]], [[unison]]). "What changed" becomes exact, and served-bytes tampering is detectable, as with Go's checksum database.[72] Like the checksum database, hashes authenticate consistency, not intent. The 2,289 Go modules would still verify.[125]
- **`flows(...)`** ([[p09-module-header-and-never|pick 9]]). The closest research relative is "Static IFC made simpler".[126] It could prove that a `Secret` never reaches a dependency's `Network`. The literature has designs but no ecosystem evidence.
- **The platform is the only unsafe layer** ([[q16-escape-hatch|Q16]]). Every surveyed capability language failed at its native boundary.[125] Mo concentrates that boundary in platforms, so **auditing platforms is the whole trusted base**, not a side question. Pony's FFI allow-list and Austral's lockfile audit of unsafe modules are the precedents.[125][57]
- ⚠️ **The closure-capture hole** ([[koka]], [[d15-effects-via-capabilities|direction 15]]). A package that declares "needs: nothing" but takes a callback can do I/O through capabilities the caller captured in that closure.[51] This is E's confused deputy in type form,[125] and it defeats the "visible at install time" guarantee for any higher-order API. The candidate fixes are on [[koka]] and [[bosque]]. Not resolved here.
- **Not covered by anything Mo has:** resource exhaustion (deadlines bound waits, not CPU or memory; [[d17-mandatory-deadlines|direction 17]]), covert channels, and publish-pipeline compromise.[125]

## Design options for Q17

Evidence for and against each. No ranking.

1. **Go-style: VCS modules, a proxy, a transparency log, minimal version selection.**
   - *For:* default-on and universal, content-authenticated, no key management, locked builds.[125][19]
   - *Against:* doesn't catch malicious-from-first-publish code, the immutable cache preserves malware, tags can be rewritten (BoltDB), and verification code has had bugs.[125][15]
2. **Central registry with mandatory trusted publishing and provenance.**
   - *For:* ends long-lived token theft; adoption follows registry *policy* (an IEEE S&P 2024 finding).[125]
   - *Against:* TanStack produced valid attestations, few consumers verify, and it authenticates the actor, not intent.[125]
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

## Sources

[15] https://socket.dev/blog/malicious-package-exploits-go-module-proxy-caching-for-persistence — Malicious package exploits Go Module Proxy caching (Socket)
[19] https://go.dev/blog/supply-chain — How Go Mitigates Supply Chain Attacks (Go blog)
[51] https://se.informatik.uni-tuebingen.de/publications/brachthaeuser22effects.pdf — Effects, Capabilities, and Boxes (Brachthäuser et al.; OOPSLA 2022)
[57] https://borretti.me/article/how-capabilities-work-austral — How Capabilities Work in Austral (Borretti, 2023)
[72] https://www.unison-lang.org/docs/the-big-idea — Unison: The big idea
[74] https://lwn.net/Articles/978955 — Programming in Unison (LWN.net)
[125] raw/research-runs/supply-chain-defenses-survey.pplx.md — Robert's research run: A Survey of Software Supply-Chain Defenses (Perplexity, Q17 prompt 2, 12 Sep 2026)
[126] raw/research-runs/package-security-research-review.pplx.md — Robert's research run: Language-Based Security for Package Dependencies, literature review 2019–2026 (Perplexity, Q17 prompt 3, 12 Sep 2026)
