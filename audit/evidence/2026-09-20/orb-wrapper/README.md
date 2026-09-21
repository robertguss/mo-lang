# Independent wrapper acceptance

Final tested tree:6a9f5898cbc4e0fbd050fc01feb01f2d0f4ea637, recorded in
final-revision.txt. Worker188258538162e73feb92017aba67d07d7791b476 has identical
guard/wrapper/control bytes. Accepted main merge6b35871e. No candidate code was
changed by the lead. Oracle reviewed exact source and final33-case evidence.

Commands ran from /tmp/mo-lead-orb-wrapper. Each used pipefail, tee and the real
PIPESTATUS[0] in its adjacent exit file. Final wrapper command:

```
timeout --kill-after=3s 300s python3 -B toolchain/harness/executor/guard-orb/controls.py --wrapper toolchain/harness/executor/guarded.py --output /tmp/mo-wrapper-lead/final-cases
```

Result:33/33, exit0. Controls independently observe group identity, payload and
descendant liveness before fallback, unrelated sentinel survival, output
stability, real child status, policy reason and cleanup classification.

For modes core/startup/harness-failure, run timeout --kill-after=3s90s followed
by python3 -B toolchain/bench/step42/guard-orb/guard_regression.py --guard
toolchain/bench/step36/guard.py --mode MODE. Actual6/6,2/2,1/1, exits0.

Baseline RED used the final controls with --controls overflow-sleep and wrapper
at /tmp/mo-lead-orb-baseline/toolchain/harness/executor/guarded.py. Guard and
wrapper bytes were diff-checked identical to1839785e. Actual0/1 exit1: both
payload and descendant live before fallback, output unstable, wrapper claimed
group absence. The test's bounded fallback then cleaned them. This is not merely
a missing-new-receipt-field failure.

Status125 for failed/unknown supervision or cleanup is an intentional
exceptional compatibility change, including standalone. Child status remains
separate; zombie-only is not literal absence. Direct-childRSS is not aggregate
memory, escaped sessions are outside containment,16MiB is an abort trigger not
hard cap, synchronous Popen is not hard-bounded, and the outer-deadline case
injects its clock rather than measures real SECONDS+5. Linux only; no compiler,
Darwin or machine-isolation acceptance follows.
