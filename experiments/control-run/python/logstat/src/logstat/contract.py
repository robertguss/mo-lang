"""Contracts as explicit checks. A failure names the condition that did not hold.

These are not `assert` statements, so `python -O` does not remove them.
"""


class ContractError(Exception):
    """A requires, ensures, or invariant check failed: a bug in logstat, not bad input."""


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
