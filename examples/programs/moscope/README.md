# moscope

`moscope` is a small, serial, local-only search CLI for Claude Code JSONL
histories. Candidate `f961c686` passed one guarded interpreter phrase smoke with
the accepted compiler: exit 0, 731 stdout bytes, 107 stderr bytes, and four
matches, with both streams byte-exact to the hand-authored expectations. That
was a narrow pre-integration check, not full app acceptance. The frozen
app-local candidate passed the first serial interpreter checkpoint (46 exact
payloads), then a corrective interpreter suite expanded it to 66 payloads: all
eight original triples, 51 additional CLI/filesystem/boundary cases, and all
seven modules' 27 non-writing tests. Every completed payload had literal absent
process-group cleanup. The ordinary native stage then repeated the same 59 CLI
expectations and all seven modules after eight cold builds; all eight generated
C files declared zero processes. Formatter/`--write` release metadata and the
full corpus remain unaccepted. The first metadata attempt stopped when
`mo test --write main.mo` reported MO0304 in `search.mo`; after the reviewed
pure-helper extraction, all seven formatter writes, seven individual metadata
writes, and seven formatter checks passed. Post-metadata interpreter and native
replays are recorded separately from the still-unexecuted full corpus.

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
  the search incomplete. A nonobject record or a record whose top-level `type`
  is missing or nonstring is also incomplete. An unknown string `type` with an
  object `message` is conversation-shaped and incomplete; other well-formed
  unknown string types are counted as bookkeeping and ignored. Unknown metadata
  is therefore neither globally rejected nor silently treated as conversation.
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
| nonobject record; missing/nonstring top-level `type`                                  | diagnosed incomplete                                     |
| unknown string `type` with object `message`                                           | conversation-shaped; diagnosed incomplete                |
| unknown string `type` without object `message`                                        | counted as bookkeeping and not searched                  |

## Identity and ordering

Logical messages are grouped **within one file** by session identity, role, and
`message.id`. The internal key explicitly tags identity as `provided` or
`physical`; a missing ID uses that physical line, so it cannot collide with a
provided string such as `physical:1`, and two missing IDs never merge. The
display label can still read `physical:N`. Repeated genuine assistant IDs may
contribute distinct blocks; blocks are not concatenated into synthetic text.
Every retained block keeps source path, physical line, local content-array
index, and an explicit `apiBlockIndex` when supplied. A local index of zero is
never substituted for a missing API index.

UUID handling is also file-local. The first record for a UUID is kept. A later
record is deduplicated only when its **complete decoded `Json` value is
structurally equal** to the first; JSON spelling and object key order are
therefore not the policy. A structurally different record with the same UUID is
diagnosed incomplete and neither overwrites nor augments the first. The per-file
UUID `seen` map retains each first complete decoded `Json` payload, including
excluded conversation content and bookkeeping, up to the file's admitted input
plus representation/map overhead. It is not a lossy hash and is not a
hard-memory guarantee.

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
kinds, unsupported options, and diagnostic fields use one terminal-safe
encoding. Rendering first takes a bounded source-grapheme prefix, then escapes
it; it never builds a whole rendered logical message before enforcing the output
limit. Printable ASCII passes except backslash, which doubles. Controls and
every byte of non-ASCII UTF-8 become uppercase `\xNN`; this conservative rule
prevents raw C0, DEL, C1, bidi, and other Unicode terminal controls from
reaching output. Result rendering leaves a 512-byte best-effort diagnostic
reserve; headers/paths/labels and diagnostic fields have fixed 256/512-grapheme
source prefixes before escaping. The reserve does not guarantee that a
particular truncation reason or an explicit sentinel is rendered when the
retained issue list is already full or diagnostics alone fill the remaining
space. The result still remains incomplete and therefore status 2.

## Fixed limits

| Limit                                       |                       Value |
| ------------------------------------------- | --------------------------: |
| query / all-words terms                     |                  4 KiB / 64 |
| traversal depth / entries / JSONL files     |         24 / 50,000 / 5,000 |
| one file / aggregate admitted bytes         |              64 MiB / 1 GiB |
| one line / records per file / total records | 1 MiB / 200,000 / 1,000,000 |
| retained logical messages / blocks          |           100,000 / 500,000 |
| matching messages / retained diagnostics    |             10,000 / 10,000 |
| excerpt source prefix / rendered output     |       240 graphemes / 8 MiB |
| one filesystem call / processing deadline   |                 10 s / 60 s |

These are deliberately fixed: large enough for realistic local histories, small
enough to expose a clear stop rather than grow without bound, and not a
configuration framework. Exceeding one returns status 2.

