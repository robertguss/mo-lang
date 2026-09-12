#!/usr/bin/env python3
"""Thin Exa client for research. Needs EXA_API_KEY in the environment (Robert keeps it in ~/.zshenv).

  python3 tools/exa.py search "query" [-n 10] [--category research paper|github|news|...] [--since 2025-01-01]
  python3 tools/exa.py contents URL [URL ...]          # full page text as markdown
  python3 tools/exa.py answer "question"               # Exa's grounded answer with citations
  python3 tools/exa.py research "task" [--model exa-research|exa-research-pro]   # deep research; polls until done
"""
import argparse, json, os, sys, time, urllib.request

KEY = os.environ.get("EXA_API_KEY")
if not KEY:
    sys.exit("EXA_API_KEY not set; run: source ~/.zshenv")
BASE = "https://api.exa.ai"

def call(path, body=None, method="POST"):
    req = urllib.request.Request(BASE + path, data=json.dumps(body).encode() if body is not None else None, method=method,
                                 headers={"x-api-key": KEY, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)

def search(a):
    body = {"query": a.query, "numResults": a.n, "type": "auto", "contents": {"highlights": {"maxCharacters": 400}}}
    if a.category: body["category"] = a.category
    if a.since: body["startPublishedDate"] = a.since
    for r in call("/search", body)["results"]:
        print(f"- {r.get('title')}\n  {r.get('url')}  ({r.get('publishedDate','')[:10]})")
        for h in r.get("highlights", [])[:1]: print(f"  > {h.strip()[:300]}")

def contents(a):
    for r in call("/contents", {"urls": a.urls, "text": True})["results"]:
        print(f"# {r.get('title')}\nsource: {r.get('url')}\n\n{r.get('text','')}\n\n---\n")

def answer(a):
    d = call("/answer", {"query": a.query, "text": False})
    print(d.get("answer", ""))
    print("\nSources:")
    for i, c in enumerate(d.get("citations", []), 1): print(f"[{i}] {c.get('title')} — {c.get('url')}")

def research(a):
    d = call("/research/v1", {"model": a.model, "instructions": a.task})
    rid = d.get("researchId") or d.get("id")
    print(f"research id: {rid}", file=sys.stderr)
    while True:
        time.sleep(15)
        s = call(f"/research/v1/{rid}", method="GET")
        st = s.get("status")
        print(f"  status: {st}", file=sys.stderr)
        if st in ("completed", "failed", "canceled"):
            if st != "completed": sys.exit(json.dumps(s, indent=1))
            out = s.get("output", {})
            print(out.get("content") if isinstance(out, dict) else out)
            for i, c in enumerate(s.get("citations", []) if isinstance(s.get("citations"), list) else [], 1):
                print(f"[{i}] {c.get('title')} — {c.get('url')}")
            return

p = argparse.ArgumentParser(); sub = p.add_subparsers(dest="cmd", required=True)
s = sub.add_parser("search"); s.add_argument("query"); s.add_argument("-n", type=int, default=10); s.add_argument("--category"); s.add_argument("--since"); s.set_defaults(f=search)
c = sub.add_parser("contents"); c.add_argument("urls", nargs="+"); c.set_defaults(f=contents)
n = sub.add_parser("answer"); n.add_argument("query"); n.set_defaults(f=answer)
r = sub.add_parser("research"); r.add_argument("task"); r.add_argument("--model", default="exa-research"); r.set_defaults(f=research)
a = p.parse_args(); a.f(a)
