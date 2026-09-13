---
title: "Q18: The shape of main and the first real platform"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [effects, runtime, syntax]
sources: [spec/design-v0/03-semantics.md, spec/grammar.md]
number: 18
status: answered
answer: in
asked: 2026-09-12
---

# Q18: The shape of `main` and the first real platform

The milestone runs modules and their tests. Nothing yet runs a program: `main` is not in the grammar, and `Mo.Server` does not exist. This is the first surface a user of Mo touches, so it is Robert's call; the recommendation is written so that "in" is enough.

## Option A: `main` is a known shape, like `update`

```ruby
fn main(platform: Platform)
  fs = platform.fs.scoped(".").read_only
  case summarize(fs, platform.args)
    Ok(report): platform.stdout.write(report)
    Error(e): platform.stderr.write("#{e}")
  end
end
```

No return type, exactly as `fn update(state, message)` has none. Every `Result` inside is consumed by the honesty law, so errors are handled in `main` and printed by the program. Exit code is 0, or whatever `platform.exit(code)` was last given, or 70 with a crash report if `main` crashes.

## Option B: `main` returns a `Result`

```ruby
fn main(platform: Platform) : Result(Unit, AppError)
  fs = platform.fs.scoped(".").read_only
  report = try summarize(fs, platform.args)
  platform.stdout.write(report)
  Ok(Unit)
end
```

`try` works at the top; the runtime prints the error and exits 1. Costs a `Unit` type and value the language does not have.

**Recommendation:** **A.** Zero new syntax, zero new types, one rule a reader already knows from `update`. The `case` at the bottom of `main` is the program's error policy, visible at the spec altitude. B can be added later if programs keep writing the same `case`.

## The platform, minimal

`Platform` is a struct of capabilities, obtained only by `main`: `args: List(String)`, `env: Env`, `stdout: Out`, `stderr: Out`, `fs: Fs`, `clock: Clock`, `exit(code)`. `Out.write(s)` cannot wait, so no `within:`. `Mo.Server` implements them in Zig over `std.Io`; `Mo.Sim` keeps the fixtures. `mo run file.mo -- args` runs `main` on `Mo.Server`; `mo test` never touches it. Network and database come with the program that needs them.

## Which program first

Q14 put the job queue first, but it needs HTTP and a database before the first line runs. **Recommendation:** program 2 from the [[program-menu]], the CLI log analyzer, first: it needs only the minimal platform above, is pure code otherwise, and tests "is Mo pleasant with no concurrency" and the stdlib ceiling before anything else. The job queue follows as soon as the platform grows a socket.

## Answer

✅ **Robert: IN** (session 5). `main` is a known shape like `update`, the minimal platform as listed, the CLI log analyzer before the job queue.

## Related
- [[q14-first-real-program]]
- [[program-menu]]
- [[d15-effects-via-capabilities]]
- [[decision-log]]
