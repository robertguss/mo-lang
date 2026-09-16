import contextlib
import http.client
import io
import json
import resource
import socket
import tempfile
import threading
import time
import unittest
from pathlib import Path
from unittest import mock

from bench.bench import write_log

from jobq import server
from jobq.api import Api, Request, Response
from jobq.board import BoardOptions
from jobq.client import Call, ClientResponse, request
from jobq.server import (
    EXIT_SPENT,
    HOST,
    BadRequest,
    QueueRunner,
    ServerThread,
    bearer_token,
    body_length,
    encode_response,
    parse_head,
)
from jobq.store import Store, StoreOpenError, replay

KEEP_ALIVE_TAIL = (
    b"content-length: 2\r\ncontent-type: application/json\r\nconnection: keep-alive\r\n\r\n{}"
)
SOCKET_TIMEOUT_S = 10.0  # within: chosen, for every test socket


class HeadTest(unittest.TestCase):
    def test_parses_request_line_query_and_headers(self) -> None:
        head = parse_head(
            b"GET /jobs?state=done HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer w1\r\n\r\n"
        )
        self.assertEqual((head.method, head.path, head.query), ("GET", "/jobs", "state=done"))
        self.assertEqual(head.headers["authorization"], "Bearer w1")
        self.assertTrue(head.keep_alive)

    def test_http_1_0_and_connection_close_do_not_keep_alive(self) -> None:
        self.assertFalse(parse_head(b"GET / HTTP/1.0\r\n\r\n").keep_alive)
        self.assertFalse(parse_head(b"GET / HTTP/1.1\r\nConnection: close\r\n\r\n").keep_alive)

    def test_rejects_malformed_heads(self) -> None:
        for raw in (
            b"GET /\r\n\r\n",
            b"GET / HTTP/2\r\n\r\n",
            b"GET / HTTP/1.1\r\nno colon\r\n\r\n",
            b"GET / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n",
            "GET /café HTTP/1.1\r\n\r\n".encode(),
        ):
            with self.assertRaises(BadRequest, msg=repr(raw)):
                parse_head(raw)

    def test_body_length(self) -> None:
        self.assertEqual(body_length(parse_head(b"POST / HTTP/1.1\r\n\r\n")), 0)
        self.assertEqual(
            body_length(parse_head(b"POST / HTTP/1.1\r\nContent-Length: 12\r\n\r\n")), 12
        )
        for header, status in (
            (b"Content-Length: -1", 400),
            (b"Content-Length: 2000000", 413),
            (b"Transfer-Encoding: chunked", 400),
        ):
            with self.assertRaises(BadRequest) as caught:
                body_length(parse_head(b"POST / HTTP/1.1\r\n" + header + b"\r\n\r\n"))
            self.assertEqual(caught.exception.status, status)

    def test_bearer_token(self) -> None:
        self.assertEqual(bearer_token("Bearer w1"), "w1")
        self.assertEqual(bearer_token("bearer w1"), "w1")
        for value in (None, "", "Bearer", "Bearer ", "Basic w1", "Bearer a b", "Bearer\tw1"):
            self.assertIsNone(bearer_token(value), value)

    def test_encode_response(self) -> None:
        self.assertEqual(
            encode_response(Response(204), keep_alive=False),
            b"HTTP/1.1 204 No Content\r\nconnection: close\r\n\r\n",
        )
        encoded = encode_response(Response(200, b"{}"), keep_alive=True)
        self.assertTrue(encoded.endswith(KEEP_ALIVE_TAIL))


class ServerCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self.thread = ServerThread(self.dir)
        self.thread.__enter__()

    def tearDown(self) -> None:
        self.thread.__exit__(None, None, None)
        self._tmp.cleanup()

    def call(
        self, token: str | None, method: str, path: str, body: object = None
    ) -> ClientResponse:
        text = None if body is None else json.dumps(body)
        return request(HOST, self.thread.port, Call(token, method, path, text), SOCKET_TIMEOUT_S)

    def raw(self, data: bytes) -> bytes:
        with socket.create_connection((HOST, self.thread.port), SOCKET_TIMEOUT_S) as sock:
            sock.sendall(data)
            chunks = []
            while chunk := sock.recv(65536):
                chunks.append(chunk)
        return b"".join(chunks)


