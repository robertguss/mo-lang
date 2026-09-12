---
source_url: https://github.com/hylo-lang/hylo-new
ingested: 2026-09-12
sha256: 57b9a0d827f610e9f9143f6b6c65beb33de1e5bf59aac17619fe31b7038de66a
---
# hylo-lang/hylo-new

# hylo-lang/hylo-new

The Hylo programming language

- Stars: 19
- Forks: 9
- Watchers: 19
- Open issues: 56
- License: Apache License 2.0
- Default branch: main
- Created: 2024-10-08T13:17:09Z

## Languages

- Dockerfile
- Swift

## Top Contributors

- kyouko-taiga (310 contributions)
- lucteo (48 contributions)
- tothambrus11 (48 contributions)
- dependabot[bot] (10 contributions)
- mvanhorn (3 contributions)

---

## README

# Hylo

[![codecov](https://codecov.io/github/hylo-lang/hylo-new/graph/badge.svg?token=2auHoqmMSq)](https://codecov.io/github/hylo-lang/hylo-new)

## Misc

Nested types can only be declared in primary declaration.
- Simplifies qualified name lookup because extensions cannot define new nested types.
- Makes sense in the context of scoped conformances because the definition of a type in an extension may break someone else's code. (not so compelling because of properties?)

Make a distinction between extensions and givens.
- An extension reopens the scope of a type and adds new members.
- A given exposes a conformance.

Let `a.m` be an expression where `a` has type `T`, we may resolve `m` to an entity introduced in the primary declaration of `a` or in an extension of `a`, but not to an entity introduced in a given.
If `m` denotes a trait requirement, then name resolution should bind it to the entity introduced in the trait, qualified by a witness of `a`'s conformance to that trait. 
 

## Ideas for optimizations

[ ] Store the contents of "small" type trees in the inline storage of their identities.
[x] Use a separate array to store the tag of each syntax tree rather than calling `tag(of:)`.
[ ] Use out-of-line storage for data structures that have to be "moved" often (e.g., `Program` and `IRFunction`).
[ ] Modify `replaceSuccessor` so that we can simply `condbr` into `br` when both branches are the same.

## Questions

- Is it desirable to write extensions of context functions?

## Building Instructions

Clone the repository, initializing the submodules:
```
git clone https://github.com/hylo-lang/hylo-new
cd hylo-new
git submodule update --init
```

### Linux
- Install `zstd`'s development package: `sudo apt-get install libzstd-dev`
- Install the latest Swift compiler using [swiftly](https://github.com/swift-server/swiftly)
- Download and install [Hylo's LLVM build](https://github.com/hylo-lang/llvm-build)
- `swift test`

### Windows
- Install the latest Swift compiler from [swift.org](https://www.swift.org/install/windows/)
- Download and install [Hylo's LLVM build](https://github.com/hylo-lang/llvm-build)
- `swift test`

### MacOS
- Install the latest Swift compiler from [swift.org](https://www.swift.org/install/macos)
- Download and install [Hylo's LLVM build](https://github.com/hylo-lang/llvm-build)
- `swift test`
- TODO see if any dependencies are missing

## Hylo Compiler's Runtime Dependencies
`hc` uses `clang` and `lld` for linking, resolving them from PATH. On macOS, you will need `xcrun` 
on PATH so the compiler can find the SDK.

