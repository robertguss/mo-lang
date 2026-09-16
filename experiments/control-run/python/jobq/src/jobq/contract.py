"""Contracts as explicit checks. A failure names the condition that did not hold.

These are not `assert` statements, so `python -O` does not remove them.
"""


class ContractError(Exception):
    """A requires, ensures, or invariant check failed: a bug in jobq, not bad input."""


def require(condition: bool, text: str) -> None:
    """A precondition the caller must meet."""
    if not condition:
        raise ContractError(f"requires {text}")


def ensure(condition: bool, text: str) -> None:
    """A postcondition the function promises."""
    if not condition:
        raise ContractError(f"ensures {text}")


def invariant(condition: bool, text: str) -> None:
    """A condition that holds after every change of state."""
    if not condition:
        raise ContractError(f"invariant {text}")


def never(condition: bool, text: str) -> None:
    """A condition no change of state may ever break, checked on every change."""
    if not condition:
        raise ContractError(f"never broken: {text}")


class BoardFailure(Exception):
    """The board failed in a way that is not one request's: a rule broken inside the queue,
    or an unexpected error while a change was being applied. The board is rebuilt from the
    log; the request that met the failure is a 503."""


class ChaosFailure(BoardFailure):
    """The failure `--crash-every` injects: after a write is on disk, before it is applied."""
