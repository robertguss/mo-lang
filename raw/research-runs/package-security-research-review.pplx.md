# Language-Based Security for Package Dependencies: A Literature Review (2019–2026)

## Object-Capability Security Applied to Package/Dependency Management

**NODESENTRY** proposes that third-party JavaScript libraries in Node.js
applications should never receive ambient authority over their host environment,
since a single vulnerable dependency can compromise an entire server. The
authors built a policy-enforcement architecture that wraps every dependency in
mediating proxies, letting operators attach web-hardening and access-control
policies to the interactions between libraries and their environment, including
transitive dependencies
([Massacci et al., _Security and Communication Networks_, 2019](https://downloads.hindawi.com/journals/scn/2019/9629034.pdf)).
Performance and security evaluation showed the wrapping approach can intercept
and restrict library behavior with acceptable overhead, making it the first
dedicated security architecture for server-side JavaScript library integration
([Massacci et al., 2019](https://downloads.hindawi.com/journals/scn/2019/9629034.pdf)).

**Gobi** argues that language-level sandboxes for third-party libraries have
historically depended on fragile, vendor-specific technology (e.g., Google's
discontinued NaCl), leaving projects orphaned, while WebAssembly's inherently
capability-oriented, import/export-based module interface offers a durable,
browser-vendor-backed alternative for confining native libraries. The authors
built a Wasm-based software-fault-isolation toolchain for sandboxing C/C++
libraries and evaluated it against existing SFI systems for compatibility and
performance
([Narayan et al., 2019](https://arxiv.org/ftp/arxiv/papers/1912/1912.02285.pdf)).
They conclude that Wasm can support practical, high-performance library
sandboxing today, and issue a call to the Wasm and SFI research communities to
formally support module sandboxing as a first-class use case
([Narayan et al., 2019](https://arxiv.org/ftp/arxiv/papers/1912/1912.02285.pdf)).

**Sandboxing Adoption in Open Source Ecosystems** claims that although OS-level
sandboxing primitives such as Seccomp, Landlock, Pledge, Unveil, and Capsicum
embody least-privilege, capability-like confinement for software components,
their direct adoption across open-source packages is minimal. The authors
statically searched the full source trees of Debian, Fedora, OpenBSD, and
FreeBSD (over 164,000 packages combined) for calls to each mechanism's API,
manually verifying matches to exclude tests, documentation, and comments
([Larsen & Kroah-Hartman (or equivalent authors), 2024](http://arxiv.org/pdf/2405.06447.pdf)).
They found that fewer than 1% of packages directly invoke a sandboxing API, and
that adoption barriers include the effort of enumerating an application's
syscalls/file access, mechanism complexity, the need to restructure applications
into multiple processes, and difficulty debugging sandbox violations
([2024](http://arxiv.org/pdf/2405.06447.pdf)).

## Language-Level Permission Systems for Third-Party Code

**Mir** claims that third-party JavaScript libraries routinely run with far more
privilege than they need, and that this excess privilege is exploitable even
when a library is merely buggy rather than actively malicious. The system
augments Node.js's module loader with a read/write/execute/import (RWXI)
permission model, automatically infers each library's required permissions via
flow-sensitive intraprocedural static analysis of how consuming code uses it,
and enforces the inferred permissions at runtime through load-time source and
context transformations
([Vasilakis et al., _MIR: Automated Quantifiable Privilege Reduction_, 2021](https://arxiv.org/pdf/2011.00253.pdf)).
The evaluation introduces a quantitative privilege-reduction metric and
demonstrates that a library subverted at runtime cannot exploit functionality
outside its inferred permission set, though permissions are inferred
automatically rather than declared by the library author
([Vasilakis et al., 2021](https://arxiv.org/pdf/2011.00253.pdf)).

**Containing Malicious Package Updates in npm with a Lightweight Permission
System** claims that automatic installation of minor/patch npm updates combined
with unrestricted application-level privilege lets a single malicious update
compromise a dependent application, even though most packages only need trivial
computation and no access to the filesystem, network, or OS processes. The
authors designed a four-permission model (network, filesystem, process, and an
"all" superset for metaprogramming) that package owners manually declare before
publishing, enforced npm-side with under 100 lines of runtime `require` wrapping
plus static rewriting of unsafe property accesses, and evaluated it against a
February 2018 snapshot of 703,457 npm packages and three real supply-chain
incidents (`eslint-scope`, `event-stream`, `electron-native-notify`)
([2021](https://arxiv.org/pdf/2103.05769.pdf)). They found that 31.9% of npm
packages could be fully protected under the model with negligible (much less
than 1%) runtime overhead, and argued that even a modest attack-surface
reduction enacted broadly would meaningfully cut security-review burden and
attacker opportunity ([2021](https://arxiv.org/pdf/2103.05769.pdf)).

**Designing with Static Capabilities and Effects: Use, Mention, and Invariants**
claims that static reference capabilities and type-and-effect systems are two
different technical routes to the same underlying goal — statically bounding
what a piece of code, including untrusted library code, is permitted to do — and
that the choice between them hinges on a fundamental "use–mention" precision
trade-off. The paper is an expository/analytical comparison (not an implemented
system) that formally contrasts how capability possession, which merely proves
code _could_ exercise an authority, differs from effect typing, which reasons
about whether code _actually exercises_ that authority in a security-relevant
way ([Xu, 2020](https://arxiv.org/pdf/2005.11444.pdf)). It concludes that
capabilities are preferable for reasoning about un-inspectable code (e.g.,
precompiled or dynamically loaded libraries) and global invariants over
shared/aliased objects, while effect systems are preferable when the use–mention
distinction matters, and that seemingly minor type-system choices such as
weakening and the structure of type contexts materially affect capability-based
reasoning's precision ([Xu, 2020](https://arxiv.org/pdf/2005.11444.pdf)).

## Information-Flow Control for Libraries

**DepSec** claims that dependent types strictly increase the expressiveness of
static information-flow-control (IFC) libraries relative to prior
state-of-the-art systems such as MAC, particularly for expressing data-dependent
security policies and fine-grained declassification. The authors implemented
DepSec as a library in the dependently typed language Idris, representing
sensitivity as part of the type itself (`Labeled ℓ a` for tagged values,
`DIO ℓ a` for secure computations over a verified join-semilattice of labels),
and formalized the design as a call-by-value calculus (TTsec) with a proof of
progress-insensitive noninterference
([Buiras et al., 2019](https://arxiv.org/pdf/1902.06590.pdf)). They demonstrate
that DepSec matches the expressiveness of a special-purpose dependent IFC type
system on a benchmark conference-management case study while supporting policies
parameterized by an abstract, statically enforced declassification rule
governing _what_, _who_, and _when_ data may be released
([Buiras et al., 2019](https://arxiv.org/pdf/1902.06590.pdf)).

**Cocoon** claims that mainstream imperative languages have lacked a static,
type-based IFC mechanism that works with an unmodified compiler, making
fine-grained secrecy enforcement for third-party or untrusted code impractical
to deploy in real Rust codebases. The authors built Cocoon as a pure Rust
library that wraps sensitive values in a `Secret<Type, Label>` type, uses
procedural macros and Rust's ownership/mutability/auto-trait system to confine
`secret_block!` regions so they can only call side-effect-free or explicitly
allow-listed functions, and requires explicit `declassify` calls (treated as
part of the trusted computing base) to let secrets flow to lower-secrecy
contexts ([2024](https://arxiv.org/pdf/2311.00097.pdf)). The paper reports that
Cocoon can be incrementally adopted in existing Rust programs, enforces
termination-insensitive noninterference through ordinary compilation (a program
that would leak a secret simply fails to compile), and imposes no detectable
runtime or memory overhead at the cost of increased compile time
([2024](https://arxiv.org/pdf/2311.00097.pdf)).

**Static Information Flow Control Made Simpler** claims that existing static IFC
systems have seen little real-world use because they force programmers to reason
about label lattices and separate confidentiality/integrity semantics, and
proposes instead that developers declare direct source-to-destination flow
prohibitions (e.g., `flow mod network_io ->! mod db_handle`) over the program's
own data and modules. The system extends Rust's type system (formally, the Oxide
model of Rust), leveraging Rust's existing borrow-checker pointer analysis, and
supports uniform confidentiality/integrity policies, incremental partial
specifications, and specificity-based rule overriding
([2022](https://arxiv.org/pdf/2210.12996.pdf)). The paper presents the design
and its formal properties rather than a large-scale empirical evaluation,
arguing that unifying confidentiality and integrity into simple, composable flow
declarations makes IFC more accessible while retaining expressive power for
library- and module-boundary policies
([2022](https://arxiv.org/pdf/2210.12996.pdf)).

**An Empirical Study of Information Flows in Real-World JavaScript** claims that
dynamically tracking implicit information flows (not just explicit taint) is
theoretically important for catching subtle leaks from third-party or vulnerable
code but has an uncertain practical payoff. The authors ran four dynamic IFC
monitoring strategies (taint tracking, observable tracking,
no-sensitive-upgrade, and permissive-upgrade) built on the Jalangi
instrumentation framework over 56 real-world JavaScript programs (including 19
vulnerable Node.js modules) spanning injection, ReDoS, buffer, and
fingerprinting/history-sniffing vulnerability classes
([Hedin et al., 2019](http://arxiv.org/pdf/1906.11507.pdf)). They found that
tracking implicit flows is costly in permissiveness, label creep, and runtime
overhead, that lightweight explicit taint tracking suffices for most of the
studied vulnerabilities, and that no evidence emerged that tracking _hidden_
implicit flows caught security problems missed by cheaper analyses — leaving
cost-effective implicit-flow analysis an open research problem
([Hedin et al., 2019](http://arxiv.org/pdf/1906.11507.pdf)).

## Measuring the Attack Surface of Package Registries

**Small World with High Risks** claims that npm's densely interconnected
dependency and maintainer graph means that a small number of compromised
packages or maintainer accounts can propagate malicious or vulnerable code to a
large fraction of the ecosystem, making recent incidents symptomatic of a
systemic problem rather than isolated events. The authors built dependency
graphs from a snapshot of 5,386,239 package releases across 676,539 packages
(observation window ending April 2018) and analyzed five distinct threat models
— malicious packages, unmaintained legacy code, package takeover, account
takeover, and maintainer collusion
([Zimmermann et al., _USENIX Security_, 2019](https://arxiv.org/pdf/1902.09217.pdf)).
They found that legacy/unmaintained dependencies and locked version ranges keep
applications exposed to known-vulnerable code for years, and that concentrated
maintainer influence over the dependency graph creates disproportionate systemic
risk, motivating mitigations such as vetted maintainers, transitive-dependency
awareness tooling, and vulnerability warnings
([Zimmermann et al., 2019](https://arxiv.org/pdf/1902.09217.pdf)).

**Towards Measuring Supply Chain Attacks on Package Managers for Interpreted
Languages** claims that package registries for interpreted languages (PyPI, npm,
RubyGems) have structural security gaps and misplaced trust relationships that
enable supply-chain attacks, given their near-total absence of publish-time
review. The authors built a comparative qualitative framework across the three
ecosystems' functionality, review processes, stakeholders, and attack vectors,
then developed MALOSS, a metadata/static/dynamic-analysis vetting pipeline
(using Docker-and-Sysdig-based execution tracing across install, import,
embedded-binary, and functional code paths) validated against a hand-collected
corpus of 312 real-world reported supply-chain attacks tracked since 2018
([Duan et al., 2020](https://arxiv.org/pdf/2002.01139.pdf)). The paper's
contribution is explicitly the measurement framework and vetting pipeline rather
than new program-analysis techniques, positioned to surface as-yet-undetected
malicious packages and inform concrete registry-security improvements
([Duan et al., 2020](https://arxiv.org/pdf/2002.01139.pdf)).

**I Know What You Imported Last Summer** claims the PyPI ecosystem has severe,
exploitable security weaknesses stemming from arbitrary code execution during
install/import, concentrated "reach" among a small set of packages and
maintainers, and rampant package impersonation. The authors combined a scraped
PyPI metadata graph (206,296 packages, 1,554,933 releases, 387,867 maintainers,
230,566 dependency edges) loaded into Neo4j with CVE/Safety-DB vulnerability
data, `setup.py` script analysis, and typosquatting/impersonation pattern
matching ([2021](https://arxiv.org/pdf/2102.06301.pdf)). They found that 0.39%
of packages import other code at install time and 0.28% execute non-standard
install functions (both exploitable vectors, demonstrated live against a
vulnerable `setup.py`), that a Django vulnerability-propagation case study
showed slow downstream patching, and that defensive typosquat registration
(e.g., by Amazon) is already an ad hoc mitigation in practice
([2021](https://arxiv.org/pdf/2102.06301.pdf)).

**A Survey on Common Threats in npm and PyPi Registries** claims that because
these open registries let any email-verified user publish packages with minimal
scanning, and because heavy code reuse and interdependency amplify blast radius,
npm and PyPI face a well-defined menu of recurring threats — typosquatting,
combosquatting, account compromise, trivial "micropackages," and technical lag.
The paper is a literature-based survey (no new experiments or developer study)
that compiles prior empirical findings on threat prevalence and proposes largely
untested, ML-oriented countermeasures such as anomaly-based detection and
maintainer trust scoring ([2021](https://arxiv.org/pdf/2108.09576.pdf)). The
authors conclude that because these ecosystems fundamentally depend on volunteer
maintainers and open access, residual risk cannot be eliminated, but structural
measures like mandatory multi-factor authentication and maintainer/package trust
scores could meaningfully reduce it
([2021](https://arxiv.org/pdf/2108.09576.pdf)).

**What are Weak Links in the npm Supply Chain?** claims that specific,
measurable package-metadata signals — such as an expired maintainer domain or
the presence of an install script — indicate elevated exposure to supply-chain
attack and can be used proactively to triage dependency risk. The authors
collected a snapshot of 1,630,101 `package.json` manifests (June 7, 2021),
derived six candidate weak-link signals (expired maintainer domain, install
scripts, unmaintained status, too many maintainers, too many contributors, and
overloaded maintainers), and validated the signals with a survey of 470 npm
package maintainers after excluding 135,996 packages with no dependents and no
license/repository/maintenance signal
([Zimmermann et al., 2022](http://arxiv.org/pdf/2112.10165.pdf)). Three of the
six proposed signals were confirmed as strong risk indicators by the maintainer
survey, and respondents suggested eight additional weak-link signals not
originally proposed, yielding a metadata-driven framework other researchers and
tool builders can extend ([2022](http://arxiv.org/pdf/2112.10165.pdf)).

**Backstabber's Knife Collection** claims that no prior work had systematically
catalogued _malicious_ (as opposed to merely vulnerable) open-source packages
used in real attacks, leaving the community without a grounded empirical basis
for defenses against supply-chain code injection. The authors manually curated
and analyzed a dataset of malicious packages found via the Snyk database,
security advisories, and research blogs across npm, Maven Central, PyPI,
Packagist, and RubyGems (collected mid-2019, updated January 2020), building two
attack trees covering how malicious code is injected into dependency trees and
how it is triggered at test-, install-, or run-time
([Ohm et al., 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7338168/)). Of 469
identified malicious packages, 174 had at least one affected version
successfully retrieved for manual analysis (59 were researcher proofs-of-concept
and excluded), producing a labeled, publicly reusable ground-truth dataset for
training and evaluating malicious-package detectors
([Ohm et al., 2020](https://pmc.ncbi.nlm.nih.gov/articles/PMC7338168/)).

## Papers Proposing Manifest- or Type-Signature-Visible Permissions

Three papers in this set specifically design permissions or security policy to
be visible in a static, inspectable artifact rather than left implicit at
runtime:

- **Containing Malicious Package Updates in npm with a Lightweight Permission
  System** ([2021](https://arxiv.org/pdf/2103.05769.pdf)) is the clearest
  manifest-based design: package owners manually declare required permissions
  (network, filesystem, process, all) before publishing, package consumers can
  see a dependency's declared permissions in the npm repository before
  installing it, and package managers are expected to block silent permission
  escalation on update, requiring explicit user confirmation instead.
- **DepSec** ([2019](https://arxiv.org/pdf/1902.06590.pdf)) makes
  information-flow policy part of the type signature itself: values are wrapped
  in dependent types (`Labeled ℓ a`, `DIO ℓ a`) whose security label `ℓ` is a
  first-class, statically checked component of the type, so a function's
  signature reveals the sensitivity level(s) it operates over.
- **Cocoon** ([2024](https://arxiv.org/pdf/2311.00097.pdf)) follows the same
  type-signature pattern in Rust: sensitive values are wrapped in
  `Secret<Type, Label>`, so the secrecy label is visible directly in a value's
  or function's type, and any flow that would violate the declared label causes
  a compile error rather than a runtime check.

By contrast, **Mir** ([2021](https://arxiv.org/pdf/2011.00253.pdf)) infers a
library's RWXI permissions automatically from static usage analysis rather than
having the library declare them in a manifest or type, and **Static Information
Flow Control Made Simpler** ([2022](https://arxiv.org/pdf/2210.12996.pdf))
declares flow policy at the module/variable level in source code (a
policy-as-code approach) rather than embedding it in the type signature or a
separate manifest file — an adjacent but distinct design point worth noting
alongside the three flagged papers above.
