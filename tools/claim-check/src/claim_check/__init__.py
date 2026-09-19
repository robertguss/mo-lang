"""Claim check: triage a worker report's claims against the raw output they rest on.

A lead-side working note. It never accepts anything, is never raw evidence,
and is never a reading.
"""

from __future__ import annotations

import argparse
import json
import subprocess
from pathlib import Path
from typing import Any


def main(argv: list[str] | None = None) -> int:
    from . import guard
    from .evidence import Log, render
    from .gate import Thresholds, run
    from .gate import render as render_result
    from .judge import Judge, RecordedJudge, TypeSafeJudge

    parser = argparse.ArgumentParser(prog="claim-check", description=__doc__)
    parser.add_argument("report", help="the report, relative to the repository root")
    parser.add_argument("--log", action="append", default=[], help="a raw log (repeatable)")
    parser.add_argument("--ref", default="HEAD", help="the branch the commits must be on")
    parser.add_argument("--live", action="store_true", help="ask Jev (needs TYPESAFE_API_KEY)")
    parser.add_argument("--confidence", type=float, default=Thresholds.confidence)
    parser.add_argument("--noul", type=float, default=Thresholds.noul)
    args = parser.parse_args(argv)

    repo = Path(
        subprocess.run(
            ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
        ).stdout.strip()
    )
    tool = repo / "tools" / "claim-check"
    answers = tool / "calibration" / "answers.json"
    recorded: dict[str, dict[str, Any]] = (
        json.loads(answers.read_text()) if answers.exists() else {}
    )
    for path in [args.report, *args.log]:
        guard.check_path(path, repo)
    judge: Judge
    if args.live:
        judge = TypeSafeJudge(
            repo, tool / "sent", tool / "calibration" / "budget.json", 2000, recorded
        )
    else:
        judge = RecordedJudge(recorded)
    logs = [Log(p, render(repo / p)) for p in args.log]
    result = run(
        (repo / args.report).read_text(),
        logs,
        args.ref,
        repo,
        judge,
        Thresholds(args.confidence, args.noul),
        args.report,
    )
    print(render_result(result), end="")
    return 0
