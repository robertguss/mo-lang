#!/bin/bash
# the round 8 suites on the kimi Python change, one category at a time with a pause, because the Python server closes every connection and macOS runs out of ephemeral ports to one destination
S=$1; W=/Users/robertguss/Projects/startups/mo-lang-r9-kimi-python/experiments/control-run/python/jobq; OLD=/Users/robertguss/Projects/startups/mo-lang-control7-python/experiments/control-run/python/jobq
cd /Users/robertguss/Projects/startups/mo-lang/mo-wiki/plans/control-run-8-suite
: > $S/r9-kimi-python-paced.txt
for c in kill torn health; do
  echo "## regressions --only $c" >> $S/r9-kimi-python-paced.txt
  python3 regressions.py --serve "uv run jobq serve {dir} --port {port}" --cwd $W --only $c >> $S/r9-kimi-python-paced.txt 2>&1
  pkill -f 'jobq serve /var/folders'; sleep 35
done
for c in fields scheduled order delete backoff runout retry health durable race load oldlog; do
  echo "## defects --only $c" >> $S/r9-kimi-python-paced.txt
  python3 defects.py --serve "uv run jobq serve {dir} --port {port}" --cwd $W --old-serve "uv run jobq serve {dir} --port {port}" --old-cwd $OLD --compact "uv run jobq compact {dir}" --only $c >> $S/r9-kimi-python-paced.txt 2>&1
  pkill -f 'jobq serve /var/folders'; sleep 35
done
echo DONE >> $S/r9-kimi-python-paced.txt
