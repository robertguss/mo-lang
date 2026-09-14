#!/bin/sh
# Program-level check: build logstat, run it over fixture/, diff against
# expected.txt and expected.json, and hold the exit codes and the card never.
set -eu
cd "$(dirname "$0")"
bin="$(mktemp -d)"
trap 'rm -rf "$bin"' EXIT
go build -o "$bin/logstat" .

fail=0
"$bin/logstat" fixture > "$bin/out.txt" || fail=1
"$bin/logstat" fixture --json > "$bin/out.json" || fail=1
diff -u expected.txt "$bin/out.txt" || fail=1
diff -u expected.json "$bin/out.json" || fail=1

if grep -Eq '[0-9]{16}' "$bin/out.txt" "$bin/out.json"; then
	echo "a card number reached stdout"; fail=1
fi

expect_code() {
	want="$1"; shift
	code=0
	"$bin/logstat" "$@" > /dev/null 2> "$bin/err" || code=$?
	if [ "$code" -ne "$want" ]; then
		echo "logstat $*: exit $code, want $want"; fail=1
	fi
}
expect_code 2 fixture --top 0
expect_code 2 fixture --top 101
expect_code 2
expect_code 1 "$bin"

if [ "$fail" -ne 0 ]; then
	echo "check.sh: FAIL"; exit 1
fi
echo "check.sh: ok"
