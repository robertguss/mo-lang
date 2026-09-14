package main

import (
	"strings"
	"testing"
)

func TestGroupThousands(t *testing.T) {
	cases := map[string]string{
		"0": "0", "12": "12", "123": "123", "1234": "1_234",
		"1234567": "1_234_567", "1204.5": "1_204.5", "40.1": "40.1",
	}
	for in, want := range cases {
		if got := groupThousands(in); got != want {
			t.Errorf("groupThousands(%q) = %q, want %q", in, got, want)
		}
	}
}

func text(t *testing.T, r Report) string {
	t.Helper()
	var b strings.Builder
	if err := WriteText(&b, r); err != nil {
		t.Fatal(err)
	}
	return b.String()
}

func TestWriteTextHeader(t *testing.T) {
	got := text(t, Report{Requests: 1204, Errors: 37, ErrorRate: 0.031, Malformed: 2, PerMinute: 40.1})
	want := "requests   1_204\n" +
		"errors        37  (3.1%)\n" +
		"malformed      2\n" +
		"per minute  40.1\n"
	if !strings.HasPrefix(got, want) {
		t.Errorf("header:\n%s\nwant:\n%s", got, want)
	}
}

func TestWriteTextSlowest(t *testing.T) {
	got := text(t, Report{Slowest: []SlowRow{
		{MS: 1340, Method: "POST", Path: "/api/orders", At: "2026-09-12T10:00:02Z"},
		{MS: 12, Method: "GET", Path: "/a", At: "2026-09-12T10:00:01Z"},
	}})
	want := "\nslowest\n" +
		"  1_340 ms  POST /api/orders   2026-09-12T10:00:02Z\n" +
		"     12 ms  GET  /a            2026-09-12T10:00:01Z\n" +
		"\nbusiest\n"
	if !strings.Contains(got, want) {
		t.Errorf("slowest section:\n%s\nwant:\n%s", got, want)
	}
}

func TestWriteTextBusiest(t *testing.T) {
	got := text(t, Report{Busiest: []BusyRow{{1611, "GET", "/api/users"}, {3, "DELETE", "/a"}}})
	want := "\nbusiest\n" +
		"  1_611  GET    /api/users\n" +
		"      3  DELETE /a\n"
	if !strings.HasSuffix(got, want) {
		t.Errorf("busiest section:\n%s\nwant:\n%s", got, want)
	}
}

func TestWriteTextEmpty(t *testing.T) {
	want := "requests     0\nerrors       0  (0.0%)\nmalformed    0\nper minute 0.0\n\nslowest\n\nbusiest\n"
	if got := text(t, Report{}); got != want {
		t.Errorf("empty report:\n%q\nwant:\n%q", got, want)
	}
}

func TestWriteJSON(t *testing.T) {
	var b strings.Builder
	r := Report{
		Requests: 1204, Errors: 37, ErrorRate: 0.031, Malformed: 2, PerMinute: 40.1,
		Slowest: []SlowRow{{MS: 340, Method: "POST", Path: "/api/orders?a=<b>&c", At: "2026-09-12T10:00:02Z"}},
		Busiest: []BusyRow{{611, "GET", "/api/users"}},
	}
	if err := WriteJSON(&b, r); err != nil {
		t.Fatal(err)
	}
	want := `{"requests":1204,"errors":37,"error_rate":0.031,"malformed":2,"per_minute":40.1,` +
		`"slowest":[{"ms":340,"method":"POST","path":"/api/orders?a=<b>&c","at":"2026-09-12T10:00:02Z"}],` +
		`"busiest":[{"count":611,"method":"GET","path":"/api/users"}]}` + "\n"
	if b.String() != want {
		t.Errorf("JSON:\n%s\nwant:\n%s", b.String(), want)
	}
}

func TestWriteJSONEmptyListsAreArrays(t *testing.T) {
	s, err := NewSummary(5)
	if err != nil {
		t.Fatal(err)
	}
	r, err := s.Report()
	if err != nil {
		t.Fatal(err)
	}
	var b strings.Builder
	if err := WriteJSON(&b, r); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(b.String(), `"slowest":[],"busiest":[]`) {
		t.Errorf("JSON = %s", b.String())
	}
}
