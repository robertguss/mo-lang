#!/bin/bash
# Redis 7.2.4's own tests, the files program 7's spec (revisions 1 plus 2) names, run in --host mode against a real
# redis-server 7.2.4, in a Debian container on Linux (OrbStack on Robert's Mac). Output: linux/baseline.txt, linux/rb-<file>.log
# usage (from the repo root): docker run --rm -v "$PWD/audit/evidence/2026-09-18/program-7-spec-r2:/out" debian:12 bash /out/redis-baseline-linux.sh
set -u
apt-get update -qq >/dev/null && apt-get install -y -qq git build-essential tcl tcl-tls pkg-config procps python3 >/dev/null 2>&1
cd /root && git clone -q --depth 1 --branch 7.2.4 https://github.com/redis/redis.git && cd redis && make -j8 >/out/linux/make.log 2>&1; echo "make exit=$?"
OUT=/out/linux/baseline.txt
echo "# $(date -u '+%Y-%m-%d %H:%M:%S UTC') $(uname -srm) tcl $(echo 'puts [info patchlevel]' | tclsh) $(src/redis-server --version)" > $OUT
start() { src/redis-server --port 7399 --save '' --appendonly no --daemonize yes --dir /tmp --logfile /tmp/redis-7399.log --enable-debug-command yes --enable-protected-configs yes --enable-module-command yes >/dev/null; sleep 1; }
start
for f in unit/type/string unit/type/incr unit/type/hash unit/type/list unit/type/list-2 unit/type/list-3 unit/type/set unit/type/stream unit/expire unit/keyspace unit/scan unit/multi unit/pubsub unit/auth unit/acl unit/acl-v2 unit/info unit/introspection unit/introspection-2 unit/other unit/protocol unit/tls; do
  n=$(echo $f | python3 -c "import sys; print(sys.stdin.read().strip().replace('/','_'))"); L=/out/linux/rb-$n.log
  src/redis-cli -p 7399 ping >/dev/null 2>&1 || { echo "  (server was down before $f: restarted)" >> $OUT; start; }
  s=$(date +%s); timeout 600 ./runtest --host 127.0.0.1 --port 7399 --single $f > $L.raw 2>&1; rc=$?; e=$(( $(date +%s) - s ))
  python3 - "$L" "$f" "$rc" "$e" >> $OUT <<'P'
import re,sys
L,f,rc,e=sys.argv[1:5]; t=re.sub(r'\x1b\[[0-9;]*m','',open(L+'.raw',errors='replace').read()); open(L,'w').write(t)
ok=len(re.findall(r'(?m)^\[ok\]',t)); err=len(re.findall(r'(?m)^\[err\]',t)); ign=len(re.findall(r'(?m)^\[(ignore|skip)\]',t)); exc=len(re.findall(r'\[exception\]',t))
last=[l for l in t.splitlines() if l.startswith('[ok]') or l.startswith('[err]')][-1:] or ['']
print(f"{f}: exit={rc}{' (TIMED OUT at 600 s)' if rc=='124' else ''} seconds={e} ok={ok} err={err} ignored={ign} exception={exc} last=\"{last[0][:70]}\"")
P
  rm -f $L.raw; pkill -f test_helper.tcl 2>/dev/null; src/redis-cli -p 7399 flushall >/dev/null 2>&1
done
src/redis-cli -p 7399 shutdown nosave 2>/dev/null; echo "# done $(date -u '+%H:%M:%S UTC')" >> $OUT; echo BASELINE-LINUX-DONE
