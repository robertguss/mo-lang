package main

import (
	"fmt"
	"strconv"
	"strings"
	"unicode/utf8"
)

// labelWidth is the width of the label column in the totals block.
const labelWidth = 11

// RenderText formats the summary as the text report.
func RenderText(s Summary) string {
	var b strings.Builder
	writeTotals(&b, s)
	b.WriteString("\nslowest\n")
	writeSlowest(&b, s.Slowest)
	b.WriteString("\nbusiest\n")
	writeBusiest(&b, s.Busiest)
	return b.String()
}

type totalRow struct{ label, whole, rest string }

// writeTotals right-aligns the whole-number parts, so a fraction like the
// ".1" of "40.1" hangs past the column, as in the spec's example.
func writeTotals(b *strings.Builder, s Summary) {
	percent := strconv.FormatFloat(100*ratio(s.Errors, s.Requests), 'f', 1, 64)
	perWhole, perFrac := splitDecimal(strconv.FormatFloat(s.PerMinute, 'f', 1, 64))
	rows := []totalRow{
		{"requests", group(s.Requests), ""},
		{"errors", group(s.Errors), "  (" + percent + "%)"},
		{"malformed", group(s.Malformed), ""},
		{"per minute", perWhole, perFrac},
	}
	width := 0
	for _, r := range rows {
		width = max(width, len(r.whole))
	}
	for _, r := range rows {
		fmt.Fprintf(b, "%-*s%*s%s\n", labelWidth, r.label, width, r.whole, r.rest)
	}
}

func writeSlowest(b *strings.Builder, list []Slow) {
	msWidth, routeWidth := 0, 0
	for _, e := range list {
		msWidth = max(msWidth, len(group(uint64(e.Duration))))
		routeWidth = max(routeWidth, utf8.RuneCountInString(routeLabel(e.Method, e.Path)))
	}
	for _, e := range list {
		fmt.Fprintf(b, "  %*s ms  %-*s   %s\n", msWidth, group(uint64(e.Duration)), routeWidth, routeLabel(e.Method, e.Path), e.At)
	}
}

func writeBusiest(b *strings.Builder, list []Busy) {
	width := 0
	for _, e := range list {
		width = max(width, len(group(e.Count)))
	}
	for _, e := range list {
		fmt.Fprintf(b, "  %*s  %s\n", width, group(e.Count), routeLabel(e.Method, e.Path))
	}
}

func routeLabel(method, path string) string { return method + " " + path }

// group writes n with '_' as the thousands separator: 1204 is "1_204".
func group(n uint64) string { return groupDigits(strconv.FormatUint(n, 10)) }

func groupDigits(digits string) string {
	var b strings.Builder
	for i := 0; i < len(digits); i++ {
		if i > 0 && (len(digits)-i)%3 == 0 {
			b.WriteByte('_')
		}
		b.WriteByte(digits[i])
	}
	return b.String()
}

// splitDecimal splits "1204.5" into "1_204" and ".5".
func splitDecimal(s string) (whole, frac string) {
	i := strings.IndexByte(s, '.')
	if i < 0 {
		return groupDigits(s), ""
	}
	return groupDigits(s[:i]), s[i:]
}

// RenderJSON formats the summary as one JSON object on one line, keys in the
// spec's order and spacing.
func RenderJSON(s Summary) string {
	var b strings.Builder
	fmt.Fprintf(&b, `{"requests": %d, "errors": %d, "error_rate": %s, "malformed": %d, "per_minute": %s, "slowest": [`,
		s.Requests, s.Errors, strconv.FormatFloat(s.ErrorRate, 'f', 3, 64), s.Malformed, strconv.FormatFloat(s.PerMinute, 'f', 1, 64))
	for i, e := range s.Slowest {
		if i > 0 {
			b.WriteString(", ")
		}
		fmt.Fprintf(&b, `{"ms": %d, "method": %s, "path": %s, "at": %s}`, e.Duration, jsonString(e.Method), jsonString(e.Path), jsonString(e.At))
	}
	b.WriteString(`], "busiest": [`)
	for i, e := range s.Busiest {
		if i > 0 {
			b.WriteString(", ")
		}
		fmt.Fprintf(&b, `{"count": %d, "method": %s, "path": %s}`, e.Count, jsonString(e.Method), jsonString(e.Path))
	}
	b.WriteString("]}\n")
	return b.String()
}

// jsonString quotes valid UTF-8 as a JSON string. Input comes from ParseLine,
// which rejects invalid UTF-8, so escaping quote, backslash and controls is enough.
func jsonString(s string) string {
	var b strings.Builder
	b.WriteByte('"')
	for _, r := range s {
		switch {
		case r == '"' || r == '\\':
			b.WriteByte('\\')
			b.WriteRune(r)
		case r < 0x20:
			fmt.Fprintf(&b, `\u%04x`, r)
		default:
			b.WriteRune(r)
		}
	}
	b.WriteByte('"')
	return b.String()
}
