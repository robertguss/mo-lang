---
title: "Pick 16: the one-line if as a value"
created: 2026-09-14
updated: 2026-09-14
type: syntax-pick
tags: [syntax]
sources: [plans/control-run-4.md, plans/interpreter-step-21.md, decisions/decision-log.md]
number: 16
status: liked
---

# Pick 16: the one-line `if` as a value

Robert (14 Sep 2026, morning): "Yes add it." Round 4 lost two loops to a model writing an `if` as a value on one line; step 21 gave it a diagnostic and a `mo fix` back to the block form; this pick adds the form.

```ruby
# a value, one line, both branches required, no statement inside either
label = if n > 1: "lines" else: "line"

# statements keep the block form
if n > 1
  out.line("many")
end
```

The rules, from the pick: the form is an expression only, never a statement; `else:` is required; each branch is one expression; the formatter keeps it on one line when it fits and no comment sits inside, and otherwise writes the block form; `mo fix` no longer rewrites it. The arm form `Pattern: expr` is the same shape, so nothing new is read.

## Related
- [[p04-conditionals|pick 4]]
- [[interpreter-step-25]]
- [[decision-log]]
