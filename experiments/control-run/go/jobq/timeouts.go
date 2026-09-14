package main

import "time"

// Every timeout literal in jobq, the Go reading of `within:`. Each says
// whether its number was chosen for its call or derived from an enclosing
// deadline. Waiting for the queue's lock takes no literal: it is bounded by
// the request's context, derived from requestTimeout.
const (
	// idleTimeout is chosen. A connection that has sent no request header
	// yet, or sits between requests, is closed after it (ReadHeaderTimeout
	// and IdleTimeout). net/http has no acceptor mailbox bound: each idle
	// connection is a goroutine and a file descriptor, so this is what frees
	// them before the descriptor limit (4,096 here) is reached.
	idleTimeout = 10 * time.Second

	// readTimeout is chosen: a whole request, a 60 KiB payload included.
	readTimeout = 15 * time.Second

	// writeTimeout is chosen: from the end of the request header to the end
	// of the response; above requestTimeout so a 503 for a busy queue can
	// still be written.
	writeTimeout = 15 * time.Second

	// requestTimeout is chosen: how long one request may wait for the queue.
	requestTimeout = 5 * time.Second

	// shutdownTimeout is chosen: how long a stopping server waits for
	// requests in flight before it closes their connections.
	shutdownTimeout = 5 * time.Second

	// clientTimeout is derived: the server's writeTimeout plus 5 s of network
	// slack, so the client gives up only after the server would have.
	clientTimeout = writeTimeout + 5*time.Second
)