They are admission/retention bounds, not hostile-input memory or cancellation
guarantees. `list` materializes a directory before the app can count it.
`fold_lines` reads synchronously, only bounds its pending partial line
internally, and cannot stop the underlying read when the callback stops
decoding. `FileFold` is data-only: the processing deadline is observed
immediately before and after each whole fold, not between lines, and an expiry
observed after a successful fold retains those results but marks them
incomplete. There is no per-line interruption promise. Discovery still checks
inside each entry iteration and the 10-second filesystem-call deadline remains.
JSON's depth limit is not a total-byte bound. The file size gate and
stable-local-input assumption are therefore necessary.

The 240-grapheme excerpt prefix is not a small byte or allocation guarantee. A
prefix dominated by combining marks can approach the admitted 1 MiB line size,
and bytewise terminal escaping can expand it toward 4 MiB plus intermediate
allocations. Incremental message rendering avoids constructing a whole rendered
logical message, but does not remove those bounds.

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
demonstrates the documented operator-supplied anchor behavior. Actual depth
24/25 trees, byte and line boundaries, and modest filesystem cases are generated
in a disposable tree. Large count, record, retained-value, result, output, and
aggregate-admission boundaries use tiny predicates called by production paths
plus focused state fixtures; they are not materialized as giant trees or files.

## Synthetic exact triples and narrow execution

The working directory for every candidate command below is the repository root.
Each stdout/stderr/status triple is independently hand-authored rather than
recorded from the program. All eight passed byte-exactly under the interpreter.

| Case      | Exact argv after `mo run examples/programs/moscope/main.mo --`                         | Expected stdout / stderr / status                                                                                                                                                       | Manual trace  |
| --------- | -------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------- |
| phrase    | `search "connection refused" examples/programs/moscope/fixtures/smoke`                 | `examples/programs/moscope/expected/smoke-phrase.stdout` / `examples/programs/moscope/expected/smoke-phrase.stderr` / `examples/programs/moscope/expected/smoke-phrase.status`          | 4 matches / 0 |
| all words | `search "connection refused" examples/programs/moscope/fixtures/smoke --all-words`     | `examples/programs/moscope/expected/smoke-all-words.stdout` / `examples/programs/moscope/expected/smoke-all-words.stderr` / `examples/programs/moscope/expected/smoke-all-words.status` | 5 matches / 0 |
| tools     | `search "connection refused" examples/programs/moscope/fixtures/smoke --include-tools` | `examples/programs/moscope/expected/smoke-tools.stdout` / `examples/programs/moscope/expected/smoke-tools.stderr` / `examples/programs/moscope/expected/smoke-tools.status`             | 5 matches / 0 |
| no match  | `search "definitely absent" examples/programs/moscope/fixtures/smoke`                  | `examples/programs/moscope/expected/no-match.stdout` / `examples/programs/moscope/expected/no-match.stderr` / `examples/programs/moscope/expected/no-match.status`                      | 0 matches / 1 |

The full candidate command prefix is:

```sh
/absolute/path/to/accepted-mo run examples/programs/moscope/main.mo --
```

That tiny tree covers hidden recursion, two skipped symlinks (including a cycle
and a would-be match), default eligibility, query-independent ordering, shared
and missing sessions, timezone normalization, unknown bookkeeping, and a valid
final record without LF. The source must be reviewed before any execution grant.
The `status2/*` roots and `expected/status2-*` triples separately cover the four
top-level classification failures. The unreadable/FIFO/root-anchor cases above
still require disposable filesystem setup.

`main.mo` is auto-enrolled by the standard corpus with three whitespace-free,
app-working-directory runs: one positive query, one absent query exiting 1, and
one independently isolated classification error exiting 2. Their
`moscope*.expected` files are hand-authored stdout expectations. The app-local
acceptance verifier separately compares stdout, stderr, and status. No shared
corpus file is changed here, and no source-complete claim implies full
acceptance.

### Manual compatibility checklist

- Every local `var` binding uses `var NAME = EXPR`; empty lists and maps receive
  their type from subsequent use or a typed enclosing initializer.
- Top-level `Json` and `Option` matches enumerate their closed alternatives;
  wildcard patterns remain only nested under named variants or for open string
  values.
- Source inspection places every function at six or fewer parameters and every
  body below 70 lines. Discovery entry handling and tool-result part handling
  are separate functions so nesting is at most three.
- Statement case arms use indented bodies. `FileFold` stores data only, and its
  `fold_lines` callback neither stores nor captures `Clock`.
- `Clock.fixture()` remains limited to app-local test source. These statements
  are source-review observations. All-module interpreter and ordinary native
  tests passed before metadata, and release formatter/metadata commands then
  passed after the reviewed shape fix. The full corpus remains pending.
