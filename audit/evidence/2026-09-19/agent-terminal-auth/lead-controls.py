"""Lead-selected status controls through independently counted HTTP requests."""
import json
from pathlib import Path
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROOT = Path(__file__).resolve().parents[4]
MO = ROOT / "toolchain/zig-out/bin/mo"
DRIVER = ROOT / "examples/programs/agent/tests/terminal-auth/driver.mo"
GUARD = ["python3", str(ROOT / "toolchain/bench/step36/guard.py"), "20", "--"]
cases = [
    ("403-recovery", [(403, "denied"), (200, '{"done":"control","tokens":8}')], 2, "Answer(control,8)"),
    ("429-recovery", [(429, "busy"), (200, '{"done":"control","tokens":8}')], 2, "Answer(control,8)"),
    ("401-with-valid-body", [(401, '{"done":"must not succeed","tokens":8}')], 1, "Status(401)"),
]
failures = 0
for mode in ("interpreter", "compiled"):
    for name, responses, expected_count, expected in cases:
        received = []

        class Handler(BaseHTTPRequestHandler):
            def do_POST(self):
                self.connection.settimeout(2)
                length = int(self.headers.get("Content-Length", "0"))
                if length > 8192:
                    raise ValueError("oversize fixture request")
                body = json.loads(self.rfile.read(length))
                status, text = responses[min(len(received), len(responses) - 1)]
                received.append({"path": self.path, "status": status, "body": body})
                payload = text.encode()
                self.send_response(status)
                self.send_header("Content-Length", str(len(payload)))
                self.end_headers()
                self.wfile.write(payload)

            def log_message(self, *_):
                pass

        server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        command = ([str(MO), "run", str(DRIVER), "--"] if mode == "interpreter"
                   else [str(ROOT / "zig-out/mo-build/terminal-auth/terminal-auth")])
        command += [str(server.server_port), "2", "2000", "false"]
        try:
            result = subprocess.run(GUARD + command, cwd=ROOT, capture_output=True, text=True, timeout=25)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=3)
        closed = not thread.is_alive() and server.fileno() == -1
        passed = (result.returncode == 0 and result.stdout.strip() == expected
                  and len(received) == expected_count and closed
                  and all(r["path"] == "/complete" for r in received))
        failures += not passed
        print(json.dumps({"case": name, "mode": mode, "command": GUARD + command,
                          "exit_code": result.returncode, "stdout": result.stdout,
                          "stderr": result.stderr, "requests": received,
                          "expected_count": expected_count, "expected": expected,
                          "server_closed": closed, "passed": passed}), flush=True)
raise SystemExit(bool(failures))
