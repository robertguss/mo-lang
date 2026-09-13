#!/bin/sh
# Program-level check: build logstat, run it over fixture/, and diff the text
# and JSON reports against expected.txt and expected.json. Also checks the
# exit codes and that no card number reaches stdout.
set -eu
cd "$(dirname "$0")"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
go build -o "$tmp/logstat" .

fail=0

"$tmp/logstat" fixture >"$tmp/out.txt" || { echo "FAIL: text run exited $?"; fail=1; }
diff -u expected.txt "$tmp/out.txt" || { echo "FAIL: text report differs"; fail=1; }

"$tmp/logstat" fixture --json >"$tmp/out.json" || { echo "FAIL: json run exited $?"; fail=1; }
diff -u expected.json "$tmp/out.json" || { echo "FAIL: json report differs"; fail=1; }

if grep -Eq '[0-9]{16}' "$tmp/out.txt" "$tmp/out.json"; then
	echo "FAIL: a card number reached stdout"
	fail=1
fi

code=0
"$tmp/logstat" fixture --top 101 >/dev/null 2>&1 || code=$?
[ "$code" -eq 2 ] || { echo "FAIL: --top 101 exited $code, want 2"; fail=1; }

mkdir "$tmp/empty"
code=0
"$tmp/logstat" "$tmp/empty" >/dev/null 2>&1 || code=$?
[ "$code" -eq 1 ] || { echo "FAIL: dir without .log exited $code, want 1"; fail=1; }

if [ "$fail" -ne 0 ]; then
	echo "check.sh: FAIL"
	exit 1
fi
echo "check.sh: ok"
