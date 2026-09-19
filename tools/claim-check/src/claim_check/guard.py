"""What may leave the machine, and the record of what did.

The sender refuses by path and by pattern before any request: nothing under
`audit/mo-audit-*`, no sealed or hidden suite, nothing that looks like a
secret, nothing outside the repository. Every request's state and questions
are written to the git-ignored `sent/` folder before they are sent.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import time
from collections.abc import Iterable, Mapping
from pathlib import Path
from typing import Any

FORBIDDEN_PATHS: tuple[re.Pattern[str], ...] = (
    re.compile(r"(^|/)audit/mo-audit-"),
    re.compile(r"(^|/)mo-audit-[^/]*$"),
    re.compile(r"sealed", re.IGNORECASE),
    re.compile(r"hidden[-_ ]?suite", re.IGNORECASE),
    re.compile(r"(^|/)\.mo-lead(/|$)"),
    re.compile(r"(^|/)fnox\.toml$"),
    re.compile(r"(^|/)[^/]*\.env(\.[^/]*)?$"),
    re.compile(
        r"(^|/)[^/]*(key|secret|token|credential|password)[^/]*\.(pem|json|txt|key|toml)$", re.I
    ),
    re.compile(r"\.(key|p12|pfx)$"),
    re.compile(r"(^|/)(capabilit(y|ies)|private)[^/]*$", re.IGNORECASE),
)

SECRET_PATTERNS: tuple[re.Pattern[str], ...] = (
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
    re.compile(r"\bsk-[A-Za-z0-9_-]{20,}"),
    re.compile(r"\bgh[pousr]_[A-Za-z0-9]{30,}"),
    re.compile(r"\bgithub_pat_[A-Za-z0-9_]{20,}"),
    re.compile(r"\bxox[abprs]-[A-Za-z0-9-]{10,}"),
    re.compile(r"\bAKIA[0-9A-Z]{16}\b"),
    re.compile(r"\bBearer\s+[A-Za-z0-9._~+/=-]{20,}"),
    re.compile(r"TYPESAFE_API_KEY\s*[=:]\s*\S+"),
    re.compile(
        r"(?i)\b(api[_-]?key|secret|access[_-]?token|password)\b\s*[:=]\s*['\"]?[A-Za-z0-9._/+=-]{16,}"
    ),
    re.compile(r"-----BEGIN AGE ENCRYPTED FILE-----"),
    re.compile(r"\bAGE-SECRET-KEY-1[0-9A-Z]{50,}"),
)


class Refused(Exception):
    """A request that would send something that must not leave the machine."""


def check_path(path: str | Path, repo: Path) -> None:
    """Refuse a source path outside the repository or matching a forbidden pattern."""
    resolved = (repo / path).resolve() if not Path(path).is_absolute() else Path(path).resolve()
    try:
        relative = resolved.relative_to(repo.resolve()).as_posix()
    except ValueError as error:
        raise Refused(f"outside the repository: {path}") from error
    for pattern in FORBIDDEN_PATHS:
        if pattern.search(relative):
            raise Refused(f"refused by path ({pattern.pattern}): {relative}")


def _strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, Mapping):
        for k, v in value.items():
            yield str(k)
            yield from _strings(v)
    elif isinstance(value, (list, tuple)):
        for v in value:
            yield from _strings(v)
    elif value is not None:
        yield str(value)


def check_payload(payload: Any, key: str | None = None) -> None:
    """Refuse a payload that carries a secret, or the key itself."""
    key = key if key is not None else os.environ.get("TYPESAFE_API_KEY")
    for text in _strings(payload):
        if key and len(key) >= 8 and key in text:
            raise Refused("refused by pattern: the payload carries the API key")
        for pattern in SECRET_PATTERNS:
            if pattern.search(text):
                raise Refused(f"refused by pattern: {pattern.pattern}")
        if re.search(r"audit/mo-audit-", text):
            raise Refused("refused by pattern: the payload names an auditor's reading")


def record(sent_dir: Path, state: Any, questions: Any, model: str, sources: list[str]) -> Path:
    """Write what is about to leave the machine, before it leaves."""
    sent_dir.mkdir(parents=True, exist_ok=True)
    body = {"model": model, "state": state, "questions": questions, "sources": sources}
    digest = hashlib.sha256(json.dumps(body, sort_keys=True).encode()).hexdigest()[:16]
    path = sent_dir / f"{time.strftime('%Y%m%dT%H%M%S')}-{digest}.json"
    body["recorded_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    path.write_text(json.dumps(body, indent=2, ensure_ascii=False) + "\n")
    return path
