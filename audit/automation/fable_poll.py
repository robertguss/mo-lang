#!/usr/bin/env python3
"""Fable's receiver for the auditor's handoffs, and its publisher for Fable's own.

Two subcommands.

  fable_poll.py check [--dry-run] [--ledger PATH] [--canary]
      Polls github.com/robertguss/mo-lang once: every open pull request whose head branch
      starts with `audit/`, plus `main`, for JSON records under audit/handoffs/<subject>/<id>.json
      addressed `to: fable` (or `to: auditor` transport-test canaries when --canary is given). Each
      record not yet in the ledger is validated with the same rules as the auditor's intake and
      printed as one neutral line: kind, subject, id, evidence commit, paths, and where it was
      found. The `request` text is printed only for kinds that carry a question or a status
      (working, evidence-needed, escalated, transport-test); for reading-filed and compared the
      pointers are printed and the auditor's files are NOT opened, so the lead can file its own
      reading first. Invalid records are printed once with the reason and remembered. The ledger
      is a JSON file outside the repository (default ~/.mo-lead/fable-intake.json).

  fable_poll.py publish --kind K --subject S --id I --commit SHA --path P [--path P ...]
                        --request TEXT [--in-reply-to ID] [--repo DIR]
      Writes audit/handoffs/S/I.json in the repository at DIR (default the current directory)
      after validating it with the intake's rules for a message from Fable, and after checking
      that every path is a regular file at the pinned commit (`git cat-file`). It does not
      commit; the lead commits the one file by path and pushes it to main.

This script never reads the body of an audit reading. It is run by the lead's own scheduler
(a Claude Code cron in the lead session, hourly) and by hand. It uses `gh` for the GitHub API
so the machine's existing login is the only credential.
"""
import argparse
import base64
import json
import os
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path, PurePosixPath

REPO = 'robertguss/mo-lang'
SHA = re.compile(r'[0-9a-f]{40}')
TOKEN = re.compile(r'[a-z0-9][a-z0-9-]{0,79}')
FIELDS = {'id', 'subject', 'from', 'to', 'kind', 'in_reply_to', 'evidence_commit', 'paths', 'request'}
# What Fable may send (the auditor's intake accepts these), and what the auditor may send to Fable.
FABLE_KINDS = {'working', 'ready', 'evidence-updated', 'parallel-filed'}
AUDITOR_KINDS = {'working', 'evidence-needed', 'reading-filed', 'compared', 'escalated', 'transport-test'}
# Kinds whose free text is a question or a status, safe to show before Fable's own reading is filed.
SHOW_REQUEST = {'working', 'evidence-needed', 'escalated', 'transport-test'}
SYNTHESIS = ('fable-reading', 'decision-log', 'for-fable', 'results.md')
DEFAULT_LEDGER = Path(os.environ.get('MO_FABLE_INTAKE', str(Path.home() / '.mo-lead' / 'fable-intake.json')))


