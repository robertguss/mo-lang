---
source_url: https://github.com/caffeinelabs/motoko
ingested: 2026-09-12
sha256: d18847e7006011b660a56998c04cd82df65f7e6d80c8b77582ade55426c99236
---
# caffeinelabs/motoko

# caffeinelabs/motoko

Simple high-level language for writing Internet Computer canisters

- Stars: 588
- Forks: 127
- Watchers: 588
- Open issues: 259
- License: Apache License 2.0
- Default branch: master
- Created: 2018-05-11T11:12:10Z

## Languages

- C
- Dune
- Emacs Lisp
- HTML
- Haskell
- JavaScript
- Makefile
- Nix
- OCaml
- Perl
- Python
- Rust
- Shell
- Standard ML
- Swift
- TeX
- WebAssembly
- sed

## Topics

- internet-computer
- motoko
- motoko-language
- programming-language

## Top Contributors

- nomeata (1707 contributions)
- crusso (910 contributions)
- ggreif (666 contributions)
- dfinity-bot (632 contributions)
- matthewhammer (535 contributions)
- rossberg (280 contributions)
- chenyan-dfinity (164 contributions)
- paulyoung (146 contributions)
- dependabot[bot] (129 contributions)
- lsgunnlsgunn (126 contributions)

---

## README

# [Motoko](https://internetcomputer.org/docs/current/motoko/main/about-this-guide) · [![Release](https://img.shields.io/github/v/release/dfinity/motoko.svg)](https://github.com/dfinity/motoko/releases) [![GitHub license](https://img.shields.io/badge/license-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0) [![Tests](https://img.shields.io/github/actions/workflow/status/dfinity/motoko/release.yml?branch=master&logo=github)](https://github.com/dfinity/motoko/actions?query=workflow:"release") [![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/dfinity/motoko/blob/master/.github/CONTRIBUTING.md)

A safe, simple, actor-based programming language for building [Internet Computer](https://internetcomputer.org/) (ICP) canister smart contracts.

![Motoko Logo](https://github.com/user-attachments/assets/844ca364-4d71-42b3-aaec-4a6c3509ee2e)

## User Documentation & Samples

* [Introduction](https://internetcomputer.org/docs/current/motoko/main/getting-started/motoko-introduction)
* [Basic concepts and terms](https://internetcomputer.org/docs/current/motoko/main/getting-started/basic-concepts)
* [Sample code](samples)
* [Language manual](doc/md/reference/language-manual.md)
* [Concrete syntax](doc/md/examples/grammar.txt)
* [Documentation sources](doc/md/)
* [Core package documentation](https://mops.one/core/docs)

## Introduction

### Motivation and Goals

* High-level programming language for ICP smart contracts

* Simple design and familiar syntax

* Convenient support for the [actor model](https://en.wikipedia.org/wiki/Actor_model)

* Good fit for underlying Wasm and ICP execution model

### Key Design Points

* Object-based language with actors, classes, modules, etc. as closures

* Classes can be actors

* Async construct for direct-style programming of asynchronous messaging

* Structurally typed with simple generics and subtyping

* Overflow-checked number types, explicit conversions

* JavaScript/TypeScript-style syntax but without the JavaScript madness

* Inspirations from Java, C#, JavaScript, Swift, Pony, ML, Haskell

## Related Repositories

* Next-Gen [Core package](https://github.com/dfinity/motoko-core)
* Legacy [Base package](https://github.com/dfinity/motoko-base)
* [Vessel package manager](https://github.com/dfinity/vessel)
* [Example projects](https://github.com/dfinity/examples/tree/master/motoko)
* [ICP Ninja, online authoring of canisters](https://icp.ninja)
* [Motoko Playground](https://github.com/dfinity/motoko-playground) &middot; (DEPRECATED — [online IDE](https://play.motoko.org))
* [Embed Motoko code snippets](https://github.com/dfinity/embed-motoko) · ([online interpreter](https://embed.smartcontracts.org/))
* [VS Code extension](https://github.com/dfinity/vscode-motoko) · ([install](https://marketplace.visualstudio.com/items?itemName=dfinity-foundation.vscode-motoko))
* [Browser and Node.js bindings](https://github.com/dfinity/node-motoko) · ([npm package](https://www.npmjs.com/package/motoko))

## Community Resources

* [Awesome Motoko](https://github.com/motoko-unofficial/awesome-motoko#readme)
* [Blocks - an online low-code editor for Motoko](https://github.com/Blocks-Editor/blocks)
* [MOPS - a Motoko package manager hosted on the IC](https://j4mwm-bqaaa-aaaam-qajbq-cai.ic0.app/)
* [Motoko Bootcamp](https://www.motokobootcamp.com) · ([YouTube channel](https://www.youtube.com/channel/UCa7_xHjvOESf9v281VU4qVw))
* [Motoko library starter template](https://github.com/ByronBecker/motoko-library-template)

## Contributing

See our [contribution guidelines](.github/CONTRIBUTING.md), [code of conduct](.github/CODE_OF_CONDUCT.md) and [build instructions](Building.md) to get started.

