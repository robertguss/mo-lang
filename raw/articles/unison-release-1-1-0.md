---
source_url: https://github.com/unisonweb/unison/releases/tag/release/1.1.0
ingested: 2026-09-12
sha256: 1407f768a6eee9004e2f9d01413bbf9d30cf9e44768b688e8c3432f8866048bf
---
# release/1.1.0

# Release: unisonweb/unison release/1.1.0

- Repository: unisonweb/unison | A friendly programming language from the future | 7K stars | Haskell
- Author: [@github-actions[bot]](https://github.com/github-actions[bot])
- Created: 2026-01-28T16:49:28Z
- Published: 2026-01-28T23:22:38Z
- Reactions: 👍 2

## What's Changed

Features:

- The `dependents` command now work on constructors and ability requests. (https://github.com/unisonweb/unison/pull/6115)
- Support for "Edit Definition" and "Open on Share" in the Unison Language VS Code extension v1.5.0. (https://github.com/unisonweb/unison/pull/6129, https://github.com/unisonweb/unison/pull/6105)
- Adds new builtins for Argon2id password hashing. (https://github.com/unisonweb/unison/pull/6094, thanks @bbarker!)
- Adds MCP tools for `history`, `reflog`, and `share-project-info` (for authenticated project lookups). (https://github.com/unisonweb/unison/pull/6103, https://github.com/unisonweb/unison/pull/6118, also @bbarker)
- More FFI work (https://github.com/unisonweb/unison/pull/6131).

Fixed:

- `Bytes` decoding and comparisons are much faster.
- `run` now allows unquoted numbers as arguments; sorry.
- `branch.diff` now accepts numbered args and branch hashes.
- `run` now gives a nicer message if the program name is ambiguous.(https://github.com/unisonweb/unison/pull/6111)
- `update` no longer leaves deleted constructors in the underlying namespace of an update branch.
- `cases` now parses correctly in Doc eval blocks.
- The MCP server to avoid the use of `oneOf` in JSON Schema, which was defined in 2014 and will surely be supported by coding agents any moment now.
- A certain kind of infinite loop no longer occurs in the runtime. (https://github.com/unisonweb/unison/issues/5889)
- Fixed a backwards subtyping check in pattern type checking. (thanks to @lJoublanc for reporting!)
- Fixed a typo in the `reflog` .(showing `alias.type` as `alias.term`)
- Fixed a pattern-matching bug around duplicate binding names .(thanks to @jcwilk, @etorreborre, and @gvolpe for reporting!)

ucm 1.1.0 updates the codebase version (not backwards-compatible) in order to support syncing of history comments.

## All PRs Since Last Release

- claude seems to not support the "oneOf" type. by @stew in https://github.com/unisonweb/unison/pull/6095
- Add a missing case to the lambda lifting transformation by @dolio in https://github.com/unisonweb/unison/pull/6093
- Fix backwards subtyping checks in pattern type checking by @dolio in https://github.com/unisonweb/unison/pull/6087
- delete Relative path type by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6097
- fix reflog typo by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6092
- bugfix: disallow duplicate binders by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6090
- Add some better implementations for some bytes reading/decoding functions by @dolio in https://github.com/unisonweb/unison/pull/6104
- Open on share VS-Code plugin api endpoint by @ChrisPenner in https://github.com/unisonweb/unison/pull/6105
- diff.branch: include current branch in completion by @ceedubs in https://github.com/unisonweb/unison/pull/6102
- Rework Bytes Chunk type and tweak comparison by @dolio in https://github.com/unisonweb/unison/pull/6112
- improve ambiguous `run` error message by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6111
- allow delete.force to delete things out of lib by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6088
- make `dependents` work on constructors by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6115
- make `alias.type` name the constructors as well by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6099
- Remove unused scratch files by @ceedubs in https://github.com/unisonweb/unison/pull/6114
- Added message argument to history.comment by @ChrisPenner in https://github.com/unisonweb/unison/pull/6123
- Implements the Pull side of comment sync by @ChrisPenner in https://github.com/unisonweb/unison/pull/6117
- Hash history comments and sign them with the author's personal key. by @ChrisPenner in https://github.com/unisonweb/unison/pull/6004
- History Comment Sync API by @ChrisPenner in https://github.com/unisonweb/unison/pull/6017
- disallow adding or updating things in lib with `update` by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6083
- Replace pseudo-extensible Foreign with a big union by @dolio in https://github.com/unisonweb/unison/pull/6125
- Add Argon2id password hashing builtins; switch from cryptonite to crypton by @bbarker in https://github.com/unisonweb/unison/pull/6094
- Fix install-hooks.bash script by @sellout in https://github.com/unisonweb/unison/pull/5910
- Edit Commands for VS Code plugin by @ChrisPenner in https://github.com/unisonweb/unison/pull/6129
- bugfix: `update` no longer leaves deleted constructors in underlying namespace of update branch by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6133
- generate cabal files by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6132
- Add additional FFI types and pointer operations by @dolio in https://github.com/unisonweb/unison/pull/6131
- bugfix: fix `cases` parsing in doc eval block by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6137
- Don't expand numbers in non-structured arguments by @ChrisPenner in https://github.com/unisonweb/unison/pull/6135
- Add share project info MCP tool by @bbarker in https://github.com/unisonweb/unison/pull/6118
- properly handle hashes and numbered args in branch.diff arg parser by @mitchellwrosen in https://github.com/unisonweb/unison/pull/6142
- Add Reflog and History MCP Tools by @bbarker in https://github.com/unisonweb/unison/pull/6103
- update help for branch.squash by @aryairani in https://github.com/unisonweb/unison/pull/6146

**Full Changelog**: https://github.com/unisonweb/unison/compare/release/1.0.2...release/1.1.0

---

## Assets

| File | Size | Downloads |
| --- | --- | --- |
| ucm-linux-arm64.tar.gz | 41442 KB | 69 downloads |
| ucm-linux-x64.tar.gz | 36493 KB | 1181 downloads |
| ucm-macos-arm64.tar.gz | 53856 KB | 415 downloads |
| ucm-macos-x64.tar.gz | 24049 KB | 35 downloads |
| ucm-windows-x64.zip | 40130 KB | 44 downloads |
