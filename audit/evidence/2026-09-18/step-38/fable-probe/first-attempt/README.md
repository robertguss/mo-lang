The first run of the lead's pipelining probe, kept as run: 3 of 16 cases "passed" and none of the failures is the runtime's.
Two errors in the probe: it used one Python SSL socket from two threads (not safe), and it started tls-echo.mo with its
default idle of 200 ms, after which the example exits by design ("served 2 connections, then went quiet", exit 0) even with a
connection open. The corrected probe (one thread, non-blocking, the example's idle argument set to 50 s) is ../pipeline_probe.py.
