# moscope

`moscope` searches your Claude Code session histories: the JSONL files under
`~/.claude/projects`. It prints each matching message with its file and line, an
excerpt around the match, and the command that resumes its session.

```text
$ moscope search "connection refused" ~/.claude/projects
Session 6adfa47b-… — latest 2026-09-21T13:00:00Z
  resume: cd /Users/me/app && claude --resume 6adfa47b-…
  user message physical:12
    /Users/me/.claude/projects/-Users-me-app/6adfa47b-….jsonl:12 user text content[0]
      ...the dev server says connection refused on port 5173 after the upgrade...
1 matching message.
```

## Build and run

From the repository root, build the Mo toolchain once, then build moscope:

```sh
(cd toolchain && zig build)                        # toolchain/zig-out/bin/mo
toolchain/zig-out/bin/mo build examples/programs/moscope/main.mo
# prints zig-out/mo-build/moscope/moscope; copy it onto your PATH
```

Or run it under the interpreter without building:

```sh
toolchain/zig-out/bin/mo run examples/programs/moscope/main.mo -- search "query" ~/.claude/projects
```

## Usage

```text
moscope search [--all-words] [--include-tools] [--strict] [--] <query> <directory>
```

| option            | effect                                                                               |
| ----------------- | ------------------------------------------------------------------------------------ |
| `--all-words`     | match messages holding every whitespace-separated term, possibly in different blocks |
| `--include-tools` | also search tool calls (name and JSON arguments) and tool results                    |
| `--strict`        | treat skipped or unrecognized records as errors, so any warning exits 2              |
| `--`              | end of options; use it before a query that starts with `-`, e.g. `-- --no-verify`    |
| `-h`, `--help`    | print help and exit 0                                                                |

Options may come before, between, or after the query and directory.

**Exit status:** 0 when something matched, 1 when nothing matched, 2 for a usage
error or an incomplete search. With `--strict`, warnings also give 2. Matches
found before a problem are still printed.

## What is searched

- Matching is a literal substring. It is ASCII-case-insensitive (`A`–`Z` fold to
  `a`–`z`), and non-ASCII text matches exactly. There are no regular expressions
  and no word boundaries.
- A phrase must occur inside one block. With `--all-words`, each term may be in
  a different block of the same logical message, and the output shows the blocks
  that hold a term.
- By default, user messages and visible assistant `text` are searched.
  `--include-tools` adds `tool_use` blocks, `tool_result` text, and
  `tool_reference` names.
- Thinking, redacted thinking, images, documents, and records marked `isMeta`,
  `isCompactSummary`, or `isApiErrorMessage` are never searched.
- Records whose `type` is not `user` or `assistant` (titles, snapshots,
  attachments, and so on) are bookkeeping. They are counted in one note line and
  not searched.
- Logical messages are grouped within one file by session, role, and
  `message.id`, and blocks keep their own file, line, and content index. A
  message without an id is keyed by its line, shown as `physical:N`.
- Sessions are ordered newest first by their latest user or assistant text,
  whether or not that text matched. Sessions without timestamps come last.

## Warnings and errors

Claude Code's format changes. moscope reads what it can and says what it skipped
instead of failing the whole search.

- **Warnings** are record-level: a malformed or over-32 MiB line, an unknown
  block or tool-result part, a missing or wrongly typed field, a record type it
  does not know that looks like a conversation, a repeated UUID in one file (the
  first record is kept), or text holding U+FFFD (possibly replaced invalid
  UTF-8). Each category is printed once with its count and first location.
  Warnings do not change the exit status unless `--strict` is given.
- **Errors** make the search incomplete (exit 2): a directory that cannot be
  listed, an entry that cannot be read or checked, a `.jsonl` path that is a
  directory, or a limit below being reached.

## Output safety

Transcript text is shown as readable Unicode. Anything that could control or
disguise the terminal is escaped:

- C0 controls and DEL become `\xNN`, except that LF, tab, and CR show as `\n`,
  `\t`, and `\r`.
- C1 controls, bidi and zero-width format characters, line and paragraph
  separators, BOM, and tag characters become `\u{XXXX}`.
- A backslash is doubled.

The `resume:` line single-quotes any directory or session id that is not a plain
word. Excerpts are 240 graphemes, starting 80 before the first match, and `...`
marks a clipped end.

Discovered symlinks are never followed; they are counted in a note. The
directory you name may itself be a symlink. moscope opens it read-only and never
writes.

## Limits

| limit                                              |                  value |
| -------------------------------------------------- | ---------------------: |
| query bytes / `--all-words` terms                  |             4 KiB / 64 |
| directory depth / entries seen / JSONL files       | 24 / 500,000 / 100,000 |
| one line (longer lines are skipped with a warning) |                 32 MiB |
| candidate messages / matching blocks retained      |      100,000 / 100,000 |
| matching messages printed                          |                 10,000 |
| rendered output                                    |                  8 MiB |
| one filesystem call                                |                   10 s |

moscope reads one line at a time and keeps only matching blocks, each as a
bounded excerpt. Its memory therefore follows the number of matches, not the
size of the history. Hitting a retention or output limit is an error. There is
no overall deadline; press Ctrl-C to stop.

## Tests

```sh
cd examples/programs/moscope
../../../toolchain/zig-out/bin/mo test <module>.mo   # each module's tests
python3 -B acceptance/check.py                      # 34 CLI cases under mo run
python3 -B acceptance/check.py --native PATH        # the same against a built binary
```

The standard corpus (`zig build test` in `toolchain/`) also runs the three
`# run:` cases at the top of `main.mo`.

`check.py` compares stdout, stderr, and exit status with the files in
`expected/`. The smoke and warning expectations were written by hand. The rest
are goldens produced with `check.py --bless` and reviewed line by line; any
re-bless must be reviewed as a diff. The fixtures are synthetic and described in
[`fixtures/MANIFEST.md`](fixtures/MANIFEST.md). For how moscope was accepted and
measured on real history, see [`ACCEPTANCE.md`](ACCEPTANCE.md).
