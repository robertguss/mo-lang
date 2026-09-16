package main

import (
	"errors"
	"io"
	"net"
	"net/http"
	"os"
	"testing"
	"time"
)

func startTestService(t *testing.T, idle time.Duration) *service {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	svc, err := startService(t.TempDir(), realClock{}, ln, idle)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() {
		if err := svc.stop(); err != nil {
			t.Error(err)
		}
	})
	return svc
}

// 1,200 connections that send nothing do not stop a producer's request.
func TestIdleConnectionsDoNotBlockAProducer(t *testing.T) {
	svc := startTestService(t, idleTimeout)
	conns := make([]net.Conn, 0, 1200)
	defer func() {
		for _, c := range conns {
			c.Close()
		}
	}()
	for range 1200 {
		c, err := net.DialTimeout("tcp", svc.addr, 5*time.Second)
		if err != nil {
			t.Fatalf("dial %d: %v", len(conns), err)
		}
		conns = append(conns, c)
	}
	client := &http.Client{Timeout: 5 * time.Second}
	start := time.Now()
	status, body, err := doRequest(client, svc.addr, "producer", "POST", "/jobs", `{"queue":"emails","payload":"hi","max_tries":3}`)
	if err != nil || status != 201 {
		t.Fatalf("producer request = %d %s, %v", status, body, err)
	}
	t.Logf("answered in %v with 1,200 idle connections open", time.Since(start))
}

// The idle timeout is what frees a connection that sends nothing.
func TestIdleConnectionIsClosed(t *testing.T) {
	svc := startTestService(t, 200*time.Millisecond)
	c, err := net.DialTimeout("tcp", svc.addr, 5*time.Second)
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	start := time.Now()
	if err := c.SetReadDeadline(start.Add(5 * time.Second)); err != nil {
		t.Fatal(err)
	}
	_, err = c.Read(make([]byte, 1))
	if !errors.Is(err, io.EOF) || errors.Is(err, os.ErrDeadlineExceeded) {
		t.Fatalf("read = %v, want the server to close the connection", err)
	}
	if elapsed := time.Since(start); elapsed < 150*time.Millisecond {
		t.Errorf("closed after %v, before the idle timeout", elapsed)
	}
}
