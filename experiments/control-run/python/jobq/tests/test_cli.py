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
from support import FIXTURES

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
            ["verify"],
            ["verify", d, "extra"],
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
            body = json.dumps({"queue": "q", "payload": "x", "max_tries": 1})
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


class VerifyTest(CliCase):
    """`jobq verify`: the check `serve` runs before it binds, without serving."""

    def fill(self) -> None:
        store, replayed = Store.open(self.dir)
        queue = Queue(store, SystemClock(), replayed)
        for n in range(4):
            queue.create("emails", str(n), 2)
        queue.create("reports", "later", 2, delay_ms=60_000)
        queue.lease("emails", "w1", 60_000)
        queue.ack("j_1", "w1")
        queue.lease("emails", "w1", 60_000)
        queue.delete("j_4")
        store.close()

    def test_an_empty_folder_verifies_to_nothing(self) -> None:
        code, out, err = invoke("verify", str(self.dir))
        self.assertEqual((code, err), (EXIT_OK, ""))
        empty = "0 jobs: queued 0, scheduled 0, leased 0, done 0, dead 0; next id j_1\n"
        self.assertEqual(out, empty)

    def test_a_folder_that_opens_prints_its_counts_and_the_next_id(self) -> None:
        self.fill()
        code, out, err = invoke("verify", str(self.dir))
        self.assertEqual((code, err), (EXIT_OK, ""))
        filled = "4 jobs: queued 1, scheduled 1, leased 1, done 1, dead 0; next id j_6\n"
        self.assertEqual(out, filled)

    def test_verify_leaves_the_folder_servable(self) -> None:
        self.fill()
        self.assertEqual(invoke("verify", str(self.dir))[0], EXIT_OK)
        with ServerThread(self.dir) as server:
            got = request(HOST, server.port, Call("w1", "GET", "/jobs/j_1"))
        self.assertEqual(got.status, 200)

    def test_an_ill_formed_record_exits_1_with_one_line_naming_the_key_and_the_rule(self) -> None:
        (self.dir / LOG_NAME).write_bytes((FIXTURES / "illformed" / LOG_NAME).read_bytes())
        code, out, err = invoke("verify", str(self.dir))
        self.assertEqual((code, out), (EXIT_FAILURE, ""))
        self.assertEqual(err, f"jobq: {self.dir}: record j_2: a leased job has no run_at\n")

    def test_serve_and_compact_refuse_the_same_folder(self) -> None:
        (self.dir / LOG_NAME).write_bytes((FIXTURES / "illformed" / LOG_NAME).read_bytes())
        for argv in (["serve", str(self.dir), "--port", "0"], ["compact", str(self.dir)]):
            code, out, err = invoke(*argv)
            self.assertEqual((code, out), (EXIT_FAILURE, ""), argv)
            self.assertEqual(err.count("\n"), 1, argv)
            self.assertIn("record j_2: a leased job has no run_at", err)

    def test_the_round7_fixture_folder_verifies(self) -> None:
        (self.dir / LOG_NAME).write_bytes((FIXTURES / "round7" / LOG_NAME).read_bytes())
        code, out, err = invoke("verify", str(self.dir))
        self.assertEqual((code, err), (EXIT_OK, ""))
        self.assertEqual(
            out, "5 jobs: queued 2, scheduled 0, leased 1, done 1, dead 1; next id j_7\n"
        )

    def test_a_folder_that_cannot_be_opened_exits_1(self) -> None:
        code, _, err = invoke("verify", str(self.dir / "missing"))
        self.assertEqual(code, EXIT_FAILURE)
        self.assertIn("missing", err)


class ClientAndCheckTest(CliCase):
    def test_client_prints_status_and_body(self) -> None:
        with ServerThread(self.dir) as server:
            port = str(server.port)
            body = '{"queue": "q", "payload": "x", "max_tries": 1}'
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
            '# a comment\n\nw1 POST /jobs {"queue": "q", "payload": "a b", "max_tries": 1}\n'
            "- GET /health\n"
        )
        store_dir = self.dir / "store"
        store_dir.mkdir()
        code, out, _ = invoke("check", str(store_dir), str(script))
        self.assertEqual(code, EXIT_OK)
        lines = out.splitlines()
        self.assertEqual(
            lines[0], '> w1 POST /jobs {"queue": "q", "payload": "a b", "max_tries": 1}'
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
