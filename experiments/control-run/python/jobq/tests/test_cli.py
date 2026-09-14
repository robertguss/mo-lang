import io
import json
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import unittest
from pathlib import Path

from jobq.cli import EXIT_FAILURE, EXIT_OK, EXIT_USAGE, run
from jobq.client import Call, request
from jobq.clock import SystemClock
from jobq.queue import Queue
from jobq.server import HOST, ServerThread
from jobq.store import LOG_NAME, Store

PROCESS_TIMEOUT_S = 20.0  # within: chosen, a Python start plus a request


def invoke(*argv: str) -> tuple[int, str, str]:
    stdout, stderr = io.StringIO(), io.StringIO()
    code = run(list(argv), stdout, stderr)
    return code, stdout.getvalue(), stderr.getvalue()


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind((HOST, 0))
        port: int = sock.getsockname()[1]
        return port


class CliCase(unittest.TestCase):
    def setUp(self) -> None:
        self._tmp = tempfile.TemporaryDirectory()
        self.dir = Path(self._tmp.name)

    def tearDown(self) -> None:
        self._tmp.cleanup()


class UsageTest(CliCase):
    def test_usage_errors_exit_2_with_one_line(self) -> None:
        d = str(self.dir)
        for argv in (
            [],
            ["bogus"],
            ["serve"],
            ["serve", d, "--port"],
            ["serve", d, "--port", "x"],
            ["serve", d, "--port", "65536"],
            ["serve", d, "--verbose", "1"],
            ["compact"],
            ["client", HOST, "0", "w1", "GET", "/health"],
            ["client", HOST, "7900", "w1", "get", "/health"],
            ["client", HOST, "7900", "w1", "GET", "health"],
            ["client", HOST, "7900", "w1"],
            ["check", d],
        ):
            code, out, err = invoke(*argv)
            self.assertEqual((code, out), (EXIT_USAGE, ""), argv)
            self.assertEqual(err.count("\n"), 1, argv)


class ServeTest(CliCase):
    def test_a_directory_that_cannot_be_opened_exits_1(self) -> None:
        code, _, err = invoke("serve", str(self.dir / "missing"), "--port", "0")
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn("missing", err)

    def test_a_port_that_cannot_be_bound_exits_1(self) -> None:
        with socket.socket() as taken:
            taken.bind((HOST, 0))
            taken.listen()
            code, _, err = invoke("serve", str(self.dir), "--port", str(taken.getsockname()[1]))
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn("cannot listen", err)

    def test_serve_as_a_process_answers_and_stops_on_sigterm(self) -> None:
        process = subprocess.Popen(
            [sys.executable, "-m", "jobq", "serve", str(self.dir), "--port", "0"],
            stderr=subprocess.PIPE,
            text=True,
        )
        killer = threading.Timer(PROCESS_TIMEOUT_S, process.kill)
        killer.start()
        try:
            assert process.stderr is not None
            line = process.stderr.readline()
            port = int(line.rsplit(":", 1)[1])
            body = json.dumps({"queue": "q", "payload": "x", "max_attempts": 1})
            created = request(HOST, port, Call("w1", "POST", "/jobs", body))
            self.assertEqual(created.status, 201)
            process.send_signal(signal.SIGTERM)
            self.assertEqual(process.wait(PROCESS_TIMEOUT_S), EXIT_OK)
        finally:
            killer.cancel()
            process.kill()
            process.wait(PROCESS_TIMEOUT_S)
            if process.stderr is not None:
                process.stderr.close()
        self.assertIn(b'"payload":"x"', (self.dir / LOG_NAME).read_bytes())


class CompactTest(CliCase):
    def test_compact_rewrites_the_log(self) -> None:
        store, replayed = Store.open(self.dir)
        queue = Queue(store, SystemClock(), replayed)
        for n in range(5):
            queue.create("q", str(n), 1)
        queue.delete("j_5")
        store.close()
        code, out, _ = invoke("compact", str(self.dir))
        self.assertEqual(code, EXIT_OK)
        self.assertIn("6 records to 5", out)
        self.assertEqual(len((self.dir / LOG_NAME).read_bytes().splitlines()), 5)

    def test_compact_of_a_missing_directory_exits_1(self) -> None:
        self.assertEqual(invoke("compact", str(self.dir / "missing"))[0], EXIT_FAILURE)


class ClientAndCheckTest(CliCase):
    def test_client_prints_status_and_body(self) -> None:
        with ServerThread(self.dir) as server:
            port = str(server.port)
            body = '{"queue": "q", "payload": "x", "max_attempts": 1}'
            code, out, _ = invoke("client", HOST, port, "w1", "POST", "/jobs", body)
            self.assertEqual(code, EXIT_OK)
            status, text = out.splitlines()
            self.assertEqual((status, json.loads(text)["id"]), ("201", "j_1"))
            self.assertEqual(
                invoke("client", HOST, port, "w1", "POST", "/queues/z/lease")[1], "204\n"
            )
            self.assertTrue(
                invoke("client", HOST, port, "-", "GET", "/jobs")[1].startswith("401\n")
            )

    def test_client_that_cannot_connect_exits_1(self) -> None:
        code, _, err = invoke("client", HOST, str(free_port()), "w1", "GET", "/health")
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn("cannot reach", err)

    def test_check_plays_a_script(self) -> None:
        script = self.dir / "script.txt"
        script.write_text(
            '# a comment\n\nw1 POST /jobs {"queue": "q", "payload": "a b", "max_attempts": 1}\n'
            "- GET /health\n"
        )
        store_dir = self.dir / "store"
        store_dir.mkdir()
        code, out, _ = invoke("check", str(store_dir), str(script))
        self.assertEqual(code, EXIT_OK)
        lines = out.splitlines()
        self.assertEqual(
            lines[0], '> w1 POST /jobs {"queue": "q", "payload": "a b", "max_attempts": 1}'
        )
        self.assertEqual((lines[1], lines[3], lines[4]), ("201", "> - GET /health", "200"))

    def test_check_with_a_bad_script_line_exits_2_and_a_missing_script_1(self) -> None:
        script = self.dir / "script.txt"
        script.write_text("w1 GET\n")
        self.assertEqual(invoke("check", str(self.dir), str(script))[0], EXIT_USAGE)
        self.assertEqual(invoke("check", str(self.dir), str(self.dir / "none"))[0], EXIT_FAILURE)
        self.assertEqual(invoke("check", str(self.dir / "none"), str(script))[0], EXIT_USAGE)


if __name__ == "__main__":
    unittest.main()
