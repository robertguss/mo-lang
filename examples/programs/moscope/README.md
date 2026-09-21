# moscope

`moscope` is a small, serial, local-only search CLI for Claude Code JSONL
histories. This directory is source-only: the implementation and synthetic
expectations have not been compiled or run.

```text
moscope search "connection refused" ./sessions/
moscope search "connection refused" ./sessions/ --all-words
moscope search "connection refused" ./sessions/ --include-tools
```

Flags may combine and may follow or precede the two positional values after
`search`. Duplicate flags, unsupported flags, a positional count other than two,
an empty/all-ASCII-whitespace query, more than 4 KiB of query, or more than 64
all-words terms are usage errors.

Exit status is 0 for a complete search with matches, 1 for a complete search
without matches, and 2 for usage errors or any incomplete search. Partial
matches are still printed when the search is incomplete. The current `Out` API
does not report write failures, so a status cannot certify that a downstream
stdout consumer received all output.

## Search rules

- Matching is literal substring matching. It is ASCII-case-insensitive: bytes
  `A` through `Z` fold to `a` through `z`; non-ASCII text is exact. There is no
  regex, fuzzy, semantic, or word-boundary behavior.
- The default phrase must occur inside one eligible text block.
- `--all-words` splits on ASCII space, tab, LF, vertical tab, form feed, and CR.
  Every term must be a substring somewhere in the same logical message, but
  terms may occur in different eligible blocks.
- Default eligibility is user-role conversation text plus visible assistant
  `text` blocks. `--include-tools` additionally searches labelled `tool_use`
  names/JSON arguments and `tool_result` text. Thinking, redacted thinking,
  images, and records marked `isMeta`, `isCompactSummary`, or
  `isApiErrorMessage` are deliberately excluded.
- Images are not searchable text. Unknown conversation block/content shapes make
  the search incomplete. Unknown top-level bookkeeping kinds are counted
  diagnostically and ignored, not globally rejected.
- A user-role record is not claimed to be human-authored. Unmarked injected
  prose cannot be reliably identified and remains eligible.

### Supported conversation shapes

| Shape                                                                                 | Behavior                                                 |
| ------------------------------------------------------------------------------------- | -------------------------------------------------------- |
| top-level `type` `user`/`assistant`; object `message`; matching string `message.role` | supported                                                |
| `message.content` string                                                              | one conversation text block                              |
| content object `type: "text"` with string `text`                                      | one conversation text block                              |
| `thinking`, `redacted_thinking`, `image`                                              | known and excluded                                       |
| `tool_use` with string `name` and any JSON `input`                                    | labelled tool block, opt-in                              |
| `tool_result` with string content or array text/image parts                           | independent labelled text parts, opt-in; images excluded |
| any other conversation shape or malformed field used above                            | diagnosed incomplete                                     |
| any other top-level `type`                                                            | counted as unknown bookkeeping and not searched          |

## Identity and ordering

Logical messages are grouped **within one file** by session identity, role, and
`message.id`. A missing message ID uses that physical line, so two missing IDs
never merge. Repeated assistant IDs may contribute distinct blocks; blocks are
not concatenated into synthetic text. Every retained block keeps source path,
physical line, local content-array index, and an explicit `apiBlockIndex` when
supplied. A local index of zero is never substituted for a missing API index.

UUID handling is also file-local. The first record for a UUID is kept. A later
record is deduplicated only when its **complete decoded `Json` value is
structurally equal** to the first; JSON spelling and object key order are
therefore not the policy. A structurally different record with the same UUID is
diagnosed incomplete and neither overwrites nor augments the first.

Equal session IDs across files share one output heading, but messages are never
reconciled or deduplicated across files; paths and lines remain visible. A
missing session ID gets a distinct file-fallback session key. Parent/fork graphs
are not reconstructed.

Session headings are ordered by the latest valid timestamp attached to an
eligible conversation block anywhere in that session, independent of the query.
Tool, thinking, image, meta, and bookkeeping activity does not advance it.
`Time.parse` normalizes RFC 3339 offsets and retains millisecond precision;
finer fractional distinctions are not promised. Missing timestamps sort last.
Stable ties use session label/key. Within a shared heading, paths sort first and
physical conversation order is retained within each file.

## Filesystem and safety

