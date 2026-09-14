package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"strconv"
	"strings"
)

// GroupInt writes n with `_` between thousands: 1204 is "1_204".
func GroupInt(n int) string {
	digits := strconv.Itoa(n)
	sign := ""
	if strings.HasPrefix(digits, "-") {
		sign, digits = "-", digits[1:]
	}
	var b strings.Builder
	for i, c := range digits {
		if i > 0 && (len(digits)-i)%3 == 0 {
			b.WriteByte('_')
		}
		b.WriteRune(c)
	}
	return sign + b.String()
}

// GroupFloat1 writes x with one decimal and a grouped integer part.
func GroupFloat1(x float64) string {
	s := strconv.FormatFloat(x, 'f', 1, 64)
	whole, frac, _ := strings.Cut(s, ".")
	n, err := strconv.Atoi(whole)
	if err != nil {
		return s
	}
	return GroupInt(n) + "." + frac
}

// FormatText renders the text report.
func FormatText(s Summary) string {
	vals := []string{GroupInt(s.Requests), GroupInt(s.Errors), GroupInt(s.Malformed), GroupFloat1(s.PerMinute)}
	w := 5 // the spec's own example pads its numbers to five
	for _, v := range vals {
		w = max(w, len(v))
	}
	var b strings.Builder
	fmt.Fprintf(&b, "%-11s%*s\n", "requests", w, vals[0])
	fmt.Fprintf(&b, "%-11s%*s  (%s%%)\n", "errors", w, vals[1], strconv.FormatFloat(s.ErrorRate*100, 'f', 1, 64))
	fmt.Fprintf(&b, "%-11s%*s\n", "malformed", w, vals[2])
	fmt.Fprintf(&b, "%-11s%*s\n", "per minute", w, vals[3])
	b.WriteString("\nslowest\n")
	msW, reqW := 0, 0
	for _, r := range s.Slowest {
		msW = max(msW, len(GroupInt(int(r.Duration))))
		reqW = max(reqW, len(r.Method)+1+len(r.Path))
	}
	for _, r := range s.Slowest {
		fmt.Fprintf(&b, "  %*s ms  %-*s   %s\n", msW, GroupInt(int(r.Duration)), reqW, r.Method+" "+r.Path, r.AtText)
	}
	b.WriteString("\nbusiest\n")
	countW := 0
	for _, p := range s.Busiest {
		countW = max(countW, len(GroupInt(p.Count)))
	}
	for _, p := range s.Busiest {
		fmt.Fprintf(&b, "  %*s  %s %s\n", countW, GroupInt(p.Count), p.Method, p.Path)
	}
	return b.String()
}

type jsonSlow struct {
	Ms     uint32 `json:"ms"`
	Method string `json:"method"`
	Path   string `json:"path"`
	At     string `json:"at"`
}

type jsonBusy struct {
	Count  int    `json:"count"`
	Method string `json:"method"`
	Path   string `json:"path"`
}

type jsonSummary struct {
	Requests  int        `json:"requests"`
	Errors    int        `json:"errors"`
	ErrorRate float64    `json:"error_rate"`
	Malformed int        `json:"malformed"`
	PerMinute float64    `json:"per_minute"`
	Slowest   []jsonSlow `json:"slowest"`
	Busiest   []jsonBusy `json:"busiest"`
}

// FormatJSON renders the summary as one JSON object on one line.
func FormatJSON(s Summary) (string, error) {
	out := jsonSummary{
		Requests: s.Requests, Errors: s.Errors, ErrorRate: s.ErrorRate,
		Malformed: s.Malformed, PerMinute: s.PerMinute,
		Slowest: make([]jsonSlow, 0, len(s.Slowest)),
		Busiest: make([]jsonBusy, 0, len(s.Busiest)),
	}
	for _, r := range s.Slowest {
		out.Slowest = append(out.Slowest, jsonSlow{Ms: r.Duration, Method: r.Method, Path: r.Path, At: r.AtText})
	}
	for _, p := range s.Busiest {
		out.Busiest = append(out.Busiest, jsonBusy{Count: p.Count, Method: p.Method, Path: p.Path})
	}
	var buf bytes.Buffer
	enc := json.NewEncoder(&buf)
	enc.SetEscapeHTML(false)
	if err := enc.Encode(out); err != nil {
		return "", err
	}
	return buf.String(), nil
}
