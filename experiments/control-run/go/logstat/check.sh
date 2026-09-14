#!/usr/bin/env bash
# Program-level check: run logstat over the fixture and diff against the
# expected text and JSON reports; fail if a card number reaches stdout.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
bin="$(mktemp -d)"
trap 'rm -rf "$bin"' EXIT
(cd "$here/.." && timeout 120 go build -o "$bin/logstat" ./logstat)
timeout 30 "$bin/logstat" "$here/fixture" > "$bin/out.txt"
timeout 30 "$bin/logstat" "$here/fixture" --json > "$bin/out.json"
diff -u "$here/expected.txt" "$bin/out.txt"
diff -u "$here/expected.json" "$bin/out.json"
if grep -Eq '[0-9]{16}|4111' "$bin/out.txt" "$bin/out.json"; then
  echo "check.sh: a card number reached stdout" >&2
  exit 1
fi
echo "check.sh: ok"
