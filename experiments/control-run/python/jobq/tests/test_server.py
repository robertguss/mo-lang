import json
import socket
import threading
import time
import unittest

from jobq.client import request
from jobq.deadlines import IDLE_TIMEOUT_S
from jobq.server import HeadError, ServerThread, parse_head
from tests.support import Rig

IDLE_CONNECTIONS = 1_200


class HeadTest(unittest.TestCase):
    def test_a_request_head(self) -> None:
        head = parse_head(
            b"POST /jobs HTTP/1.1\r\nHost: x\r\nAuthorization: Bearer w1\r\n"
            b"Content-Length: 12\r\n\r\n"
        )
        self.assertEqual((head.method, head.target, head.content_length), ("POST", "/jobs", 12))
        self.assertEqual(head.headers["authorization"], "Bearer w1")
        self.assertTrue(head.keep_alive)

    def test_keep_alive_follows_the_version_and_connection_header(self) -> None:
        self.assertFalse(parse_head(b"GET / HTTP/1.1\r\nConnection: close\r\n\r\n").keep_alive)
        self.assertFalse(parse_head(b"GET / HTTP/1.0\r\n\r\n").keep_alive)
        self.assertTrue(parse_head(b"GET / HTTP/1.0\r\nConnection: keep-alive\r\n\r\n").keep_alive)

    def test_rejects(self) -> None:
        cases = {
            b"GET /\r\n\r\n": 400,
            b"GET / HTTP/2\r\n\r\n": 505,
            b"get / HTTP/1.1\r\n\r\n": 400,
            b"GET jobs HTTP/1.1\r\n\r\n": 400,
            b"GET / HTTP/1.1\r\nbroken\r\n\r\n": 400,
            b"POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n": 501,
            b"POST / HTTP/1.1\r\nContent-Length: -1\r\n\r\n": 400,
            b"POST / HTTP/1.1\r\nContent-Length: 2000000\r\n\r\n": 413,
            b"POST / HTTP/1.1\r\nContent-Length: 1\r\nContent-Length: 2\r\n\r\n": 400,
        }
        for data, status in cases.items():
            with self.subTest(data=data), self.assertRaises(HeadError) as caught:
                parse_head(data)
            self.assertEqual(caught.exception.status, status)


class SocketTest(unittest.TestCase):
    def setUp(self) -> None:
        self.rig = Rig()
        self.server = ServerThread(self.rig.queue)
        self.port = self.server.start()
        self.addCleanup(self.server.stop)

    def call(self, token: str | None, method: str, path: str, body: str | None = None) -> int:
        return request("127.0.0.1", self.port, token, method, path, body)[0]

    def test_the_client_round_trips_through_a_real_socket(self) -> None:
        body = '{"queue": "emails", "payload": "hi", "max_attempts": 3}'
        status, reply = request("127.0.0.1", self.port, "w1", "POST", "/jobs", body)
        self.assertEqual((status, json.loads(reply)["id"]), (201, "j_1"))
        status, reply = request("127.0.0.1", self.port, None, "GET", "/health")
        self.assertEqual((status, json.loads(reply)["queued"]), (200, 1))
        self.assertEqual(self.call("w1", "POST", "/queues/emails/lease"), 200)
        self.assertEqual(self.call("w1", "POST", "/queues/emails/lease"), 204)

    def test_one_connection_serves_several_requests(self) -> None:
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            sock.sendall(b"GET /health HTTP/1.1\r\n\r\nGET /nowhere HTTP/1.1\r\n\r\n")
            received = b""
            while received.count(b"HTTP/1.1 ") < 2 or not received.endswith(b"}"):
                chunk = sock.recv(4096)
                if not chunk:
                    break
                received += chunk
        self.assertIn(b"HTTP/1.1 200 OK", received)
        self.assertIn(b"HTTP/1.1 404 Not Found", received)

    def test_a_malformed_request_is_400_and_the_connection_closes(self) -> None:
        with socket.create_connection(("127.0.0.1", self.port), timeout=5) as sock:
            sock.sendall(b"NONSENSE\r\n\r\n")
            received = b""
            while chunk := sock.recv(4096):
                received += chunk
        self.assertTrue(received.startswith(b"HTTP/1.1 400 Bad Request"), received)

    def test_two_workers_race_for_one_job_and_exactly_one_holds_it(self) -> None:
        body = '{"queue": "race", "payload": "x", "max_attempts": 3}'
        for round_number in range(25):
            self.assertEqual(self.call("producer", "POST", "/jobs", body), 201)
            barrier = threading.Barrier(2)
            statuses: dict[str, int] = {}

            def race(worker: str, barrier: threading.Barrier = barrier) -> None:
                barrier.wait(timeout=5)
                statuses[worker] = self.call(worker, "POST", "/queues/race/lease")

            threads = [threading.Thread(target=race, args=(w,)) for w in ("w1", "w2")]
            for thread in threads:
                thread.start()
            for thread in threads:
                thread.join(timeout=10)
            with self.subTest(round=round_number):
                self.assertEqual(sorted(statuses.values()), [200, 204])
                winner = next(worker for worker, status in statuses.items() if status == 200)
                job = self.rig.queue.snapshot()[f"j_{round_number + 1}"]
                self.assertEqual((job.state, job.worker, job.attempts), ("leased", winner, 1))

    def test_1200_idle_connections_do_not_stop_a_producer(self) -> None:
        idle: list[socket.socket] = []
        try:
            for _ in range(IDLE_CONNECTIONS):
                idle.append(socket.create_connection(("127.0.0.1", self.port), timeout=5))
            started = time.monotonic()
            body = '{"queue": "emails", "payload": "still answered", "max_attempts": 1}'
            self.assertEqual(self.call("producer", "POST", "/jobs", body), 201)
            elapsed = time.monotonic() - started
            self.assertLess(elapsed, 2.0)
            self.assertLess(elapsed, IDLE_TIMEOUT_S)
            idle[0].setblocking(False)
            with self.assertRaises(BlockingIOError):
                idle[0].recv(1)
        finally:
            for sock in idle:
                sock.close()


if __name__ == "__main__":
    unittest.main()
