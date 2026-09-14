"""Explicit contract checks: a broken `requires` raises ContractError."""


class ContractError(Exception):
    """A value broke a stated contract; this is a bug in the caller."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ContractError(message)
