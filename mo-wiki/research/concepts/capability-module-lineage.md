---
title: "Capability module lineage"
created: 2026-09-12
updated: 2026-09-17
type: concept
tags: [research, security, effects]
sources: [raw/research-runs/pl-ideas-that-did-not-win.pplx.md, raw/research-runs/supply-chain-defenses-survey.pplx.md, raw/papers/newspeak-modules-as-objects.md, raw/papers/joe-e-security-oriented-subset-java.md, raw/papers/wyvern-type-specific-languages-ecoop14.md, raw/papers/wyvern-capability-safe-modules-ecoop17.md, raw/papers/kernighan-descent-into-limbo.md, raw/papers/hardy-confused-deputy-1988.md]
confidence: medium
---

# Capability module lineage

Five older designs that bear on how Mo hands out authority. Each is mapped to [[p13-capabilities-and-logging|pick 13]] (capabilities obtained at `main` and passed down), [[q16-escape-hatch|Q16]] (the platform is the only escape hatch) and [[q17-package-management-and-supply-chain|Q17]] (packages). A follow-up from [[landscape-second-lane]]. Nothing here is decided.

## Newspeak: every module receives `platform`

- **What.** Newspeak has "no global namespace" and no static state. A top-level class is a module definition, and every external dependency arrives as a factory argument: `class ShapeLibrary usingPlatform: platform = ( … private List = platform collections List. … )`.[143] Because there are no globals, the same library can be instantiated twice with different platform objects, side by side.[143] The did-not-win run's reading: this boilerplate is "what agents are for", and it bounds an agent's blast radius "by construction". The real costs are awkward mutual recursion and hostility to static analysis.[142]
- **Pick 13.** Mo's `main(platform: Platform)` is the same move at the program root. Newspeak applies it to *every module*, including pure libraries.
- **Q16.** In both designs the platform object is the only source of authority.
- **Q17.** Newspeak's side-by-side instantiation is a precedent for the open question of two versions of one package ([[unison]]).

## Joe-E: a tamed subset, not a new language

- **What.** "A Joe-E program is a Java program" that passes a verifier which "does not transform the program".[142][144] The verifier's rules:
  - global state is immutable data only
  - no native methods
  - no reflection that bypasses access checks
  - throwables are immutable, and code may not catch `Error` or use `finally`

  Ambient-authority JDK APIs are "tamed" behind safe wrappers.[142] The authors blame the lack of adoption on capability design being "unfamiliar to most programmers", plus the work of taming the library. The run argues that both costs shrink when agents do the work.[142]
- **Pick 13.** Joe-E's immutable-only global scope is the same rule as Mo's "no globals" ([[d14-processes-are-the-only-identity|direction 14]]). Its ban on catching `Error` matches [[d18-two-kinds-of-failure|direction 18]].
- **Q16.** The native-method ban is Q16's rule: unsafe code only in the platform.
- **Q17.** Taming is the job Mo's stdlib and platform do once ([[q11-platform-and-stdlib|Q11]]). A library born tame never needs wrappers, but every platform API added later needs the same review. The run also names Joe-E as a *counterweight* to Mo: its likely modern form is "per-module capability manifests enforced by a verifier over a mainstream language".[142] That is the null hypothesis on [[case-against-new-languages]].

## Wyvern: non-transitive authority and type-specific literals

- **Non-transitive authority.** Modules are "first class, statically typed capabilities". Wyvern "defines authority non-transitively, allowing engineers to reason about … wrappers that provide an attenuated version of a more powerful capability". You find a module's authority by examining the capabilities passed to it.[146] Wyvern's I/O library narrows from `fileSystem` to `Directory` to `File` to read-only `Reader` or write-only `Writer`. The root `fileSystem` needs a `java` FFI capability that only the top-level script receives. That library is 47% trusted Java.[142][125]
- **Type-specific languages (TSLs).** A type controls how its literals parse, "hygienically". The type's TSL is "invoked only when a literal appears where a term of that type is expected, guaranteeing non-interference".[145] Security follows directly: user-supplied text is `String`, not `FormatString`, and "cannot be coerced, forcing format strings to be literals in program text".[142] The TSL paper motivates this with SQL injection and cross-site scripting.[145]
- **Pick 13.** `fs.scoped(…).read_only` is Wyvern's hierarchy. Non-transitivity says what a module holding only the narrowed capability can reach: nothing broader.
- **Q16.** The `java` FFI capability given only to the top-level script is Mo's `Platform`. The trusted-Java share is Mo's platform audit burden.
- **Q17.** A capability manifest should list the *narrowed* capability a package receives, following Wyvern's non-transitive definition, not the powerful one it was derived from ([[supply-chain-defenses]]).
- ⚠️ **Tension with [[q02-strings-and-interpolation|Q2]] ("every string interpolates").** If every string interpolates, a SQL or shell command gets built by splicing unless literals are typed. Wyvern's answer is literals whose type decides the parsing, so user text can never become the command.[145][142] This bears on `flows(...)` ([[p09-module-header-and-never|pick 9]]). Not resolved here.

