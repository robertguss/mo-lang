#!/bin/sh
# The program-level check for logstat. The corpus test cannot hold a program made of
# several modules (TOOLCHAIN-BUGS.md 1 and 2), so this does what it would: every module's
# formatting and tests, then the program on the fixture, as text and as JSON, and its exit
# codes. MO names the mo binary; the default is the one `zig build` installs.
set -u
here=$(cd "$(dirname "$0")" && pwd)
mo=${MO:-$here/../../../toolchain/zig-out/bin/mo}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
failed=0
fail() { echo "logstat check: $1" >&2; failed=1; }

cd "$here" || exit 1
for m in parse stats report main; do
  "$mo" fmt --check "$m.mo" > "$work/$m.fmt" 2>&1 || { cat "$work/$m.fmt" >&2; fail "$m.mo is not formatted"; }
done
for m in parse stats report; do
  "$mo" test "$m.mo" > "$work/$m.test" 2>&1 || { cat "$work/$m.test" >&2; fail "mo test $m.mo failed"; }
done

# main.mo uses the other three, so it is tested and run joined with them.
joined="$work/logstat.mo"
awk -f join.awk parse.mo stats.mo report.mo main.mo > "$joined"
if ! "$mo" test "$joined" > "$work/joined.test" 2>&1; then
  cat "$work/joined.test" >&2
  fail "the joined program does not pass mo test (over 500 lines is TOOLCHAIN-BUGS.md 3)"
  exit 1
fi

"$mo" run "$joined" -- fixture a.log b.log c.log notes.txt > "$work/text.out" 2> "$work/text.err"
[ $? -eq 0 ] || fail "the text run did not exit 0: $(cat "$work/text.err")"
diff -u logstat.expected "$work/text.out" || fail "the text report differs from logstat.expected"

"$mo" run "$joined" -- fixture c.log b.log a.log --top 3 --since 2026-09-12T10:00:10Z --json \
  > "$work/json.out" 2> "$work/json.err"
[ $? -eq 0 ] || fail "the JSON run did not exit 0: $(cat "$work/json.err")"
diff -u logstat-json.expected "$work/json.out" || fail "the JSON differs from logstat-json.expected"

if grep -qE '[0-9]{16}' "$work/text.out" "$work/json.out"; then fail "a card number reached stdout"; fi

"$mo" run "$joined" -- fixture a.log --top 0 > "$work/usage.out" 2> "$work/usage.err"
[ $? -eq 2 ] || fail "--top 0 did not exit 2"
[ "$(wc -l < "$work/usage.err")" -eq 1 ] || fail "a usage error is not one line on stderr"
[ -s "$work/usage.out" ] && fail "a usage error wrote to stdout"

"$mo" run "$joined" -- fixture notes.txt > /dev/null 2>&1
[ $? -eq 1 ] || fail "no .log file did not exit 1"

[ "$failed" -eq 0 ] && echo "logstat: four modules formatted and tested; text, JSON, and exit codes match"
exit "$failed"
