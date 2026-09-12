---
title: "Direction 31: Effects never hide in a value"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [effects, syntax]
sources: [research/comparisons/koka.md, research/comparisons/bosque.md]
number: 31
status: liked
origin: "Claude's recommendation, Robert: in (session 3)"
---

# Direction 31: Effects never hide in a value

Resolves tension 1 of the [[comparison-synthesis-draft]]. A closure that captures a capability would do I/O that no signature shows, which breaks [[d15-effects-via-capabilities|direction 15]] and lets a "no capabilities" package act through stored callbacks ([[q17-package-management-and-supply-chain|Q17]]).

The rule (Bosque's, adopted):

- Anonymous functions (`fn(x) ... end`) appear only as call arguments. They are never bound to a name, stored in a struct, or returned.
- Their captures are read-only.
- Named `fn`s are top-level and capture nothing, so a named function used as a value carries its capabilities in its own signature.

```ruby
cs.filter(fn(c) db.exists?(c.id, within: 50.ms) end)   # ok: dies when filter returns
pred = fn(c) db.exists?(c.id) end                       # error: anonymous fn bound to a name
fn make_reader(fs: Fs) : fn(Path) : Bytes ... end       # error: returns an anonymous fn
handlers = [on_refund]                                  # ok: named fn, effects in its signature
```

Consequence: a captured capability cannot outlive the call, so the enclosing function's signature still bounds every effect. Narrowing (`fs.scoped(...)`, [[p13-capabilities-and-logging|pick 13]]) is unaffected: it returns a capability, not a closure.

Cost: no currying, no stored closures. "Call me later" in Mo is a process and a message ([[d14-processes-are-the-only-identity|direction 14]]).

Reopen if: measurement under [[d28-nothing-final-until-measured|direction 28]] shows agents need returned closures; the fallback is System C-style function types that record captures.

## Related
- [[d15-effects-via-capabilities]]
- [[p11-loops-and-anonymous-functions]]
- [[koka]]
- [[bosque]]
