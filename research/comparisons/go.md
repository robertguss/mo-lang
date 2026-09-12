---
title: "Mo vs Go"
created: 2026-09-12
updated: 2026-09-12
type: comparison
tags: [research, laws, security]
sources: [raw/articles/pike-go-at-google-2012.md, raw/articles/go-error-syntax-2025.md, raw/articles/go-1-27-released.md, raw/articles/go-1-18-released.md, raw/articles/go-type-parameters-proposal.md, raw/articles/go1-compat-promise.md, raw/articles/go-supply-chain-mitigations.md, raw/articles/go-module-mirror-launch.md, raw/articles/go-sumdb-proposal.md, raw/articles/socket-boltdb-go-typosquat.md, raw/articles/cox-our-software-dependency-problem.md, raw/papers/tu-go-concurrency-bugs-asplos19.md, raw/articles/go-developer-survey-2025.md, raw/articles/go-testing-time-synctest.md]
confidence: medium
---

# Mo vs Go

**One line:** the model for "simplicity by law", a batteries-included stdlib, and concurrency at the edges ([[d12-concurrency-at-the-edges|direction 12]]); on the list to pin down *precisely* what Go's discipline is, and what its module system offers [[q17-package-management-and-supply-chain|Q17]].

## What it is (status as of Sep 2026)

Go was conceived at Google in late 2007 for server software of tens of millions of lines, where builds took "many minutes, even hours".[16] Go 1.27 shipped on 19 August 2026. It added generic methods, `encoding/json/v2`, and a generally available goroutine-leak profile.[12] Programs written for Go 1 are intended to "continue to compile and run correctly, unchanged".[17] In the 2025 survey, 91% of respondents were satisfied, and almost two thirds were "very satisfied".[22]

## The ideas, one by one

- **Discipline enforced by tools, not taste.** `gofmt` gives every program one layout. Because it reformats from the parse tree, it also enabled rewrites like `gofmt -r 'a[b:len(a)] -> a[b:]'` and `gofix`, which migrated the whole tree before Go 1.[16] An unused import is "a compile-time error (not a warning, an error)". The grammar has 25 keywords, and default arguments were left out on purpose.[16] Go 1.27 still ships new `go fix` modernizers.[12]
  - *Mo today:* one formatter resolves "one way to write each thing" ([[d26-developer-and-agent-happiness|direction 26]]). Errors only, no warnings ([[q09-compiler-diagnostics|Q9]]). Unused bindings are errors ([[p03-bindings|pick 3]]).
  - *Verdict:* **already have** the formatter and error-not-warning rules. **Steal** `gofix`: a rewriter that ships with every language change.

- **Saying no, for a decade.** Generics arrived in Go 1.18, in March 2022.[23] Constraints must be declared, not derived from the body, because otherwise "a minor change … might change the constraints". The design has no compile-time metaprogramming.[20] The cost is visible: 28% of 2025 respondents said "a feature I value from another language isn't part of Go". 65% said their next-favorite language has type-safe enums.[22]
  - *Mo today:* generics with explicit `where T: Comparable` bounds, and enums with data from day one ([[p15-methods-traits-generics|pick 15]], [[d22-rust-plus-refinements-types|direction 22]]).
  - *Verdict:* **already have** explicit bounds, for Go's reason. **Reject** omitting enums: Go's own survey shows it is the complaint.

- **Errors as values, and a failed decade of sugar.** `if err != nil` topped the survey complaints for years. The Go team tried `check`/`handle` (2018), `try` (2019, about 900 comments) and `?` (2024). In June 2025 it stopped pursuing error syntax altogether.[11] `try` was rejected because it returned "from potentially deeply nested expressions, thus hiding this control flow". The team now says a keyword "restricted … to assignments and statements" might have worked.[11]
  ```go
  x, err := strconv.Atoi(a)
  if err != nil {
      return err
  }
  ```
  - *Mo today:* `try` prefix, the only propagation, no unwrap ([[p06-results-and-propagation|pick 6]]). Rain and bugs never cross ([[d18-two-kinds-of-failure|direction 18]]).
  - *Verdict:* **already have**, and Go's post-mortem sharpens it. "If Go had introduced specific syntactic sugar for error handling early on, few would argue over it today."[11] Mo is early.

- **Goroutines, channels, and shared memory together.** A study of 171 concurrency bugs in Docker, Kubernetes, gRPC and three other projects found more than half caused by Go-specific problems. 85 were blocking and 86 non-blocking. 105 came from shared-memory protection and 66 from message passing.[21] Go 1.27's goroutine-leak profile detects permanently blocked goroutines after the fact.[12]
  - *Mo today:* no mutexes or shared state ([[d14-processes-are-the-only-identity|direction 14]]). `ask` requires `within:` ([[d17-mandatory-deadlines|direction 17]], [[q07-process-api|Q7]]).
  - *Verdict:* **already have**. Mo removes the shared-memory class by construction and unbounded waits by law. The message-passing class remains, which is why the mailbox question below matters.

- **Deterministic time in tests (`synctest`).** A test runs in a "bubble" with a fake clock. Time advances only when every goroutine in the bubble is durably blocked. The package became generally available in Go 1.25.[24]
  - *Mo today:* `Mo.Sim`, a platform that makes everything deterministic, swapped in with one `use` line ([[q11-platform-and-stdlib|Q11]]).
  - *Verdict:* **already have**, more broadly. **Steal** the exact rule: virtual time advances only when every process is blocked.

