from __future__ import annotations

from dataclasses import replace
from typing import Any

import pytest

from claim_check.calibrate import REPO
from claim_check.judge import Judgment

BASE = Judgment(
    relation="supports",
    probabilities={"supports": 0.95, "contradicts": 0.03, "says_nothing": 0.02},
    confidence=0.95,
    empty_selection=0.02,
    masked_failure=0.02,
    skipped=0.02,
    model="jev-1.13.0",
    input_tokens=500,
    seconds=0.2,
)


class ScriptedJudge:
    """A fake that answers every state with one judgment and remembers what it was asked."""

    def __init__(self, **changes: Any):
        self.judgment = replace(BASE, **changes)
        self.asked: list[dict[str, Any]] = []

    def ask(self, state: dict[str, Any], sources: list[str]) -> Judgment:
        self.asked.append(state)
        return self.judgment


@pytest.fixture
def repo() -> Any:
    return REPO
