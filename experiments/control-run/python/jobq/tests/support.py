"""Shared helpers: a board on a temporary directory with a fake clock, and API calls."""

import errno
import json
import os
import tempfile
import unittest
from pathlib import Path

from jobq.api import Request, Response
from jobq.board import Board, BoardOptions
from jobq.clock import FakeClock
from jobq.queue import Queue
from jobq.store import FileOps

FIXTURES = Path(__file__).parent / "fixtures"


class FailingOps:
    """File calls that fail while `failing` is set; a failing write first writes half."""

    def __init__(self) -> None:
        self.failing = False
        self.fail_fsync_only = False

    def write(self, fd: int, data: bytes) -> int:
        if self.failing and not self.fail_fsync_only:
            os.write(fd, data[: len(data) // 2])
            raise OSError(errno.EIO, "injected write failure")
        return os.write(fd, data)

    def fsync(self, fd: int) -> None:
        if self.failing:
            raise OSError(errno.EIO, "injected fsync failure")


class QueueCase(unittest.TestCase):
    """A fresh board per test under a temporary directory, with a fake clock. `queue` is the
    board's current queue, so it follows the board across its own restarts."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self.clock = FakeClock()
        self.ops = FailingOps()
        self.api = self.open()

    def tearDown(self) -> None:
        self.api.close()
        self._tmp.cleanup()

    @property
    def queue(self) -> Queue:
        return self.api.queue

    def open(self, ops: FileOps | None = None, options: BoardOptions | None = None) -> Board:
        return Board(self.dir, self.clock, ops or self.ops, options)

    def restart(self) -> None:
        self.api.close()
        self.api = self.open()

    def call(
        self,
        method: str,
        path: str,
        body: object = None,
        token: str | None = "w1",
        raw: bytes | None = None,
    ) -> Response:
        path, _, query = path.partition("?")
        data = raw if raw is not None else b"" if body is None else json.dumps(body).encode()
        return self.api.handle(Request(method, path, query, token, data))

    def create(
        self, queue: str = "emails", payload: str = "p", max_tries: int = 3, **fields: int
    ) -> str:
        body = {"queue": queue, "payload": payload, "max_tries": max_tries} | fields
        response = self.call("POST", "/jobs", body)
        self.assertEqual(response.status, 201, response.body)
        return str(body_of(response)["id"])


def body_of(response: Response) -> dict[str, object]:
    parsed = json.loads(response.body)
    assert isinstance(parsed, dict)
    return parsed
