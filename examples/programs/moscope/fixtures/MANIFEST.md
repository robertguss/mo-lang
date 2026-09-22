# moscope synthetic fixture manifest

Every identifier and transcript fragment here is invented. No private transcript
or private-derived content is present.

| Fixture                                   | Source-review purpose                                                                                                                                                                       |
| ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `smoke/a.jsonl`                           | ASCII-case phrase, phrase split across repeated assistant message IDs, explicit API indices, later nonmatching conversation activity, thinking/tool/meta/image exclusion, newer bookkeeping |
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
| `status2/nonobject/case.jsonl`            | standalone nonobject top-level JSON status-2 control                                                                                                                                        |
| `status2/missing-type/case.jsonl`         | standalone missing top-level type status-2 control                                                                                                                                          |
| `status2/nonstring-type/case.jsonl`       | standalone nonstring top-level type status-2 control                                                                                                                                        |
| `status2/unknown-conversation/case.jsonl` | standalone unknown type with object message status-2 control                                                                                                                                |

The files under `expected/` are hand-authored expectations, not captured output.
Each `status2` directory is an independent invocation root and maps to the
same-named `expected/status2-*` stdout, stderr, and status triple. The two
symlinks are committed filesystem fixtures. Git cannot portably preserve an
unreadable directory, FIFO, or operator-supplied root symlink; `README.md` gives
unexecuted setup instructions for those cases.
