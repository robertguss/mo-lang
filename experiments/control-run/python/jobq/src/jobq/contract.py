"""Contracts as explicit checks: a broken one raises with the condition's text."""


class ContractError(Exception):
    """A `requires`, `ensures`, `invariant`, or `never` did not hold."""


def require(condition: bool, text: str) -> None:
    if not condition:
        raise ContractError(f"requires {text}")


def ensure(condition: bool, text: str) -> None:
    if not condition:
        raise ContractError(f"ensures {text}")


def invariant(condition: bool, text: str) -> None:
    if not condition:
        raise ContractError(f"invariant {text}")


def never(broken: bool, text: str) -> None:
    if broken:
        raise ContractError(f"never {text}")
