package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"strconv"
	"time"
)

// parseAge reads a prune age in ms: a canonical whole number the prune's
// requires allows.
func parseAge(val string) (time.Duration, bool) {
	n, err := strconv.ParseInt(val, 10, 64)
	if err != nil || val != strconv.FormatInt(n, 10) || requireOlderThanMS(n) != nil {
		return 0, false
	}
	return time.Duration(n) * time.Millisecond, true
}

// cmdPrune is `jobq prune <dir> --older-than-ms n`: the prune of
// POST /archive/prune, offline, under the log's lock. It prints the two
// counts.
func cmdPrune(args []string, stdout, stderr io.Writer) int {
	if len(args) != 3 || args[1] != "--older-than-ms" {
		return usageError(stderr, "prune takes <dir> --older-than-ms <n>")
	}
	age, ok := parseAge(args[2])
	if !ok {
		return usageError(stderr, "--older-than-ms is 1000 to 3153600000000")
	}
	q, s, err := openQueue(args[0], realClock{})
	if err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	pruned, remaining, err := q.Prune(context.Background(), age.Milliseconds())
	if err = errors.Join(err, s.Close(), q.closeArchive()); err != nil {
		fmt.Fprintf(stderr, "jobq: %v\n", err)
		return 1
	}
	fmt.Fprintf(stdout, "pruned %d, remaining %d\n", pruned, remaining)
	return 0
}

// retentionLoop prunes with the configured retention on every tick, until
// the board stops or gives up. A prune that finds nothing writes nothing.
func (b *Board) retentionLoop(ticks <-chan time.Time) {
	defer b.loops.Done()
	for {
		select {
		case <-b.quit:
			return
		case <-b.done:
			return
		case <-ticks:
			n, err := b.pruneOnce()
			switch {
			case err != nil:
				b.logf("jobq: the background prune failed: %v", err)
			case n > 0:
				b.logf("jobq: the background prune removed %d archived jobs", n)
			}
			if b.cfg.onPrune != nil {
				b.cfg.onPrune(n, err)
			}
		}
	}
}

// pruneOnce is one background prune on the live queue, answered as a
// request is: a panic or a broken rule takes the board down to be rebuilt.
func (b *Board) pruneOnce() (pruned int, err error) {
	st := b.state()
	if st == nil {
		return 0, ErrRestarting
	}
	defer func() {
		if v := recover(); v != nil {
			err = fmt.Errorf("panic: %v", v)
		}
		b.failed(st)
	}()
	ctx, cancel := context.WithTimeout(context.Background(), requestTimeout)
	defer cancel()
	pruned, _, err = st.q.Prune(ctx, b.cfg.Retention.Milliseconds())
	return pruned, err
}