class SocketTest(ServerCase):
    def test_create_then_get_over_a_socket(self) -> None:
        created = self.call(
            "w1", "POST", "/jobs", {"queue": "q", "payload": "hi\n", "max_tries": 2}
        )
        self.assertEqual(created.status, 201)
        got = self.call("w1", "GET", "/jobs/j_1")
        self.assertEqual((got.status, json.loads(got.body)), (200, json.loads(created.body)))

    def test_statuses_over_a_socket(self) -> None:
        self.assertEqual(self.call(None, "GET", "/jobs").status, 401)
        self.assertEqual(self.call("w1", "GET", "/nope").status, 404)
        self.assertEqual(self.call("w1", "POST", "/queues/q/lease").status, 204)
        self.assertEqual(self.call(None, "GET", "/health").status, 200)

    def test_405_carries_allow(self) -> None:
        connection = http.client.HTTPConnection(HOST, self.thread.port, timeout=SOCKET_TIMEOUT_S)
        try:
            connection.request("PATCH", "/jobs/j_1", headers={"authorization": "Bearer w1"})
            response = connection.getresponse()
            response.read()
        finally:
            connection.close()
        self.assertEqual((response.status, response.getheader("allow")), (405, "GET, DELETE"))

    def test_keep_alive_serves_requests_on_one_connection(self) -> None:
        connection = http.client.HTTPConnection(HOST, self.thread.port, timeout=SOCKET_TIMEOUT_S)
        try:
            statuses = []
            for _ in range(3):
                connection.request("GET", "/health")
                response = connection.getresponse()
                response.read()
                statuses.append(response.status)
                if _ == 0:
                    first_socket = connection.sock
            self.assertIs(connection.sock, first_socket)
        finally:
            connection.close()
        self.assertEqual(statuses, [200, 200, 200])

    def test_malformed_requests_are_answered_and_closed(self) -> None:
        self.assertTrue(self.raw(b"NONSENSE\r\n\r\n").startswith(b"HTTP/1.1 400 "))
        big = b"POST /jobs HTTP/1.1\r\nContent-Length: 9999999\r\n\r\n"
        self.assertTrue(self.raw(big).startswith(b"HTTP/1.1 413 "))
        chunked = b"POST /jobs HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n0\r\n\r\n"
        self.assertTrue(self.raw(chunked).startswith(b"HTTP/1.1 400 "))

    def test_two_workers_race_for_one_job_and_exactly_one_holds_it(self) -> None:
        for round_number in range(5):
            self.call(
                "p",
                "POST",
                "/jobs",
                {"queue": "race", "payload": str(round_number), "max_tries": 1},
            )
            workers = [f"w{n}" for n in range(8)]
            gate = threading.Barrier(len(workers))
            results: dict[str, int] = {}

            def lease(worker: str, gate: threading.Barrier, results: dict[str, int]) -> None:
                gate.wait(SOCKET_TIMEOUT_S)
                results[worker] = self.call(worker, "POST", "/queues/race/lease").status

            threads = [threading.Thread(target=lease, args=(w, gate, results)) for w in workers]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(SOCKET_TIMEOUT_S)
            winners = [worker for worker, status in results.items() if status == 200]
            self.assertEqual(len(winners), 1, results)
            self.assertEqual(sorted(results.values()), [200] + [204] * 7)
            job = json.loads(self.call("p", "GET", f"/jobs/j_{round_number + 1}").body)
            self.assertEqual(job["worker"], winners[0])

    def test_1200_connections_that_send_nothing_do_not_stop_a_producer(self) -> None:
        soft, hard = resource.getrlimit(resource.RLIMIT_NOFILE)
        needed = 2 * 1200 + 200
        if hard != resource.RLIM_INFINITY and hard < needed:
            self.skipTest(f"needs {needed} file descriptors, the hard limit is {hard}")
        if soft != resource.RLIM_INFINITY and soft < needed:
            resource.setrlimit(resource.RLIMIT_NOFILE, (needed, hard))
        idle = []
        try:
            for _ in range(1200):
                idle.append(socket.create_connection((HOST, self.thread.port), SOCKET_TIMEOUT_S))
            started = time.monotonic()
            created = self.call(
                "producer", "POST", "/jobs", {"queue": "q", "payload": "x", "max_tries": 1}
            )
            elapsed = time.monotonic() - started
            self.assertEqual(created.status, 201)
            self.assertLess(elapsed, 2.0)
            assert self.thread.http is not None
            self.assertGreaterEqual(self.thread.http.connections, 1200)
        finally:
            for sock in idle:
                sock.close()

    def test_a_connection_that_sends_nothing_is_closed_after_the_idle_timeout(self) -> None:
        with (
            mock.patch.object(server, "IDLE_TIMEOUT_S", 0.3),
            socket.create_connection((HOST, self.thread.port), SOCKET_TIMEOUT_S) as sock,
        ):
            started = time.monotonic()
            self.assertEqual(sock.recv(1), b"")
            self.assertLess(time.monotonic() - started, 3.0)

    def test_run_out_leases_are_recorded_while_the_listener_is_idle(self) -> None:
        self.call("p", "POST", "/jobs", {"queue": "q", "payload": "x", "max_tries": 2})
        self.call("w1", "POST", "/queues/q/lease", {"lease_ms": 100})
        deadline = time.monotonic() + 5.0  # within: chosen, five sweeps
        while replay(self.dir).jobs[1].state != "queued":
            self.assertLess(time.monotonic(), deadline, "the sweep never returned the lease")
            time.sleep(0.05)

    def test_a_second_server_on_the_same_directory_is_refused(self) -> None:
        with self.assertRaises(StoreOpenError), ServerThread(self.dir):
            pass


