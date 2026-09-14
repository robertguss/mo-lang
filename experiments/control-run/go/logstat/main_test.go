package main

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func runArgs(args ...string) (int, string, string) {
	var out, errOut bytes.Buffer
	code := run(args, &out, &errOut)
	return code, out.String(), errOut.String()
}

func TestUsageErrorsExitTwoWithOneLine(t *testing.T) {
	for _, args := range [][]string{
		{},
		{"--json"},
		{"fixture", "--top", "0"},
		{"fixture", "--top", "101"},
		{"fixture", "--top", "five"},
		{"fixture", "--top"},
		{"fixture", "--since", "yesterday"},
		{"fixture", "--frobnicate"},
		{"fixture", "other"},
		{"fixture", "--json", "--json"},
		{"fixture", "--since", "2026-09-12T10:00:00Z\nsecond line"},
	} {
		code, out, errOut := runArgs(args...)
		if code != 2 || out != "" || strings.Count(errOut, "\n") != 1 || !strings.HasSuffix(errOut, "\n") {
			t.Errorf("%q: exit %d, stdout %q, stderr %q", args, code, out, errOut)
		}
	}
}

func TestTopIsAUsageErrorNotAClamp(t *testing.T) {
	code, _, errOut := runArgs("fixture", "--top", "101")
	if code != 2 || !strings.Contains(errOut, "top >= 1 && top <= 100") {
		t.Errorf("exit %d, stderr %q", code, errOut)
	}
}

func TestNoLogFilesExitsOne(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "notes.txt"), []byte("x\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Mkdir(filepath.Join(dir, "sub.log"), 0o755); err != nil {
		t.Fatal(err)
	}
	if code, _, errOut := runArgs(dir); code != 1 || !strings.Contains(errOut, "no .log file found") {
		t.Errorf("exit %d, stderr %q", code, errOut)
	}
	if code, _, _ := runArgs(filepath.Join(dir, "missing")); code != 1 {
		t.Errorf("missing dir: exit %d", code)
	}
}

func TestFixtureMatchesExpected(t *testing.T) {
	for _, c := range []struct {
		args []string
		file string
	}{
		{[]string{"fixture"}, "expected.txt"},
		{[]string{"fixture", "--json"}, "expected.json"},
	} {
		want, err := os.ReadFile(c.file)
		if err != nil {
			t.Fatal(err)
		}
		code, out, errOut := runArgs(c.args...)
		if code != 0 || out != string(want) || errOut != "" {
			t.Errorf("%v: exit %d, stderr %q, stdout\n%s", c.args, code, errOut, out)
		}
	}
}

func TestCardNumberNeverReachesStdout(t *testing.T) {
	for _, args := range [][]string{{"fixture"}, {"fixture", "--json"}, {"fixture", "--top", "100"}} {
		_, out, _ := runArgs(args...)
		if HasCardNumber(out) || strings.Contains(out, "4111111111111111") || strings.Contains(out, "5500000000000004") {
			t.Errorf("%v leaked a card number:\n%s", args, out)
		}
	}
}

func TestNeverReadsOutsideDir(t *testing.T) {
	outside := t.TempDir()
	secret := filepath.Join(outside, "secret.log")
	if err := os.WriteFile(secret, []byte("2026-09-12T10:00:00Z GET /secret 200 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.log"), []byte("2026-09-12T10:00:00Z GET /inside 200 1\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(secret, filepath.Join(dir, "b.log")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink(outside, filepath.Join(dir, "c.log")); err != nil {
		t.Fatal(err)
	}
	code, out, errOut := runArgs(dir)
	if code != 0 || strings.Contains(out, "/secret") || !strings.Contains(out, "/inside") {
		t.Errorf("exit %d, stderr %q, stdout\n%s", code, errOut, out)
	}
}

func TestLongAndUnterminatedLines(t *testing.T) {
	dir := t.TempDir()
	body := "2026-09-12T10:00:00Z GET /" + strings.Repeat("x", 3*maxLine) + " 200 1\n" +
		"2026-09-12T10:00:00Z GET /" + strings.Repeat("y", maxLine) + "\n" +
		"2026-09-12T10:00:30Z GET /ok 200 1\n" +
		"2026-09-12T10:01:00Z GET /last 200 1"
	if err := os.WriteFile(filepath.Join(dir, "a.log"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	code, out, _ := runArgs(dir, "--json")
	if code != 0 || !strings.HasPrefix(out, `{"requests":2,"errors":0,"error_rate":0,"malformed":2,"per_minute":4,`) {
		t.Errorf("exit %d, stdout %s", code, out)
	}
}

func TestFlagsInAnyOrder(t *testing.T) {
	code, out, _ := runArgs("--json", "--since", "2026-09-12T10:01:00Z", "--top", "1", "fixture")
	if code != 0 || !strings.HasPrefix(out, `{"requests":5,`) || strings.Count(out, `"ms"`) != 1 {
		t.Errorf("exit %d, stdout %s", code, out)
	}
}
