# The agent's report cap and the clamped command's margin: worker report

Worker: Claude Opus 5 (fresh session, bypass permissions), branch
`agent/report-cap`, base `90add2f3`. Brief:
`mo-wiki/plans/mo-agent-report-cap.md`. No subagents. Every mo, build and test
process ran under `toolchain/bench/step36/guard.py`: the Python runners
themselves, and each child through `common.invoke`. There were no toolchain,
wiki, `audit/`, `HANDOFF.md` or machine changes, and nothing was pushed. I did
not run the full suite or use the machine.

## Verdict

- **The report cap.** `report_cap()` is now derived from the profile: 16 ×
  (851968 + 524288) + 1048576 = **23,068,672** bytes. The profile line reports
  it.
- **Rendering.** Transcripts of 300,598 bytes, 1,000,598 bytes, and the largest
  a run can make (3,669,468 bytes) render whole in both runtimes. The two
  runtimes' reports are identical except for `took_ms`.
- **The bound itself.** A Book holding exactly 23,068,672 bytes renders a 46 MB
  report. One byte more is a proved `transcript_too_large`.
- **D1 is fixed.** A command's timeout is now what remains less
  `candidate_margin_ms()` (5 s). A clamped command whose reply comes 1.4 s after
  its timeout is now received, with its execution known.

## Commits

| commit     | what                                                                                                            |
| ---------- | --------------------------------------------------------------------------------------------------------------- |
| `2e24dcd7` | report cap RED: the matrix rows and the driver rows at the cap and one byte past it; RED output                 |
| `bdd99951` | report cap GREEN: `report_cap()` derived, comment rewritten, README; GREEN output                               |
| `37769240` | D1 RED: driver rows for the margin; RED output                                                                  |
| `f4a7b3c4` | D1 GREEN: `candidate_margin_ms()`, `timed`, profile, README; GREEN output                                       |
| `466e22c4` | `report_cap.py`: the whole-report diff between runtimes, and the numbers                                        |
| `8e7e61a8` | the margin's unit test (its RED on a scratch copy), the finding 5 control updated, final runs, real_bridge note |
| this one   | this report                                                                                                     |

## Part 1: RED (committed before GREEN)

`matrix.py` gains `report-300k`, `report-1m` and `report-largest`, and
`request-bound` now expects a whole report. `report-over` (350,000 bytes of
text) is gone, because it is now far under the cap; the new rows replace it.

Each row checks:

- there is no `reporting_error`;
- every `step` in the report is the Book's step byte for byte, in order
  (`Context.whole`), then the terminal;
- the transcript is at least the named size;
- the context bound ended the run (`over_budget`/`context_bytes`).

At `2e24dcd7` (evidence `red-cap-matrix-{interpreter,native}-01.jsonl`, both
exit 1), every one of these rows failed with
`{"error": "transcript_too_large", "persistence": "proved"}`. `six-tools` failed
on the profile's new `report_bytes`. `red-cap-drivers-*-01` (exit 1) failed only
on size, because the old cap was 262,144.

## Part 2: the bound

In `application.mo`:

```
fn model_reply_cap() : UInt64
  1_048_576
end

fn report_cap() : UInt64
  application_order("").budget.steps * (request_cap() + response_cap()) + model_reply_cap()
end
```

- **The comment** states what the cap bounds and why no run of this profile
  meets it. It does not mention the defect.
- **The profile's `bounds` line** gives `"report_bytes": 23068672`.
  `matrix.py`'s `PROFILE` expects `16 * (851968 + 524288) + 1048576`.
- **README.** Item 10, the 256 KiB sentence in "Watching and reporting", and the
  "Toolchain defect, not fixed" limitation are rewritten.

GREEN evidence, all exit 0: `green-cap-matrix-{interpreter,native}-01` and
`green-cap-drivers-{interpreter,native}-01`. The rows in these tables are from
those files; `masked sha256` is the report's hash with `took_ms` values and the
bridge's workspace id masked.

| row            | transcript bytes      | report bytes          | masked sha256 (interpreter = native) |
| -------------- | --------------------- | --------------------- | ------------------------------------ |
| request-bound  | (refused write)       | 2,557,686             | `b3145c71…` = `b3145c71…`            |
| report-300k    | 300,598               | 452,037               | `19325973…` = `19325973…`            |
| report-1m      | 1,000,598             | 1,502,037             | `d6f2f89b…` = `d6f2f89b…`            |
| report-largest | 3,669,468 / 3,669,466 | 5,112,210 / 5,112,208 | `f236999d…` = `f236999d…`            |

The 2-byte gaps between the runtimes are `took_ms` digits.

## Part 3: still refused

No CLI run can pass the derived bound, so the row past it is a driver mode.
`driver.mo`'s `oversized` mode writes one step into the operator's Book before
the run begins. It sizes that step with `step_json` so the transcript is exactly
`report_cap() + 0` or `+ 1` bytes. The run's own first step then finds that
number taken, the run answers from the model and ends, and the production
watcher reports.

