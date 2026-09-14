"""Every timeout the program sets, in one place: each is chosen for its call or derived."""

IDLE_TIMEOUT_S = 10.0
"""Chosen. How long an accepted connection may wait to send a request head before it is closed.
asyncio has no acceptor mailbox to fill; what 1,200 silent connections exhaust is file
descriptors (4,096 here), and 10 s frees them long before a steady trickle reaches that."""

REQUEST_TIMEOUT_S = 10.0
"""Chosen. One request's budget from its head to its written response. The body read, the wait
for the queue thread, and the write each take what is left of it."""

CLOSE_TIMEOUT_S = 1.0
"""Chosen. How long closing a connection may wait for the peer."""

SWEEP_INTERVAL_S = 1.0
"""Chosen. How often the listener looks at every lease when nothing else does (Idle)."""

SWEEP_TIMEOUT_S = REQUEST_TIMEOUT_S
"""Derived. A sweep waits for the queue thread as long as a request would."""

START_TIMEOUT_S = 5.0
"""Chosen. How long `jobq check` and the tests wait for a server thread to bind."""

STOP_TIMEOUT_S = REQUEST_TIMEOUT_S + CLOSE_TIMEOUT_S
"""Derived. Stopping waits for an in-flight request to finish and its connection to close."""

CLIENT_TIMEOUT_S = REQUEST_TIMEOUT_S + 5.0
"""Derived. The client outwaits the server's request deadline, so it sees a 503 rather than a
timeout of its own."""
