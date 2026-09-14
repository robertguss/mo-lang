#!/bin/sh
# Program-level check: build logstat, run it over fixture/, and diff the text
# and JSON reports against expected.txt and expected.json.
set -eu
here=$(cd "$(dirname "$0")" && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

(cd "$here" && go build -o "$work/logstat" .)

"$work/logstat" "$here/fixture" > "$work/out.txt"
diff -u "$here/expected.txt" "$work/out.txt"

"$work/logstat" "$here/fixture" --json > "$work/out.json"
diff -u "$here/expected.json" "$work/out.json"

if grep -Eq '[0-9]{16}' "$work/out.txt" "$work/out.json"; then
  echo "check.sh: a card number reached stdout" >&2
  exit 1
fi

set +e
"$work/logstat" "$here/fixture" --top 0 2> /dev/null
code=$?
set -e
if [ "$code" -ne 2 ]; then
  echo "check.sh: --top 0 exited $code, want 2" >&2
  exit 1
fi

echo "check.sh: ok"
