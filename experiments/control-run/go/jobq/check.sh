#!/usr/bin/env bash
# The program-level check: build jobq, play check.script through `jobq check`
# (a real socket, and a restart), then serve the same dir with `jobq serve`,
# talk to it with `jobq client`, stop it, compact, and serve again. Times and
# uptime vary, so they are masked before the diff against check.expected.
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"
pid=""
cleanup() {
	if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
	rm -rf "$tmp"
}
trap cleanup EXIT
timeout 120 go build -o "$tmp/jobq" .
mkdir "$tmp/dir"

serve() {
	"$tmp/jobq" serve "$tmp/dir" --port 0 > "$tmp/serve.out" &
	pid=$!
	for _ in $(seq 100); do
		if grep -q ' on ' "$tmp/serve.out"; then break; fi
		sleep 0.05
	done
	addr="$(sed -n 's/.* on //p' "$tmp/serve.out")"
	host="${addr%:*}"
	port="${addr##*:}"
}

stop() {
	kill -TERM "$pid"
	timeout 20 tail --pid="$pid" -f /dev/null
	pid=""
}

{
	timeout 60 "$tmp/jobq" check "$tmp/dir" check.script
	echo "# jobq serve, jobq client"
	serve
	timeout 20 "$tmp/jobq" client "$host" "$port" producer POST /jobs '{"queue": "thumbs", "payload": "cat.png", "max_attempts": 3}'
	timeout 20 "$tmp/jobq" client "$host" "$port" producer GET /jobs
	stop
	echo "# jobq compact"
	timeout 20 "$tmp/jobq" compact "$tmp/dir" | sed "s#$tmp/dir#<dir>#"
	wc -l < "$tmp/dir/jobq.log"
	serve
	timeout 20 "$tmp/jobq" client "$host" "$port" worker POST /queues/thumbs/lease
	timeout 20 "$tmp/jobq" client "$host" "$port" producer POST /jobs '{"queue": "thumbs", "payload": "dog.png", "max_attempts": 3}'
	stop
} > "$tmp/out.raw"

sed -E -e 's/[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z/<time>/g' \
	-e 's/"uptime_ms":[0-9]+/"uptime_ms":<n>/g' "$tmp/out.raw" > "$tmp/out.txt"
if [ "${1:-}" = "--update" ]; then
	cp "$tmp/out.txt" check.expected
fi
diff -u check.expected "$tmp/out.txt"
echo "check.sh: ok"
