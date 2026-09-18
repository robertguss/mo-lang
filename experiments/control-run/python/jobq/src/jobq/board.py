"""The board and its supervisor: the queue that answers requests, rebuilt from the log when it
fails in a way that is not one request's.

A failure of the board (a broken contract, a `BoardFailure`, or `--crash-every`) closes the
store, replays the log into a fresh queue, and answers the request that met it with a 503.
Every write that reached the disk before the failure is on the new board, since the board is
the log's. More than `max_restarts` restarts inside `restart_window_s` and the board stops
instead: it writes nothing more, answers 503, and `exhausted` tells the listener to exit 70.

Everything here runs on the queue's one thread; `restarting` and `exhausted` are only read
from elsewhere.
"""

import sys
import time
from collections import deque
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

from jobq.api import Api, Request, Response, error
from jobq.clock import Clock, SystemClock
from jobq.contract import BoardFailure, ContractError, require
from jobq.jobs import DEFAULT_RETAIN_MS
from jobq.queue import Chaos, Queue
from jobq.store import FileOps, Store, StoreOpenError

DEFAULT_MAX_RESTARTS = 5
DEFAULT_RESTART_WINDOW_S = 60
# A rebuild that cannot open the folder is tried again after this long, each try counting
# as a restart, so the budget ends a folder that never opens (chosen: 0.1 s).
REOPEN_PAUSE_S = 0.1
SPENT = "jobq is stopping: the restart budget is spent"


@dataclass(frozen=True)
class BoardOptions:
    """The restart budget, the chaos switch, how long a finished job stays on the board, and
    how old an archived job is pruned, as `serve` takes them."""

    max_restarts: int = DEFAULT_MAX_RESTARTS
    restart_window_s: float = DEFAULT_RESTART_WINDOW_S
    crash_every: int = 0
    retain_ms: int = DEFAULT_RETAIN_MS
    retention_ms: int = 0  # the background prune's age; 0 never prunes


class Board:
    def __init__(
        self,
        directory: Path,
        clock: Clock | None = None,
        ops: FileOps | None = None,
        options: BoardOptions | None = None,
        monotonic: Callable[[], float] = time.monotonic,
    ) -> None:
        """Open and replay the store under `directory`. StoreOpenError when it cannot."""
        self._directory = directory
        self._clock = clock or SystemClock()
        self._ops = ops
        self._budget = options or BoardOptions()
        require(self._budget.max_restarts >= 0, "max_restarts is 0 or more")
        require(self._budget.restart_window_s > 0, "restart_window is above 0")
        self._chaos = Chaos(self._budget.crash_every)
        self._monotonic = monotonic
        self._recent: deque[float] = deque()
        self._started_ms = self._clock.now_ms()
        self.restarts = 0
        self.restarting = False
        self.exhausted = False
        self.queue, self.api = self._open()

    def _open(self) -> tuple[Queue, Api]:
        store, replayed = Store.open(self._directory, self._ops)
        try:
            queue = Queue(
                store,
                self._clock,
                replayed,
                self._chaos,
                self._budget.retain_ms,
                self._budget.retention_ms,
            )
        except BaseException:
            store.close()
            raise
        return queue, Api(queue, self._clock, self._started_ms, lambda: self.restarts)

    def handle(self, request: Request) -> Response:
        """The API's answer, or a 503 when the board fails, has failed, or is spent."""
        if self.exhausted:
            return error(503, SPENT)
        try:
            return self.api.handle(request)
        except (ContractError, BoardFailure) as failure:
            self.fail(f"{request.method} {request.path}: {failure}")
            if self.exhausted:
                return error(503, f"{SPENT}; read the job to learn what happened")
            return error(503, "the service is restarting; read the job to learn what happened")

    def expire_due(self) -> int:
        """The idle look, supervised as a request is."""
        if self.exhausted:
            return 0
        try:
            return self.queue.expire_due()
        except (ContractError, BoardFailure) as failure:
            self.fail(f"the idle look: {failure}")
            return 0

    def fail(self, what: str) -> None:
        """The board failed: rebuild it from the log, or stop when the budget is spent."""
        print(f"jobq: the board failed ({what}); rebuilding it from the log", file=sys.stderr)
        self.restarting = True
        try:
            self.queue.store.close()
            while not self._restart():
                time.sleep(REOPEN_PAUSE_S)
        finally:
            self.restarting = False

    def _restart(self) -> bool:
        """One restart, counted against the budget; whether the board is serving again."""
        now = self._monotonic()
        while self._recent and now - self._recent[0] >= self._budget.restart_window_s:
            self._recent.popleft()
        if len(self._recent) >= self._budget.max_restarts:
            print(
                f"jobq: {self._budget.max_restarts} restarts in "
                f"{self._budget.restart_window_s:g} s; stopping",
                file=sys.stderr,
            )
            self.exhausted = True
            return True
        self._recent.append(now)
        self.restarts += 1
        try:
            self.queue, self.api = self._open()
        except StoreOpenError as unopened:
            print(f"jobq: the board cannot be rebuilt: {unopened}", file=sys.stderr)
            return False
        return True

    def close(self) -> None:
        self.queue.store.close()