| row (drivers.py) | runtime     | transcript bytes | code | report                                                                 |
| ---------------- | ----------- | ---------------- | ---- | ---------------------------------------------------------------------- |
| report-at-cap    | interpreter | 23,068,672       | 0    | 46,138,164 bytes, 3 lines, terminal `done` (1.04 s)                    |
| report-at-cap    | native      | 23,068,672       | 0    | 46,138,164 bytes, terminal `done` (1.13 s)                             |
| report-past-cap  | interpreter | 23,068,673       | 3    | one line, `{"error": "transcript_too_large", "persistence": "proved"}` |
| report-past-cap  | native      | 23,068,673       | 3    | the same                                                               |

## Part 4: whole-report check

`report_cap.py diff` (`report-cap-diff-02.jsonl`, exit 0) ran `report-largest`
once under `mo run` and once as the `mo build` binary, with the workspace id
fixed.

- It cut both whole reports (5,112,239 and 5,112,238 bytes) at every `took_ms`
  field.
- All 5 non-`took_ms` segments are identical byte for byte: 5,112,188 bytes.
- The only differences are the four `took_ms` values: 2/3, 38/18, 8/5 and
  301/69.

Attempt 01 (`report-cap-diff-01.jsonl`, exit 1) is kept. It compared the two
reports byte by byte at the same offsets, so the one-digit shift at the first
`took_ms` misaligned everything after it. That was a checker bug, not a
difference in the reports.

## Numbers

`report_cap.py numbers` (`report-cap-numbers-01.jsonl`, exit 0) ran
`report-largest` five times per runtime under `/usr/bin/time -l`. Wall time is
the whole agent process: for the interpreter that includes `mo run` loading the
program, for native the built binary alone.

| runtime     | wall s (5 runs)          | best wall | peak RSS, best (range)         | load average before   |
| ----------- | ------------------------ | --------- | ------------------------------ | --------------------- |
| interpreter | 0.64 0.60 0.33 0.34 0.33 | 0.33 s    | 104,415,232 B (104.4–104.6 MB) | 25.43 / 14.85 / 14.71 |
| native      | 0.29 0.14 0.14 0.14 0.14 | 0.14 s    | 63,340,544 B (63.3–65.0 MB)    | 23.79 / 14.69 / 14.65 |

The host was shared with other workers, which is why the load average was high.

## Part 5: the clamped command's margin (D1)

`workspace-adapter.mo`:

- The new `candidate_margin_ms()` is 5,000 ms, with a comment giving the
  measured 0.5 to 1.4 s.
- `timed` now takes
  `min_of(candidate_ms(), by.remaining.ms - candidate_margin_ms())` and refuses
  below the 500 ms floor, as before.
- `posted` still waits for the whole remaining time, so the reply has the margin
  to arrive.
- The profile line reports `"candidate_margin_ms": 5000`.

**RED** (`37769240`, `red-margin-drivers-*-01`, exit 1) reproduces D1 through
the real socket. In `near-collected`, the bridge answers 1.4 s after the timeout
it was sent.

- Before the fix: 8000 ms remained, `timeout_ms` was 8000, and the adapter
  returned `timeout`/`transport_timeout`, execution `unknown`, with 0 ms left.
- In `near-margin-refused` (5,400 ms left), the command was sent before the fix.

**GREEN** (`f4a7b3c4`, `green-margin-drivers-*-01`, exit 0):

- `near-collected` sent `timeout_ms` 3000. The reply was received as
  `success`/`completed` with 3,599 ms (interpreter) and 3,595 ms (native) left.
- `near-margin-refused` gives `refusal`/`deadline` with no HTTP request.
- `near-sent`, `near-largest` and `reserve-inside` pass at deadlines raised by
  the margin: timeouts 1500, 2997/2995, and 4997/4994.

**The unit test.** `workspace-adapter.mo` gained
`test "a clamped command leaves the collection margin of what remains, so its late reply can arrive"`.
It was added after GREEN, so its RED was shown on a scratch copy of the agent
with the old `timed` (`red-margin-unit-01.jsonl`):
`3 passed, 1 failed, 0 skipped`, exit 1, `left = ... 8000}}`,
`right = ... 3000}}`. In the tree it is `4 passed, 0 failed, 0 skipped`.

**The finding 5 control.** `controls/near.mo.txt` pinned the old values
(`700 ms → 700`). It failed in `controls-cap-final.jsonl` (kept) and now uses
5,700/5,500/5,499 ms.

The machine was not used, so the margin is not yet shown against the real
service at 120 s. That is the lead's.

## Final focused runs on the final tree (`8e7e61a8`, real exit codes)

