package main

import (
	"bytes"
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

func runCLI(args ...string) (int, string, string) {
	var out, errOut bytes.Buffer
	code := run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestUsageErrorsExitTwo(t *testing.T) {
	dir := t.TempDir()
	for _, args := range [][]string{
		{},
		{"frobnicate"},
		{"serve"},
		{"serve", dir, "--port"},
		{"serve", dir, "--port", "http"},
		{"serve", dir, "--port", "70000"},
		{"serve", dir, "--port", "1", "--port", "2"},
		{"serve", dir, "other"},
		{"serve", dir, "--verbose"},
		{"compact"},
		{"compact", dir, dir},
		{"client", "127.0.0.1", "7900", "t", "GET"},
		{"client", "127.0.0.1", "port", "t", "GET", "/health"},
		{"client", "127.0.0.1", "7900", "t", "GET", "health"},
		{"check", dir},
	} {
		code, _, errOut := runCLI(args...)
		if code != 2 || strings.Count(errOut, "\n") != 1 || !strings.Contains(errOut, "usage:") {
			t.Errorf("%q: exit %d, stderr %q", args, code, errOut)
		}
	}
}

func TestDirThatCannotBeOpenedExitsOne(t *testing.T) {
	missing := filepath.Join(t.TempDir(), "missing")
	for _, args := range [][]string{{"serve", missing, "--port", "0"}, {"compact", missing}, {"check", missing, "script"}} {
		if code, _, errOut := runCLI(args...); code != 1 || errOut == "" {
			t.Errorf("%q: exit %d, stderr %q", args, code, errOut)
		}
	}
}

func TestPortThatCannotBeBoundExitsOne(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = ln.Close() }()
	port := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	dir := t.TempDir()
	if code, _, errOut := runCLI("serve", dir, "--port", port); code != 1 || !strings.Contains(errOut, "address already in use") {
		t.Errorf("exit %d, stderr %q", code, errOut)
	}
	st, err := openStore(dir)
	if err != nil {
		t.Fatalf("the failed serve kept the lock: %v", err)
	}
	_ = st.close()
}

func TestClientThroughARealSocket(t *testing.T) {
	s, err := startService(t.TempDir(), "127.0.0.1:0", time.Now)
	if err != nil {
		t.Fatal(err)
	}
	defer func() {
		if err := s.stop(); err != nil {
			t.Error(err)
		}
	}()
	host, port, err := net.SplitHostPort(s.addr())
	if err != nil {
		t.Fatal(err)
	}
	code, out, _ := runCLI("client", host, port, "p", "POST", "/jobs", `{"queue":"q","payload":"p","max_attempts":1}`)
	if code != 0 || !strings.HasPrefix(out, "201\n{\"id\":\"j_1\"") {
		t.Errorf("exit %d, stdout %q", code, out)
	}
	if code, out, _ := runCLI("client", host, port, "-", "GET", "/jobs"); code != 0 || !strings.HasPrefix(out, "401\n") {
		t.Errorf("exit %d, stdout %q", code, out)
	}
	if code, out, _ := runCLI("client", host, port, "p", "DELETE", "/jobs/j_1"); code != 0 || out != "204\n" {
		t.Errorf("exit %d, stdout %q", code, out)
	}
}

func TestClientWithNoServerExitsOne(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	if err := ln.Close(); err != nil {
		t.Fatal(err)
	}
	if code, _, errOut := runCLI("client", "127.0.0.1", port, "t", "GET", "/health"); code != 1 || errOut == "" {
		t.Errorf("exit %d, stderr %q", code, errOut)
	}
}

func TestCheckPlaysAScriptAcrossARestart(t *testing.T) {
	dir := t.TempDir()
	script := filepath.Join(t.TempDir(), "script")
	body := "# comment\n\np POST /jobs {\"queue\": \"q\", \"payload\": \"a b\", \"max_attempts\": 2}\n" +
		"w POST /queues/q/lease {\"lease_ms\": 100}\nrestart\nsleep 150\nw GET /jobs/j_1\n"
	if err := os.WriteFile(script, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runCLI("check", dir, script)
	if code != 0 || errOut != "" {
		t.Fatalf("exit %d, stderr %q", code, errOut)
	}
	lines := strings.Split(out, "\n")
	if len(lines) != 12 || lines[0] != `> p POST /jobs {"queue": "q", "payload": "a b", "max_attempts": 2}` || lines[1] != "201" ||
		lines[4] != "200" || lines[6] != "> restart" || lines[8] != "> w GET /jobs/j_1" || !strings.Contains(lines[10], `"state":"queued","payload":"a b","attempts":1`) {
		t.Errorf("output:\n%s", out)
	}
	if err := os.WriteFile(script, []byte("nonsense\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, errOut := runCLI("check", dir, script); code != 1 || !strings.Contains(errOut, "line 1") {
		t.Errorf("bad script: exit %d, stderr %q", code, errOut)
	}
}

func TestCompactCommand(t *testing.T) {
	dir := t.TempDir()
	q, st := openTestQueue(t, dir, newClock())
	for i := 0; i < 3; i++ {
		if _, err := q.Create(bg(), "q", "p", 1); err != nil {
			t.Fatal(err)
		}
	}
	if err := q.Delete(bg(), "j_2"); err != nil {
		t.Fatal(err)
	}
	if err := st.close(); err != nil {
		t.Fatal(err)
	}
	if code, out, errOut := runCLI("compact", dir); code != 0 || !strings.Contains(out, "to 2 jobs") {
		t.Errorf("exit %d, %q %q", code, out, errOut)
	}
}
