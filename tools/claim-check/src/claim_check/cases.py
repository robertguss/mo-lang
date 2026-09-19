"""The labelled set: each case is a report, its raw logs and the known truth."""

from __future__ import annotations

import json
import subprocess
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any

from . import guard
from .evidence import Log, render
from .report import Claim


@dataclass(frozen=True)
class Label:
    kind: str
    contains: str
    truth: bool  # is the claim true?
    why: str

    def matches(self, claim: Claim) -> bool:
        return claim.kind == self.kind and self.contains in claim.value


@dataclass(frozen=True)
class Case:
    id: str
    kind: str  # "historical", "planted" or "accurate"
    source: str
    report: str  # repository-relative path
    report_at: str | None  # read the report at this revision, if set
    logs: list[str]
    ref: str
    defective: bool
    defect: str
    expected: str  # "caught" or "missed", written before the live run
    caught_by_incomplete: bool
    labels: list[Label] = field(default_factory=list)

    def report_text(self, repo: Path) -> str:
        if self.report_at:
            return subprocess.run(
                ["git", "show", f"{self.report_at}:{self.report}"],
                cwd=repo,
                capture_output=True,
                text=True,
                check=True,
            ).stdout
        return (repo / self.report).read_text()

    def load_logs(self, repo: Path) -> list[Log]:
        loaded = []
        for path in self.logs:
            guard.check_path(path, repo)
            loaded.append(Log(path, render(repo / path)))
        return loaded


def load(path: Path) -> Case:
    data: dict[str, Any] = json.loads(path.read_text())
    labels = [Label(**label) for label in data.pop("labels", [])]
    return Case(labels=labels, **data)


def load_all(folder: Path) -> list[Case]:
    return [load(p) for p in sorted(folder.glob("*.json"))]
