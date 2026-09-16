import os, socket, subprocess, sys, tempfile, time, threading
mo, kvmain = sys.argv[1], sys.argv[2]
d = tempfile.mkdtemp(prefix="kvrss-"); open(d + "/kv.log", "w").close()
s = socket.socket(); s.bind(("127.0.0.1", 0)); port = s.getsockname()[1]; s.close()
p = subprocess.Popen([mo, "run", kvmain, "--", "serve", d, "--port", str(port)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def rss(): o = subprocess.run(["ps", "-o", "rss=", "-p", str(p.pid)], capture_output=True, text=True).stdout.strip(); return int(o) if o else 0
def guard():
    t0 = time.time()
    while p.poll() is None:
        if rss() > 4 << 20 or time.time() - t0 > 300: p.kill(); return
        time.sleep(0.5)
threading.Thread(target=guard, daemon=True).start()
for _ in range(500):
    try: c = socket.create_connection(("127.0.0.1", port)); break
    except OSError: time.sleep(0.02)
f = c.makefile("rwb")
for i in range(50000):
    f.write(f"SET key{i} value{i}\n".encode()); f.flush(); f.readline()
print(rss()); p.kill()
