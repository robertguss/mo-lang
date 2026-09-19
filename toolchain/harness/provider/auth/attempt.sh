#!/bin/bash
# Called only in the owned Herdr run pane. Refuse historical attempt reuse.
set -u
auth_root="$(cd "$(dirname "$0")" && pwd)"
auth_repo="$(cd "$auth_root/../../../.." && pwd)"
auth_attempt="$1"
case "$auth_attempt" in ''|*[!a-zA-Z0-9_-]*) exit 2;; esac
test ! -e "$auth_root/evidence/$auth_attempt" || exit 2
# executor/guarded.py replaced auth/run.py: empty home, 550-second guard, records in evidence/<attempt>.
python3 "$auth_repo/toolchain/harness/executor/guarded.py" 550 "$auth_root/evidence/$auth_attempt" \
  --cwd "$auth_root" --home "$auth_root/.cache/home-$auth_attempt" -- "${@:2}"
auth_exit=$?
printf '%s\n' "$auth_exit" > "$auth_root/evidence/$auth_attempt/outer.exit"
printf 'outer-guard-exit=%s\n' "$auth_exit"
exit "$auth_exit"
