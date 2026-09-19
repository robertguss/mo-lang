"""The four questions, and the one small interface the model sits behind.

`TypeSafeJudge` calls Jev through the SDK; `RecordedJudge` answers from a
file of recorded answers, so every test and every re-run of the calibration
works offline. Both return the same `Judgment`.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Protocol

from . import guard

# The newest jev-1.x the Models page lists (docs.typesafe.ai/models, read
# 19 Sep 2026): Jev 1.13, versioned ID `jev-1.13.0`. Pinned by exact name.
MODEL = "jev-1.13.0"

# Price on the Models page: $0.042 per million input tokens; output is free.
DOLLARS_PER_INPUT_TOKEN = 0.042 / 1_000_000

QUESTIONS: dict[str, dict[str, Any]] = {
    "relation": {
        "type": "choice",
        "instructions": (
            "Does the output in `log_excerpt` support the claim in `claim`, contradict it, "
            "or say nothing about it? `report_words` are the words of the report the claim "
            "was taken from."
        ),
        "criteria": {
            "supports": (
                "The output shows the result the claim states, for the run the claim is about"
            ),
            "contradicts": (
                "The output shows a different result for that run: failures, a crash, a "
                "timeout, a different exit code, or a run that did not finish"
            ),
            "says_nothing": ("The output does not show the result the claim is about, either way"),
        },
    },
    "empty_selection": {
        "type": "noul",
        "instructions": (
            "Does the output in `log_excerpt` show that zero tests, checks or inputs were "
            "selected, run or counted?"
        ),
        "criteria": {
            "true": (
                "The output reports 0 tests, 0 checks or 0 inputs, 0 passed with 0 failed, "
                "or that nothing matched a selection or filter"
            ),
            "false": "The output shows at least one test, check or input actually ran",
        },
    },
    "masked_failure": {
        "type": "noul",
        "instructions": (
            "Does the output in `log_excerpt` show a failure, panic, crash or timeout and "
            "still end in a success status?"
        ),
        "criteria": {
            "true": (
                "A line reports a failed test or batch, a panic, an abort, a crash or a "
                "timeout, and a later line reports success, exit 0, OK or 0 crashes"
            ),
            "false": ("No failure, panic, crash or timeout appears, or the output ends in failure"),
        },
    },
    "skipped": {
        "type": "noul",
        "instructions": (
            "Does the output in `log_excerpt` show tests that were skipped, filtered out or "
            "never reached?"
        ),
        "criteria": {
            "true": (
                "The output reports skipped tests, a filter that left tests out, or a run "
                "cut short before its last test"
            ),
            "false": "Every selected test is reported as run to its end",
        },
    },
}


@dataclass(frozen=True)
class Judgment:
    relation: str
    probabilities: dict[str, float]
    confidence: float
    empty_selection: float
    masked_failure: float
    skipped: float
    model: str
    input_tokens: int
    seconds: float


class Judge(Protocol):
    def ask(self, state: dict[str, Any], sources: list[str]) -> Judgment: ...


def state_key(state: dict[str, Any]) -> str:
    """A stable key for a state and the current questions, for recorded answers."""
    body = json.dumps({"state": state, "questions": QUESTIONS, "model": MODEL}, sort_keys=True)
    return hashlib.sha256(body.encode()).hexdigest()


class RecordedJudge:
    """Answers from recorded answers only; an unrecorded state is an error, never a call."""

    def __init__(self, answers: dict[str, dict[str, Any]]):
        self.answers = answers

    @classmethod
    def load(cls, path: Path) -> RecordedJudge:
        return cls(json.loads(path.read_text()) if path.exists() else {})

    def ask(self, state: dict[str, Any], sources: list[str]) -> Judgment:
        key = state_key(state)
        if key not in self.answers:
            raise KeyError(f"no recorded answer for state {key[:12]}")
        return Judgment(**self.answers[key]["judgment"])


class BudgetExceeded(Exception):
    pass


class TypeSafeJudge:
    """Jev through the SDK, behind the guard, with a request budget and a record of each send."""

    def __init__(
        self,
        repo: Path,
        sent_dir: Path,
        budget_file: Path,
        budget: int,
        recorded: dict[str, dict[str, Any]],
        client: Any = None,
    ):
        key = os.environ.get("TYPESAFE_API_KEY")
        if not key:
            raise RuntimeError("TYPESAFE_API_KEY is not set")
        self._key = key
        if client is None:
            # imported here so offline use needs neither
            import httpx2
            from typesafe_sdk import TypeSafeClient

            # The environment's proxy settings are read here and passed explicitly:
            # httpx2 cannot parse a NO_PROXY entry of "[::1]", which some hosts set.
            proxy = os.environ.get("HTTPS_PROXY") or os.environ.get("https_proxy") or None
            http = httpx2.Client(trust_env=False, proxy=proxy, timeout=120.0)
            client = TypeSafeClient(api_key=key, model=MODEL, http_client=http)
        self.client = client
        self.repo = repo
        self.sent_dir = sent_dir
        self.budget_file = budget_file
        self.budget = budget
        self.recorded = recorded

    def _spent(self) -> int:
        if self.budget_file.exists():
            return int(json.loads(self.budget_file.read_text())["requests"])
        return 0

    def ask(self, state: dict[str, Any], sources: list[str]) -> Judgment:
        key = state_key(state)
        if key in self.recorded:
            return Judgment(**self.recorded[key]["judgment"])
        for source in sources:
            guard.check_path(source, self.repo)
        guard.check_payload(state, self._key)
        spent = self._spent()
        if spent >= self.budget:
            raise BudgetExceeded(f"{spent} requests spent of {self.budget}")
        guard.record(self.sent_dir, state, QUESTIONS, MODEL, sources)
        self.budget_file.write_text(json.dumps({"requests": spent + 1}) + "\n")
        started = time.perf_counter()
        response = self.client.system_one(state=state, questions=QUESTIONS, model=MODEL)
        seconds = round(time.perf_counter() - started, 3)
        relation = response.choices["relation"]
        judgment = Judgment(
            relation=relation.choice,
            probabilities=dict(relation.probabilities),
            confidence=relation.confidence,
            empty_selection=response.nouls["empty_selection"].noul,
            masked_failure=response.nouls["masked_failure"].noul,
            skipped=response.nouls["skipped"].noul,
            model=response.model,
            input_tokens=response.usage.input_tokens or 0,
            seconds=seconds,
        )
        self.recorded[key] = {"state": state, "judgment": asdict(judgment)}
        return judgment
