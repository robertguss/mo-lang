package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
)

// labelWidth fits the longest label, "per minute", plus one space.
const labelWidth = 11

// WriteText writes the text report: counts, slowest, busiest.
func WriteText(w io.Writer, s Summary) error {
	var b strings.Builder
	writeCounts(&b, s)
	b.WriteString("\nslowest\n")
	writeSlowest(&b, s.Slowest)
	b.WriteString("\nbusiest\n")
	writeBusiest(&b, s.Busiest)
	_, err := io.WriteString(w, b.String())
	return err
}

// writeCounts right-aligns the four numbers in one column.
func writeCounts(b *strings.Builder, s Summary) {
	vals := []string{Grouped(s.Requests), Grouped(s.Errors), Grouped(s.Malformed), Decimal(s.PerMinute, 1)}
	w := maxLen(vals)
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "requests", w, vals[0])
	fmt.Fprintf(b, "%-*s%*s  (%s%%)\n", labelWidth, "errors", w, vals[1], Decimal(100*ErrorRate(s), 1))
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "malformed", w, vals[2])
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "per minute", w, vals[3])
}

func writeSlowest(b *strings.Builder, recs []Record) {
	ms := make([]string, len(recs))
	reqs := make([]string, len(recs))
	for i, r := range recs {
		ms[i] = Grouped(int(r.Duration))
		reqs[i] = r.Method + " " + r.Path
	}
	msW, reqW := maxLen(ms), maxLen(reqs)
	for i, r := range recs {
		fmt.Fprintf(b, "  %*s ms  %-*s   %s\n", msW, ms[i], reqW, reqs[i], r.Stamp)
	}
}

func writeBusiest(b *strings.Builder, rows []PathCount) {
	counts := make([]string, len(rows))
	for i, r := range rows {
		counts[i] = Grouped(r.Count)
	}
	w := maxLen(counts)
	for i, r := range rows {
		fmt.Fprintf(b, "  %*s  %s %s\n", w, counts[i], r.Method, r.Path)
	}
}

// WriteJSON writes the summary as one JSON object on one line, in the key
// order and spacing of the spec. error_rate has 3 decimals, per_minute 1.
func WriteJSON(w io.Writer, s Summary) error {
	var b strings.Builder
	fmt.Fprintf(&b, `{"requests": %d, "errors": %d, "error_rate": %s, "malformed": %d, "per_minute": %s, "slowest": [`,
		s.Requests, s.Errors, Decimal(ErrorRate(s), 3), s.Malformed, Decimal(s.PerMinute, 1))
	for i, r := range s.Slowest {
		if i > 0 {
			b.WriteString(", ")
		}
		fmt.Fprintf(&b, `{"ms": %d, "method": %s, "path": %s, "at": %s}`,
			r.Duration, jsonString(r.Method), jsonString(r.Path), jsonString(r.Stamp))
	}
	b.WriteString(`], "busiest": [`)
	for i, r := range s.Busiest {
		if i > 0 {
			b.WriteString(", ")
		}
		fmt.Fprintf(&b, `{"count": %d, "method": %s, "path": %s}`, r.Count, jsonString(r.Method), jsonString(r.Path))
	}
	b.WriteString("]}\n")
	_, err := io.WriteString(w, b.String())
	return err
}

// jsonString quotes s as a JSON string without HTML escaping. Encoding a
// Go string cannot fail, so the error is dropped only after checking it.
func jsonString(s string) string {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(s); err != nil {
		return `""`
	}
	return strings.TrimSuffix(buf.String(), "\n")
}

// ErrorRate is errors over requests, 0 with no requests.
func ErrorRate(s Summary) float64 {
	if s.Requests == 0 {
		return 0
	}
	return float64(s.Errors) / float64(s.Requests)
}

// Grouped formats n with '_' between groups of three digits: 1_204.
func Grouped(n int) string {
	digits := strconv.Itoa(n)
	sign := ""
	if n < 0 {
		sign, digits = "-", digits[1:]
	}
	return sign + group(digits)
}

func group(digits string) string {
	var b strings.Builder
	for i, d := range digits {
		if i > 0 && (len(digits)-i)%3 == 0 {
			b.WriteByte('_')
		}
		b.WriteRune(d)
	}
	return b.String()
}

// Decimal formats x with the given number of decimals, grouping the whole
// part like Grouped: 1_234.5.
func Decimal(x float64, places int) string {
	s := strconv.FormatFloat(x, 'f', places, 64)
	whole, frac, _ := strings.Cut(s, ".")
	sign := ""
	if strings.HasPrefix(whole, "-") {
		sign, whole = "-", whole[1:]
	}
	if frac == "" {
		return sign + group(whole)
	}
	return sign + group(whole) + "." + frac
}

func maxLen(ss []string) int {
	n := 0
	for _, s := range ss {
		n = max(n, len(s))
	}
	return n
}
