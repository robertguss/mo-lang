package main

import (
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"controlrun/contract"
)

// Record is one well-formed log line. Path has card numbers masked already,
// so an unmasked card number never leaves ParseLine.
type Record struct {
	At     time.Time
	AtText string
	Method string
	Path   string
	Status int
	MS     uint32
}

// MalformedError says why a line does not fit the log format.
type MalformedError struct{ Reason string }

func (e *MalformedError) Error() string { return "malformed line: " + e.Reason }

func malformed(reason string) (Record, error) {
	return Record{}, &MalformedError{Reason: reason}
}

// ParseLine parses `<timestamp> <method> <path> <status> <duration_ms>`.
func ParseLine(line string) (Record, error) {
	if !utf8.ValidString(line) {
		return malformed("not UTF-8")
	}
	f := strings.Split(line, " ")
	if len(f) != 5 {
		return malformed("want 5 space-separated fields")
	}
	at, err := time.Parse(time.RFC3339Nano, f[0])
	if err != nil {
		return malformed("timestamp is not ISO-8601 with a zone")
	}
	if !isMethod(f[1]) {
		return malformed("method is not 1 to 16 uppercase letters")
	}
	if !isPath(f[2]) {
		return malformed("path does not start with / or has a control character")
	}
	status, ok := parseStatus(f[3])
	if !ok {
		return malformed("status is not 100 to 599")
	}
	ms, ok := parseMS(f[4])
	if !ok {
		return malformed("duration_ms does not fit UInt32")
	}
	rec := Record{At: at, AtText: f[0], Method: f[1], Path: MaskCards(f[2]), Status: status, MS: ms}
	if err := contract.Ensure(rec.Status >= 100 && rec.Status <= 599, "rec.Status >= 100 && rec.Status <= 599"); err != nil {
		return Record{}, err
	}
	return rec, nil
}

func isMethod(s string) bool {
	if len(s) == 0 || len(s) > 16 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 'A' || s[i] > 'Z' {
			return false
		}
	}
	return true
}

func isPath(s string) bool {
	if !strings.HasPrefix(s, "/") {
		return false
	}
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return false
		}
	}
	return true
}

func allDigits(s string) bool {
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return len(s) > 0
}

func parseStatus(s string) (int, bool) {
	if len(s) != 3 || !allDigits(s) {
		return 0, false
	}
	n, err := strconv.Atoi(s)
	return n, err == nil && n >= 100 && n <= 599
}

func parseMS(s string) (uint32, bool) {
	if !allDigits(s) {
		return 0, false
	}
	n, err := strconv.ParseUint(s, 10, 32)
	return uint32(n), err == nil
}

// cardRuns returns the [start, end) spans of digit runs, optionally joined
// by single hyphens, that hold 16 or more digits.
func cardRuns(s string) [][2]int {
	var spans [][2]int
	for i := 0; i < len(s); {
		if !isDigit(s[i]) {
			i++
			continue
		}
		j, digits := i, 0
		for j < len(s) && (isDigit(s[j]) || (s[j] == '-' && j+1 < len(s) && isDigit(s[j+1]))) {
			if isDigit(s[j]) {
				digits++
			}
			j++
		}
		if digits >= 16 {
			spans = append(spans, [2]int{i, j})
		}
		i = j
	}
	return spans
}

func isDigit(b byte) bool { return b >= '0' && b <= '9' }

// MaskCards replaces the digits of every card number in s with '*'.
func MaskCards(s string) string {
	spans := cardRuns(s)
	if len(spans) == 0 {
		return s
	}
	b := []byte(s)
	for _, sp := range spans {
		for k := sp[0]; k < sp[1]; k++ {
			if isDigit(b[k]) {
				b[k] = '*'
			}
		}
	}
	return string(b)
}
