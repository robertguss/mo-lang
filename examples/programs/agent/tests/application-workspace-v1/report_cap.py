"""The largest report the profile allows, across the two runtimes. Usage: report_cap.py diff|numbers ATTEMPT

diff: the matrix's report-largest case once under mo run and once as the mo build binary, the
bridge's workspace id fixed, both whole reports kept in a scratch directory; every byte where they
differ is accounted for: the reports are cut at every took_ms field, every other segment must be
identical byte for byte, and the took_ms values are listed.
numbers: the same case five times in each runtime under /usr/bin/time -l, with wall time, peak
resident memory and the load average before each run; the best of five of each is summarised."""
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import tempfile

from common import MO, Attempt, invoke, trimmed
import fake_bridge as fb
import matrix

CASE = 'report-largest'
WORKSPACE = 'a' * 32


class Fixed:
    hex = WORKSPACE


def build(attempt):
    built = invoke([MO, 'build', str(matrix.MAIN), '-o', 'application-agent'], 600)
    ok = built['exit_code'] == 0 and os.access(matrix.NATIVE, os.X_OK)
    attempt.record(trimmed(dict(built, check='native-executable'), ok))
    return ok


def run(runtime, timed=False):
    """One run of the case; the row, untrimmed, with the whole stdout."""
    fb.uuid.uuid4 = lambda: Fixed
    original = matrix.invoke
    if timed:
        matrix.invoke = lambda args, seconds, **kw: original(['/usr/bin/time', '-l'] + args, seconds, **kw)
    kept = matrix.trimmed
    matrix.trimmed = lambda row, passed: dict(row, passed=passed)
    try:
        return matrix.run_case(CASE, matrix.CASES[CASE], runtime)
    finally:
        matrix.invoke = original
        matrix.trimmed = kept


def part_diff(attempt):
    if not build(attempt):
        return
    scratch = Path(tempfile.mkdtemp(prefix='mo-report-cap-diff-'))
    reports = {}
    for runtime in ('interpreter', 'native'):
        row = run(runtime)
        text = row['stdout']
        path = scratch / f'{runtime}.jsonl'
        path.write_text(text)
        reports[runtime] = text
        attempt.record(dict(trimmed(row, row['passed']), check='whole-report', report=str(path),
                            report_bytes=len(text.encode()), sha256=hashlib.sha256(text.encode()).hexdigest()))
    # The whole reports, cut at every took_ms field: every other segment must match byte for
    # byte, and the took_ms values that differ are listed.
    took = re.compile(r'(\\*"took_ms\\*": [0-9]+)')
    parts = {r: took.split(t) for r, t in reports.items()}
    a, b = parts['interpreter'], parts['native']
    segments = len(a) == len(b) and all(a[i] == b[i] for i in range(0, len(a), 2))
    values = [[a[i], b[i]] for i in range(1, min(len(a), len(b)), 2)]
    attempt.record(dict(check='whole-report-diff', passed=segments,
                        lengths=[len(reports['interpreter'].encode()), len(reports['native'].encode())],
                        segments=len(a), other_segments_identical=segments,
                        other_bytes=sum(len(a[i].encode()) for i in range(0, len(a), 2)),
                        took_ms_fields=values, took_ms_differing=sum(1 for x, y in values if x != y),
                        identical_raw=reports['interpreter'] == reports['native']))


def measured(stderr):
    real = re.search(r'([0-9.]+) real', stderr)
    rss = re.search(r'([0-9]+)\s+maximum resident set size', stderr)
    return (float(real.group(1)) if real else None, int(rss.group(1)) if rss else None)


def part_numbers(attempt):
    if not build(attempt):
        return
    best = {}
    for runtime in ('interpreter', 'native'):
        rows = []
        for i in range(5):
            load = os.getloadavg()
            row = run(runtime, timed=True)
            wall, rss = measured(row['stderr'])
            rows.append((wall, rss))
            attempt.record(dict(trimmed(row, row['passed'] and wall is not None and rss is not None),
                                check='timed', runtime=runtime, run=i + 1, wall_s=wall, peak_rss_bytes=rss,
                                load_before=[round(x, 2) for x in load]))
        best[runtime] = dict(wall_s=min(w for w, _ in rows if w is not None),
                             peak_rss_bytes=min(r for _, r in rows if r is not None))
    attempt.record(dict(check='best-of-five', passed=True, best=best, load_after=[round(x, 2) for x in os.getloadavg()]))


def main():
    part, name = sys.argv[1], sys.argv[2]
    if part not in ('diff', 'numbers'):
        raise SystemExit('part is diff or numbers')
    attempt = Attempt(name)
    part_diff(attempt) if part == 'diff' else part_numbers(attempt)
    sys.exit(int(attempt.failed))


if __name__ == '__main__':
    main()