def validate(m, path, direction):
    """direction: 'to-fable' for the auditor's records, 'from-fable' for Fable's own."""
    if not isinstance(m, dict) or set(m) != FIELDS:
        raise ValueError('wrong message fields')
    for field in ('id', 'subject'):
        if not isinstance(m[field], str) or not TOKEN.fullmatch(m[field]):
            raise ValueError('invalid identifier')
    if path != f"audit/handoffs/{m['subject']}/{m['id']}.json":
        raise ValueError('message path/ID mismatch')
    if direction == 'to-fable':
        if m['from'] != 'auditor' or m['to'] != 'fable' or m['kind'] not in AUDITOR_KINDS:
            raise ValueError('unsupported sender, recipient, or kind')
    elif direction == 'canary':
        if m['from'] != 'auditor' or m['kind'] != 'transport-test':
            raise ValueError('not a transport canary')
    else:
        if m['from'] != 'fable' or m['to'] != 'auditor' or m['kind'] not in FABLE_KINDS:
            raise ValueError('unsupported sender, recipient, or kind')
    if not isinstance(m['evidence_commit'], str) or not SHA.fullmatch(m['evidence_commit']):
        raise ValueError('full lowercase commit SHA required')
    if m['in_reply_to'] is not None and not TOKEN.fullmatch(str(m['in_reply_to'])):
        raise ValueError('invalid reply identifier')
    if m['kind'] == 'evidence-updated' and m['in_reply_to'] is None:
        raise ValueError('evidence update needs a reply identifier')
    if not isinstance(m['request'], str) or len(m['request']) > 2000:
        raise ValueError('bounded request required')
    if not isinstance(m['paths'], list) or not 1 <= len(m['paths']) <= 30:
        raise ValueError('bounded evidence path list required')
    for p in m['paths']:
        if not isinstance(p, str) or len(p) > 240 or not re.fullmatch(r'[A-Za-z0-9_./-]+', p):
            raise ValueError('invalid evidence path')
        if p.startswith('/') or '..' in PurePosixPath(p).parts or str(PurePosixPath(p)) != p:
            raise ValueError('noncanonical evidence path')
        if direction == 'from-fable' and m['kind'] != 'parallel-filed' and any(x in p.lower() for x in SYNTHESIS):
            raise ValueError('synthesis pointer forbidden at intake')
    if m['kind'] == 'parallel-filed':
        if not any(p.startswith('audit/mo-audit-') for p in m['paths']) or not any(p.startswith('audit/fable-reading-') for p in m['paths']):
            raise ValueError('comparison needs both committed reading paths')
        if not all(p.startswith(('audit/mo-audit-', 'audit/fable-reading-')) for p in m['paths']):
            raise ValueError('comparison only accepts filed reading paths')
    return m


# ---- GitHub, through gh -----------------------------------------------------------------------

def gh(endpoint):
    out = subprocess.run(['gh', 'api', endpoint], capture_output=True, text=True)
    if out.returncode != 0:
        raise RuntimeError(f'gh api {endpoint}: {out.stderr.strip()[:200]}')
    return json.loads(out.stdout)


def handoff_paths(sha):
    tree = gh(f'repos/{REPO}/git/trees/{sha}?recursive=1')
    if tree.get('truncated'):
        print(f'WARN tree at {sha[:7]} truncated; some records may be unseen', file=sys.stderr)
    return [x['path'] for x in tree.get('tree', [])
            if x['type'] == 'blob' and x['path'].startswith('audit/handoffs/') and x['path'].endswith('.json')]


def fetch_json(sha, path):
    blob = gh(f'repos/{REPO}/contents/{path}?ref={sha}')
    return json.loads(base64.b64decode(blob['content']).decode())


def sources():
    """Where records may sit: every open audit/* pull request's head, then main."""
    out = []
    for pr in gh(f'repos/{REPO}/pulls?state=open&per_page=50'):
        if pr['head']['ref'].startswith('audit/'):
            out.append((f"PR #{pr['number']} {pr['html_url']}", pr['head']['sha']))
    main = gh(f'repos/{REPO}/git/ref/heads/main')['object']['sha']
    out.append(('main', main))
    return out


def load_ledger(path):
    if path.exists():
        return json.loads(path.read_text())
    return {'seen': {}}


def save_ledger(path, ledger):
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix('.tmp')
    tmp.write_text(json.dumps(ledger, indent=2, sort_keys=True) + '\n')
    tmp.replace(path)


def fable_reading_exists(main_sha, subject):
    try:
        listing = gh(f'repos/{REPO}/contents/audit?ref={main_sha}')
    except RuntimeError:
        return None
    return any(x['name'].startswith('fable-reading-') and x['name'].endswith(f'-{subject}.md') for x in listing)


