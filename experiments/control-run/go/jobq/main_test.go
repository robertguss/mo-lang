package main

import (
	"net"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
)

func runCmd(args ...string) (int, string, string) {
	var out, errOut strings.Builder
	code := run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestUsageErrorsExit2(t *testing.T) {
	dir := t.TempDir()
	for _, args := range [][]string{
		{}, {"bogus"}, {"serve"}, {"serve", dir, "--port"}, {"serve", dir, "--port", "0"},
		{"serve", dir, "--port", "70000"}, {"serve", dir, "--port", "08"}, {"serve", dir, "extra"},
		{"compact"}, {"compact", dir, dir},
		{"verify"}, {"verify", dir, dir},
		{"client", "localhost", "7900", "t", "GET"},
		{"client", "localhost", "x", "t", "GET", "/health"},
		{"client", "localhost", "7900", "t", "get", "/health"},
		{"client", "localhost", "7900", "t", "GET", "health"},
		{"check", dir},
	} {
		code, out, errOut := runCmd(args...)
		if code != 2 || out != "" || strings.Count(errOut, "\n") != 1 {
			t.Errorf("jobq %q = %d, stdout %q, stderr %q; want 2 and one line", args, code, out, errOut)
		}
	}
}

func TestServeExit1(t *testing.T) {
	dir := t.TempDir()
	file := filepath.Join(dir, "file")
	if err := os.WriteFile(file, nil, 0o644); err != nil {
		t.Fatal(err)
	}
	for _, d := range []string{filepath.Join(dir, "missing"), file} {
		if code, _, _ := runCmd("serve", d); code != 1 {
			t.Errorf("serve %s = %d, want 1", d, code)
		}
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	port := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	store := t.TempDir()
	if code, _, errOut := runCmd("serve", store, "--port", port); code != 1 {
		t.Errorf("serve on a bound port = %d, %s", code, errOut)
	}
	if code, _, errOut := runCmd("compact", store); code != 0 {
		t.Errorf("the failed serve kept the store locked: compact = %d, %s", code, errOut)
	}
	if code, _, _ := runCmd("compact", filepath.Join(dir, "missing")); code != 1 {
		t.Errorf("compact of a missing dir = %d, want 1", code)
	}
}

func TestClientCommand(t *testing.T) {
	svc := startTestService(t, idleTimeout)
	host, port, _ := net.SplitHostPort(svc.addr)
	code, out, errOut := runCmd("client", host, port, "w1", "POST", "/jobs", `{"queue":"a","payload":"p","max_tries":1}`)
	if code != 0 || !strings.HasPrefix(out, "201\n{\"id\":\"j_1\"") || !strings.HasSuffix(out, "}\n") {
		t.Errorf("client = %d, %q, %q", code, out, errOut)
	}
	if code, out, _ := runCmd("client", host, port, "-", "GET", "/jobs"); code != 0 || !strings.HasPrefix(out, "401\n") {
		t.Errorf("client with no token = %d, %q", code, out)
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	closed := strconv.Itoa(ln.Addr().(*net.TCPAddr).Port)
	ln.Close()
	if code, _, _ := runCmd("client", "127.0.0.1", closed, "w1", "GET", "/health"); code != 1 {
		t.Errorf("client to a closed port = %d, want 1", code)
	}
}

func TestCheckCommandMatchesExpected(t *testing.T) {
	want, err := os.ReadFile("testdata/check.expected")
	if err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runCmd("check", t.TempDir(), "testdata/check.script")
	if code != 0 || out != string(want) {
		t.Errorf("check = %d, stderr %q\n%s\nwant\n%s", code, errOut, out, want)
	}
	script := filepath.Join(t.TempDir(), "bad.script")
	if err := os.WriteFile(script, []byte("w1 get /jobs\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, _ := runCmd("check", t.TempDir(), script); code != 2 {
		t.Errorf("check with a bad script line = %d, want 2", code)
	}
	if code, _, _ := runCmd("check", t.TempDir(), filepath.Join(t.TempDir(), "missing")); code != 1 {
		t.Errorf("check with a missing script = %d, want 1", code)
	}
}
