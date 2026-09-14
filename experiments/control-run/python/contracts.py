"""Contracts as explicit checks. A broken clause raises; `assert` is not used, since `python -O` strips it."""


class ContractViolation(Exception):
    """A `requires` or `ensures` clause did not hold."""


def require(condition: bool, clause: str) -> None:
    """Raise ContractViolation naming the clause when the condition is false."""
    if not condition:
        raise ContractViolation(clause)
