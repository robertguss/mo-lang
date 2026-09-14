import fcntl
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

from jobq.cli import LOCK_NAME, run
from jobq.clock import ManualClock
from jobq.fs import OsFs
from jobq.queue import Queue
from jobq.server import ServerThread
from jobq.store import LOG_NAME, Store
from tests.support import START_MS


def invoke(*argv: str) -> tuple[int, str, str]:
    out, err = io.StringIO(), io.StringIO()
    code = run(list(argv), out, err)
    return code, out.getvalue(), err.getvalue()


class UsageTest(unittest.TestCase):
    def test_usage_errors_exit_2(self) -> None:
        cases = [
            [],
            ["run"],
            ["serve"],
            ["serve", "d", "--port"],
            ["serve", "d", "--port", "70000"],
            ["serve", "d", "--port", "x"],
            ["compact"],
            ["client", "localhost", "7900", "t", "GET"],
            ["client", "localhost", "0", "t", "GET", "/health"],
            ["client", "localhost", "7900", "t", "get", "/health"],
            ["client", "localhost", "7900", "t", "GET", "health"],
            ["check", "d"],
        ]
        for argv in cases:
            code, out, err = invoke(*argv)
            with self.subTest(argv=argv):
                self.assertEqual((code, out), (2, ""))
                self.assertIn("usage: jobq", err)


class DirectoryTest(unittest.TestCase):
    def test_a_directory_that_cannot_be_opened_exits_1(self) -> None:
        for command in (["serve"], ["compact"]):
            code, _, err = invoke(*command, "/nonexistent/jobq")
            self.assertEqual(code, 1, command)
            self.assertIn("cannot open", err)

    def test_a_directory_held_by_another_jobq_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            fd = os.open(Path(tmp, LOCK_NAME), os.O_RDWR | os.O_CREAT)
            try:
                fcntl.flock(fd, fcntl.LOCK_EX)
                code, _, err = invoke("compact", tmp)
            finally:
                os.close(fd)
        self.assertEqual(code, 1)
        self.assertIn("held by another jobq", err)

    def test_a_corrupt_log_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, LOG_NAME).write_bytes(b"00000000 {}\n00000000 {}\n")
            code, _, err = invoke("compact", tmp)
        self.assertEqual(code, 1)
        self.assertIn("damaged line", err)

    def test_a_port_that_cannot_be_bound_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, socket.socket() as taken:
            taken.bind(("127.0.0.1", 0))
            taken.listen()
            code, _, err = invoke("serve", tmp, "--port", str(taken.getsockname()[1]))
        self.assertEqual(code, 1)
        self.assertIn("cannot serve", err)


class CompactTest(unittest.TestCase):
    def test_compact_rewrites_the_log_to_one_line_per_live_job(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = Store(OsFs(), Path(tmp))
            queue = Queue.open(store, ManualClock(START_MS))
            for _ in range(5):
                job = queue.create("q", "x", 1)
                queue.lease("q", "w1", 1_000)
                queue.ack(job.id, "w1")
            queue.delete(job.id)
            store.close()
            code, out, _ = invoke("compact", tmp)
            lines = Path(tmp, LOG_NAME).read_bytes().splitlines()
            reopened = Store(OsFs(), Path(tmp))
            snapshot = Queue.open(reopened, ManualClock(START_MS))
            self.assertEqual(snapshot.create("q", "y", 1).id, "j_6")
            reopened.close()
        self.assertEqual((code, len(lines)), (0, 5))
        self.assertIn("5 records", out)


class ClientTest(unittest.TestCase):
    def test_client_prints_status_and_body(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            store = Store(OsFs(), Path(tmp))
            with ServerThread(Queue.open(store, ManualClock(START_MS))) as server:
                body = '{"queue": "q", "payload": "x", "max_attempts": 1}'
                code, out, _ = invoke("client", "127.0.0.1", str(server.port), "w1", "POST", "/jobs", body)
                self.assertEqual(code, 0)
                status, _, reply = out.partition(" ")
                self.assertEqual((status, json.loads(reply)["id"]), ("201", "j_1"))
                code, out, _ = invoke("client", "127.0.0.1", str(server.port), "w1", "POST", "/queues/q/lease")
                self.assertEqual((code, out.split(" ")[0]), (0, "200"))
                code, out, _ = invoke("client", "127.0.0.1", str(server.port), "w1", "POST", "/queues/q/lease")
                self.assertEqual((code, out), (0, "204\n"))
            store.close()

    def test_no_response_exits_1(self) -> None:
        with socket.socket() as unused:
            unused.bind(("127.0.0.1", 0))
            port = unused.getsockname()[1]
        code, _, err = invoke("client", "127.0.0.1", str(port), "w1", "GET", "/health")
        self.assertEqual(code, 1)
        self.assertIn("no response", err)


class CheckTest(unittest.TestCase):
    def test_check_plays_a_script_through_the_client(self) -> None:
        script = "\n".join(
            [
                "# comment",
                "- GET /health",
                'w1 POST /jobs {"queue": "q", "payload": "a b", "max_attempts": 1}',
                "w1 POST /queues/q/lease",
                "advance 30000",
                "- GET /health",
                "",
            ]
        )
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "script.txt").write_text(script)
            store = Path(tmp, "store")
            store.mkdir()
            code, out, _ = invoke("check", str(store), str(Path(tmp, "script.txt")))
        self.assertEqual(code, 0)
        lines = out.splitlines()
        self.assertEqual(lines[0], "> - GET /health")
        self.assertEqual(
            lines[1], '< 200 {"queued":0,"leased":0,"done":0,"dead":0,"uptime_ms":0}'
        )
        self.assertTrue(lines[3].startswith('< 201 {"id":"j_1"'))
        self.assertEqual(lines[6], "> advance 30000")
        self.assertEqual(
            lines[8], '< 200 {"queued":0,"leased":0,"done":0,"dead":1,"uptime_ms":30000}'
        )

    def test_a_bad_script_line_exits_1(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            Path(tmp, "script.txt").write_text("w1 GET\n")
            code, _, err = invoke("check", tmp, str(Path(tmp, "script.txt")))
        self.assertEqual(code, 1)
        self.assertIn("line 1", err)


class ServeProcessTest(unittest.TestCase):
    def test_serve_answers_through_a_real_socket_and_stops_on_sigterm(self) -> None:
        with tempfile.TemporaryDirectory() as tmp, socket.socket() as probe:
            probe.bind(("127.0.0.1", 0))
            port = probe.getsockname()[1]
            probe.close()
            process = subprocess.Popen(
                [sys.executable, "-c", "from jobq.cli import main; main()", "serve", tmp, "--port", str(port)],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            try:
                assert process.stdout is not None
                self.assertIn(f"127.0.0.1:{port}", process.stdout.readline())
                code, out, _ = invoke("client", "127.0.0.1", str(port), "", "GET", "/health")
                self.assertEqual((code, out.split(" ")[0]), (0, "200"))
                process.terminate()
                self.assertEqual(process.wait(timeout=20), 0)
            finally:
                if process.poll() is None:
                    process.kill()
                    process.wait(timeout=5)
                if process.stdout is not None:
                    process.stdout.close()
                if process.stderr is not None:
                    process.stderr.close()


if __name__ == "__main__":
    unittest.main()
