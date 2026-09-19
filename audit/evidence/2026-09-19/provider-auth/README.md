# Private auth independent acceptance — 19 Sep 2026

Lead reading: open after your own source reading. Worker branch
harness/provider-auth-v1, base 54c3dcd, immutable commits c1d4fe16 and 2a6360c1;
integrated e845fef1/29f0dd24. Exactly 90 worker files match the integrated patch.
This is offline acceptance only; no real credentials, login or inference.

attempt-01 runs from a fresh ignored copy with explicit previously verified
prepared dependencies. It passed setup, 28 auth controls (43 synthetic requests,
four denied egress attempts), 28 unchanged provider foundation controls and two
independent cleanup probes. All 186 original tracked provider files and the
copied worker source remained byte-identical; all guarded child groups absent.
copy-evidence contains actual child outputs, exits and cleanup, while top-level
per-step status records capture the independent guards. Node 24.20.0/npm 11.19.0;
source/artifact differences and 92 dependencies retain foundation disclosures.
This fresh offline preparation is not a new cold npm installation.

lead-controls.mjs checks cancellation of a Response that arrives after abort,
and cancellation of a redirected Response before a reader is acquired. Exactly
two synthetic fetch calls, no external requests. The independent late-response
RED and corrected GREEN are under ../auth-readiness; the first attempt there
failed only due to the lead probe's relative module path. Actual red is
late-response-02.log, actual corrected green late-response-03.log. Corrected
auth.mjs SHA256 7c9b3b724bbbe1c7133e2cde2684fac2623b432796f71604b15ce570a5188a2c.

Reproduce in an owned Herdr run pane with a fresh output name:

```sh
python3 toolchain/bench/step36/guard.py 1500 -- python3 audit/evidence/2026-09-19/provider-auth/accept.py auth fresh-01
```

The prior prepared source path is explicitly recorded in accept.py and
source-identity.json. Existing output directories are refused. No historical
worker evidence is regenerated. Last full compiler suite 243/243 at e6f04ce;
these commits add only provider/auth. Full integrated suite repeats at the next
bridge checkpoint. Private-store atomic rename is not a power-loss durability
claim. Killed lock holders require deliberate operator recovery after proof.
Live registration, account/model entitlement and end-to-end auth remain untested.
