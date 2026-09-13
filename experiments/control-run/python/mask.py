"""Card-number masking: a run of 16 or more digits never reaches stdout."""

import re

CARD_RUN = re.compile(r"[0-9]{16,}")


def mask_card_numbers(text: str) -> str:
    """Replace every digit of every run of 16+ ASCII digits with `*`."""
    return CARD_RUN.sub(lambda match: "*" * len(match.group()), text)
