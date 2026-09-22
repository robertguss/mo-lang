# moscope synthetic fixture manifest

Every identifier and transcript fragment here is invented. No private transcript
or private-derived content is present.

| Fixture                                   | Source-review purpose                                                                                                                                                                       |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `smoke/a.jsonl`                           | ASCII-case phrase, phrase split across repeated assistant message IDs, explicit API indices, later nonmatching conversation activity, thinking/tool/meta/image exclusion, newer bookkeeping, a cwd needing shell quotes |
| `smoke/.hidden/b.jsonl`                   | hidden recursion, timezone offset, shared session across files, missing-session file fallback, valid final record without LF                                                                |
| `smoke/z.jsonl`                           | a separate missing-session fallback with no timestamp                                                                                                                                       |
| `smoke/link.jsonl`                        | symlink to the would-be matching `outside.jsonl`; must be skipped                                                                                                                           |
| `smoke/.hidden/cycle`                     | discovered directory symlink cycle; must be skipped rather than followed                                                                                                                    |
| `cases/eligibility.jsonl`                 | thinking/meta/image/tool arguments/tool result, punctuation, ASCII versus non-ASCII case, terminal controls in labels and text                                                              |
| `cases/identity.jsonl`                    | interleaved IDs, local index zero versus explicit API index, exact UUID duplicate, UUID conflict, physical fallback IDs                                                                     |
| `cases/identity-kind.jsonl`               | missing line-1 ID versus provided `physical:1`; all-words `alpha omega` must not merge them                                                                                                 |
| `cases/ordering.jsonl`                    | latest nonmatching conversation, newer bookkeeping, timezone offsets, millisecond tie, missing timestamp                                                                                    |
| `cases/malformed-middle.jsonl`            | malformed middle record with valid records before and after                                                                                                                                 |
| `cases/malformed-tail.jsonl`              | truncated final record                                                                                                                                                                      |
| `cases/unsupported.jsonl`                 | unsupported conversation block/content versus unknown bookkeeping                                                                                                                           |
| `cases/tool-parts.jsonl`                  | tool_use arguments, tool_reference name, document and image parts excluded, an unknown part type, a record holding U+FFFD                                                                     |
| `warnings/nonobject/case.jsonl`           | nonobject top-level JSON: a warning, or exit 2 with `--strict`                                                                                                                              |
| `warnings/missing-type/case.jsonl`        | missing top-level type: a warning, or exit 2 with `--strict`                                                                                                                                |
| `warnings/nonstring-type/case.jsonl`      | nonstring top-level type: a warning, or exit 2 with `--strict`                                                                                                                              |
| `warnings/unknown-conversation/case.jsonl` | unknown type with an object message: a warning, or exit 2 with `--strict`                                                                                                                  |

`acceptance/check.py` names every case, what it searches, and its arguments.
Expectations are under `expected/`: the smoke and `warning-*` triples were
written by hand, and the rest are reviewed goldens (see `README.md`). The two
symlinks are committed fixtures. Unreadable directories, depth trees, the
oversized line, and the operator-supplied root symlink are built in a
temporary directory by `check.py`.
