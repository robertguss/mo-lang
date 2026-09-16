#!/usr/bin/env python3
"""Strip a Mo module to the spec a fresh agent regenerates it from (mo-wiki/plans/sampling-as-verification.md).

Kept: the module, expose, and use lines, `intent`, every `never`, every struct and enum with the
comment above it, the signature of every exposed function and of every function a test or
property calls (with its comment and its `requires`/`ensures` lines), every test, test-rejects,
and property block as written. Gone: every body, every other function, the `verified:` line.

usage: strip.py board.mo > board.stripped.mo
"""
import re, sys

src = open(sys.argv[1]).read().split("\n")

# --- split into top-level items: (kind, name, lines, comment_lines) ---
items = []
i = 0
pending_comment = []
def block_end(start):
    j = start + 1
    while j < len(src) and src[j] != "end":
        j += 1
    return j
while i < len(src):
    line = src[i]
    if line.startswith("#"):
        pending_comment.append(line); i += 1; continue
    if line.strip() == "":
        pending_comment = []; i += 1; continue
    m = re.match(r"(fn|struct|enum|test rejects|test|property|never|process)\b\s*(\S*)", line)
    if m:
        kind = m.group(1)
        name = m.group(2)
        if kind == "fn":
            name = re.match(r"fn\s+([A-Za-z_][A-Za-z0-9_?!]*)", line).group(1)
        if kind == "fn" and line.rstrip().endswith("end"):
            j = i
        else:
            j = block_end(i)
        items.append((kind, name, src[i:j + 1], pending_comment))
        pending_comment = []; i = j + 1; continue
    if line.startswith("verified:"):
        i += 1
        while i < len(src) and src[i].startswith(" "):
            i += 1
        continue
    items.append(("line", "", [line], pending_comment)); pending_comment = []; i += 1

expose = set()
for kind, _, lines, _ in items:
    if kind == "line" and lines[0].startswith("expose "):
        expose = {x.strip() for x in lines[0][len("expose "):].split(",")}

fn_names = {name for kind, name, _, _ in items if kind == "fn"}
called = set()
for kind, _, lines, _ in items:
    if kind in ("test", "test rejects", "property"):
        for ln in lines:
            for ident in re.findall(r"\b([a-z_][A-Za-z0-9_?!]*)\(", ln):
                if ident in fn_names:
                    called.add(ident)

def signature(lines):
    """The fn line (joined if it wraps), then its requires/ensures lines, then `end`."""
    out = []
    k = 0
    head = lines[0]
    while not re.search(r":\s*[A-Za-z(].*$", head) or head.rstrip().endswith(","):
        k += 1
        if k >= len(lines): break
        head = head + "\n" + lines[k]
    out.append(head)
    for ln in lines[k + 1:]:
        s = ln.strip()
        if s.startswith("requires ") or s.startswith("ensures ") or s.startswith("rejects ") or s == "":
            if s: out.append(ln)
        else:
            break
    out.append("  # body gone; regenerate")
    out.append("end")
    return out

kept = []
for kind, name, lines, comment in items:
    if kind == "fn":
        if name in expose or name in called:
            kept.append("\n".join(comment + signature(lines)))
    elif kind in ("struct", "enum", "never", "test", "test rejects", "property", "process"):
        kept.append("\n".join(comment + lines))
    else:
        kept.append("\n".join(comment + lines))

text = "\n\n".join(k for k in kept if k.strip() != "")
text = re.sub(r"\n{3,}", "\n\n", text)
print(text)