class QueueTimeoutTest(unittest.TestCase):
    """A queue touch that does not answer is a 503 for that request; the next is answered."""

    def test_a_touch_that_hangs_is_503_and_the_next_request_is_answered(self) -> None:
        hang = threading.Event()
        answered = Api.handle

        def slow(api: Api, request: Request) -> Response:
            if request.path == "/jobs/j_9":
                hang.wait(SOCKET_TIMEOUT_S)
            return answered(api, request)

        with (
            tempfile.TemporaryDirectory() as tmp,
            mock.patch.object(server, "QUEUE_TIMEOUT_S", 0.3),
            mock.patch.object(Api, "handle", slow),
            ServerThread(Path(tmp)) as thread,
        ):
            started = time.monotonic()
            hung = request(HOST, thread.port, Call("w1", "GET", "/jobs/j_9"), SOCKET_TIMEOUT_S)
            self.assertEqual(hung.status, 503)
            self.assertIn("did not answer", hung.body)
            self.assertLess(time.monotonic() - started, 3.0)
            hang.set()
            health = request(HOST, thread.port, Call(None, "GET", "/health"), SOCKET_TIMEOUT_S)
            self.assertEqual(health.status, 200)


JOB = {"queue": "q", "payload": "x", "max_tries": 3}
LOAD_JOBS = 20_000  # the log a load of this size leaves: 80,000 records


def send(
    port: int, token: str | None, method: str, path: str, body: object = None
) -> ClientResponse:
    text = None if body is None else json.dumps(body)
    return request(HOST, port, Call(token, method, path, text), SOCKET_TIMEOUT_S)


