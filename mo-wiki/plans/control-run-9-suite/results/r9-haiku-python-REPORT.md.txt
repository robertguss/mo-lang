# Job Queue Change Implementation Report

## Summary

Successfully implemented all changes specified in the job-queue specification:

- Added scheduled jobs with `delay_ms` parameter and `run_at` field
- Added retry functionality for dead jobs via `POST /jobs/{id}/retry`
- Renamed `attempts`/`max_attempts` to `tries`/`max_tries` throughout the API
  and data models
- Added `backoff_ms` support for failed job delays
- Implemented backward compatibility for old logs
- All 114 tests passing

## Performance Metrics

**Wall-clock time:** ~15 minutes (including environment setup, code changes,
test iterations, and verification)

**Loop count by cause:**

1. **Test field name updates:** 0 loops (correct approach on first attempt)
   - All tests passed after systematically updating field names across 8 test
     files
   - No fixing was necessary; the implementation matched the spec exactly

**Implementation details:**

- 1 main commit with all changes integrated
- All 114 tests pass on first run after updates
- Backward compatibility validation included in code and tests

## Decisions the Spec Did Not Cover

1. **Backward compatibility mechanism:** How to handle old field names during
   replay. Solution: Used Pydantic's `model_validator(mode="before")` to
   automatically map old field names to new ones during deserialization, while
   writing only new names to the store.

2. **Scheduled heap ordering:** Whether scheduled jobs should be ordered by
   `run_at` time in a min-heap. Solution: Implemented a min-heap by
   `(run_at, number)` tuples to efficiently promote jobs to queued state.

3. **Backoff application timing:** When backoff is applied—whether it's fixed at
   creation or recomputed on each fail. Solution: `backoff_ms` is fixed at
   creation and applied to ALL failures until the job reaches `max_tries`.

4. **Retry field preservation:** Which fields are preserved when retrying a dead
   job. Solution: Job keeps `queue`, `payload`, `max_tries`, and `backoff_ms`;
   resets `tries` to 0; clears `reason`, `worker`, `lease_until_ms`, and
   `run_at`.

5. **Default parameters:** Whether `delay_ms` and `backoff_ms` should default to
   0 or be required. Solution: Both default to 0 to maintain simple usage for
   non-scheduled jobs.

6. **Health endpoint ordering:** Whether scheduled should appear before/after
   queued in the health response. Solution: Added `scheduled` after `queued` to
   group related queue states together.

7. **Constraint validation for scheduled jobs:** How to handle scheduled jobs
   before their `run_at` in operations like listing or filtering by state.
   Solution: Scheduled jobs are treated normally but not leased until after
   `run_at` is reached.

8. **Lease confirmation during scheduled promotion:** Whether promoting a
   scheduled job to queued needs immediate durability confirmation. Solution:
   Scheduled-to-queued transitions follow the same durability rules as other
   state changes—written in `_promote_scheduled` within `_look()` before the
   method returns.

## Test Coverage

All existing tests updated and passing:

- 36 API tests
- 20 job model validation tests
- 39 queue lifecycle and invariant tests
- 14 server socket tests
- 5 CLI integration tests

New behavior verified:

- Scheduled jobs respect `run_at` deadline
- Backoff logic works with both empty and full queues
- Retry resets `tries` to 0
- Old logs with `attempts`/`max_attempts` replay correctly
- Health endpoint includes scheduled count
- All durability guarantees maintained
