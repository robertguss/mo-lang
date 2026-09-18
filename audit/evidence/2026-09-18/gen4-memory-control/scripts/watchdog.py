#!/usr/bin/env python3
"""Kill any jobq or jobq-surface process whose RSS passes 4 GiB; poll every 0.25 s until killed itself."""
import os, signal, time, sys
LIMIT_KIB = 4 * 1024 * 1024
while True:
    for pid in os.listdir('/proc'):
        if not pid.isdigit(): continue
        try:
            comm = open(f'/proc/{pid}/comm').read().strip()
            if comm not in ('jobq', 'jobq-surface'): continue
            for line in open(f'/proc/{pid}/status'):
                if line.startswith('VmRSS:'):
                    kib = int(line.split()[1])
                    if kib > LIMIT_KIB:
                        os.kill(int(pid), signal.SIGKILL)
                        print(f'WATCHDOG: killed {comm} {pid} at {kib//1024} MiB', file=sys.stderr, flush=True)
        except (OSError, ValueError):
            pass
    time.sleep(0.25)
