from __future__ import annotations

import json
from pathlib import Path
from typing import Any

import pytest

from claim_check import guard
from claim_check.judge import TypeSafeJudge

REFUSED_PATHS = [
    "audit/mo-audit-2026-09-18-current-state.md",
    "audit/evidence/2026-09-19/mo-audit-copy.md",
    "audit/sealed/suite.py",
    "audit/evidence/x/hidden-suite/run.py",
    "../../../.mo-lead/typesafe.env",
    "../mo-lang/fnox.toml",
    "examples/effects/tls/key.pem",
    "audit/evidence/2026-09-18/step-37/worker-raw/step36/step36-pairs/key-p256.pem",
    "tools/typesafe.env",
    "provider/private-capability.json",
    "/etc/passwd",
]


@pytest.mark.parametrize("path", REFUSED_PATHS)
def test_the_sender_refuses_by_path(path: str, repo: Path) -> None:
    with pytest.raises(guard.Refused):
        guard.check_path(path, repo)


@pytest.mark.parametrize(
    "path",
    [
        "toolchain/STEP-43-REPORT.md",
        "audit/evidence/2026-09-19/fable-lead-verification/step43/darwin-full-suite.log",
        "toolchain/bench/step40/numbers.tsv",
    ],
)
def test_the_sender_allows_reports_and_logs(path: str, repo: Path) -> None:
    guard.check_path(path, repo)


SECRETS = [
    "-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEI\n-----END PRIVATE KEY-----",
    "-----BEGIN EC PRIVATE KEY-----",
    "export TYPESAFE_API_KEY=ts-live-abcdef0123456789",
    "api_key: abcdefghijklmnop0123",
    "Authorization: Bearer abcdefghijklmnopqrstuvwxyz012345",
    "ghp_abcdefghijklmnopqrstuvwxyz0123456789",
    "AKIAABCDEFGHIJKLMNOP",
    "sk-abcdefghijklmnopqrstuvwxyz",
    "see audit/mo-audit-2026-09-18-x.md",
    "-----BEGIN AGE ENCRYPTED FILE-----",
]


@pytest.mark.parametrize("text", SECRETS)
def test_the_sender_refuses_by_pattern(text: str) -> None:
    with pytest.raises(guard.Refused):
        guard.check_payload({"log_excerpt": text}, key="")


def test_the_key_itself_is_refused_wherever_it_sits() -> None:
    key = "not-a-real-key-0000"
    with pytest.raises(guard.Refused):
        guard.check_payload({"claim": "x", "nested": ["ok", f"...{key}..."]}, key=key)


def test_an_ordinary_state_passes() -> None:
    guard.check_payload(
        {
            "claim": "The run printed `Build Summary: 5/5 steps succeeded; 9/9 tests passed`.",
            "log_excerpt": "test success\nexit=0",
        },
        key="",
    )


def test_the_record_is_written_before_sending(tmp_path: Path) -> None:
    path = guard.record(tmp_path / "sent", {"claim": "c"}, {"q": {}}, "jev-1.13.0", ["a.log"])
    body = json.loads(path.read_text())
    assert body["state"] == {"claim": "c"} and body["model"] == "jev-1.13.0"
    assert body["sources"] == ["a.log"]


class ExplodingClient:
    def system_one(self, **_: Any) -> Any:
        raise AssertionError("a refused request reached the client")


def _judge(tmp_path: Path, repo: Path, monkeypatch: pytest.MonkeyPatch, key: str) -> TypeSafeJudge:
    monkeypatch.setenv("TYPESAFE_API_KEY", key)
    return TypeSafeJudge(
        repo, tmp_path / "sent", tmp_path / "budget.json", 2, {}, client=ExplodingClient()
    )


def test_a_refused_state_is_neither_sent_nor_recorded(
    tmp_path: Path, repo: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    key = "fake-key-for-the-test-0000"
    judge = _judge(tmp_path, repo, monkeypatch, key)
    with pytest.raises(guard.Refused):
        judge.ask({"claim": "c", "log_excerpt": f"TOKEN {key}"}, ["toolchain/STEP-43-REPORT.md"])
    with pytest.raises(guard.Refused):
        judge.ask({"claim": "c"}, ["audit/mo-audit-2026-09-18-current-state.md"])
    assert not (tmp_path / "sent").exists()
    assert not (tmp_path / "budget.json").exists()


def test_the_budget_stops_requests(
    tmp_path: Path, repo: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    from claim_check.judge import BudgetExceeded

    judge = _judge(tmp_path, repo, monkeypatch, "fake-key-for-the-test-0000")
    (tmp_path / "budget.json").write_text('{"requests": 2}\n')
    with pytest.raises(BudgetExceeded):
        judge.ask({"claim": "c"}, ["toolchain/STEP-43-REPORT.md"])
    assert not (tmp_path / "sent").exists()
