#!/bin/bash
# usage: r9-brief.sh <agent> <worktree> <lang: mo|go|python>
# Round 8's brief word for word (control-run-8.md), sent to a round 9 session already started in its worktree.
A=$1; W=$2; L=$3
case $L in
  mo) WHERE="the Mo program in examples/programs/jobq/ (the toolchain binary is toolchain/zig-out/bin/mo; never run zig build or zig build test; read examples/README.md first)";;
  go) WHERE="the Go program in experiments/control-run/go/ (go, staticcheck on PATH)";;
  python) WHERE="the Python program in experiments/control-run/python/jobq/ (uv; the checkers are dev dependencies run through uv run)";;
esac
B="You are a worker on a software project in the worktree $W. Your one task: make the change described in mo-wiki/spec/programs/01b-job-queue-change.md to $WHERE. The existing tests must pass, the new behaviour must have tests, and the service must keep its durability: every change is on the disk before the response that reports it. Put a timeout on every server or test process you run (timeout 300) and kill anything past 4 GB. Never use tr (aliased on this machine; use python3). Keep a count of your loops: every time a check, a build, or a test fails, note the diagnostic or the failing test and whether your next edit fixed it. Commit when green with the subject 'jobq: the change' and do not push. Do not stop early; stop when every check and test is green with the wall-clock, the loop count by cause (and whether the first fix worked), and a numbered list 'Decisions the spec did not cover', and write that same report to REPORT.md at the worktree root."
herdr agent prompt "$A" "$B" 2>&1 | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('result',d).get('type', d))"