def check(args):
    ledger = load_ledger(args.ledger)
    seen = ledger['seen']
    new = 0
    srcs = sources()
    main_sha = srcs[-1][1]
    for where, sha in srcs:
        for path in handoff_paths(sha):
            key = f'{path}@{sha}' if where != 'main' else path
            # A record is one message: once seen at any ref it is not re-announced from another.
            if path in seen or key in seen:
                continue
            try:
                m = fetch_json(sha, path)
            except Exception as e:  # noqa: BLE001
                print(f'INVALID {path} at {sha[:7]}: unreadable ({e})')
                seen[key] = {'status': 'unreadable', 'at': now()}
                continue
            if isinstance(m, dict) and m.get('from') == 'fable':
                continue  # our own records; nothing to receive
            direction = 'to-fable'
            if args.canary and isinstance(m, dict) and m.get('kind') == 'transport-test':
                direction = 'canary'
            try:
                validate(m, path, direction)
            except ValueError as e:
                print(f'INVALID {path} at {sha[:7]}: {e}')
                seen[path] = {'status': 'invalid', 'reason': str(e), 'at': now()}
                continue
            new += 1
            line = (f"NEW kind={m['kind']} subject={m['subject']} id={m['id']} "
                    f"in_reply_to={m['in_reply_to']} evidence_commit={m['evidence_commit']} "
                    f"paths={json.dumps(m['paths'])} found_in={where}")
            print(line)
            if m['kind'] in SHOW_REQUEST:
                print(f"  request: {m['request']}")
            elif m['kind'] == 'reading-filed':
                filed = fable_reading_exists(main_sha, m['subject'])
                if filed:
                    print("  the lead's reading for this subject is on main: publish parallel-filed naming both files")
                else:
                    print("  FILE FIRST: no audit/fable-reading-*-{subject}.md on main; write and push it before opening the auditor's file".replace('{subject}', m['subject']))
            else:
                print("  (pointers only; the auditor's text is not shown here)")
            seen[path] = {'status': 'announced', 'kind': m['kind'], 'subject': m['subject'], 'found_in': where, 'sha': sha, 'at': now()}
    if not args.dry_run:
        save_ledger(args.ledger, ledger)
    print(f'checked {len(srcs)} refs, {new} new record(s), {now()}')
    return 0


def now():
    return datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')


# ---- publish ------------------------------------------------------------------------------------

def publish(args):
    m = {
        'id': args.id, 'subject': args.subject, 'from': 'fable', 'to': 'auditor', 'kind': args.kind,
        'in_reply_to': args.in_reply_to, 'evidence_commit': args.commit, 'paths': args.path,
        'request': args.request,
    }
    rel = f'audit/handoffs/{args.subject}/{args.id}.json'
    validate(m, rel, 'from-fable')
    repo = Path(args.repo).resolve()
    for p in m['paths']:
        r = subprocess.run(['git', '-C', str(repo), 'cat-file', '-t', f"{m['evidence_commit']}:{p}"], capture_output=True, text=True)
        if r.returncode != 0 or r.stdout.strip() != 'blob':
            raise SystemExit(f'not a regular file at the pinned commit: {p} ({r.stderr.strip()[:120]})')
    target = repo / rel
    if target.exists():
        raise SystemExit(f'{rel} exists; a consumed message is never edited, choose a new id')
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(m, indent=2) + '\n')
    print(rel)
    return 0


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest='cmd', required=True)
    c = sub.add_parser('check')
    c.add_argument('--dry-run', action='store_true')
    c.add_argument('--ledger', type=Path, default=DEFAULT_LEDGER)
    c.add_argument('--canary', action='store_true', help='also announce auditor transport-test canaries not addressed to fable')
    c.set_defaults(fn=check)
    p = sub.add_parser('publish')
    p.add_argument('--kind', required=True, choices=sorted(FABLE_KINDS))
    p.add_argument('--subject', required=True)
    p.add_argument('--id', required=True)
    p.add_argument('--commit', required=True)
    p.add_argument('--path', action='append', required=True)
    p.add_argument('--request', required=True)
    p.add_argument('--in-reply-to', default=None)
    p.add_argument('--repo', default='.')
    p.set_defaults(fn=publish)
    args = ap.parse_args(argv)
    return args.fn(args)


if __name__ == '__main__':
    sys.exit(main())
