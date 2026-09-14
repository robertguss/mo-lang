"""The card-number never: sixteen digits never reach stdout."""

import re

from logstat.contract import ensure

# Sixteen or more digits in a row, optionally split by single dashes (4111-1111-1111-1111).
_CARD_NUMBER = re.compile(r"\d(?:-?\d){15,}")


def find_card_number(text: str) -> str | None:
    """The first card-number-like run in `text`, or None."""
    match = _CARD_NUMBER.search(text)
    return None if match is None else match.group()


def mask_card_numbers(text: str) -> str:
    """`text` with every digit of every card-number-like run replaced by `*`."""
    masked = _CARD_NUMBER.sub(lambda m: re.sub(r"\d", "*", m.group()), text)
    ensure(find_card_number(masked) is None, "no card number survives masking")
    ensure(len(masked) == len(text), "masking keeps the length")
    return masked
