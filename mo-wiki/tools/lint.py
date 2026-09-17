#!/usr/bin/env python3
"""Wiki lint for the Mo Lang vault. Run from the repo root: python3 tools/lint.py"""
import re, sys, hashlib
from pathlib import Path
from collections import defaultdict

ROOT = Path(__file__).resolve().parent.parent
WIKI_DIRS = ["directions", "questions", "decisions", "syntax", "deep-dives", "plans", "sessions", "research", "maps"]
# Link targets that are not wiki pages: the spec artifacts (chapters, programs, grammar, errors), the vault's own
# standing files, and the repo-root handoff. They get no frontmatter, index, or orphan check; a link to them is not broken.
ARTIFACT_DIRS = ["spec"]
STANDING = {"index": "index.md", "log": "log.md", "SCHEMA": "SCHEMA.md", "HANDOFF": "../HANDOFF.md"}
REQUIRED = ["title", "created", "updated", "type", "tags", "sources"]
TYPES = {"direction", "question", "decision", "syntax-pick", "example", "deep-dive", "plan", "session", "comparison", "concept", "research", "map", "synthesis"}

def taxonomy():
    text = (ROOT / "SCHEMA.md").read_text()
    sec = text.split("## Tag taxonomy")[1].split("## ")[0]
    return set(re.findall(r"`([a-z-]+)`", sec))

def frontmatter(text):
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m: return None
    fm = {}
    for line in m.group(1).splitlines():
        if ":" in line:
            k, v = line.split(":", 1); fm[k.strip()] = v.strip()
    return fm

def main():
    tags_ok = taxonomy()
    pages = {}
    for d in WIKI_DIRS:
        for p in (ROOT / d).rglob("*.md"):
            if p.name.startswith("_") or p.name == "README.md": continue
            pages[p.stem] = p
    for p in ROOT.glob("*.md"):  # the root's standing pages (the state of the project); index, log, and SCHEMA are not pages
        if p.name not in ("index.md", "log.md", "SCHEMA.md"): pages[p.stem] = p
    targets = dict(pages)  # everything a [[link]] may name: pages, artifacts, standing files, and path-form links
    for d in ARTIFACT_DIRS:
        for p in (ROOT / d).rglob("*.md"):
            targets.setdefault(p.stem, p)
    for slug, rel in STANDING.items():
        if (ROOT / rel).exists(): targets[slug] = ROOT / rel
    def resolves(link):
        if link in targets: return True
        if "/" in link:  # a path-form link such as research/README, relative to the vault root
            q = ROOT / (link if link.endswith(".md") else link + ".md")
            return q.exists()
        return False
    issues = defaultdict(list)
    inbound = defaultdict(int)
    index_text = (ROOT / "index.md").read_text()
    for slug, p in pages.items():
        text = p.read_text()
        fm = frontmatter(text)
        if fm is None:
            issues["frontmatter"].append(f"{p.relative_to(ROOT)}: missing frontmatter"); continue
        for k in REQUIRED:
            if k not in fm: issues["frontmatter"].append(f"{p.relative_to(ROOT)}: missing `{k}`")
        if fm.get("type") not in TYPES: issues["frontmatter"].append(f"{p.relative_to(ROOT)}: unknown type `{fm.get('type')}`")
        for t in re.findall(r"[a-z-]+", fm.get("tags", "")):
            if t not in tags_ok: issues["tags"].append(f"{p.relative_to(ROOT)}: tag `{t}` not in taxonomy")
        links = set(re.findall(r"\[\[([^\]|#]+)", text))
        for l in links:
            if not resolves(l): issues["broken-links"].append(f"{p.relative_to(ROOT)} -> [[{l}]]")
            else: inbound[l] += 1
        if len(links) < 2: issues["few-links"].append(f"{p.relative_to(ROOT)}: {len(links)} outbound links")
        if f"[[{slug}" not in index_text: issues["index"].append(f"{p.relative_to(ROOT)}: not in index.md")
        if fm.get("contested") == "true" or fm.get("confidence") == "low":
            issues["review"].append(f"{p.relative_to(ROOT)}: contested/low-confidence")
        n = text.count("\n")
        if n > 200: issues["size"].append(f"{p.relative_to(ROOT)}: {n} lines")
    for slug in pages:
        if inbound[slug] == 0: issues["orphans"].append(f"{pages[slug].relative_to(ROOT)}")
    # index entries pointing nowhere
    for l in set(re.findall(r"\[\[([^\]|#]+)", index_text)):
        if not resolves(l): issues["index"].append(f"index.md -> [[{l}]] does not exist")
    # raw drift
    for p in (ROOT / "raw").rglob("*.md"):
        text = p.read_text(); fm = frontmatter(text)
        if fm and "sha256" in fm:
            body = text.split("---\n", 2)[2]
            if hashlib.sha256(body.encode()).hexdigest() != fm["sha256"]:
                issues["raw-drift"].append(f"{p.relative_to(ROOT)}")
    # log size
    entries = len(re.findall(r"^## \[", (ROOT / "log.md").read_text(), re.M))
    if entries > 500: issues["log"].append(f"log.md has {entries} entries; rotate")

    order = ["broken-links", "index", "frontmatter", "tags", "orphans", "raw-drift", "review", "few-links", "size", "log"]
    total = sum(len(v) for v in issues.values())
    print(f"{len(pages)} wiki pages checked, {total} issues")
    for k in order:
        if issues[k]:
            print(f"\n[{k}] ({len(issues[k])})")
            for i in sorted(issues[k]): print("  " + i)
    sys.exit(1 if issues["broken-links"] or issues["index"] or issues["frontmatter"] else 0)

if __name__ == "__main__":
    main()
