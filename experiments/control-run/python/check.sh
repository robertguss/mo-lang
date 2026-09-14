#!/bin/sh
# Program-level check: run logstat over fixture/ and diff against expected.txt and expected.json.
# Unit tests:  python3 -m unittest discover -s tests -t .
# Type check:  uvx mypy --strict logstat tests
set -eu

here=$(cd "$(dirname "$0")" && pwd)
out=$(mktemp -d)
trap 'rm -rf "$out"' EXIT
cd "$here"

python3 -m logstat fixture >"$out/report.txt"
diff -u expected.txt "$out/report.txt"

python3 -m logstat fixture --json >"$out/report.json"
diff -u expected.json "$out/report.json"

if grep -Eq '[0-9]{16}' "$out/report.txt" "$out/report.json"; then
    echo "check.sh: a 16-digit card number reached stdout" >&2
    exit 1
fi

if grep -rnE 'except *:' logstat tests; then
    echo "check.sh: bare except" >&2
    exit 1
fi

echo "check.sh: ok"
