package main

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"
)

func sp(n int) string { return strings.Repeat(" ", n) }

// smallResult is the small fixture every output section is tested on.
func smallResult(t *testing.T) Result {
	t.Helper()
	s, _ := NewSummary(2)
	for _, l := range []string{
		"2026-09-12T10:00:00Z GET /api/users 200 12",
		"2026-09-12T10:00:30Z POST /api/orders 500 1340",
		"2026-09-12T10:01:00Z GET /api/users 200 7",
		"2026-09-12T10:02:00Z GET /api/cards/4111111111111111 502 340",
	} {
		if err := s.Add(rec(t, l)); err != nil {
			t.Fatal(err)
		}
	}
	for range 1234 {
		s.AddMalformed()
	}
	res, err := s.Result()
	if err != nil {
		t.Fatal(err)
	}
	return res
}

func section(t *testing.T, text, name string) string {
	t.Helper()
	parts := strings.Split(text, "\n\n")
	if len(parts) != 3 {
		t.Fatalf("want 3 sections, got %d:\n%s", len(parts), text)
	}
	return map[string]string{"header": parts[0], "slowest": parts[1], "busiest": parts[2]}[name]
}

func TestTextHeaderSection(t *testing.T) {
	want := "requests       4\n" +
		"errors         2  (50.0%)\n" +
		"malformed  1_234\n" +
		"per minute   2.0"
	if got := section(t, RenderText(smallResult(t)), "header"); got != want {
		t.Fatalf("got\n%s\nwant\n%s", got, want)
	}
}

func TestTextSlowestSection(t *testing.T) {
	want := "slowest\n" +
		"  1_340 ms  POST /api/orders" + sp(18) + "2026-09-12T10:00:30Z\n" +
		"    340 ms  GET /api/cards/****************" + sp(3) + "2026-09-12T10:02:00Z"
	if got := section(t, RenderText(smallResult(t)), "slowest"); got != want {
		t.Fatalf("got\n%q\nwant\n%q", got, want)
	}
}

func TestTextBusiestSection(t *testing.T) {
	want := "busiest\n" +
		"  2  GET /api/users\n" +
		"  1  GET /api/cards/****************\n"
	if got := section(t, RenderText(smallResult(t)), "busiest"); got != want {
		t.Fatalf("got\n%q\nwant\n%q", got, want)
	}
}

func TestTextEmptyResult(t *testing.T) {
	s, _ := NewSummary(5)
	res, _ := s.Result()
	want := "requests       0\nerrors         0  (0.0%)\nmalformed      0\nper minute   0.0\n\nslowest\n\nbusiest\n"
	if got := RenderText(res); got != want {
		t.Fatalf("got %q", got)
	}
}

func TestJSONOutput(t *testing.T) {
	got, err := RenderJSON(smallResult(t))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"requests":4,"errors":2,"error_rate":0.500,"malformed":1234,"per_minute":2.0,` +
		`"slowest":[{"ms":1340,"method":"POST","path":"/api/orders","at":"2026-09-12T10:00:30Z"},` +
		`{"ms":340,"method":"GET","path":"/api/cards/****************","at":"2026-09-12T10:02:00Z"}],` +
		`"busiest":[{"count":2,"method":"GET","path":"/api/users"},` +
		`{"count":1,"method":"GET","path":"/api/cards/****************"}]}` + "\n"
	if got != want {
		t.Fatalf("got\n%s\nwant\n%s", got, want)
	}
	var back map[string]any
	if err := json.Unmarshal([]byte(got), &back); err != nil {
		t.Fatalf("not valid JSON: %v", err)
	}
}

func TestJSONEmptyListsAreArrays(t *testing.T) {
	s, _ := NewSummary(5)
	res, _ := s.Result()
	got, err := RenderJSON(res)
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(got, `"slowest":[]`) || !strings.Contains(got, `"busiest":[]`) {
		t.Fatalf("got %s", got)
	}
}

func TestJSONKeepsAmpersand(t *testing.T) {
	s, _ := NewSummary(1)
	_ = s.Add(rec(t, "2026-09-12T10:00:00Z GET /q?a=1&b=<2> 200 1"))
	res, _ := s.Result()
	got, _ := RenderJSON(res)
	if !strings.Contains(got, `/q?a=1&b=<2>`) {
		t.Fatalf("got %s", got)
	}
}

func TestThousands(t *testing.T) {
	cases := map[uint64]string{0: "0", 999: "999", 1000: "1_000", 1204: "1_204", 1234567: "1_234_567", 100000: "100_000"}
	for n, want := range cases {
		if got := Thousands(n); got != want {
			t.Errorf("Thousands(%d) = %q, want %q", n, got, want)
		}
	}
}

func TestDecimal(t *testing.T) {
	cases := map[float64]string{0: "0.0", 40.14: "40.1", 4.5714: "4.6", 18.75: "18.8", 1234.56: "1_234.6"}
	for x, want := range cases {
		if got := decimal(x, 1); got != want {
			t.Errorf("decimal(%v) = %q, want %q", x, got, want)
		}
	}
}

func TestCheckOutputRejectsCardNumber(t *testing.T) {
	if err := CheckOutput("path /4111111111111111"); !errors.Is(err, ErrContract) {
		t.Fatalf("want ErrContract, got %v", err)
	}
	if err := CheckOutput("1_234_567_890_123_456"); err != nil {
		t.Fatalf("separated digits are not a card: %v", err)
	}
}
