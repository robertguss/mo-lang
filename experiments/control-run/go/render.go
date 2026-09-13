package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"
)

// labelWidth is the width of the label column in the totals block.
const labelWidth = 11

// Group inserts '_' every three digits from the right of a digit string.
func Group(digits string) string {
	if len(digits) <= 3 {
		return digits
	}
	head := len(digits) % 3
	if head == 0 {
		head = 3
	}
	var b strings.Builder
	b.WriteString(digits[:head])
	for i := head; i < len(digits); i += 3 {
		b.WriteByte('_')
		b.WriteString(digits[i : i+3])
	}
	return b.String()
}

// GroupUint formats n with '_' thousands separators.
func GroupUint(n uint64) string {
	return Group(strconv.FormatUint(n, 10))
}

// OneDecimal rounds x to one decimal and groups the integer part.
func OneDecimal(x float64) string {
	s := strconv.FormatFloat(roundTo(x, 1), 'f', 1, 64)
	whole, frac, _ := strings.Cut(s, ".")
	return Group(whole) + "." + frac
}

// RenderText is the text report: totals, slowest, busiest.
func RenderText(s Summary) string {
	var b strings.Builder
	writeTotals(&b, s)
	b.WriteString("\nslowest\n")
	writeSlowest(&b, s.Slowest)
	b.WriteString("\nbusiest\n")
	writeBusiest(&b, s.Busiest)
	return b.String()
}

func writeTotals(b *strings.Builder, s Summary) {
	vals := []string{GroupUint(s.Requests), GroupUint(s.Errors), GroupUint(s.Malformed), OneDecimal(s.PerMinute())}
	w := widest(vals)
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "requests", w, vals[0])
	fmt.Fprintf(b, "%-*s%*s  (%s%%)\n", labelWidth, "errors", w, vals[1], OneDecimal(s.ErrorRate()*100))
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "malformed", w, vals[2])
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "per minute", w, vals[3])
}

func writeSlowest(b *strings.Builder, list []Slow) {
	ms := make([]string, len(list))
	reqs := make([]string, len(list))
	for i, e := range list {
		ms[i], reqs[i] = GroupUint(uint64(e.Duration)), e.Method+" "+e.Path
	}
	wm, wr := widest(ms), widest(reqs)
	for i, e := range list {
		fmt.Fprintf(b, "  %*s ms  %-*s   %s\n", wm, ms[i], wr, reqs[i], e.AtText)
	}
}

func writeBusiest(b *strings.Builder, list []Busy) {
	counts := make([]string, len(list))
	for i, e := range list {
		counts[i] = GroupUint(e.Count)
	}
	w := widest(counts)
	for i, e := range list {
		fmt.Fprintf(b, "  %*s  %s %s\n", w, counts[i], e.Method, e.Path)
	}
}

// widest is the largest rune count in vals; fmt pads by runes too.
func widest(vals []string) int {
	w := 0
	for _, v := range vals {
		w = max(w, utf8.RuneCountInString(v))
	}
	return w
}

// RenderJSON is the summary as one JSON object on one line.
func RenderJSON(s Summary) (string, error) {
	var b strings.Builder
	fmt.Fprintf(&b, `{"requests": %d, "errors": %d, "error_rate": %s, "malformed": %d, "per_minute": %s, "slowest": [`,
		s.Requests, s.Errors, jsonFloat(roundTo(s.ErrorRate(), 3)), s.Malformed, jsonFloat(roundTo(s.PerMinute(), 1)))
	for i, e := range s.Slowest {
		fields, err := jsonStrings(e.Method, e.Path, e.AtText)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(&b, `%s{"ms": %d, "method": %s, "path": %s, "at": %s}`, sep(i), e.Duration, fields[0], fields[1], fields[2])
	}
	b.WriteString(`], "busiest": [`)
	for i, e := range s.Busiest {
		fields, err := jsonStrings(e.Method, e.Path)
		if err != nil {
			return "", err
		}
		fmt.Fprintf(&b, `%s{"count": %d, "method": %s, "path": %s}`, sep(i), e.Count, fields[0], fields[1])
	}
	b.WriteString("]}\n")
	return b.String(), nil
}

func sep(i int) string {
	if i == 0 {
		return ""
	}
	return ", "
}

// jsonFloat prints the shortest form of x, always with a decimal point.
func jsonFloat(x float64) string {
	s := strconv.FormatFloat(x, 'f', -1, 64)
	if !strings.Contains(s, ".") {
		s += ".0"
	}
	return s
}

// jsonStrings encodes each value as a JSON string without HTML escaping.
func jsonStrings(vals ...string) ([]string, error) {
	out := make([]string, len(vals))
	for i, v := range vals {
		var buf bytes.Buffer
		enc := json.NewEncoder(&buf)
		enc.SetEscapeHTML(false)
		if err := enc.Encode(v); err != nil {
			return nil, err
		}
		out[i] = strings.TrimSuffix(buf.String(), "\n")
	}
	return out, nil
}