- **Modules built against tampering.** Every build is "locked" by `go.mod`, and minimal version selection picks the versions that dependencies declared, not the latest. `go.sum` hashes are checked against a global append-only checksum database.[19] That database is a Merkle-tree transparency log.[13] Authors need no registry account or keys, because the VCS is the source of truth. "Neither fetching nor building code will let that code execute."[19] The Go team also admits "there is no security boundary within a build".[19]
  - *Mo today:* [[d30-supply-chain-security|direction 30]] and [[q17-package-management-and-supply-chain|Q17]]: capabilities as package permissions, no install scripts or build-time code.
  - *Verdict:* **steal** locked builds, a transparency log, and no execution at fetch or build (a Q17 input, not a design). Mo's capabilities are the in-build boundary Go says it lacks.

- **The hole: immutable caches of malicious code.** `github.com/boltdb-go/bolt`, a typosquat of BoltDB with a remote-access backdoor, was cached by the Go module mirror. The attacker then rewrote the Git tag to point at clean code, so GitHub showed nothing wrong while the mirror kept serving the backdoor. It went unnoticed for about three years.[15] 26% of survey respondents named "finding trustworthy Go modules" a top frustration.[22]
  - *Mo today:* nothing yet. Q17 lists typosquat resistance as an open sub-question.
  - *Verdict:* **open**. The lesson for Q17 is that people must review the bytes that get hashed, not the VCS view.

## What it gives up

- **Expressiveness.** No sum types, nil pointers, unchecked `err`. Survey quotes ask for all three.[22] Mo does not accept this ([[q05-option-and-no-nil|Q5]]).
- **A garbage collector in every binary.** Go accepts the GC; Mo plans Perceus-style reference counting instead ([[d10-immutable-by-default|direction 10]]).
- **Speed of evolution.** About twelve years from the 2009 release to generics, and four more to generic methods.[23][12] Mo will pay this once it makes a stability promise, but not before.
- **An in-build security boundary.** Any package can run `init`.[19] Mo rejects this cost.

## Evidence

- **Build pain that motivated Go:** a 2007 Google binary took 45 minutes to build; in 2012 the same program took 27. Go's source fanout measured 40X, about fifty times better than C++.[16]
- **Satisfaction:** 91% satisfied in 2025. The top frustrations were idioms (33%), a missing feature (28%), and trustworthy modules (26%).[22]
- **Concurrency bugs:** 171 bugs, split roughly evenly between blocking and non-blocking.[21]
- **Supply chain:** one backdoored module persisted in the mirror for about three years.[15]
- **LLM benchmarks for Go:** none gathered this pass.

## What Mo should take from this

- **Proposal:** `mo fix` from the first release. Every language change ships with a rewriter, the `gofix` precedent.[16] A zero-corpus language will change often before v1, and agents can run rewriters but can't absorb folklore.
- **Question for Robert:** restrict `try` to the head of a binding or statement (`x = try …`, `try save(…)`), never nested inside an expression? That is Go's own post-mortem on why `try` failed.[11] Mo's examples already use only those positions.
- **Proposal:** `Mo.Sim` advances virtual time only when every process is blocked, taken from `synctest`.[24]
- ⚠️ **Tension between [[q07-process-api|Q7]] and [[d04-style-rules-become-laws|direction 4]]:** "`send` never blocks or fails" implies an unbounded mailbox. Power of Ten–style laws want a bound on everything. A bound makes `send` either block or return rain. Not resolved here.
- **Q17 inputs, not recommendations:** locked builds with minimal version selection, a transparency log, no execution at fetch or build, and the BoltDB lesson (review the hashed bytes).[19][15]
- **Question for Robert:** a Go-style compatibility promise at Mo v1, with a per-module language-version line so new keywords can arrive without breaking old code?[11][17]
- **Proposal:** a keyword budget as a law number ([[q12-law-numbers|Q12]] style). Go has 25.[16]

## Related
- [[language-landscape]]
- [[elixir]]
- [[d12-concurrency-at-the-edges]]
- [[d23-compile-speed-first-class]]
- [[d30-supply-chain-security]]
- [[q11-platform-and-stdlib]]
- [[q17-package-management-and-supply-chain]]
- [[p06-results-and-propagation]]

## Sources

[11] https://go.dev/blog/error-syntax — [ On | No ] syntactic support for error handling (Go blog, 2025)
[12] https://go.dev/blog/go1.27 — Go 1.27 is released
[13] https://go.dev/blog/module-mirror-launch — Module Mirror and Checksum Database Launched (Go blog)
[15] https://socket.dev/blog/malicious-package-exploits-go-module-proxy-caching-for-persistence — Malicious package exploits Go Module Proxy caching (Socket)
[16] https://go.dev/talks/2012/splash.article — Go at Google: Language Design in the Service of Software Engineering (Pike)
[17] https://go.dev/doc/go1compat — Go 1 and the Future of Go Programs
[19] https://go.dev/blog/supply-chain — How Go Mitigates Supply Chain Attacks (Go blog)
[20] https://go.googlesource.com/proposal/+/HEAD/design/43651-type-parameters.md — Type Parameters Proposal (Go)
[21] https://songlh.github.io/paper/go-study.pdf — Understanding Real-World Concurrency Bugs in Go (Tu et al., ASPLOS 2019)
[22] https://go.dev/blog/survey2025 — Results from the 2025 Go Developer Survey
[23] https://go.dev/blog/go1.18 — Go 1.18 is released (generics)
[24] https://go.dev/blog/testing-time — Testing Time (and other asynchronicities) — Go synctest
