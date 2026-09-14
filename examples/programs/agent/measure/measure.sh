#!/bin/zsh
# measure.sh WORK interp|binary: agent's numbers under one runtime (program 5's report).
# WORK is a scratch folder outside the repository: the program is copied there without its
# verified: lines, built with mo build --surface for the binary, and served over folders there.
# Needs python3; mo is toolchain/zig-out/bin/mo. Every process runs under a timeout.
here=${0:A:h}
repo=${here:h:h:h:h}
S=$1
mode=$2
B=$S/bench
M=$repo/toolchain/zig-out/bin/mo
G=(timeout 900)
mkdir -p $B/agent $B/svc/work $B/svc2/work
touch $B/mo.root
cp $here/../*.mo $B/agent/
for f in $B/agent/*.mo; do python3 -c "import sys; p=sys.argv[1]; s=open(p).read(); i=s.find('\\nverified: '); open(p,'w').write(s if i < 0 else s[:i+1])" $f; done
now='{"tool": "now", "tokens": 10}'
printf '%s\n%s\n%s\n%s\n%s\n' $now $now $now $now '{"done": "five steps", "tokens": 10}' > $B/five.txt
printf '%s\n%s\n' '{"slow_ms": 120000}' '{"done": "held", "tokens": 1}' > $B/held.txt
echo bench > $B/svc/work/readme.txt
echo bench > $B/svc2/work/readme.txt
if [ "$mode" = binary ]; then (cd $B/agent && $M build --surface main.mo -o agent > /dev/null); fi
if [ "$mode" = interp ]; then
  run=($M run $B/agent/main.mo --)
  base=7960
else
  run=($B/agent/zig-out/mo-build/agent/agent)
  base=7980
fi
out=$S/measure-$mode
mkdir -p $out
rm -rf $B/svc/runs $B/svc2/runs

wait_port() {
  python3 - "$1" <<'EOF'
import socket, sys, time
port = int(sys.argv[1])
for _ in range(200):
    try:
        socket.create_connection(("127.0.0.1", port), 0.2).close(); sys.exit(0)
    except OSError:
        time.sleep(0.05)
sys.exit(1)
EOF
}

rss_of() { ps -o rss= -p $1 | awk '{print $1}'; }
# The pid of the matching process with the largest resident memory: the mo or agent process, not
# the guard or timeout around it.
biggest() { ps -eo pid,rss,args | grep -F -- "$1" | grep -v grep | sort -k2 -n -r | awk 'NR==1 {print $1}'; }

# 32 concurrent runs of five steps, 20 seconds, with the operator's view asked in the middle.
$G $run mock $B/five.txt --port $((base+1)) > $out/mock.log 2>&1 &
mock=$!
wait_port $((base+1))
$G $run serve $B/svc --model 127.0.0.1:$((base+1)) --port $base --surface $((base+2)) > $out/serve.log 2>&1 &
serve=$!
wait_port $base
wait_port $((base+2))
serve_pid=$(biggest "serve $B/svc --model")
python3 $here/bench.py rate $base 32 20 now > $out/rate.json &
bench=$!
sleep 8
for route in /inflight /slowest /runs; do
  start=$(python3 -c 'import time; print(time.time())')
  python3 $here/bench.py view $((base+2)) $route > $out/view${route//\//-}.txt
  python3 -c "import time; print('took %.1f ms' % ((time.time() - $start) * 1000))" >> $out/view${route//\//-}.txt
done
echo "serve rss during rate: $(rss_of $(biggest "serve $B/svc --model")) KiB" > $out/rss.txt
wait $bench
echo "serve rss after rate: $(rss_of $(biggest "serve $B/svc --model")) KiB" >> $out/rss.txt
kill $serve $mock 2>/dev/null
pkill -f "serve $B/svc --model" 2>/dev/null
pkill -f "mock $B/five.txt" 2>/dev/null
sleep 1

# 1,000 concurrent runs held in their first model call.
$G $run mock $B/held.txt --port $((base+11)) > $out/mock2.log 2>&1 &
wait_port $((base+11))
$G $run serve $B/svc2 --model 127.0.0.1:$((base+11)) --port $((base+10)) --surface $((base+12)) > $out/serve2.log 2>&1 &
wait_port $((base+10))
serve2_pid=$(biggest "serve $B/svc2 --model")
mock2_pid=$(biggest "mock $B/held.txt")
echo "serve rss before hold: $(rss_of $serve2_pid) KiB" >> $out/rss.txt
python3 $here/bench.py hold $((base+10)) 1000 '{"wall_ms": 600000, "tool_ms": 60000}' > $out/hold.json
sleep 5
echo "serve rss holding 1000: $(rss_of $(biggest "serve $B/svc2 --model")) KiB" >> $out/rss.txt
echo "mock rss holding 1000: $(rss_of $(biggest "mock $B/held.txt")) KiB" >> $out/rss.txt
start=$(python3 -c 'import time; print(time.time())')
python3 $here/bench.py view $((base+12)) /inflight > $out/view-hold-inflight.txt
python3 -c "import time; print('took %.1f ms' % ((time.time() - $start) * 1000))" >> $out/view-hold-inflight.txt
python3 $here/bench.py view $((base+10)) /health > $out/hold-health.txt
pkill -f "serve $B/svc2 --model" 2>/dev/null
pkill -f "mock $B/held.txt" 2>/dev/null
sleep 1
cat $out/rate.json $out/rss.txt $out/hold.json $out/view-inflight.txt $out/view-slowest.txt $out/view-hold-inflight.txt $out/hold-health.txt
head -c 600 $out/view-runs.txt
