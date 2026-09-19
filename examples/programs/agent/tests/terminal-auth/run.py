#!/usr/bin/env python3
"""Independent loopback HTTP statuses and received-request counts; no provider access."""
import argparse
import json
import os
import pathlib
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = pathlib.Path(__file__).resolve().parents[5]
HERE = pathlib.Path(__file__).resolve().parent
GUARD = ["python3", str(ROOT / "toolchain/bench/step36/guard.py")]
MO = os.environ.get("MO_BIN", str(ROOT / "toolchain/zig-out/bin/mo"))
VALID = '{"done":"7","tokens":5}'
CASES = [
    ("immediate-401", [(401, "denied"), (200, VALID)], 2, 2000, False, 1, "Status(401)"),
    ("503-401", [(503, "busy"), (401, "denied"), (200, VALID)], 2, 2000, False, 2, "Status(401)"),
    ("malformed-401", [(200, "garbage"), (401, "denied"), (200, VALID)], 2, 2000, False, 2, "Status(401)"),
    ("503-success", [(503, "busy"), (200, VALID)], 2, 2000, False, 2, "Answer(7,5)"),
    ("attempt-limit", [(503, "busy")] * 3 + [(200, VALID)], 2, 2000, False, 3, "Status(503)"),
    ("success", [(200, VALID)], 2, 2000, False, 1, "Answer(7,5)"),
    ("exhausted", [(200, VALID)], 2, 2000, True, 0, "Late"),
    ("delayed", [(200, VALID)], 2, 200, False, 1, "Late"),
    ("zero-retries", [(401, "denied")], 0, 2000, False, 1, "Status(401)"),
]

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["interpreter", "compiled"])
    parser.add_argument("--only", choices=[case[0] for case in CASES])
    args = parser.parse_args()
    failures = 0
    for name, replies, retries, budget, exhausted, count, expected in CASES:
        if args.only and name != args.only:
            continue
        received = []
        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                self.connection.settimeout(3)
                body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
                index = len(received)
                status, text = replies[min(index, len(replies) - 1)]
                received.append({"path": self.path, "body": body.decode(), "status": status})
                if name == "delayed":
                    time.sleep(0.6)
                payload = text.encode()
                try:
                    self.send_response(status)
                    self.send_header("Content-Length", str(len(payload)))
                    self.end_headers()
                    self.wfile.write(payload)
                except (BrokenPipeError, ConnectionResetError):
                    pass
            def log_message(self, *_):
                pass
        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        server.daemon_threads = False
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        command = ([MO, "run", str(HERE / "driver.mo"), "--"] if args.mode == "interpreter"
                   else [str(ROOT / "zig-out/mo-build/terminal-auth/terminal-auth")])
        command += [str(server.server_port), str(retries), str(budget), str(exhausted).lower()]
        try:
            result = subprocess.run(GUARD + ["20", "--"] + command, cwd=ROOT, capture_output=True, text=True, timeout=25)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()
        cleaned_up = not thread.is_alive() and server.fileno() == -1
        passed = cleaned_up and result.returncode == 0 and result.stdout.strip() == expected and len(received) == count
        failures += not passed
        print(json.dumps(dict(case=name, mode=args.mode, command=GUARD + ["20", "--"] + command,
            exit_code=result.returncode, stdout=result.stdout, stderr=result.stderr,
            requests=received, server_closed=cleaned_up, expected_count=count, expected_outcome=expected, passed=passed)), flush=True)
    return int(failures != 0)

if __name__ == "__main__":
    raise SystemExit(main())
