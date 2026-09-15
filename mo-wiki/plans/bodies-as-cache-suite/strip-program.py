#!/usr/bin/env python3
"""Strip every function body in a Mo program to the spec a fresh agent regenerates it from
(mo-wiki/plans/bodies-as-cache.md, measurement 1 of direction 43).

Kept, in every module: the `# run:` headers, the module, expose, and use lines, `intent`, every
`never`, every struct, enum, type, and recipe line, every `process` and `supervisor` block with its
state, invariants, and message lines, every function's signature with its comment and its
`requires`/`ensures` lines (top-level and inside a process), and every test, test-rejects, and
property block as written. Gone: every function body and the `verified:` line.

usage: strip-program.py <program-dir>     rewrites every .mo file in place
"""
import re, sys, os

def signature_lines(lines, i, indent):
    """From the fn line at i, return (kept lines, index after the fn's end)."""
    head = [lines[i]]
    j = i
    # a signature may wrap: keep joining while the line does not yet show a return type or a closing paren
    while not re.search(r"\)\s*(:\s*\S.*)?$", head[-1].rstrip()) and j + 1 < len(lines):
        j += 1; head.append(lines[j])
    kept = list(head)
    j += 1
    body_indent = indent + "  "
    # contract lines first
    while j < len(lines) and (lines[j].startswith(body_indent + "requires ") or lines[j].startswith(body_indent + "ensures ")):
        kept.append(lines[j]); j += 1
    kept.append(body_indent + "# body gone; regenerate")
    # skip to the fn's own `end`
    while j < len(lines) and lines[j] != indent + "end":
        j += 1
    kept.append(indent + "end")
    return kept, j + 1

def strip(text):
    lines = text.split("\n")
    out = []
    i = 0
    in_test = False
    while i < len(lines):
        ln = lines[i]
        if re.match(r"(test|test rejects|property)\b", ln):
            # a test block is kept whole, to its `end` at column 0
            out.append(ln); i += 1
            while i < len(lines) and lines[i] != "end":
                out.append(lines[i]); i += 1
            if i < len(lines): out.append(lines[i]); i += 1
            continue
        m = re.match(r"^(\s*)fn\s+[A-Za-z_][A-Za-z0-9_?!]*\s*\(", ln)
        if m and not ln.rstrip().endswith("end"):
            kept, i = signature_lines(lines, i, m.group(1))
            out.extend(kept)
            continue
        if ln.startswith("verified:"):
            i += 1
            while i < len(lines) and lines[i].startswith(" "):
                i += 1
            continue
        out.append(ln); i += 1
    text = "\n".join(out)
    return re.sub(r"\n{3,}", "\n\n", text).rstrip("\n") + "\n"

def main():
    d = sys.argv[1]
    before = after = 0
    for name in sorted(os.listdir(d)):
        if not name.endswith(".mo"): continue
        p = os.path.join(d, name); src = open(p).read()
        out = strip(src)
        open(p, "w").write(out)
        before += src.count("\n"); after += out.count("\n")
        print(f"{name}: {src.count(chr(10))} -> {out.count(chr(10))} lines")
    print(f"total {before} -> {after} lines")

if __name__ == "__main__": main()
