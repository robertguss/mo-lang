# Toolchain defect: large application report, both runtimes

Worker observation, 19 Sep 2026, base 030290b8 compiler (unchanged). Not fixed
here: the compiler and runtimes are outside this slice's write scope. Reported
for lead triage.

## Reproduction

The `application-workspace` CLI, the strict bridge double and the scripted model
are driven by `sizes_probe.py`, retained as `sizes_probe.py.txt`. The model
replies once with `write_file(path="big.txt", text="y" * N)` and then answers.
The run records that model step and the remote tool step, then ends over budget
at the 64 KiB context check. The Book log is complete, including its end line.
The Application watcher then renders the report.

Before the cap (commit 5caec127 source, no report cap; 500,000 row with a 1 MiB cap):

| N                 | interpreter                                                                                    | native                                            |
| ----------------- | ---------------------------------------------------------------------------------------------- | ------------------------------------------------- |
| 60,000 to 250,000 | correct report                                                                                 | correct report                                    |
| 350,000 / 450,000 | correct report (700 KB)                                                                        | exit 3, stdout is raw memory bytes (`\t\x00...`)  |
| 500,000           | correct report                                                                                 | raw memory bytes (matrix-native-03, report-bound) |
| 700,000           | correct report                                                                                 | not run                                           |
| 800,000 / 851,700 | exit 134, VM panic `access of union field 'string' while field 'none' is active` (vm.zig:1531) | raw memory bytes                                  |

The same 800,000-byte reply through the accepted `coding-fixture` mode reports
correctly in both runtimes. Isolated probes of each component in the interpreter
all work at these sizes: Book replay of the crashed log (Open/Look/Steps plus
`application_report`), a 4 MB deferred reply, 3.3 MB asks and stdout writes,
`read_lines` on 1.1 MB lines, and `Http.send` of an 851 KB body. Native plain
and deferred replies up to 2 MB also work. Bisection in a scratch copy of the
live path narrowed the interpreter panic to `application_report` inside the
Application `Poll` arm (reached by a delayed self-send). Replacing the answered
text with its size did not help; returning before `application_report` did. The
root cause was not established.

Native corruption can print arbitrary process memory to stdout. The capability
token could therefore be exposed on that path, although no instance of it was
observed.

## Mitigation in this slice

`Agent.Application.report_cap` is 262,144 transcript bytes. A larger transcript
produces a proved-persistence `reporting_error "transcript_too_large"` instead
of rendering. The cap appears in the profile line as `report_bytes`. Legitimate
transcripts stay far below it: model requests are refused over 64 KiB of
context, and core results are about 64 KiB. With the cap, N = 350,000 and
851,700 produce the correct versioned error in native, and matrix cases
`report-bound` (under the cap) and `report-over` / `request-bound` (over it)
cover both runtimes.