## Limbo: module types checked again at load

- **What.** Limbo modules "are always loaded dynamically, at run time: the Limbo load operator fetches the code and performs run-time type checking". Programs are checked at compile time "and further when modules are loaded".[148] The did-not-win run calls this "a runtime-enforced contract at the plugin boundary", with WebAssembly component interfaces as today's analog.[142]
- **Pick 13.** No direct overlap. Mo passes authority statically.
- **Q16.** Platforms are native code linked into Mo's single binary. Checking a platform's declared interface at link time is the static equivalent.
- **Q17.** "Load time" for Mo is fetch and build time. The toolchain would re-check that a fetched package's `pub` signatures, contracts and capability manifest match the hashes that were reviewed, and refuse the build otherwise.

## E and the confused deputy

- **What.** Hardy's story: a compiler was given licence to write files in its own directory, so it could record usage statistics. A user named the billing file as the compiler's debug-output file, and "the billing information was lost". The compiler's code was correct. It "became wrong when we added home files license".[147] The object-capability answer is a reference that "indivisibly combines designation of the object, permission to access it, and the means to access it". Even so, forwarding *information* stays possible, and covert channels are out of scope.[125]
- **Pick 13.** Mo is a deputy wherever a process holds a broad capability and acts on a *name* someone else supplies, such as `fs.write(msg.path, …)`. The fix is the E move: take a narrowed capability or a handle, not a path string.
- **Q16.** Platform APIs that take handles rather than names shrink the deputy surface.
- **Q17.** A closure that captures a capability and is handed to a "needs: nothing" package is a deputy in type form ([[koka]]).

## What this lineage adds, in one list

- Newspeak and Wyvern: authority arrives as arguments to *modules*, not only to functions, so a module's capabilities can be read off its factory signature.
- Joe-E: the stdlib and platform are the tamed library, and taming is a review job.
- Wyvern: non-transitive authority makes capability manifests precise, and typed literals end injection.
- Limbo: re-check interfaces and manifests at the boundary where foreign code enters.
- E and Hardy: pass capabilities, not names.

## Related

- [[hermes-daily-2026-09-17]] — Hermes follow-up on storage crash consistency and capability API boundaries.
- [[landscape-second-lane]]
- [[p13-capabilities-and-logging]]
- [[q16-escape-hatch]]
- [[q17-package-management-and-supply-chain]]
- [[supply-chain-defenses]]
- [[austral]]
- [[koka]]

## Sources

[125] raw/research-runs/supply-chain-defenses-survey.pplx.md — Robert's research run: A Survey of Software Supply-Chain Defenses (Perplexity, Q17 prompt 2, 12 Sep 2026)
[142] raw/research-runs/pl-ideas-that-did-not-win.pplx.md — Robert's research run: Programming Language Ideas That Did Not Win (Perplexity, landscape prompt 2)
[143] https://bracha.org/newspeak-modules.pdf — Modules as Objects in Newspeak (Bracha et al., ECOOP 2010)
[144] https://www.ndss-symposium.org/wp-content/uploads/2017/09/met.pdf — Joe-E: A Security-Oriented Subset of Java (Mettler, Wagner, Close; NDSS 2010)
[145] https://www.cs.cmu.edu/~aldrich/papers/ecoop14-tsls.pdf — Safely Composable Type-Specific Languages (Omar et al., ECOOP 2014)
[146] https://potanin.github.io/files/MelicherShiPotaninAldrichECOOP2017.pdf — A Capability-Based Module System for Authority Control (Melicher, Shi, Potanin, Aldrich; ECOOP 2017)
[147] https://www.cs.utexas.edu/~witchel/380L/papers/hardy88confused.pdf — The Confused Deputy (Norm Hardy, 1988)
[148] https://www.vitanuova.com/inferno/papers/descent.pdf — A Descent into Limbo (Brian Kernighan)
