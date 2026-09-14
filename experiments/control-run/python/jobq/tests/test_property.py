"""Property: create then get round-trips any valid payload, through the API and a replay."""

import random
import unittest

from jobq.jobs import MAX_PAYLOAD_BYTES, payload_problem
from support import QueueCase, body_of

# Printable ASCII, the one allowed control character, and 2-, 3-, and 4-byte UTF-8.
ALPHABET = [chr(c) for c in range(0x20, 0x7F)] + ["\n", "é", "\u00a0", "中", "\U0001f600"]


def payload(rng: random.Random) -> str:
    shape = rng.random()
    if shape < 0.1:
        return ""
    if shape < 0.2:
        return "\U0001f600" * (MAX_PAYLOAD_BYTES // 4)  # exactly 60 KiB of 4-byte characters
    return "".join(rng.choice(ALPHABET) for _ in range(rng.randrange(1, 400)))


class RoundTripTest(QueueCase):
    def test_create_then_get_round_trips_any_valid_payload(self) -> None:
        rng = random.Random(20260914)
        created: dict[str, str] = {}
        for _ in range(300):
            text = payload(rng)
            self.assertIsNone(payload_problem(text))
            job_id = self.create(queue=rng.choice(["a", "b"]), payload=text)
            got = self.call("GET", f"/jobs/{job_id}")
            self.assertEqual(got.status, 200)
            self.assertEqual(body_of(got)["payload"], text)
            created[job_id] = text
        self.restart()
        for job_id, text in created.items():
            self.assertEqual(body_of(self.call("GET", f"/jobs/{job_id}"))["payload"], text)


if __name__ == "__main__":
    unittest.main()
