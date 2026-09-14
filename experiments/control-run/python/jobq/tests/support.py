"""Shared by the tests: a queue on the simulated filesystem, with a clock the test moves."""

import json
import random
from pathlib import Path
from typing import Any

from jobq.api import Request, Response, respond
from jobq.clock import ManualClock
from jobq.fs import Faults, MemoryFs
from jobq.queue import Queue
from jobq.store import LOG_NAME, Store

START_MS = 1_767_225_600_000
SIM_DIR = Path("/sim")
LOG = SIM_DIR / LOG_NAME


class Rig:
    def __init__(self, seed: int = 0) -> None:
        self.faults = Faults(random.Random(seed))
        self.fs = MemoryFs(self.faults)
        self.clock = ManualClock(START_MS)
        self.store = Store(self.fs, SIM_DIR)
        self.queue = Queue.open(self.store, self.clock)

    def restart(self, crash: bool = True) -> Queue:
        """Stop without warning (unsynced bytes lost) and replay the log into a new queue."""
        if crash:
            self.fs.crash()
        self.store = Store(self.fs, SIM_DIR)
        self.queue = Queue.open(self.store, self.clock)
        return self.queue

    def call(
        self,
        method: str,
        path: str,
        token: str | None = "w1",
        body: object = None,
        raw: bytes | None = None,
    ) -> Response:
        headers = {} if token is None else {"authorization": f"Bearer {token}"}
        if raw is None:
            raw = b"" if body is None else json.dumps(body).encode()
        return respond(self.queue, Request(method, path, headers, raw))

    def create(self, queue: str = "emails", payload: str = "hi", max_attempts: int = 3) -> str:
        response = self.call(
            "POST", "/jobs", body={"queue": queue, "payload": payload, "max_attempts": max_attempts}
        )
        assert response.status == 201, response
        job_id: str = body_of(response)["id"]
        return job_id

    def durable_log(self) -> bytes:
        file = self.fs.files.get(LOG)
        return b"" if file is None else file.durable


def body_of(response: Response) -> Any:
    return json.loads(response.body)
