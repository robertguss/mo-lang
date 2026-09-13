package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// thousands formats n with '_' between groups of three digits, like Mo.
func thousands(n uint64) string {
	digits := strconv.FormatUint(n, 10)
	var b strings.Builder
	for i := 0; i < len(digits); i++ {
		if i > 0 && (len(digits)-i)%3 == 0 {
			b.WriteByte('_')
		}
		b.WriteByte(digits[i])
	}
	return b.String()
}

// tenths formats a count of tenths as "12_345.6".
func tenths(n uint64) string {
	return thousands(n/10) + "." + strconv.FormatUint(n%10, 10)
}

// formatAt prints a timestamp in UTC as RFC 3339, with fractional seconds
// only when present. Normalizing keeps at most nine fractional digits, so
// a timestamp cannot carry a card number to stdout.
func formatAt(t time.Time) string {
	return t.UTC().Format(time.RFC3339Nano)
}

// maxLen is the widest string in runes, the unit fmt pads in.
func maxLen(ss []string) int {
	n := 0
	for _, s := range ss {
		n = max(n, utf8.RuneCountInString(s))
	}
	return n
}

// renderText is the text report. Writes to a strings.Builder cannot fail,
// so their results are not checked.
func renderText(s Summary) string {
	var b strings.Builder
	writeCounts(&b, s)
	b.WriteString("\nslowest\n")
	writeSlowest(&b, s.Slowest)
	b.WriteString("\nbusiest\n")
	writeBusiest(&b, s.Busiest)
	return b.String()
}

func writeCounts(b *strings.Builder, s Summary) {
	values := []string{
		thousands(s.Requests),
		thousands(s.Errors),
		thousands(s.Malformed),
		tenths(perMinuteTenths(s.Requests, s.First, s.Last)),
	}
	w := maxLen(values)
	percent := tenths(errorRateThousandths(s.Errors, s.Requests))
	fmt.Fprintf(b, "%-10s %*s\n", "requests", w, values[0])
	fmt.Fprintf(b, "%-10s %*s  (%s%%)\n", "errors", w, values[1], percent)
	fmt.Fprintf(b, "%-10s %*s\n", "malformed", w, values[2])
	fmt.Fprintf(b, "%-10s %*s\n", "per minute", w, values[3])
}

func writeSlowest(b *strings.Builder, list []Slow) {
	ms := make([]string, len(list))
	routes := make([]string, len(list))
	for i, e := range list {
		ms[i] = thousands(uint64(e.Duration))
		routes[i] = e.Method + " " + e.Path
	}
	wm, wr := maxLen(ms), maxLen(routes)
	for i, e := range list {
		fmt.Fprintf(b, "  %*s ms  %-*s  %s\n", wm, ms[i], wr, routes[i], formatAt(e.At))
	}
}

func writeBusiest(b *strings.Builder, list []Busy) {
	counts := make([]string, len(list))
	for i, e := range list {
		counts[i] = thousands(e.Count)
	}
	w := maxLen(counts)
	for i, e := range list {
		fmt.Fprintf(b, "  %*s  %s %s\n", w, counts[i], e.Method, e.Path)
	}
}

// member is one "key": value pair; value is already JSON.
type member struct {
	key, value string
}

// jsonObject joins members spaced like the spec's example. Keys are
// constants that need no escaping.
func jsonObject(members ...member) string {
	parts := make([]string, len(members))
	for i, m := range members {
		parts[i] = `"` + m.key + `": ` + m.value
	}
	return "{" + strings.Join(parts, ", ") + "}"
}

func jsonArray(items []string) string {
	return "[" + strings.Join(items, ", ") + "]"
}

func jsonUint(n uint64) string {
	return strconv.FormatUint(n, 10)
}

// jsonDecimal prints n/scale in the shortest form that reads back exactly.
func jsonDecimal(n, scale uint64) string {
	return strconv.FormatFloat(float64(n)/float64(scale), 'f', -1, 64)
}

// jsonStrings quotes each string as JSON, leaving <, > and & readable.
func jsonStrings(ss ...string) ([]string, error) {
	out := make([]string, len(ss))
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	for i, s := range ss {
		buf.Reset()
		if err := enc.Encode(s); err != nil {
			return nil, err
		}
		out[i] = strings.TrimSuffix(buf.String(), "\n")
	}
	return out, nil
}

// renderJSON is the summary as one JSON object on one line.
func renderJSON(s Summary) (string, error) {
	slowest, err := jsonSlowest(s.Slowest)
	if err != nil {
		return "", err
	}
	busiest, err := jsonBusiest(s.Busiest)
	if err != nil {
		return "", err
	}
	return jsonObject(
		member{"requests", jsonUint(s.Requests)},
		member{"errors", jsonUint(s.Errors)},
		member{"error_rate", jsonDecimal(errorRateThousandths(s.Errors, s.Requests), 1000)},
		member{"malformed", jsonUint(s.Malformed)},
		member{"per_minute", jsonDecimal(perMinuteTenths(s.Requests, s.First, s.Last), 10)},
		member{"slowest", slowest},
		member{"busiest", busiest},
	) + "\n", nil
}

func jsonSlowest(list []Slow) (string, error) {
	items := make([]string, 0, len(list))
	for _, e := range list {
		q, err := jsonStrings(e.Method, e.Path, formatAt(e.At))
		if err != nil {
			return "", err
		}
		items = append(items, jsonObject(
			member{"ms", jsonUint(uint64(e.Duration))},
			member{"method", q[0]},
			member{"path", q[1]},
			member{"at", q[2]},
		))
	}
	return jsonArray(items), nil
}

func jsonBusiest(list []Busy) (string, error) {
	items := make([]string, 0, len(list))
	for _, e := range list {
		q, err := jsonStrings(e.Method, e.Path)
		if err != nil {
			return "", err
		}
		items = append(items, jsonObject(
			member{"count", jsonUint(e.Count)},
			member{"method", q[0]},
			member{"path", q[1]},
		))
	}
	return jsonArray(items), nil
}
