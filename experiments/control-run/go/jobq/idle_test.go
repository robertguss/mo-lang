package main

import (
	"context"
	"errors"
	"net"
	"net/http"
	"os"
	"testing"
	"time"
)

// 1,200 connections that send nothing do not stop a producer's request.
func TestIdleConnectionsDoNotBlockAProducer(t *testing.T) {
	s, err := startService(t.TempDir(), "127.0.0.1:0", time.Now)
	if err != nil {
		t.Fatal(err)
	}
	var conns []net.Conn
	defer func() {
		for _, c := range conns {
			_ = c.Close()
		}
		if err := s.stop(); err != nil {
			t.Error(err)
		}
	}()
	for i := 0; i < 1200; i++ {
		c, err := net.DialTimeout("tcp", s.addr(), 2*time.Second)
		if err != nil {
			t.Fatalf("dial %d: %v", i, err)
		}
		conns = append(conns, c)
	}
	ctx, cancel := context.WithTimeout(bg(), 3*time.Second)
	defer cancel()
	started := time.Now()
	status, body, err := request(ctx, &http.Client{Timeout: 3 * time.Second}, "http://"+s.addr(), "producer", "POST", "/jobs", `{"queue":"q","payload":"p","max_attempts":1}`)
	if err != nil || status != 201 {
		t.Fatalf("producer: %d %s %v", status, body, err)
	}
	t.Logf("answered in %v with 1,200 idle connections open", time.Since(started))
}

// The idle: choice: a connection that sends nothing is closed after
// readHeaderTimeout.
func TestIdleConnectionIsClosed(t *testing.T) {
	if testing.Short() {
		t.Skip("waits readHeaderTimeout")
	}
	s, err := startService(t.TempDir(), "127.0.0.1:0", time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := s.stop(); err != nil {
			t.Error(err)
		}
	}()
	c, err := net.DialTimeout("tcp", s.addr(), 2*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = c.Close() }()
	started := time.Now()
	if err := c.SetReadDeadline(started.Add(readHeaderTimeout + 3*time.Second)); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 512)
	for {
		if _, err = c.Read(buf); err != nil {
			break
		}
	}
	if errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("still open after %v", time.Since(started))
	}
	if waited := time.Since(started); waited < readHeaderTimeout-time.Second {
		t.Errorf("closed after only %v", waited)
	}
}
