package main

import (
	"encoding/json"
	"strings"
	"testing"
)

func small(t *testing.T) Summary {
	return summarize(t, 2,
		"2026-09-12T10:00:00Z GET /api/users 200 12",
		"2026-09-12T10:00:30Z POST /api/orders 500 1340",
		"2026-09-12T10:01:00Z GET /api/users 200 9",
		"nope",
	)
}

func TestGroupInt(t *testing.T) {
	cases := map[int]string{0: "0", 7: "7", 999: "999", 1000: "1_000", 1204: "1_204", 1234567: "1_234_567", -1204: "-1_204"}
	for n, want := range cases {
		if got := GroupInt(n); got != want {
			t.Errorf("GroupInt(%d) = %q, want %q", n, got, want)
		}
	}
	if got := GroupFloat1(12345.67); got != "12_345.7" {
		t.Errorf("GroupFloat1 = %q", got)
	}
}

func TestTextHeaderSection(t *testing.T) {
	want := "requests       3\nerrors         1  (33.3%)\nmalformed      1\nper minute   3.0\n"
	if got := FormatText(small(t)); !strings.HasPrefix(got, want) {
		t.Errorf("got\n%s\nwant prefix\n%s", got, want)
	}
}

func TestTextSlowestSection(t *testing.T) {
	want := "\nslowest\n" +
		"  1_340 ms  POST /api/orders   2026-09-12T10:00:30Z\n" +
		"     12 ms  GET /api/users     2026-09-12T10:00:00Z\n"
	if got := FormatText(small(t)); !strings.Contains(got, want) {
		t.Errorf("got\n%s", got)
	}
}

func TestTextBusiestSection(t *testing.T) {
	want := "\nbusiest\n  2  GET /api/users\n  1  POST /api/orders\n"
	if got := FormatText(small(t)); !strings.HasSuffix(got, want) {
		t.Errorf("got\n%s", got)
	}
}

func TestTextEmptySections(t *testing.T) {
	want := "requests       0\nerrors         0  (0.0%)\nmalformed      0\nper minute   0.0\n\nslowest\n\nbusiest\n"
	if got := FormatText(summarize(t, 5)); got != want {
		t.Errorf("got\n%q", got)
	}
}

func TestJSONShape(t *testing.T) {
	out, err := FormatJSON(small(t))
	if err != nil {
		t.Fatal(err)
	}
	want := `{"requests":3,"errors":1,"error_rate":0.333,"malformed":1,"per_minute":3,` +
		`"slowest":[{"ms":1340,"method":"POST","path":"/api/orders","at":"2026-09-12T10:00:30Z"},{"ms":12,"method":"GET","path":"/api/users","at":"2026-09-12T10:00:00Z"}],` +
		`"busiest":[{"count":2,"method":"GET","path":"/api/users"},{"count":1,"method":"POST","path":"/api/orders"}]}` + "\n"
	if out != want {
		t.Errorf("got\n%s\nwant\n%s", out, want)
	}
	var back map[string]any
	if err := json.Unmarshal([]byte(out), &back); err != nil {
		t.Fatal(err)
	}
}

func TestJSONEmptyListsAreArrays(t *testing.T) {
	out, err := FormatJSON(summarize(t, 5))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, `"slowest":[]`) || !strings.Contains(out, `"busiest":[]`) {
		t.Errorf("got %s", out)
	}
}

func TestJSONDoesNotEscapeHTML(t *testing.T) {
	out, err := FormatJSON(summarize(t, 5, "2026-09-12T10:00:00Z GET /a?x=1&y=<2> 200 1"))
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(out, `"/a?x=1&y=<2>"`) {
		t.Errorf("got %s", out)
	}
}
