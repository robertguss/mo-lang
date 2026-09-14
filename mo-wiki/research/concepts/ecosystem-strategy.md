---
title: "Ecosystem strategy: the stdlib, kits, and the registry"
created: 2026-09-13
updated: 2026-09-13
type: concept
tags: [research, stdlib, security, roadmap]
sources: [raw/research-runs/ecosystem-stdlib-platform-depth.pplx.md, raw/research-runs/mo-parallel-tracks-brief-2-ecosystem.pplx.md, spec/design-v0/09-stdlib.md, plans/program-4.md]
confidence: medium
---

# Ecosystem strategy: the stdlib, kits, and the registry

Fable's reading of the session 6 deep run on ecosystems, as an answer to [[q11-platform-and-stdlib|Q11]]: what Mo ships first-party, what it ships as recipes, and what it never ships. Held against what the stdlib holds today after step 20.

## Three findings the run rests on

First-party primitives that take real production traffic beat second-party frameworks every time, but only once the language enforces them long enough for an ecosystem to accrete: Go's `net/http`, `encoding/json`, and `database/sql` are fifteen years old and still load-bearing, and a v2 of `encoding/json` took fourteen years.^[raw/research-runs/ecosystem-stdlib-platform-depth.pplx.md] Second, first-party kits, Phoenix's generated auth, Rails scaffolds, shadcn's copied components, are what move an ecosystem from toy to production, and they are exactly the mechanism an agent-authored codebase wants, because generated code in the repo is inspectable and editable where a dependency is not. Third, how a package gets in now matters as much as what it is: Go's checksum database had full coverage on day one, npm provenance reached a third of the top packages after two and a half years.

## Recipes are kits, and the run says what kits need

Direction 34's recipes are the shadcn and Phoenix model with the bodies generated rather than copied, and the run's evidence is on their side: shadcn won, and the same maintenance model, the user owns the code, turned a supply-chain problem into a defense. The run also names the failure: create-react-app died because nobody owned the generated code once it existed, so a kit needs a maintained template and an upgrade story. For Mo that is the recipe registry the outside review deferred, and step 19's conformance check (`mo check --recipe`) is the upgrade story in embryo: a changed recipe fails the check until the implementation follows. Program 4 measured the cost: five minutes to write the store recipe, a design settled before code, and drift until the check existed.

## The stdlib, against the run's day-one list

| the run's day-one module | Mo today | call |
|---|---|---|
| strings, unicode, bytes | strings and `List(UInt8)`; no normalization | a `Bytes` type and normalization are a step |
| io with backpressure | processes, bounded mailboxes, step 20's `serve` and `lines` | done, Mo's way |
| time, durations, deadlines | `Time`, `Duration`, `within:` on every waiting call | done |
| files, paths, subprocess, signals, env | `Fs` scoped and read-only, args, env, exit; no subprocess, no signals | subprocess is a capability to design, not a row |
| net TCP and DNS; TLS 1.3 | `Net` TCP; no TLS | TLS is the first big brick and must be first-party and audited; Zig's std has a client |
| HTTP/1.1 client and server; HTTP/2 within a year | `Http` 1.1, one request per connection | keep-alive before HTTP/2 |
| websocket | none | after program 1 says it needs one |
| json, safe and specified once | `Json` | done; the run's warning is to never ship a v1 bug |
| sql interface only, drivers separate | none | the interface as a recipe, drivers as first-party bricks, after program 1 |
| crypto: hashing, HMAC, AEAD, random, argon2id | none | the second big brick; ship the small audited surface, curves and TLS as one first-party package |
| context, cancel, deadline | `within:`, supervisors | done |
| structured log | none by law: no logs, trace everything | the outside review's point stands: allow typed operational logs under a classification |
| test, benchmarks, property, fuzz | `mo test`, properties, `--sim`, the bench | done; mutation testing since step 19 |
| sync | none needed: processes | done, Mo's way |
| regexp without backtracking | none | RE2-style, a step, when a program asks |
| encodings: hex, base64, csv, toml, gzip | none | rows when asked; never YAML |
| errors with wrapping | `Result` and `try` | done |
| url, mail, mime | `Http` parses a query; no url row | small rows when asked |

## What Mo never ships

The run's list matches chapter 6: no YAML, no JWT, no ORM, no web framework in the stdlib, no micro-packages. Mo's answer to the framework layer is recipes plus first-party kits that version faster than the language: a web kit over `Http`, a jobs kit (program 1 is its prototype), an auth kit, a deploy kit that emits a static binary and a container.

## The registry, when it comes

Checksums and trusted publishing from day one and not optional, as Go did; a recipe is signed source that executes nothing, so the registry's job is advisories and template diffs, not code. The outside review's deferral stands: not before an outsider runs one real service.

## What changes because of this page

- Q11's answer: the stdlib is the run's day-one list minus what processes and capabilities make unnecessary, with TLS and crypto as the two bricks that gate any real deployment, first-party and audited.
- Two steps join the queue after program 1: TLS and the small crypto surface; the `sql` interface as a recipe with a first-party driver.
- The recipe registry's design is the conformance check plus advisories and diffs; it waits.

## Related
- [[q11-platform-and-stdlib]]
- [[d34-packages-are-recipes]]
- [[supply-chain-defenses]]
- [[program-4]]
- [[outside-review-2026-09-13-response]]
- [[prompts-mo-parallel-tracks]]
