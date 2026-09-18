#!/bin/bash
# Redis 7.2.4's own tests, the files program 7's spec names, run in --host mode against a real redis-server 7.2.4: how many run, pass, skip
cd /private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad && [ -d redis ] || git clone -q --depth 1 --branch 7.2.4 https://github.com/redis/redis.git
cd redis && make -j8 > /private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad/redis-make.log 2>&1; echo "make exit=$?"
src/redis-server --port 7399 --save '' --appendonly no --daemonize yes --dir /private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad --logfile /private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad/redis-7399.log --enable-debug-command yes; sleep 1
OUT=/private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad/redis-baseline.txt; echo "# $(date) redis $(src/redis-server --version)" > $OUT
for f in unit/type/string unit/type/incr unit/type/hash unit/type/list unit/type/list-2 unit/type/list-3 unit/type/set unit/type/stream unit/expire unit/keyspace unit/scan unit/multi unit/pubsub unit/auth unit/acl unit/acl-v2 unit/info unit/introspection unit/introspection-2 unit/other unit/protocol unit/tls unit/aofrw integration/aof integration/aof-multi-part; do
  timeout 900 ./runtest --host 127.0.0.1 --port 7399 --single $f > /private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad/rb-$(echo $f | python3 -c "import sys; print(sys.stdin.read().strip().replace('/','_'))").log 2>&1; rc=$?
  L=/private/tmp/claude-501/-Users-robertguss-Projects-startups-mo-lang/19ba221d-878a-497b-89f8-cc63f5053d64/scratchpad/rb-$(echo $f | python3 -c "import sys; print(sys.stdin.read().strip().replace('/','_'))").log
  echo "$f exit=$rc ok=$(grep -c '^\[ok\]' $L) err=$(grep -c '^\[err\]' $L) exception=$(grep -c -i 'exception' $L) skip=$(grep -c '^\[skip\]\|^\[ignore\]' $L)" | tee -a $OUT
done
src/redis-cli -p 7399 shutdown nosave; echo BASELINE-DONE | tee -a $OUT
