# Audit reading: step-38 prerequisite plan

**Date:** 2026-09-18  
**Author:** Mo Auditor (independent model session)  
**Charter:** raw-evidence review; only Robert may amend or reject this reading.  
**Scope:** requirements/readiness of step 38's queued brief, not TLS implementation, completed step evidence or a runtime verdict.  
**Status:** filed independently before lead synthesis, against `64982b23b1dfed0bd0af3430125589da43058ac0`; recent-change baseline `aace4ee36516c9dc67cdb7b0d0c8cab3a5f9c024`.  
**Explicit gap in this reading:** no step-38 build, implementation or result was audited. The orientation's prior performance/defect statements were treated as motivation supplied in the authorized plan, not independently reproduced evidence. The linked RESULTS and decision-log files were not opened.

## Reading

The brief provides a concrete prerequisite acceptance test for program 7's pipelining/nonblocking promise, including explicit **per-cell liveness** rather than aggregate server survival. It is a plan, not evidence that those prerequisites are implemented. Program 7 must not inherit a completed-step claim from this review.

## Requirements checked against the spec

Files read: `mo-wiki/plans/interpreter-step-38.md:1–100`, `mo-wiki/spec/design-v0/09-stdlib.md:241–270`, `mo-wiki/spec/programs/07-redis-subset.md:113–124,233–250`.

| Plan | Applicable requirement | Acceptance evidence still needed |
|---|---|---|
| A, duplex (`step-38:52–62`) | `Net` promises only competing readers/writers get `Busy` (`09-stdlib:261–265`); a waiting process does not hold up others (`:243`). Program 7 requires pipelined ordered replies and no slow/blocked connection stopping another (`07:113–115,248–249`). | Both runtimes, plain/TLS, the fixture and real socket evidence called for in A. Verify the write deadline and competing-writer/reader `Busy` obligations as well as the bulk completion time. TLS record/KeyUpdate serialization is an explicit requirement, not proved merely by a fast echo. |
| B, NODELAY (`step-38:64–67`) | Connection behavior/performance, without changing the listener/connect API. | Before/after windows 1, 16, 256 and echo-1k data, with identical rig settings and load beside results. |
| C, abuse (`step-38:69–79`) | Deadline and connection-close behavior, connection-local failures and subsequent useful service. | Every state/stimulus/runtime cell with an expected error, actual error, and immediate next-connection health check; client process alive for client cases. Aggregate completion alone is insufficient. |
| Done gate (`step-38:87–93`) | Bounded build, complete matrix and performance report, limited spec edits. | Actual `timeout 2400 zig build test --summary all` exit and summary, duplex/fixture results, complete table, timing data, scoped spec diff and decisions list. |

**Actual cheap check:** computed `(5 server states + 3 client states) × 4 stimuli = 32` per runtime and `× 2 = 64` total from part C's enumeration. The advertised 32/64 counts are internally consistent. This is arithmetic validation, not 64 tests executed.

## Readiness gap — Medium: freeze the cell oracles before the result

The brief requires “the expected answer (`Handshake`, `Closed`, `Timeout`) per cell” (`step-38:75–78`) but does not enumerate the mapping. The implementation/harness author must fix that table before observing outcomes. A peer reset, alert, graceful close and deadline are not interchangeable success conditions. In particular, a missing/never-reached handshake state must not be counted as the requested state simply because the connection eventually closes. No new error semantics or rule is imposed by this reading; the existing brief requires those cell-specific answers.

Part A also distinguishes blocked-writer progress, deadline behavior and simultaneous-reader/writer ownership. A sub-second echo alone would leave the latter obligations unproven. A later audit should review the test scheduling and state reachability, not only totals.

## Standing concerns and candidate falsifier

- Step 38's “best of five” numbers (`:81–85`) are its own measurement requirement; they do not replace program 7's three-trial median requirement (`07:289–300`). Keep those result labels separate.
- No source change, rule amendment or state edit is made. Parent review handles TLS implementation evidence separately.
- **Would close this gap:** an immutable pre-run expected-error table plus raw per-cell state/reachability, immediate liveness and error evidence; complete duplex/deadline/Busy and before/after measurements at a named implementation commit.
- **Candidate falsifier of the prerequisite claim:** one cell leaves the server unable to handle its immediate next connection, or a blocked writer prevents the same connection's reader from making progress despite an available reply. Either defeats the relevant requirement even if the overall test process exits successfully.
