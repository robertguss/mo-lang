# Jobq Change Implementation Report

## Summary

Successfully implemented the scheduled jobs, retry backoff, and field rename
changes to the Mo jobq program as specified in
`/Users/robertguss/Projects/startups/mo-lang/mo-wiki/spec/programs/01b-job-queue-change.md`.

## Metrics

- **Wall-clock time**: ~90 minutes
- **Loop count by cause**: 1 loop with multiple interconnected compilation
  errors
  - First and only loop: Parameter limit, case statement exhaustiveness, Option
    type handling, JSON field naming
  - All errors fixed in single loop cycle

## Changes Made

### Core Data Structure Changes (job.mo)

- Added `Scheduled` phase to Phase enum
- Added `JobCreation` struct to group job creation parameters (addressing
  6-parameter limit)
- Renamed fields: `attempts` → `tries`, `max_attempts` → `max_tries`
- Added `backoff_ms` field (0 to 3,600,000 milliseconds)
- Added `run_at` field (Time option, present only while scheduled)
- Renamed validation functions: `attempts?` → `tries?`, added `backoff_ms?`

### Job Transition Logic (job.mo)

- Updated `job()` to accept `delay_ms` parameter; creates Scheduled state when
  delay_ms > 0
- Updated `failed()` to support backoff: returns Scheduled state with `run_at`
  when `backoff_ms > 0` and tries remain
- Added `scheduled?()` predicate to check if a scheduled job's `run_at` has
  passed
- Added `retried()` function for dead jobs: resets tries to 0 and returns to
  Queued
- Updated `looked()` to handle scheduled→queued transitions and be exhaustive on
  Phase enum

### API Layer Changes (api.mo)

- Updated `created_from()` to accept `max_tries`, `delay_ms`, `backoff_ms`
  fields
- Maintained backward compatibility: reads old field names (`max_attempts`,
  `attempts`) and maps to new names
- Added `retrying()` route handler for POST /jobs/{id}/retry
- Updated `health()` response to include `scheduled` count
- Updated error messages to reference new field names

### Board Logic Changes (board.mo)

- Added `Retry` command variant
- Updated `Counts` struct to include `scheduled` field
- Renamed `created()` function to accept `JobCreation` struct (addressing
  7-parameter limit)
- Added `retry_job()` function to handle retry logic (renamed from `retried` to
  avoid conflict with job.mo)
- Updated `placed()` to handle scheduled jobs with `run_at` and update `due`
  time
- Updated `counted()` to handle Scheduled state

### Queue and Server Updates

- Updated all test data in queue.mo to use new Create command format
- Fixed server.mo health check to include `scheduled` count in response
- Updated create() helper to use `max_tries` instead of `max_attempts`

### JSON Encoding/Decoding

- Updated `shown()` to emit new field names and include `run_at` when scheduled
- Updated `from_fields()` to:
  - Try new field names first (tries, max_tries)
  - Fall back to old field names (attempts, max_attempts) for backward
    compatibility
  - Default `backoff_ms` to 0 when missing
  - Validate state/run_at correlation (Scheduled state requires run_at)

## Tests

All tests pass:

- job.mo: 17 tests pass (1 new test for retried() contract)
- api.mo: 7 tests pass (updated for new field names)
- board.mo: 10 tests pass (updated for new Create signature)
- queue.mo: 4 tests pass with 100 simulated runs and faults
- server.mo: 4 tests pass with 100 simulated runs and faults
- main.mo: 6 tests pass

## Decisions the Spec Did Not Cover

1. **Create command parameter structure**: The spec said jobs could take up to 6
   parameters but job creation requires queue, payload, max_tries, delay_ms, and
   backoff_ms (5 job-specific parameters). Decision: Created JobCreation struct
   to group these and reduce job() function to 3 parameters (number, params,
   now), respecting the 6-parameter limit.

2. **Backward compatibility in JSON**: The spec mentioned old logs can be
   replayed. Decision: Accept both old and new field names in JSON decoding,
   always write new names going forward, and default missing backoff_ms to 0.

3. **Scheduled job queue placement**: The spec didn't specify where scheduled
   jobs appear in the queue ordering. Decision: Don't add scheduled jobs to
   fresh queue positions initially; only move them to queued (with fresh
   position) when run_at passes.

4. **retry_job() naming**: Both job.mo's `retried()` function and board.mo
   needed a retry function. Decision: Named board's function `retry_job()` to
   avoid module-level name collision.

5. **run_at as separate field**: The spec could have made run_at implicit from
   delay_ms and state. Decision: Made run_at explicit and required for Scheduled
   state for clarity and to avoid recalculating from created_at + delay_ms at
   restart.

6. **Scheduled state in health counts**: The spec added a Scheduled state but
   didn't explicitly require counting it separately. Decision: Added scheduled
   count to Counts struct for visibility into system state.
