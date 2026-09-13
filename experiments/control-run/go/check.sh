#!/bin/sh
# Program-level check: run logstat over fixture/ and diff against the expected files.
set -eu
cd "$(dirname "$0")"
bin=$(mktemp -d)/logstat
trap 'rm -rf "$(dirname "$bin")"' EXIT
go build -o "$bin" .
"$bin" fixture | diff -u expected.txt -
"$bin" fixture --json | diff -u expected.json -
if "$bin" fixture | grep -Eq '[0-9]{16}'; then echo "card number on stdout" >&2; exit 1; fi
set +e
"$bin" fixture --top 0 >/dev/null 2>&1; [ $? -eq 2 ] || { echo "--top 0 should exit 2" >&2; exit 1; }
"$bin" "$(dirname "$bin")" >/dev/null 2>&1; [ $? -eq 1 ] || { echo "empty dir should exit 1" >&2; exit 1; }
echo "check.sh: ok"