The program establishes `platform.fs.scoped(DIR).read_only` once, then narrows
only from that root. Every directory is obtained with sorted `list`, and each
name is checked separately with observable `kind_of`; `list_kinds` is
intentionally not used because its implementation can fall back to a
directory-entry kind after stat failure. Hidden directories are included.
Discovered symlinks are never followed and are counted as deliberate skips, not
errors. Stat/list failures, unreadable directories, a nonregular `.jsonl`
candidate, size/read failure, malformed JSON, a truncated record, unsupported
conversation shape, UUID conflict, or a limit makes the result incomplete.

The operator-supplied root anchor may itself follow a symlink in the current
runtime. The runtime's descriptor-relative descendant lookup refuses discovered
symlinks, but moscope does not promise a filesystem snapshot or safety against
concurrent mutation. Size admission occurs before reading and assumes stable
local input; growth detected while folding is incomplete.

A complete final JSON record without LF is valid. `fold_lines` replaces
malformed UTF-8 bytes with U+FFFD without saying whether U+FFFD was original or
replacement, so moscope conservatively marks any line containing U+FFFD
incomplete. It may still show partial results.

All transcript-derived text, filenames, session/message IDs, labels, unknown
kinds, and diagnostic fields use one terminal-safe encoding. Printable ASCII
passes except backslash, which doubles. Controls and every byte of non-ASCII
UTF-8 become uppercase `\xNN`; this conservative rule prevents raw C0, DEL, C1,
bidi, and other Unicode terminal controls from reaching output.

## Fixed limits

| Limit                                       |                       Value |
| ------------------------------------------- | --------------------------: |
| query / all-words terms                     |                  4 KiB / 64 |
| traversal depth / entries / JSONL files     |         24 / 50,000 / 5,000 |
| one file / aggregate admitted bytes         |              64 MiB / 1 GiB |
| one line / records per file / total records | 1 MiB / 200,000 / 1,000,000 |
| retained logical messages / blocks          |           100,000 / 500,000 |
| matching messages / retained diagnostics    |             10,000 / 10,000 |
| escaped excerpt / rendered output           |           240 bytes / 8 MiB |
| one filesystem call / processing deadline   |                 10 s / 60 s |

These are deliberately fixed: large enough for realistic local histories, small
enough to expose a clear stop rather than grow without bound, and not a
configuration framework. Exceeding one returns status 2.

They are admission/retention bounds, not hostile-input memory or cancellation
guarantees. `list` materializes a directory before the app can count it.
`fold_lines` reads synchronously, only bounds its pending partial line
internally, and cannot stop the underlying read when the callback stops
decoding. Deadlines are checked between calls/lines. JSON's depth limit is not a
total-byte bound. The file size gate and stable-local-input assumption are
therefore necessary.

## Synthetic source cases

See [`fixtures/MANIFEST.md`](fixtures/MANIFEST.md). All content is invented. The
expected files are independently hand-authored, not generated goldens.

For filesystem cases Git cannot preserve, a later authorized verifier can copy
`fixtures/smoke` to a temporary directory and, before invoking moscope:

```sh
# UNEXECUTED setup examples
mkdir unreadable && chmod 000 unreadable
mkfifo special.jsonl
ln -s "$PWD" root-link
```

Restore permission before deleting the temporary tree. `unreadable` tests a list
failure, `special.jsonl` tests nonregular admission, and `root-link`
demonstrates the documented operator-supplied anchor behavior. Depth, count,
byte, record, retained-value, result, output, and deadline boundaries can be
generated in a disposable tree; they are not committed as giant files.

## Unexecuted readiness packet

Candidate interpreter smoke command from the repository root:

```sh
toolchain/zig-out/bin/mo run examples/programs/moscope/main.mo -- \
  search "connection refused" examples/programs/moscope/fixtures/smoke
```

Independently expected artifacts:

- stdout: `expected/smoke-phrase.stdout`
- stderr: `expected/smoke-phrase.stderr`
- status: `expected/smoke-phrase.status` (0)

That tiny tree covers hidden recursion, two skipped symlinks (including a cycle
and a would-be match), default eligibility, query-independent ordering, shared
and missing sessions, timezone normalization, unknown bookkeeping, and a valid
final record without LF. The source must be reviewed before any execution grant.
No source-complete claim here implies runnable, safe, verified, or accepted.
