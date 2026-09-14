package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

const (
	labelWidth    = 11 // "per minute" and one space
	minValueWidth = 5
	slowGap       = "   "
)

// RenderText is the text report: a header of four numbers, then the
// slowest and busiest lists, each list a blank line after the last.
func RenderText(r Result) string {
	var b strings.Builder
	writeHeader(&b, r)
	b.WriteString("\nslowest\n")
	writeSlowest(&b, r.Slowest)
	b.WriteString("\nbusiest\n")
	writeBusiest(&b, r.Busiest)
	return b.String()
}

func writeHeader(b *strings.Builder, r Result) {
	values := []string{
		Thousands(uint64(r.Requests)),
		Thousands(uint64(r.Errors)),
		Thousands(uint64(r.Malformed)),
		decimal(r.PerMinute, 1),
	}
	w := max(minValueWidth, widest(values))
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "requests", w, values[0])
	fmt.Fprintf(b, "%-*s%*s  (%s%%)\n", labelWidth, "errors", w, values[1], decimal(r.ErrorRate*100, 1))
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "malformed", w, values[2])
	fmt.Fprintf(b, "%-*s%*s\n", labelWidth, "per minute", w, values[3])
}

func writeSlowest(b *strings.Builder, rows []Record) {
	ms := make([]string, len(rows))
	calls := make([]string, len(rows))
	for i, r := range rows {
		ms[i] = Thousands(uint64(r.Ms))
		calls[i] = r.Method + " " + r.Path
	}
	msW, callW := widest(ms), widest(calls)
	for i, r := range rows {
		fmt.Fprintf(b, "  %*s ms  %-*s%s%s\n", msW, ms[i], callW, calls[i], slowGap, r.AtText)
	}
}

func writeBusiest(b *strings.Builder, rows []PathCount) {
	counts := make([]string, len(rows))
	for i, r := range rows {
		counts[i] = Thousands(uint64(r.Count))
	}
	w := widest(counts)
	for i, r := range rows {
		fmt.Fprintf(b, "  %*s  %s %s\n", w, counts[i], r.Method, r.Path)
	}
}

func widest(values []string) int {
	w := 0
	for _, v := range values {
		w = max(w, len(v))
	}
	return w
}

// Thousands writes n with '_' between groups of three digits.
func Thousands(n uint64) string {
	s := strconv.FormatUint(n, 10)
	var b strings.Builder
	for i := range len(s) {
		if i > 0 && (len(s)-i)%3 == 0 {
			b.WriteByte('_')
		}
		b.WriteByte(s[i])
	}
	return b.String()
}

// decimal rounds to places digits with thousands separators on the whole
// part. Rounding is strconv's: nearest, ties by the exact binary value.
func decimal(x float64, places int) string {
	s := strconv.FormatFloat(x, 'f', places, 64)
	whole, frac, _ := strings.Cut(s, ".")
	n, err := strconv.ParseUint(whole, 10, 64)
	if err != nil { // never negative or huge here; keep the digits as they are
		return s
	}
	return Thousands(n) + "." + frac
}

type jsonSummary struct {
	Requests  int           `json:"requests"`
	Errors    int           `json:"errors"`
	ErrorRate json.Number   `json:"error_rate"`
	Malformed int           `json:"malformed"`
	PerMinute json.Number   `json:"per_minute"`
	Slowest   []jsonSlow    `json:"slowest"`
	Busiest   []jsonBusiest `json:"busiest"`
}

type jsonSlow struct {
	Ms     uint32 `json:"ms"`
	Method string `json:"method"`
	Path   string `json:"path"`
	At     string `json:"at"`
}

type jsonBusiest struct {
	Count  int    `json:"count"`
	Method string `json:"method"`
	Path   string `json:"path"`
}

// RenderJSON is the summary as one JSON object on one line. error_rate
// has three decimals and per_minute one, as in the spec's example.
func RenderJSON(r Result) (string, error) {
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(toJSON(r)); err != nil {
		return "", err
	}
	return buf.String(), nil
}

func toJSON(r Result) jsonSummary {
	out := jsonSummary{
		Requests:  r.Requests,
		Errors:    r.Errors,
		ErrorRate: json.Number(strconv.FormatFloat(r.ErrorRate, 'f', 3, 64)),
		Malformed: r.Malformed,
		PerMinute: json.Number(strconv.FormatFloat(r.PerMinute, 'f', 1, 64)),
		Slowest:   make([]jsonSlow, 0, len(r.Slowest)),
		Busiest:   make([]jsonBusiest, 0, len(r.Busiest)),
	}
	for _, s := range r.Slowest {
		out.Slowest = append(out.Slowest, jsonSlow{s.Ms, s.Method, s.Path, s.AtText})
	}
	for _, b := range r.Busiest {
		out.Busiest = append(out.Busiest, jsonBusiest{b.Count, b.Method, b.Path})
	}
	return out
}

// CheckOutput is the last guard before stdout: no run of 16 digits.
func CheckOutput(s string) error {
	if ContainsCard(s) {
		return broken("output holds a card number")
	}
	return nil
}