class RestartOverSocketTest(unittest.TestCase):
    """The board restarts itself under a listener that stays bound."""

    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)
        self._quiet = contextlib.redirect_stderr(io.StringIO())
        self._quiet.__enter__()

    def tearDown(self) -> None:
        self._quiet.__exit__(None, None, None)
        self._tmp.cleanup()

    def test_health_answers_within_a_second_of_a_failure_on_a_loaded_log(self) -> None:
        write_log(self.dir, LOAD_JOBS, "full")
        options = BoardOptions(crash_every=1)
        with ServerThread(self.dir, options=options) as thread:
            before = send(thread.port, None, "GET", "/health")
            self.assertEqual(json.loads(before.body)["restarts"], 0)
            crashed = send(thread.port, "w1", "POST", "/jobs", JOB)
            failed_at = time.monotonic()
            self.assertEqual(crashed.status, 503)
            health = send(thread.port, None, "GET", "/health")
            self.assertLess(time.monotonic() - failed_at, 1.0)
            self.assertEqual(health.status, 200)
            self.assertEqual(json.loads(health.body)["restarts"], 1)
            new_id = f"j_{LOAD_JOBS + 1}"
            self.assertEqual(send(thread.port, "w1", "GET", f"/jobs/{new_id}").status, 200)
        with ServerThread(self.dir) as thread:
            self.assertEqual(send(thread.port, "w1", "GET", f"/jobs/{new_id}").status, 200)
            health = send(thread.port, None, "GET", "/health")
            self.assertEqual(json.loads(health.body)["restarts"], 0)

    def test_a_spent_budget_stops_serve_with_70_and_the_folder_reopens(self) -> None:
        options = BoardOptions(crash_every=1, max_restarts=2)
        with ServerThread(self.dir, options=options) as thread:
            for _ in range(3):
                self.assertEqual(send(thread.port, "w1", "POST", "/jobs", JOB).status, 503)
            thread._thread.join(SOCKET_TIMEOUT_S)
            self.assertFalse(thread._thread.is_alive())
            self.assertEqual(thread.exit_code, EXIT_SPENT)
            with self.assertRaises(OSError):
                send(thread.port, None, "GET", "/health")
        store, replayed = Store.open(self.dir)
        store.close()
        self.assertEqual(list(replayed.jobs), [1, 2, 3])

    def test_requests_while_the_board_rebuilds_are_503_without_waiting(self) -> None:
        with ServerThread(self.dir) as thread:
            assert thread.http is not None
            thread.http.board.restarting = True
            refused = send(thread.port, "w1", "POST", "/jobs", JOB)
            self.assertEqual(refused.status, 503)
            self.assertIn("restarting", refused.body)
            thread.http.board.restarting = False
            self.assertEqual(send(thread.port, "w1", "POST", "/jobs", JOB).status, 201)
            self.assertEqual(list(replay(self.dir).jobs), [1])

    def test_a_queue_thread_that_dies_is_replaced_and_the_board_rebuilt(self) -> None:
        settle = QueueRunner._settle
        broken = [2]

        def dying(runner: QueueRunner, *outcome: object) -> None:
            if broken[0]:
                broken[0] -= 1
                raise RuntimeError("the queue thread breaks")
            settle(runner, *outcome)  # type: ignore[arg-type]

        with ServerThread(self.dir) as thread:
            self.assertEqual(send(thread.port, "w1", "POST", "/jobs", JOB).status, 201)
            with mock.patch.object(QueueRunner, "_settle", dying):
                lost = send(thread.port, "w1", "POST", "/jobs", JOB)
                self.assertEqual(lost.status, 503)
                health = send(thread.port, None, "GET", "/health")
            self.assertEqual((health.status, json.loads(health.body)["restarts"]), (200, 1))
            self.assertEqual(send(thread.port, "w1", "GET", "/jobs/j_2").status, 200)
            self.assertEqual(send(thread.port, "w1", "POST", "/jobs", JOB).status, 201)

    def test_the_chaos_switch_under_load(self) -> None:
        options = BoardOptions(crash_every=7, max_restarts=100_000)
        statuses: dict[int, int] = {}
        created: list[str] = []
        lock = threading.Lock()

        def client(port: int, worker: str) -> None:
            for _ in range(40):
                answers = [send(port, worker, "POST", "/jobs", JOB)]
                answers.append(send(port, worker, "POST", "/queues/q/lease", {"lease_ms": 500}))
                if answers[-1].status == 200:
                    job_id = json.loads(answers[-1].body)["id"]
                    answers.append(send(port, worker, "POST", f"/jobs/{job_id}/ack"))
                with lock:
                    for answer in answers:
                        statuses[answer.status] = statuses.get(answer.status, 0) + 1
                    if answers[0].status == 201:
                        created.append(json.loads(answers[0].body)["id"])

        with ServerThread(self.dir, options=options) as thread:
            workers = [
                threading.Thread(target=client, args=(thread.port, f"w{n}")) for n in range(16)
            ]
            for worker in workers:
                worker.start()
            for worker in workers:
                worker.join(60)
            assert thread.http is not None
            restarts = thread.http.board.restarts
            health = send(thread.port, None, "GET", "/health")
            self.assertEqual(json.loads(health.body)["restarts"], restarts)
        self.assertGreater(restarts, 10)
        self.assertLessEqual(set(statuses), {200, 201, 204, 409, 503})
        self.assertGreater(statuses[503], 10)
        on_disk = replay(self.dir).jobs
        self.assertTrue(all(int(job_id[2:]) in on_disk for job_id in created))
        with ServerThread(self.dir) as thread:
            for job_id in created:
                self.assertEqual(send(thread.port, "w1", "GET", f"/jobs/{job_id}").status, 200)


if __name__ == "__main__":
    unittest.main()
