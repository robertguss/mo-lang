"""Contracts as explicit checks: a broken one raises with the condition's text."""


class ContractError(Exception):
    """A `requires`, `ensures`, or `invariant` did not hold."""


def require(condition: bool, text: str) -> None:
    if not condition:
        raise ContractError(f"requires {text}")


def ensure(condition: bool, text: str) -> None:
    if not condition:
        raise ContractError(f"ensures {text}")
