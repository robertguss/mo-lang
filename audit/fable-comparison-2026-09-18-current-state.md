# Lead comparison: PR 12 current-state audit

Amp (OpenAI assistant, project lead; exact model identifier unavailable), 18 Sep
2026, after the 5:28 PM ET reproductions.

The lead's reading `audit/fable-reading-2026-09-18-current-state.md` was
published on main at `3473239` before the auditor's conclusions were opened. The
auditor's `audit/mo-audit-2026-09-18-current-state.md` is anchored at `0f827a9`,
with the baseline delta through `1fa19e3`. PR 12 was merged unchanged at
`981376d`. Neither reading is represented as a cold reading of project history.
No hidden suite or seed was opened.

## Disposition

**Agree with the verdict at its anchor. No substantive disagreement with the
auditor is asserted.** The implementation is substantial, the TLS brick remains
unaccepted, and program 7 is not ready for its binding evaluation. No retirement
rule is triggered early. Integration preserves evidence; it accepts no code.

| Finding                 | Lead disposition and remaining evidence                                                                                                                                                                                                                                                                                                                                 |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1, chain authorization  | Confirmed historical failure. A/B landed after the audit anchor (`git log 0f827a9..main -- toolchain/src/bricks/tls.zig`). Worker outputs now refuse all four chains. Do not present the audit as a fresh failure of A/B, or the worker outputs as full closure: independent full-runtime checks and the zero-Limbo gate remain owed.                                   |
| 2, false-success suites | Conceded and reproduced on current main: both runner functions return success after injected exit 1 or 124; invalid category selection actually exits 0 with zero checks. Preserve sealed suites and historical results; repaired runners must aggregate statuses and assert expected coverage before further acceptance.                                               |
| 3, fuzz/abuse scoring   | Conceded. Current-main mocks reproduce a failed batch reported as zero crashes and 20/20 server cells despite all stimuli throwing. Client source has the analogous omission. These are logical counterexamples, not proof that a real historical campaign was false-green. Require evidence of the intended state and stimulus, not only matching output and survival. |
| 4, ALPN                 | Confirmed historical failure; B's preserved probe now passes the 65-name overlap. Independent acceptance remains owed; the audit itself is not rewritten.                                                                                                                                                                                                               |
| 5, CI                   | Conceded: the only tracked workflow publishes the wiki. PR 12 has Socket checks, not a compiler/corpus gate. A bounded, reproducible Zig/corpus CI gate is follow-up work; no workflow or branch protection was changed by this review.                                                                                                                                 |

Raw fresh reproductions and exact commands:
`audit/evidence/2026-09-18/current-state-lead/README.md` and its two logs. The
original sealed generation-six hash still matches in the harness probe. No new
full Zig suite, real TLS campaign, fuzz hour, or Darwin verification ran.

## Program 7 measurement reconciliation: for Robert

The auditor's three discrepancies are conceded. They must be resolved before the
builds, not after seeing comparative results. The lead's initial reading did not
separately resolve RC1 or the R4 denominator; this comparison adds them.
Revision 2 remains sealed and is not edited in place. The following are
recommendations, not amendments to ratified rules:

- **R2:** recommend that Robert explicitly ratify the shared twenty-keyspace-
  kill rig in revision 2 as R2's measurement, retaining the 1.2x MTTR threshold.
  It is narrower than the original mixed simulator-fault wording; retain
  disk/network/deadline stress as separately reported evidence, not as a claim
  that twenty kills are the same experiment. Until ratified, the discrepancy
  remains open and R2 cannot be scored from that substitution.
- **RC1:** retain separate timestamps for first prompt, final maintainer report,
  and first passing hidden suite, with repair time and auditor wait separately
  recorded. Recommend keeping the binding endpoint (first passing hidden suite)
  unless Robert explicitly ratifies a replacement; the report- only clock cannot
  clear the current rule. Hidden-suite administration and any post-build repair
  protocol must be sealed without exposing test contents to the maintainers or
  the lead prematurely.
- **R4:** fewer than 100 observed edits is incomplete evidence, not a cleared
  hundred-edit gate. Do not manufacture no-op commits. A pre-registered
  meaningful-edit follow-up can supply missing observations; any denominator
  amendment is Robert's, not an implicit exception in the result.

The baseline is also incomplete as security coverage: zero executed TLS tests
and zero passing auth/ACL/INFO tests cannot establish those behaviors. Finish
fresh-server per-file checks and the shared pre-build skip list; do not convert
every Redis baseline failure into a permanent skip. Obtain the auditor's seal
only after the measurement discrepancies are explicitly resolved.

## Continuation boundary

Step 39 stays first in the implementation queue and unaccepted; its evidence
must use sound instruments. The harness work is an acceptance prerequisite, not
cleanup to postpone until after another claimed green. Program 7 readiness also
needs the orientation findings resolved: binary-safe Conn input, R5's
snapshot-plus-log replay versus whole-test rerun, and the directory-sync
durability boundary. They are lead findings, not discoveries attributed to
PR 12.

The lead role has transferred to Amp, but this audit-review session starts no
worker and no experiment. The orb has Zig 0.16 and one registered worktree;
Herdr is not on PATH and the private transfer inventory is unverified. Do not
claim the old working environment is restored. Darwin verification still needs a
Mac. No implementation, threshold, or retirement mapping changed here.
