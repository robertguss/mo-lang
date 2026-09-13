---
tool: Perplexity
prompt: prompts-mo-parallel-tracks / prompt 2 (ecosystem and stdlib depth)
run: 2026-09-13
run_by: Claude (via Perplexity session 45e714aa)
session_url: https://www.perplexity.ai/computer/tasks/45e714aa-c96f-42ea-9ee3-13b9bc6621ff
sha256: 2fcdeac6af1c27a85b34877a34791eb73cafd6012c6ba2c15b51c375c1901e5e
---
# Ecosystem, Standard Library, and Platform Depth for a New Programming Language

A research report on stdlib and ecosystem strategy for a language whose primary authors are AI agents and whose customers are engineering teams building production services.

The report has eight parts. Parts 1–7 are evidence. Part 8 is opinion, per the brief.

---

## Executive framing

Three findings dominate everything that follows.

First, the historical record is unambiguous that shipped, first‑party primitives that get real production traffic beat second‑party frameworks every time, but only when the language enforces the primitives long enough that a real ecosystem accretes on top of them. Go's `net/http`, `encoding/json`, and `database/sql` are 15 years old and still the load-bearing base of virtually every Go service; Go's stdlib itself is deliberately versioned so aggressively that a v2 of `encoding/json` took 14 years and was still considered a big deal ([Yoshi Yamaguchi, *The 14-Year Road to encoding/json/v2*](https://www.ymotongpoo.com/books/go-json-v2-history/)).

Second, first‑party _extensions_ to the stdlib in the form of official frameworks and "kits" — Phoenix's `mix phx.gen.auth`, Rails scaffolds, Laravel's starter kits, and shadcn/ui's copy‑paste registry — are what actually move ecosystems from "toy" to "production‑viable." They also happen to be exactly the mechanism a language for agent authors most needs, because they turn brittle transitive dependencies into inspectable, agent‑editable source code inside the user's repo ([shadcn/ui, *Introduction*](https://ui.shadcn.com/docs); [Phoenix, `mix phx.gen.auth`](https://hexdocs.pm/phoenix/mix_phx_gen_auth.html); [Laravel 12.x, *Starter Kits*](https://laravel.com/docs/12.x/starter-kits)).

Third, the 2023–2026 supply‑chain record has made "how a package gets in" as important as "what the package is." Go's mandatory checksum database achieved 100% coverage on day one; npm provenance reached only 34.1% coverage of the top 10,000 packages by weekly downloads two and a half years after launch ([Safeguard, *npm Provenance Adoption: Late 2025 Review*](https://safeguard.sh/resources/blog/npm-provenance-adoption-tracking-late-2025)); PyPI Trusted Publishers reached ~25% of monthly file uploads by October 2025 ([PyPI blog, *Trusted Publishers coming to organizations*](https://blog.pypi.org/posts/2025-11-10-trusted-publishers-coming-to-orgs/)). Defaults win. Opt‑in loses.

The remainder of this document works through the evidence.

---

## Part 1: The historical record of stdlib and platform strategies

### Go — batteries included, retrofitted where needed

Go's original stdlib shipped `net/http`, `encoding/json`, `database/sql`, `crypto/*`, `io`, `sync`, `fmt`, `os`, `net`, and a small collection of utility packages. Fifteen years later those same packages remain the backbone of nearly every Go service. `database/sql` is still the abstraction, `net/http`'s `ServeMux` gained method+path matching only in Go 1.22, and `encoding/json/v2` was formalized for Go 1.27 after 14 years of unfixable v1 problems including case‑insensitive field matching that broke security expectations ([*The 14-Year Road to encoding/json/v2*](https://www.ymotongpoo.com/books/go-json-v2-history/); [`encoding/json` package docs](https://pkg.go.dev/encoding/json)).

Two Go decisions are worth pulling out explicitly.

**`context` as a retrofit.** The `context` package landed in `golang.org/x/net/context` in July 2014 and moved into stdlib only in Go 1.7 (August 2016) ([Go blog, *Go Concurrency Patterns: Context*](https://go.dev/blog/context)). It solved deadline/cancellation/request‑scoped values across API boundaries, and because Go had no async colour, retrofitting it required almost every long‑running function in the ecosystem to be re‑signatured. The lesson: cancellation is not optional and cannot be bolted on later without churning every library.

**Modules were late and painful.** Russ Cox proposed `vgo` on 20 February 2018 ([Russ Cox, *Go += Package Versioning, Part 1*](https://research.swtch.com/vgo-intro)) after five years of `GOPATH`, and years of `dep`, `glide`, `godep`, and `gopkg.in` competing. Modules landed as experimental in Go 1.11 (August 2018) and default in Go 1.16 (February 2021). The Go team then made two structural bets: the module proxy (`proxy.golang.org`) and the checksum database (`sum.golang.org`). Both are default‑on and _cannot_ be opted out of by an individual dependency; the client always verifies against the transparency log ([Go Modules Reference, *Checksum database*](https://go.dev/ref/mod#checksum-database)).

Despite the "batteries included" reputation, third‑party de facto standards exist and matter: Gin/Echo/Chi for routing ergonomics, `sqlx` and Bun for query helpers, `pgx` for Postgres, `zap`/`zerolog`/`slog` for structured logging (`slog` moved to stdlib in Go 1.21), `viper` for configuration, and `gorm` and `ent` for ORMs. The pattern: stdlib is the base; the community layers ergonomics.

### Rust — deliberately small std, load-bearing crates

Rust std is intentionally minimal. The `#![no_std]` attribute exists specifically so the same code can target embedded systems, and std is factored into `core`, `alloc`, and `std` for that reason ([Wikipedia, *Rust*](https://en.wikipedia.org/wiki/Rust_(programming_language))). Rust has never shipped an HTTP client, an HTTP server, an async runtime, or a database driver in std. The stability guarantee — "no breaking changes to std ever" — is why.

The consequences are visible in the crates.io ecosystem.

**`serde` as the load-bearing foundation.** Every Rust service depends on `serde` and `serde_json` for serialization; they are essentially _de facto_ std. The Rust team has considered pulling parts into std for a decade and has consistently declined.

**Async runtime fragmentation.** Rust chose stackless coroutines with a caller-supplied executor in 2017–2019. Tokio, `async-std`, `smol`, and `glommio` all shipped different runtimes. Tokio 1.0 (23 December 2020) explicitly ended the churn with a 5‑year support commitment for the 1.x branch and a "no Tokio 2.0 for at least 3 years" pledge ([Tokio blog, *Announcing Tokio 1.0*](https://tokio.rs/blog/2020-12-tokio-1-0)). `async-std` effectively wound down; Tokio won. But the design decision that `async fn` in traits, `Send` boundaries, and executor choice would be user‑facing continues to draw pointed criticism ([without.boats, *Why async Rust?*](https://without.boats/blog/why-async-rust/)). Rust's response has been to slowly stabilize AFIT, RPITIT, and related features, not to pick a runtime.

**HTTP stack.** `hyper` (low level) → `reqwest` (client) → `axum` and `actix-web` (server) is the modern stack. Axum was announced 30 July 2021 explicitly to reuse the `tower::Service` middleware trait, so middleware could be shared with `hyper` clients and `tonic` gRPC servers ([Tokio blog, *Announcing Axum*](https://tokio.rs/blog/2021-07-announcing-axum)). `actix-web` predated it and remains actively used. The lesson: even without picking a framework, Rust picked an ecosystem convention (`tower::Service`) that lets frameworks share middleware.

**Crypto.** `ring` (mostly BoringSSL-derived), `rustls` (a pure-Rust TLS implementation), `RustCrypto` traits and implementations, and `webpki`/`x509-parser` for cert handling. All third-party. All widely used. `rustls` is being adopted inside `curl` upstream, is used by AWS, and is Ferrocene's TLS choice.

**Databases.** `sqlx` (compile-time-checked SQL), `diesel` (typed query DSL), `sea-orm` (async ORM). No first-party driver. `pgx` in Go and `psycopg` in Python show what the alternative looks like — a language with a de facto driver ecosystem tends to have one clear best choice.

**crates.io scale.** As of October 2025 there are roughly 200,000–290,000 crates depending on how you count; lib.rs indexes 292,568 ([Lib.rs, *State of the Rust/Cargo crates ecosystem*](https://lib.rs/stats)). Downloads grow at ~2.7×/year and a single day peaked at 1.205 billion downloads. But 45.2% of crates have not been updated in more than two years and 41.5% are "one-shot" packages published once and never touched again ([Frank Denis, *The state of the Rust dependency ecosystem*](https://00f.net/2025/10/17/state-of-the-rust-ecosystem/)). Big number, sparse maintenance.

### Elixir / Phoenix / OTP — first-party opinions, community consolidation

Elixir extended Erlang's OTP. Erlang's OTP already gave the language `gen_server`, supervisors, `ETS`/`Mnesia`, `crypto`, `ssl`, `inets`, and hot code loading. Elixir added a modern build tool (`mix`), a testing framework (`ExUnit`), doctests, and a first-class metaprogramming story. As of Elixir 1.20 (3 June 2026) Elixir also has gradual typing built into the compiler ([Wikipedia, *Elixir*](https://en.wikipedia.org/wiki/Elixir_(programming_language))).

**Phoenix.** Written by Chris McCord, Phoenix sits on the `Plug` middleware library and the Cowboy HTTP server. Its most consequential architectural bet is **LiveView**, which pushes server-rendered HTML over WebSockets and reconciles DOM diffs on the client; the templating language is HEEx with HTML-aware compile-time checking. Phoenix's 1.8.0 release (5 August 2025) continues to be the de facto framework in the ecosystem ([Wikipedia, *Phoenix (web framework)*](https://en.wikipedia.org/wiki/Phoenix_(web_framework))).

**Generators.** `mix phx.gen.auth` generates a full authentication system as source code in the user's repo: user registration with email confirmation, magic-link login, opt-in passwords, and "sudo mode" for sensitive actions. The documentation is explicit that the code lives in the app "so you now have complete freedom to modify the authentication system," at the cost that generated code is not upgraded by future Phoenix releases ([Phoenix, `mix phx.gen.auth`](https://hexdocs.pm/phoenix/mix_phx_gen_auth.html)).

**Ecto.** The de facto data layer, wrapping SQL databases with changesets, migrations, transactions, and query DSL. It is _not_ Phoenix — a deliberate separation.

**Oban.** The de facto background job library. On Hex.pm as of September 2026 it shows 27,000,513 all-time downloads, 216,723 weekly, and 94 dependant packages ([Hex.pm, *oban*](https://hex.pm/packages/oban)).

**Broadway.** José Valim's data-ingestion framework built on GenStage. 13,892,979 all-time downloads and 56 dependants ([Hex.pm, *broadway*](https://hex.pm/packages/broadway)).

The Elixir pattern: OTP is the runtime primitive layer; the language adds ergonomics; Phoenix ships as a separate but blessed framework; and one library per domain (Ecto for data, Oban for jobs, Broadway for pipelines) reaches consensus without being nominally first-party.

### Node.js — small modules, real consequences

npm is the largest package registry by every measure. Sonatype's 2024 State of the Software Supply Chain reported 4.8 million npm projects and 48.8 million versions with 4.5 trillion download requests for 2023, growing 23% YoY in projects and 70% in downloads ([Sonatype, *SSCR 2024*](https://sonatype.com/hubfs/SSCR-2024/SSCR_2024-FINAL-optimized.pdf)). By April 2026 estimates put the registry at 3.2 million+ packages with 2.1 billion downloads per week; over 99% of open-source malware in 2025 targeted npm and 454,600+ new malicious packages were identified that year ([nullsec.news, *The State of npm in 2026*](https://nullsec.news/the-state-of-npm-in-2026-security-crisis-and-ecosystem-response)).

The historical incidents are worth naming because each moved the industry.

- **left-pad (March 2016).** An 11-line package (`left-pad`) was unpublished, breaking the CI pipelines of Babel, React, and thousands of other projects. The response was `npm unpublish` policy tightening.
- **event-stream (2018).** A malicious maintainer added a dependency (`flatmap-stream`) that stole cryptocurrency wallets. The response was a slow crawl toward 2FA and provenance.
- **ua-parser-js (October 2021).** Maintainer account takeover; injected crypto-mining and password stealers in three versions. Response: npm auto-enrolled top-100 package maintainers in 2FA.
- **colors.js / faker.js (January 2022).** Maintainer Marak Squires intentionally shipped a version that printed "LIBERTY LIBERTY LIBERTY" in infinite loops, breaking AWS CDK and countless CIs. There was no "response" beyond re-publishing the previous version — the language has no way to prevent a maintainer from doing whatever they want with their own package.
- **xz-utils (March 2024).** Not npm, but the single most sophisticated open-source supply-chain attack to date. Russ Cox's timeline documents "Jia Tan" cultivating maintainer trust from 29 October 2021 through commit access, eventually inserting a backdoor into liblzma that landed in sshd on Debian, Ubuntu, and Fedora ([Russ Cox, *Timeline of the xz open source attack*](https://research.swtch.com/xz-timeline)). Discovered by Andres Freund's `postgres` benchmark, publicly disclosed 29 March 2024. This is the moment "malicious releases signed by legitimate maintainers" moved from theory to observed practice.
- **Shai-Hulud (September 2025).** A self-propagating npm worm hit chalk, debug, and other top-100 packages. Adoption of Trusted Publishing then surged from ~40 packages/week to ~430/week ([Aikido, *Shai-Hulud was the best thing to happen to supply chain security*](https://www.aikido.dev/blog/shai-hulud-trusted-publishing)).

npm's design philosophy — small modules, no privileged position for stdlib because Node's stdlib is small — created the deepest dependency graphs in the industry and the deepest attack surface. Deno and Bun are reactions.

### Deno — clean-break ambition, npm-compatibility pivot

Deno launched with the pitch of no `node_modules`, URL-based imports, permission flags (`--allow-net`, `--allow-read`), TypeScript-first execution, and a curated standard library (`deno_std`). Every one of those bets was moderated:

- **URL imports.** Retained but supplemented; JSR (JavaScript Registry) launched in 2024 as a proper package registry with a slug-based module system, addressing the fact that "URL as import path" broke on registrar changes.
- **Permissions.** Retained; still opt-in and not enforced on npm modules once you enable npm compat.
- **`deno_std`.** Slowly deprecated in favour of individual `@std/*` packages on JSR.
- **Node compat.** Deno 1.44 (June 2024) added private npm registry support and dramatically expanded Node.js compatibility. Deno now ships with `node:` built-in support and treats npm modules as first-class ([Deno blog, *Deno 1.44*](https://deno.com/blog/v1.44)).

The takeaway: a clean break from an existing ecosystem cost more adoption than any of the security or ergonomic wins bought. The pivot to compatibility is now permanent.

### Bun — the aggressive batteries-included bet

Bun 1.0 shipped 8 September 2023, written in Zig using JavaScriptCore. The stated design is a "single, dependency-free binary" that is a runtime, package manager, test runner, and bundler ([Bun docs, *Welcome to Bun*](https://bun.sh/docs); [Wikipedia, *Bun*](https://en.wikipedia.org/wiki/Bun_(software))). Where Node ships a small stdlib, Bun ships:

- `bun:sqlite` — native SQLite bindings.
- `bun:test` — Jest-compatible runner.
- `bun:ffi` — a Foreign Function Interface.
- `Bun.serve()` — HTTP server, WebSocket server, and static file server.
- Native S3 and Postgres clients (S3 as `Bun.s3`, Postgres as `Bun.sql`).
- Native Redis (`Bun.redis`), Cloudflare R2, and other cloud store integrations announced through 2024–2025.

Bun stable is 1.4.2 as of September 2026. Every Bun release is a bet against the small-modules philosophy: the runtime aggressively absorbs what the community had been packaging.

Two important marketing-vs-reality checks:

- Node.js compatibility is _high but not complete_. `bun install` targeting an existing Node project usually works; some native modules and some corners of `node:test` do not.
- The "up to 30× faster than npm" comparison is real for cold installs on empty caches but usually more like 3–8× in normal use.

### Ruby on Rails / Laravel / Django — the "opinionated framework" model

Rails ships scaffolds (`rails generate`), Active Record, Action Cable, Action Mailer, and Action Text. The scaffolds are generators; the runtime pieces are dependencies. Its dominance in the Ruby ecosystem is total — Ruby is essentially "the Rails language" outside of infrastructure use.

Laravel followed Rails' template and then explicitly built a starter-kit distribution model. Laravel 12.x ships React, Vue, and Livewire starter kits with WorkOS AuthKit or Laravel Fortify, and generated frontend code including the shadcn/ui component library ([Laravel 12.x docs, *Starter Kits*](https://laravel.com/docs/12.x/starter-kits)). Jetstream (2020) and Breeze (2021) were the previous generation; Nova is the commercial admin panel.

Django ships an ORM, an admin, an auth system, and templating in stdlib. It uses ordinary Python packaging (`pip`) and has no equivalent to Rails' generator model.

The pattern common to all three: **first-party frameworks convert language adoption directly.** PHP without Laravel was a legacy language. Ruby without Rails is niche. Python's web share fluctuates but is materially driven by Django and Flask/FastAPI. First-party frameworks are the single most reliable ecosystem driver in the history of programming languages.

### Roc — the platform model, cautionary in execution

Roc's core design bet is that _the language has no I/O; platforms provide it_. An application depends on a platform (URL-imported), and the platform provides side effects ([Roc, *Platforms*](https://www.roc-lang.org/platforms)). Two platforms are official:

- `basic-cli` — a command-line platform.
- `basic-webserver` — a webserver platform built on Rust's `hyper` and `tokio` ([roc-lang/basic-webserver on GitHub](https://github.com/roc-lang/basic-webserver)).

The Roc docs list only these two platforms plus `builtins`, `plans`, and language reference stubs ([Roc docs](https://www.roc-lang.org/docs)). Years after the platform concept was formalized, the ecosystem has not filled in: there is no de facto Roc HTTP client, no Roc database driver, and community platforms are experimental. The design has philosophical clarity; the ecosystem has thin coverage.

The cautionary reading: platforms are a beautiful abstraction for a language that already has 10,000 users, and a coordination problem for a language that does not. The "platform" burden falls on people who would otherwise be writing applications.

### Zig — small language, evolving stdlib, async reset

Zig's stdlib is small and philosophically consistent. Every allocator is explicit; "no allocations are performed inside Zig's standard library" and the standard library "avoids hidden allocations" ([Wikipedia, *Zig*](https://en.wikipedia.org/wiki/Zig_(programming_language))). The `Allocator` interface is passed to functions that allocate. This is a design choice that solves memory-safety and testability problems the C stdlib created, at the cost of API verbosity.

Zig's async story was withdrawn in Zig 0.11 (August 2023) and is being redesigned. As of Zig 0.15.0 a small subset of the new I/O design ships; the full new design will land later. The new plan puts an `Io` interface into user hands the same way `Allocator` is now ([Loris Cro, *Zig's New Async I/O*](https://kristoff.it/blog/zig-new-async-io/)). Large parts of the stdlib — TLS, HTTP server, HTTP client — will be rewritten. Zig's willingness to withdraw a shipped feature is unusual and worth respecting; it is also unusually expensive on downstream users.

### MoonBit — AI-native positioning, thin production evidence

MoonBit's core standard library (`moonbitlang/core`) is bundled with the compiler. As of version `0.1.20260908` the docs describe it as "experimental and under active development" with an API "subject to change" ([mooncakes.io, *moonbitlang/core*](https://mooncakes.io/docs/moonbitlang/core)). The design does have some clean choices — `builtin` is auto-imported, `prelude` is auto-opened and re-exports common names, everything else is an ordinary `moonbitlang/core/<pkg>` — but the production evidence is limited. MoonBit's marketing emphasizes AI-native workflows; the actual stdlib is a solid but conventional core (`Array`, `Map`, `Hash`, `Json`, `Test`, `IO`) without an official HTTP stack, database drivers, or observability primitives.

Verdict: promising language, standard library still bootstrapping, not a template for what a production-services language should look like on day one.

### Others — Kotlin, Swift, OCaml, Clojure

- **Kotlin** inherits the JVM stdlib. Kotlin's own stdlib is small and additive — collection extension functions, `Result`, coroutines. Kotlin Multiplatform reimplements a `kotlin.stdlib` for Native and JS but the JVM inheritance is the load-bearing story. This is the most successful "small language + big host stdlib" pattern.
- **Swift** has Foundation (`URLSession`, `JSONEncoder`, `FileManager`, `Date`, `Data`). Open-source `swift-corelibs-foundation` for Linux exists and is a permanent second-class citizen — subtle differences from Apple Foundation are a real source of bugs.
- **OCaml** had a famously threadbare stdlib for two decades. Jane Street's `Base`, `Core`, and `Core_kernel` filled the gap ([Jane Street, `ocaml-core`](https://ocaml.janestreet.com/ocaml-core/v0.13/doc/base/index.html)) and are now the industry default. This is the cautionary tale for languages that ship a minimal stdlib: someone else _will_ ship the real one, and if it's outside your governance you lose the ability to shape it.
- **Clojure** ships opinions in the language (immutability, sequences, transducers, `spec`) and lets libraries ship code. `Ring` for HTTP, `next.jdbc` for databases, `Compojure`/`Reitit` for routing. Small community; consistent philosophy; low fragmentation compared to Node.

---

## Part 2: What modern production services actually require

The table below is the operating consensus for backend services in 2025–2026. Each row identifies whether the capability typically belongs in stdlib, in first-party kits/frameworks, or in third-party libraries, plus the failure mode when the tier is wrong.

| Capability | Typical tier | Failure mode when miscategorized |
|---|---|---|
| TCP, DNS, TLS 1.3 | stdlib | Third-party TLS fragments the ecosystem; every service picks a different implementation and CVE coverage varies wildly. Rust with `rustls` vs `native-tls` is the canonical example. |
| HTTP/1.1, HTTP/2 | stdlib | Rust's decision to leave HTTP out of std pushed everyone onto `hyper`/`reqwest`, which is now effectively std. That worked because `hyper` is well-maintained; if it hadn't been, the ecosystem would have split. |
| HTTP/3, WebSockets | first-party framework | Too new to freeze in stdlib; too load-bearing for third-party. |
| gRPC | first-party framework | Go has `google.golang.org/grpc` as an official but non-stdlib package; Rust has `tonic` (community). Both models work. |
| JSON | stdlib | `encoding/json` and Python's `json` are canonical. When left to third-party (as historically Java with Jackson vs Gson vs Moshi) the ecosystem splinters and every framework picks a different one. |
| CBOR/MessagePack/Protobuf/Avro | third-party | Rarely needed; specializations. |
| YAML/TOML | stdlib for TOML; third-party for YAML | YAML is a security minefield (billion laughs, code execution); the safer default is TOML. Rust's decision to ship `toml` support was pragmatic. |
| Symmetric/asymmetric crypto, hashing, HMAC | stdlib | "Don't roll your own crypto" is only meaningful if a first-party audited implementation exists. Go's `crypto/*` is the model. Rust's decision to leave it to `RustCrypto`/`ring` works but forces every user to make an audit judgment. |
| JWT | third-party or first-party framework | Not stdlib. JWT is a specification full of pitfalls (alg=none, key confusion); the wisdom is to depend on a battle-tested library like `jose` or `jsonwebtoken`. |
| Password hashing (argon2id, bcrypt) | stdlib preferred | OWASP updates the recommended parameters yearly; a first-party implementation keeps everyone current. |
| Constant-time comparison, secure random | stdlib **required** | Every language must ship `crypto/rand` (or equivalent) and `subtle`/`ConstantTimeCompare`. Getting these wrong is a CVE. |
| SQL driver interface + connection pool | stdlib interface, drivers first-party or third-party | Go's `database/sql` is the interface, individual drivers implement it. This is a well-proven pattern. |
| Postgres/MySQL/SQLite drivers | first-party if the interface is stdlib | Almost no language ships drivers in stdlib. Doing so ties stdlib to a wire-protocol version. Better model: stdlib interface, first-party reference driver kits. |
| Redis client | third-party or first-party framework | Bun ships one. Most languages don't. |
| Structured concurrency, cancellation, deadlines | stdlib **required** | Go bolted `context` on; Rust bolted `CancellationToken` on. Every language will eventually need it. Ship it from day 1. |
| Structured logging | stdlib | Go 1.21 added `slog` after years of `logrus`/`zap`/`zerolog` fragmentation. That was correct but late. |
| Metrics (Prometheus/OpenMetrics) | third-party | Wire format is stable; a first-party client is nice but not required. |
| Tracing (OpenTelemetry) | first-party integration | OTel is the de facto standard for distributed tracing; a first-party integration eliminates the "which OTel wrapper do I use" question that has plagued Rust and Node. |
| UTF-8, Unicode normalization | stdlib **required** | Getting this wrong causes security bugs (IDN homograph attacks). |
| Regex | stdlib | Go's `regexp` (RE2) is fast and does not backtrack, so ReDoS is impossible by design. This is the model. |
| Time (monotonic, wall, tz, durations, deadlines) | stdlib **required** | Time is a top-3 source of production bugs. Ship it correctly on day 1. |
| Filesystem, temp files, atomic rename, path manipulation | stdlib | |
| gzip, zstd, brotli | stdlib gzip; third-party zstd/brotli acceptable | |
| Subprocess spawning, signals, env | stdlib | |
| Testing (unit, snapshot, benchmark) | stdlib **required** | Go, Rust, Zig, Deno, Bun, Elixir all ship first-party test runners. Python and Node leaving it to pytest and Jest/Mocha caused years of ecosystem churn. |
| Property/fuzz testing | stdlib or first-party | Rust's `cargo fuzz` and Go's `testing.F` are the model. |
| Config, env vars, secrets | first-party framework | Stdlib env access; framework-level secret handling. |
| Web routing, middleware, request/response | first-party framework | Not stdlib. Frameworks evolve too fast. |
| Sessions, CSRF, auth | first-party kit (generated code) | This is the shadcn/Phoenix model. Ships in the user's repo, not as a dependency. |
| Background jobs, scheduling, queues | first-party framework | Oban (Elixir), Sidekiq (Ruby), Celery (Python) are all effectively required. |
| Email, SMS, push abstractions | third-party | |
| AI/LLM integration (HTTP clients, streaming, tool use, structured outputs) | first-party framework | New requirement 2024–2026. See below. |
| Deployment: static linking, cross-compilation, container-friendly binaries | stdlib **required** | Go's static binaries and cross-compilation are a major reason for its cloud adoption. |

### Incidents that map to miscategorization

- **log4shell (December 2021).** JNDI lookup in a logging library led to unauthenticated RCE. Root cause: Java logging is third-party, log4j2 had accreted esoteric features, and organizations had 30-deep transitive dependencies on it. Sonatype's 2024 report noted that "13% of all Log4j downloads are still of a vulnerable version" nearly three years after the fix ([Sonatype, *SSCR 2024 Risk*](https://www.sonatype.com/state-of-the-software-supply-chain/2024/risk)).
- **event-stream, ua-parser-js, colors.js, xz.** All are compromises where third-party code got runtime authority a stdlib primitive would never have granted.
- **left-pad.** An 11-line function was a critical dependency. In any language with a real stdlib it would not have existed.

The pattern: everything you leave to third-party is a potential CVE vector. Everything you put in stdlib is a maintenance commitment for the life of the language. Choose deliberately.

---

## Part 3: The "shape" of a successful stdlib

### Stability guarantees

Go and Java have committed to "no breaking changes ever." Both have shipped since; both have felt the cost. Go's `encoding/json` shipped known bugs for 14 years because they could not be fixed without breaking the API. Java's stdlib has whole packages that are essentially unrecommended (`java.util.Date`, `java.io.File`) but still present, with `java.time` and `java.nio.file` shipped alongside them.

Python's `distutils` was removed in 3.12 after decades of deprecation; the community managed the migration but not without pain. Rust std has been stable since 1.0 (May 2015) and has grown by addition only.

**Lesson.** A language that intends to be used for 30 years cannot ship v1 stdlib and expect to break it. Design as if v1 is v∞. If you must ship early, version your std modules independently and be explicit that v1 modules can be deprecated in favour of v2 modules.

### Size and coherence

Small stdlib (Rust, Zig, OCaml) forces the community to build alternatives. Big stdlib (Go, Java, Python) means the stdlib becomes the anchor. There is no right size, but there is a right _shape_:

- Anything that _cannot_ be community-implemented safely (crypto primitives, UTF-8, time, `Result`/`Option` types, error types crossing library boundaries) must be in stdlib.
- Anything with rapid evolution (web frameworks, ORMs, cloud provider SDKs) should not.
- Everything else is a judgment call, and the correct default is: ship the interface in stdlib, the implementation as a first-party package that can version faster than the language.

### "One obvious way" vs "many good libraries"

Python's "one obvious way" (Zen of Python) proved a valuable coordination signal but not a technical mechanism — `requests` beat `urllib`, `pytest` beat `unittest`, `poetry`/`uv` are beating `pip`. What Python did get right was that community winners eventually get absorbed (`requests`'s ideas fed `http.client` improvements, `pytest`'s ideas fed `unittest`).

Go's "one obvious way" was more enforced: `gofmt`, `go test`, `go build`, `go mod`. This turned out to be more consequential than any stdlib package — the tooling monoculture is why Go codebases look the same across companies.

### Testing in stdlib

Languages with built-in test runners (Go, Rust, Zig, Deno, Bun, Elixir) have far higher test coverage in their public packages than languages without. Rust crates without tests are rare; Node packages without tests are common. Correlation is not causation, but the friction of "install a test framework, choose a runner, learn its API, integrate with CI" is not zero, and every language that has removed it has benefitted.

### HTTP in stdlib

Go's `net/http` is what makes Go the boring default for backends. Rust's decision to keep HTTP out of std forced the community to converge on `hyper` and `axum`, and it took ~8 years for the ecosystem to feel as stable as Go's did on day one.

**Judgment call.** For a services-focused language, a stdlib HTTP client and server are essentially required. The question is not whether to ship them but how ambitious to be (HTTP/2 support? HTTP/3? WebSockets?). Ship at least HTTP/1.1 client and server on day one; add HTTP/2 in the first 12 months.

### Cryptography in stdlib

Both arguments have merit. "Don't roll your own crypto" argues for stdlib because a language-team implementation is at least reviewed by the language team. "Audit is only meaningful if it's first-party" cuts the other way for languages without crypto expertise.

The compromise adopted by most modern languages: ship a small, audited stdlib crypto package (hashing, HMAC, constant-time compare, secure random, chacha20-poly1305) and delegate elliptic curves and TLS to first-party or vetted third-party packages.

### Database drivers

Almost no language ships database drivers in stdlib because doing so ties stdlib to a wire-protocol version. The right pattern is what Go did: `database/sql` in stdlib as the interface, individual drivers as separately versioned packages. Bun's decision to ship a native Postgres client in the runtime is an interesting bet but has not been in-market long enough to evaluate.

---

## Part 4: The "kits" model — first-party generated code

### What is being observed

Four patterns qualify as "kit" distribution:

1. **Phoenix generators.** `mix phx.gen.auth` writes a full auth system into the user's app.
2. **Laravel starter kits.** `laravel new my-app` prompts for a starter kit and scaffolds React/Vue/Livewire with Fortify or WorkOS AuthKit ([Laravel 12.x, *Starter Kits*](https://laravel.com/docs/12.x/starter-kits)).
3. **Rails generators.** `rails generate scaffold Post title:string body:text` writes model, migration, controller, view, and tests. Weaker than Phoenix's because the generated code depends on a large amount of "magic" Rails runtime behaviour.
4. **shadcn/ui.** "This is not a component library. It is how you build your component library." Components are copied into the user's repo via a CLI + registry system, not installed as npm packages ([shadcn/ui, *Introduction*](https://ui.shadcn.com/docs)). The architecture is a well-documented registry-item schema with 14 registry types and 10 workspace templates ([readoss.com, *shadcn/ui Architecture*](https://readoss.com/en/shadcn-ui/ui/shadcn-ui-architecture-component-distribution-system)).

### What has actually worked

The shadcn model is winning. Vercel's own Next.js templates ship with shadcn/ui by default; Laravel's React starter kit uses it; every major AI code assistant supports it because the components are, quite literally, "the code in the user's repo." The maintenance model — the user owns the code and modifies it — turned what looked like a supply-chain problem into a supply-chain _defense_: there is no transitive dependency to hijack, no version to pin, and the user reads the code before shipping.

Phoenix's `mix phx.gen.auth` is universally recommended by Elixir community leadership as _the_ way to build authentication in Phoenix. Its explicit design point — "you now have complete freedom to modify the authentication system" at the cost that generated code is not upgraded automatically — is the same trade-off shadcn/ui makes, and the community has accepted it.

Laravel starter kits' history is more mixed. Jetstream (2020) was over-opinionated (Tailwind + Livewire or Inertia + Vue only), Breeze (2021) was minimal, and Laravel 12's starter kits (2025) settled on WorkOS AuthKit as the default auth provider — a choice several community members have criticized as vendor lock-in for authentication.

### What has failed

**create-react-app.** Officially deprecated in early 2025. The generated code was a starter, but nobody owned the generated code once it existed; the ecosystem moved to Next.js, Vite, Remix, and Astro, all of which regenerate their scaffolds through their own CLIs. Lesson: kit generators need a maintained _template_, or the "kit" model becomes a one-time snapshot that ages badly.

**Rails scaffolds.** Not failed, but weaker than Phoenix's generators because so much of the generated code depends on convention-over-configuration Rails runtime behaviour that "reading the generated code" doesn't tell you what actually happens. Phoenix generators produce code that is largely self-contained.

### Is the kits model a supply-chain defense or problem?

**Defense.** Because generated code lives in the user's repo, it cannot be silently changed by a compromised upstream. Every future change requires a git commit the user's team can review. This is a real security benefit.

**Problem.** The user is now responsible for security patches to the generated code. If Phoenix ships a fix to `mix phx.gen.auth`'s magic-link expiration logic, every generated auth system needs a manual reapply. In practice, Phoenix keeps its generators simple enough that this rarely matters, but for a language shipping many kits, an "upgrade template" story is necessary.

**Assessment.** Kits are a net defense _when combined with_ a first-party template registry that publishes advisories and diffs, and _when the generated code is small enough_ that human review is realistic. For agent authors specifically, kits are unambiguously better than dependencies because agents can read, edit, test, and re-generate the code directly.

---

## Part 5: Supply-chain risk and the modern registry

### Registry-level defenses as of late 2026

| Ecosystem | Defense | Adoption / status |
|---|---|---|
| Go | `sum.golang.org` transparency-log checksum verification | Default-on since Go 1.13; 100% of module downloads verified. Cannot be opted out by an individual dependency ([Go Modules Ref](https://go.dev/ref/mod#checksum-database)). |
| Go | `proxy.golang.org` module proxy | Default; provides caching and immutability. |
| npm | Package Provenance (Sigstore-signed, SLSA build attestation) | Launched April 2023. **34.1% of top 10,000 packages by weekly downloads** as of Nov 2025, up from 20.5% (Nov 2024) and 6.1% (Nov 2023). Developer tooling category is 58%; UI libraries 29%; "everything else" 17% ([Safeguard, *npm Provenance Adoption*](https://safeguard.sh/resources/blog/npm-provenance-adoption-tracking-late-2025)). |
| npm | Trusted Publishing (OIDC, GA July 2025) | 11,001 of top 51,370 packages by end of 2025; covers ~25% of download volume; ~75% of downloads still ship from long-lived tokens ([Aikido, *Shai-Hulud*](https://www.aikido.dev/blog/shai-hulud-trusted-publishing)). |
| npm | Mandatory 2FA (WebAuthn) for top-500 publishers | Announced after September 2025 Shai-Hulud incident. |
| PyPI | Trusted Publishers (OIDC-based, launched 2023) | 50,000+ projects, >20% of 2025 file uploads. Files uploaded via Trusted Publishers: ~10% Feb 2024, >25% by Oct 2025 ([PyPI blog, *Trusted Publishers coming to organizations*](https://blog.pypi.org/posts/2025-11-10-trusted-publishers-coming-to-orgs/); [PyPI, *2025 in Review*](https://blog.pypi.org/posts/2025-12-31-pypi-2025-in-review/)). |
| PyPI | Digital Attestations (PEP 740) | Default for Trusted Publisher users via `pypa/gh-action-pypi-publish` since Oct 2024. ~20,000 packages could attest to provenance by default at launch ([Trail of Bits, *Attestations*](https://blog.trailofbits.com/2024/11/14/attestations-a-new-generation-of-signatures-on-pypi/)). |
| PyPI | 2FA (non-phishable) | >52% of active users on non-phishable 2FA by end of 2025 ([PyPI, *2025 in Review*](https://blog.pypi.org/posts/2025-12-31-pypi-2025-in-review/)). |
| crates.io | `Cargo.lock` SHA-256 checksums | Universal — every lockfile ships checksums. |
| crates.io | Trusted Publishing (without provenance) | Recently added; adoption early. Categorized as SLSA L1 as of March 2026 ([zenn.dev, *Package Registry Provenance Status: 2026 Edition*](https://zenn.dev/sqer/articles/e4df3d397f5651?locale=en)). |
| Maven Central | Mandatory PGP signatures; opt-in Sigstore | SLSA L3-capable. Mandatory PGP for decades. |
| NuGet | X.509 signatures; provenance via GitHub Artifact Attestations | SLSA L1. |
| Deno | URL-based imports with hash locking; JSR with signed manifests | JSR's SLSA level not formally rated. |

### Evidence for what has and hasn't worked

The zenn.dev summary from early 2026 places npm, PyPI, and Maven Central at "SLSA L3" (provenance with transparency log) and Go and crates.io at "L1" (integrity checksums only, but 100% coverage) ([zenn.dev, *Package Registry Provenance Status: 2026 Edition*](https://zenn.dev/sqer/articles/e4df3d397f5651?locale=en)). By that framework:

- **Go's L1 with 100% coverage** has never had a Shai-Hulud-scale incident, in part because the checksum database is default-on and every consumer verifies against it.
- **npm's L3 at ~34% coverage of top packages** did not prevent Shai-Hulud, because 75% of download volume still came from long-lived-token packages that were vulnerable to token exfiltration. Coverage matters more than level.
- **PyPI's Trusted Publishers uptake** accelerated dramatically after 2024 when it became the default in `pypa/gh-action-pypi-publish`, showing that _defaults win_.

### State of the art and state of practice

- **Sigstore** (cosign, rekor, fulcio) is the transparency-log backbone used by npm provenance, PyPI attestations, and GitHub Artifact Attestations. Adoption is real but sub-half.
- **in-toto** is the metadata format for build attestation and is used inside SLSA.
- **SLSA** defines levels 1–4; L4 (full dependency-tree provenance) is described in the 2026 evidence as "currently difficult for most ecosystems" ([zenn.dev](https://zenn.dev/sqer/articles/e4df3d397f5651?locale=en)).
- **Reproducible builds** are pursued at the Debian and Fedora levels but rarely for language-package builds. Nix and Bazel are the main reproducibility stories.
- **Capability-based module systems** exist in research (Wyvern, Newspeak) and in some production contexts (Deno's permission flags, Bun's implicit trust-but-narrower runtime). They are early in practice.

### Specific proposals evaluated

- **Age gates.** `--minimum-release-age` in `cargo` and equivalents give a soft delay before a new version is trusted. Effective against fast-moving worms (Shai-Hulud propagated in hours) but not against long-cultivated attacks (xz took two and a half years).
- **Transparency logs.** Sigstore's Rekor is the reference. When combined with client-side verification, they make forgery detectable; when combined with OIDC identity, they make it hard to publish anonymously. Both are necessary conditions, not sufficient.
- **WebAuthn-required publishing.** npm's mandatory WebAuthn for top-500 publishers post-Shai-Hulud is the clearest example. Effective at blocking token theft; ineffective against maintainer-account-takeover-via-social-engineering (xz).
- **Capability manifests.** DepSec, Cocoon, and various npm permission-manifest proposals give per-package declarations of what a dependency needs (network, filesystem, subprocesses). None have shipped at scale in a major registry.
- **Reputation signals.** OpenSSF Scorecard, deps.dev, socket.dev, snyk.io. Useful for humans and CI gates; do not by themselves stop attacks.

**Summary.** The two techniques with the strongest empirical evidence for reducing incidents are (a) Go's model of default-on cryptographic verification integrated into the client, and (b) short-lived credential publishing that removes the theft target (Trusted Publishing / OIDC). Everything else is a helper.

---

## Part 6: Adoption dynamics — how ecosystems actually grow

### Package and registry scale (late 2024 / late 2025 baseline)

| Ecosystem | Projects | Versions | Annual downloads | YoY project growth | YoY download growth |
|---|---:|---:|---:|---:|---:|
| Java (Maven Central) | 671,000 | 18.7M | 1.5T | 7% | 36% |
| JavaScript (npm) | 4.8M | 48.8M | 4.5T | 23% | 70% |
| Python (PyPI) | 635,000 | 6.6M | 530B | 10% | 31% |
| .NET (NuGet) | 664,000 | 10.5M | 159B | 6% | 14% |
| Rust (crates.io) | ~200,000–290,000 | — | — | — | ~2.7×/yr |
| Go modules | ~750,000 (per Russ Cox 2019, current larger) | — | — | — | — |

Sources: [Sonatype SSCR 2024](https://sonatype.com/hubfs/SSCR-2024/SSCR_2024-FINAL-optimized.pdf); [Lib.rs stats](https://lib.rs/stats); [research.swtch.com, *Our Software Dependency Problem*](https://research.swtch.com/deps).

Only ~10.5% of the 7 million tracked open-source components are actively downloaded and used ([Sonatype, *SSCR 2024*](https://sonatype.com/hubfs/SSCR-2024/SSCR_2024-FINAL-optimized.pdf)). Ecosystem headline package counts are dominated by long-tail unused libraries.

### What predicts toy → production-viable

The historical record identifies six variables:

1. **A killer first-party framework.** Rails made Ruby production. Phoenix pulled Elixir into serious production. Django and Flask sustain Python's web share. Next.js is what makes TypeScript the default web language, not the language itself.
2. **A killer use case that matches a real market need.** Go for cloud infrastructure (Docker, Kubernetes, Terraform, Prometheus). Rust for systems where memory safety is a hard requirement (Fastly, Cloudflare, Discord's Read States). Swift for iOS. Kotlin for Android. TypeScript for anywhere JavaScript is unavoidable.
3. **Corporate backing that provides economic patience.** Mozilla for early Rust; Google for Go, Kotlin (indirectly, via Android endorsement), TypeScript (indirectly); Apple for Swift; JetBrains for Kotlin; Microsoft for TypeScript. Every mainstream modern language has a corporate patron with a strategic reason to fund it for a decade.
4. **A cohesive tooling story that ships with the language.** `cargo`, `go`, `mix`, `dotnet`, `dart`. Languages where tooling is fragmented (JavaScript's yarn/pnpm/npm/bun, Python's pip/poetry/uv/pdm) pay an adoption tax.
5. **A stable ABI or FFI story.** Rust and Zig can call C; C can call Go with `cgo`; JVM languages interoperate. Languages without an FFI story hit a ceiling.
6. **A learnable syntax and semantics for humans.** This matters less than the others but is not zero. Elixir's pipe operator and Rust's `?` operator both moved adoption noticeably.

### The role of corporate backing, quantified

| Language | Sponsor | First major release | Time to production-scale users |
|---|---|---:|---:|
| Go | Google | Nov 2009 | ~4 years (Docker/Kubernetes 2013–2014) |
| Rust | Mozilla, then Foundation | May 2015 (1.0) | ~5 years (Fastly, Discord, Firefox internals) |
| Swift | Apple | June 2014 | ~2 years (iOS/macOS adoption forced) |
| Kotlin | JetBrains | Feb 2016 (1.0) | ~2 years (Android official May 2017) |
| TypeScript | Microsoft | Oct 2012 | ~5 years (Angular 2 in 2016, React uptake 2017–2018) |
| Elixir | Community, funded via Dashbit | May 2012 | ~5 years (Discord chat backbone) |

### Where "batteries included from a benevolent authority" succeeds and fails

- **Succeeds.** Go, Elixir/Phoenix, Rails, Django, Laravel, Swift/Foundation, .NET. The commonality: a single authority makes a coherent set of decisions and defends them for a decade.
- **Fails.** Roc (thin community, few platforms), CoffeeScript (no killer app once ES6 shipped), Elm (frozen and forked). The commonality: the authority is small, the community is small, and there is no external forcing function creating adoption.

The "let the community sort it out" model has succeeded in Rust (largely) and JavaScript (with enormous cost). It has failed in nearly every other case.

---

## Part 7: The specific stack for a modern services language shipping today

Independent of any specific language design, the following table is the minimum-viable batteries-included stdlib and platform strategy for a language whose customers are engineering teams building production services in 2026.

### Ship in stdlib on day one

| Module | Rationale |
|---|---|
| `bytes`, `strings`, `unicode` (UTF-8, normalization) | Required. Getting these wrong is a CVE class. |
| `io`, `bufio` (async-aware) | Required. Backpressure is a foundational concern. |
| `time` (monotonic, wall, tz, durations, deadlines) | Required. |
| `os`, `path` (filesystem, temp files, atomic rename, subprocess, signals, env) | Required. |
| `net` (TCP, UDP, DNS) + `tls` (TLS 1.3 client and server) | Required. |
| `http` (client and server, HTTP/1.1 + HTTP/2) | Required for a services language. |
| `websocket` (framed, with `net/http` integration) | Required. |
| `json` (safe, well-specified — no v1 bugs) | Required. Design once; do not repeat Go's 14-year saga. |
| `sql` (interface only, with prepared statements, transactions, and context-aware cancellation) | Required. |
| `crypto` (hashing, HMAC, chacha20-poly1305, secure random, constant-time compare, argon2id password hashing) | Required. Ship a minimum audited surface; delegate elliptic curves to a first-party package. |
| `context` / `Cancel` / `Deadline` (structured concurrency primitive) | Required. |
| `log` (structured, level-aware, JSON output) | Required. |
| `test` (test runner, benchmarks, snapshot, property-based) | Required. |
| `fuzz` | Required. |
| `sync` (Mutex, RWMutex, WaitGroup, atomics, channels or equivalent) | Required. |
| `regexp` (RE2-style, no backtracking) | Required. ReDoS by design is unacceptable. |
| `encoding` — `hex`, `base64`, `csv`, `toml`, `gzip` | Required. Skip YAML in stdlib; leave to first-party. |
| `errors` (wrapping, unwrap, joining, stack traces) | Required. Error handling is a language boundary. |
| `net/mail`, `net/url`, `mime` | Required. Small utilities that eliminate a class of bugs. |

### Ship as first-party frameworks but not stdlib

| Framework | Model |
|---|---|
| `web` framework | Router + middleware + form parsing + templating + first-class HTTP/2 and HTTP/3. Ship independently; version faster than stdlib. |
| `data` framework (ORM/query-builder) | The Ecto model: separately versioned, first-party opinion, works with the stdlib `sql` interface. |
| `jobs` framework (background jobs, queues, scheduling) | The Oban / Sidekiq model. |
| `otel` integration | First-party OpenTelemetry SDK, wired into stdlib `http`, `sql`, and `log`. |
| `llm` framework | HTTP clients for OpenAI, Anthropic, Google, xAI; streaming; tool use; structured outputs. This is a table-stakes 2026 capability. |
| `auth` kit (generated code) | The Phoenix `mix phx.gen.auth` model. Users own the generated code. |
| `deploy` kit (Dockerfile, `distroless` base, health checks, static binary, cross-compilation) | Container-friendly by default. |
| `starter` kit (project scaffolds) | The Laravel model. React/HTMX/Svelte/static-HTML scaffolds. |

### Ship as blessed community packages

| Domain | Approach |
|---|---|
| Redis, RabbitMQ, Kafka clients | Community-maintained, blessed via the official registry with capability manifests. |
| S3, R2, GCS clients | Community. |
| Postgres, MySQL, SQLite drivers | Community-maintained reference implementations of the stdlib `sql` interface. Blessed via registry. |
| CBOR, MessagePack, Protobuf, Avro | Community. |
| Advanced cryptography (elliptic curves, PAKEs, zk-proofs) | First-party package, not stdlib. Distinct release cadence. |

### What to deliberately not ship

- **No YAML in stdlib.** Security surface too high.
- **No JWT in stdlib.** Foot-guns too many; users should depend on a battle-tested library.
- **No ORM in stdlib.** Data-model preferences differ too much.
- **No web framework in stdlib.** Frameworks evolve faster than stdlib can tolerate.
- **No `left-pad`.** Do not encourage micro-packages; put small utilities in stdlib where they belong.

### 24-month sequence

**Months 0–6 (v1.0 stdlib + language stability).**

- Ship the day-one stdlib listed above.
- Ship `mo` (or equivalent) tooling: package manager, test runner, formatter, linter, LSP.
- Ship checksum database and OIDC-based Trusted Publishing from day one. Cannot be opted out.
- Ship one starter kit (`starter/http-service`) and one auth kit.
- No web framework yet — force the community to converge before blessing.

**Months 6–12 (first-party frameworks).**

- Ship the `web` framework as a first-party package, versioned independently.
- Ship the `data` framework (ORM/query-builder).
- Ship the `otel` integration wired into stdlib.
- Ship the `jobs` framework.
- Add HTTP/3 to stdlib `http`.
- Ship a second starter kit (`starter/full-stack`) with generated auth, generated CRUD, and generated tests.

**Months 12–24 (ecosystem and safety hardening).**

- Ship the `llm` framework.
- Add capability manifests to the package registry (a package declares what it needs; the runtime enforces).
- Add release-age gates as a first-class registry feature (an install command can require "no version younger than 14 days").
- Add reproducible-build support in the tooling.
- Add per-package effect annotations to the language (if the language supports it) or as a manifest opt-in (if it does not).
- Bless three to five community packages per domain (Redis, S3, Kafka) after they demonstrate maintainership.

---

## Part 8: Synthesis — "if I ran this project"

The evidence in Parts 1–7 supports six specific recommendations. Order matters.

### 1. Ship an actual batteries-included stdlib. Do not ship a "small std" and hope

The two most successful services languages in modern history — Go and Elixir/OTP — shipped meaningful batteries. The most technically pure "small std" languages (OCaml pre-Jane-Street, Roc, MoonBit) have systematically thin production adoption. Rust succeeded despite a small std because `serde`, `tokio`, and `hyper` are so well-maintained that they became stdlib in practice — a bet that took a decade and requires ongoing maintenance from foundations. Do not assume that bet is available.

**Concretely:** ship HTTP client and server, `json`, `sql` interface, structured logging, structured concurrency, testing and fuzzing, TLS, and crypto primitives from day one. Design them as if you cannot break them for 30 years, because you probably cannot.

### 2. The framework strategy is Phoenix + Ecto, not Rails

Ship a first-party web framework and a first-party data framework, but version them independently from the language and independently from each other. The Ecto pattern — Ecto is not Phoenix, and both are first-party — is more robust than the Rails pattern where the ORM is bundled with the framework. When one wants to move faster than the other, they can.

### 3. The kit strategy is shadcn/ui + Phoenix generators, not Jetstream

Ship generated code that lives in the user's repo, is small enough for a human or agent to read in one sitting, and comes with tests. Do not ship large ambitious "kits" (Jetstream, Nova) that generate hundreds of files the user cannot realistically own. This is the single biggest lever for agent authors: generated code is inspectable, editable, and re-runnable in a way a dependency graph never is.

The auth kit, the CRUD kit, the LLM-tool-use kit, and the deployment kit should all be generators. They should include OpenTelemetry hooks. They should include tests. They should say "here is the code, it is yours."

### 4. The supply-chain strategy is Go's, upgraded with OIDC

**Default-on, cannot-be-disabled, transparency-logged checksum verification.** Every install verifies. There is no `--insecure`. The client refuses to fetch a package whose hash does not match the log.

**Publishing requires OIDC or WebAuthn.** Long-lived API tokens should be disallowed for new packages from day one. Grandfather in nothing.

**Install scripts, build scripts, procedural macros, and native code default to off.** A dependency that wants any of these must declare it in a capability manifest, and the manifest becomes part of the resolved dependency's identity. If the manifest changes, the checksum changes, and the install fails until re-approved.

**Release-age gates as a first-class installer feature.** `mo install --min-age 14d` is a supported invocation. This absorbs entire classes of fast-moving worm attacks (Shai-Hulud propagated in hours; a 14-day gate would have blocked every affected release).

### 5. Sequence: language and stdlib first, framework at 6 months, ecosystem hardening at 12–24 months

Do not ship a framework in v1.0. Let the language and stdlib prove themselves; let the community show which patterns win. Then bless.

Do not ship "many good options" in v1.0. Ship one obvious way for HTTP, one obvious way for JSON, one obvious way for SQL access, one obvious way for tests. If those decisions are wrong, versioned stdlib packages let you fix them. But shipping five options guarantees fragmentation.

### 6. Two or three specific bets that most differentiate a successful ecosystem strategy from a failed one

- **Bet 1: Default-on, non-optional supply-chain verification.** Copy Go's checksum DB architecture, mandate OIDC publishing, and disable build/install scripts by default. This is the single largest defensive lever. It is also the one that is hardest to add later — Go could add `sumdb` because it had no legacy; npm cannot mandate 2FA on everyone because too many existing publishers would break. Do this at v0.1.
- **Bet 2: First-party generators as the framework distribution mechanism.** The kit model is a supply-chain defense that agents can use natively. It also creates a value ladder — a new user gets a working service in one command; an advanced user owns and modifies every line. Phoenix and shadcn/ui both exemplify this.
- **Bet 3: A language-level effect or capability system that is enforced at the module boundary.** If the language has this (Roc-style platforms, WebAssembly component model-style capabilities, Java-style modules with `requires`), then supply-chain security stops being "we hope you audit" and becomes "the runtime cannot let the dependency exceed its declared surface." This is where Mo's brief specifically differentiates: an agent-authored ecosystem cannot rely on human audit of every package, and mechanical verification of dependency authority becomes the only real defense.

### Fatal mistakes to avoid

- **Ship a small std and delay HTTP/json/sql.** Rust survived this because of Mozilla's patience and the `hyper`/`tokio`/`serde` maintainers. Assume you do not have their luck.
- **Ship a batteries-included std and freeze v1 forever.** Go's `encoding/json` shipped known bugs for 14 years. Version your stdlib modules independently from day one; make v2 possible on year 2, not year 14.
- **Ship a heavy first-party framework in v1.** Rails needed a decade to reach its current shape. Do not lock the language to a framework's architectural choices when both are unproven.
- **Rely on opt-in security features.** npm provenance at 34% is the counterexample. Go's checksum DB at 100% is the model.
- **Design a beautiful platform model and expect the community to fill it in.** Roc has been at this for years; `basic-cli` and `basic-webserver` are what you get. Ship the platforms yourself, then let the community add specialized ones.
- **Ignore observability.** OTel integration must be first-party from month 12 at the latest. A services language that does not trace, meter, and log by default is unshipped.
- **Ignore the AI-tool-use surface.** In 2026, every services language needs LLM streaming, tool use, and structured outputs as first-party. This is now a category with the same weight as HTTP was in 2010.

---

### Frontier: people, teams, and projects doing credible work on modern language ecosystems

- **Go team (Russ Cox, Ian Lance Taylor, Robert Griesemer, Cherry Mui).** The go.dev blog and research!rsc are the strongest primary sources on package versioning, module proxies, and checksum databases.
- **Tokio team (Alice Ryhl, Carl Lerche, David Barsky).** Long-form technical writing on async runtime tradeoffs and 5-year stability commitments.
- **José Valim and the Dashbit team.** Elixir's stewardship model — small team, opinionated releases, deep first-party frameworks — is the clearest example of a community-scale ecosystem run well.
- **Trail of Bits (William Woodruff, Alex Cameron).** The most rigorous writing on PyPI Trusted Publishers, PEP 740 attestations, and Sigstore integration.
- **Sigstore, OpenSSF, SLSA.** Cross-ecosystem infrastructure for provenance and attestation; adopt-once used by many.
- **Andres Freund.** Discovered xz. Demonstrated that end-user paranoia still matters.
- **Shadcn and the Vercel design engineering team.** Reinvented component distribution and validated the copy-paste-not-package model at industry scale.
- **PyPA (Donald Stufft, Dustin Ingram, Ee Durbin, William Woodruff).** Trusted Publishers rollout is the most successful cross-registry security lift in recent memory.
- **Jarred Sumner and the Bun team.** The most aggressive test of the batteries-included runtime hypothesis in a decade.
- **without.boats (Boats).** The most detailed retrospective writing on Rust's async design decisions.
- **Loris Cro, Andrew Kelley (Zig).** Willing to withdraw and redesign shipped features on evidence — an unusual and admirable pattern.

---

*Report compiled 13 September 2026.*
