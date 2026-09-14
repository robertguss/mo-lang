package main

import (
	"encoding/json"
	"io"
	"strconv"
	"strings"
	"unicode/utf8"
)

// groupThousands puts '_' between every three digits of the integer part.
func groupThousands(num string) string {
	intPart, frac, hasFrac := strings.Cut(num, ".")
	var b strings.Builder
	for i, c := range intPart {
		if i > 0 && (len(intPart)-i)%3 == 0 {
			b.WriteByte('_')
		}
		b.WriteRune(c)
	}
	if hasFrac {
		b.WriteString("." + frac)
	}
	return b.String()
}

func fmtUint(n uint64) string { return groupThousands(strconv.FormatUint(n, 10)) }

func fmtFloat1(f float64) string { return groupThousands(strconv.FormatFloat(f, 'f', 1, 64)) }

func padRight(s string, width int) string {
	return s + strings.Repeat(" ", max(0, width-utf8.RuneCountInString(s)))
}

func padLeft(s string, width int) string {
	return strings.Repeat(" ", max(0, width-utf8.RuneCountInString(s))) + s
}

func widest(xs []string) int {
	w := 0
	for _, x := range xs {
		w = max(w, utf8.RuneCountInString(x))
	}
	return w
}

// WriteText prints the report in the text layout of the spec.
func WriteText(w io.Writer, r Report) error {
	vals := []string{fmtUint(r.Requests), fmtUint(r.Errors), fmtUint(r.Malformed), fmtFloat1(r.PerMinute)}
	vw := widest(vals)
	var b strings.Builder
	b.WriteString("requests   " + padLeft(vals[0], vw) + "\n")
	b.WriteString("errors     " + padLeft(vals[1], vw) + "  (" + fmtFloat1(r.ErrorRate*100) + "%)\n")
	b.WriteString("malformed  " + padLeft(vals[2], vw) + "\n")
	b.WriteString("per minute " + padLeft(vals[3], vw) + "\n")
	b.WriteString("\nslowest\n")
	writeSlowest(&b, r.Slowest)
	b.WriteString("\nbusiest\n")
	writeBusiest(&b, r.Busiest)
	_, err := io.WriteString(w, b.String())
	return err
}

func writeSlowest(b *strings.Builder, rows []SlowRow) {
	ms, methods, paths := make([]string, len(rows)), make([]string, len(rows)), make([]string, len(rows))
	for i, row := range rows {
		ms[i], methods[i], paths[i] = fmtUint(uint64(row.MS)), row.Method, row.Path
	}
	msw, mw, pw := widest(ms), widest(methods), widest(paths)
	for i, row := range rows {
		b.WriteString("  " + padLeft(ms[i], msw) + " ms  " + padRight(row.Method, mw) + " " + padRight(row.Path, pw) + "   " + row.At + "\n")
	}
}

func writeBusiest(b *strings.Builder, rows []BusyRow) {
	counts, methods := make([]string, len(rows)), make([]string, len(rows))
	for i, row := range rows {
		counts[i], methods[i] = fmtUint(row.Count), row.Method
	}
	cw, mw := widest(counts), widest(methods)
	for i, row := range rows {
		b.WriteString("  " + padLeft(counts[i], cw) + "  " + padRight(row.Method, mw) + " " + row.Path + "\n")
	}
}

// WriteJSON prints the report as one JSON object on one line.
func WriteJSON(w io.Writer, r Report) error {
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	return enc.Encode(r)
}