| run                                 | evidence                           | result                                                          | exit |
| ----------------------------------- | ---------------------------------- | --------------------------------------------------------------- | ---- |
| matrix, interpreter                 | `matrix-interpreter-cap-final-02`  | 34 of 34                                                        | 0    |
| matrix, native (incl. build)        | `matrix-native-cap-final-02`       | 35 of 35                                                        | 0    |
| drivers, interpreter                | `drivers-interpreter-cap-final-02` | 14 of 14                                                        | 0    |
| drivers, native (incl. build)       | `drivers-native-cap-final-02`      | 15 of 15                                                        | 0    |
| controls                            | `controls-cap-final-02`            | 8 of 8; `near` `1 passed, 0 failed, 0 skipped` in both runtimes | 0    |
| verify.py mo (fmt, mo test, native) | `verify-mo-cap-final-02`           | 81 of 81                                                        | 0    |
| closure (verified lines)            | `closure-margin-02`                | 24 of 24, no stale line, non-owned sources byte-identical       | 0    |

The two sources the brief names, from `verify-mo-cap-final-02`:

- `mo test examples/programs/agent/workspace-adapter.mo`:
  `4 passed, 0 failed, 0 skipped`, exit 0. Its native test binary: the same
  line, exit 0.
- `mo test examples/programs/agent/application.mo`:
  `0 passed, 0 failed, 0 skipped`, exit 0. Its native test binary: the same
  line, exit 0.

The `-cap-final` runs (without `-02`) came before the unit test and the control
update. Their matrix and driver results were identical.

## real_bridge.py fails, and it did so before this branch

`real-bridge-{interpreter,native}-cap-final.jsonl` (exit 1): 1 of 3 cases
passed. The same two checks fail on an archive of base `90add2f3` with the same
`mo` (`real-bridge-interpreter-base-90add2f3.jsonl`, exit 1):

- `four-files`: `all_accepted` is false, because the double's `exact_edit` now
  returns a completed `missing_match` refusal.
- `double-list`: the double's `list_files` rows now carry
  `length`/`sha256`/`mode`. The adapter therefore accepts them, and the case,
  which expects them refused as invalid, fails.

The accepted test double under `toolchain/harness/executor` appears to have
changed since that slice. This is not caused by this branch, and it is not fixed
here: it is outside the brief, and the double is toolchain. It is for the lead.

## Decisions the brief did not cover

1. **The model text bound.** It is the runtime's 1 MiB HTTP body limit
   (`toolchain/src/http.zig`), the most a model reply can be. Past it, the reply
   is `TooLarge` and never becomes a step.
   - It is a named function, `model_reply_cap()`, in `application.mo`. No Mo
     function stated it before, so this is one new named literal. `report_cap()`
     itself is an expression, as the brief asked.
   - It is not exposed and not on the profile line.
   - The step count comes from `application_order("").budget.steps`.
2. **"The largest the profile allows"** is the largest transcript a run can
   make. It is not the cap, which no run reaches.
   - The context bound ends a run at its first model request over 64 KiB. So a
     run holds under 64 KiB of steps, then one model reply and the one call it
     makes.
   - `report-largest` builds that case:
     - first, a read whose text leaves the context at 65,526 bytes;
     - then a `read_file` whose path is quotes, filling the request cap to
       exactly 851,968 bytes;
     - answered with text of quotes filling the response cap (524,287 bytes).
   - A quote is 2 bytes on the wire and 4 in a step.
   - A command cannot carry more, because its streams are capped at 64 KiB. A
     refused oversized request carries less.
   - The adapter and the accepted protocol admit this call. The real service
     would refuse such a path, so this is an upper construction, not a realistic
     run.
3. **"One row past the bound"** is a driver row, not a CLI row, since no CLI run
   can exceed 23 MB (see Part 3). I added the matching row at the bound.
4. **What "byte-identical in both runtimes" means here.** Every report step is
   the Book's step byte for byte, in each runtime. Across runtimes, the whole
   reports are equal outside `took_ms`, a per-run measurement; the matrix rows
   also mask the bridge's random workspace id.
5. **`common.invoke` gained `keep`** (default 4 MiB, as before), so the report
   rows can read reports of up to 64 MiB.
6. **The margin is 5 s**, about 3.5 times the largest measured need. It is named
   `candidate_margin_ms()` beside the other candidate bounds, and it is on the
   profile line as `candidate_margin_ms`, so the profile now has one more key.
   - The driver rows whose deadlines assumed no margin moved up by it:
     `near-sent`, `near-largest`, `reserve-inside` (now 25 s outer with a 13 s
     reply).
   - `near-margin-refused` is new.
7. **The margin's unit test** was added after GREEN. Its RED was shown on a
   scratch copy of the agent rather than by reordering commits.

## Limitations

- The model and bridge are the scripted local doubles. There was no machine or
  real service.
- The numbers are from a shared host with a load average of about 24.
- The interpreter's wall time includes `mo run` start-up.
- The full `zig build test` suite was not run, per the brief. `zig build` was
  run once at the start, exit 0.
