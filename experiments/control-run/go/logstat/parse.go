package main

import (
	"errors"
	"fmt"
	"math"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"

	"logstat/contract"
)

// Record is one well-formed log line. Path is already masked: a card number
// read from a file never leaves ParseLine.
type Record struct {
	At       time.Time
	AtText   string
	Method   string
	Path     string
	Status   int
	Duration uint32
}

// ErrMalformed marks a line that does not fit the log format.
var ErrMalformed = errors.New("malformed line")

func malformed(why string) error { return fmt.Errorf("%w: %s", ErrMalformed, why) }

// ParseLine parses `<timestamp> <method> <path> <status> <duration_ms>`.
// It yields a record whose status is 100 to 599 and whose duration fits a
// uint32, or an error wrapping ErrMalformed.
func ParseLine(line string) (Record, error) {
	line = strings.TrimSuffix(line, "\r")
	if !utf8.ValidString(line) {
		return Record{}, malformed("not UTF-8")
	}
	fields := strings.Split(line, " ")
	if len(fields) != 5 {
		return Record{}, malformed("want 5 space-separated fields")
	}
	at, err := time.Parse(time.RFC3339, fields[0])
	if err != nil {
		return Record{}, malformed("timestamp: " + err.Error())
	}
	if HasCardNumber(fields[0]) {
		// Sixteen fractional-second digits would be printed as they are.
		return Record{}, malformed("timestamp has a run of 16 digits")
	}
	if !isMethod(fields[1]) {
		return Record{}, malformed("method")
	}
	if !isPath(fields[2]) {
		return Record{}, malformed("path")
	}
	status, err := parseStatus(fields[3])
	if err != nil {
		return Record{}, err
	}
	duration, err := parseDuration(fields[4])
	if err != nil {
		return Record{}, err
	}
	rec := Record{At: at, AtText: fields[0], Method: fields[1], Path: MaskCards(fields[2]), Status: status, Duration: duration}
	if err := contract.Ensure(!HasCardNumber(rec.Path) && !HasCardNumber(rec.AtText), "!HasCardNumber(rec.Path) && !HasCardNumber(rec.AtText)"); err != nil {
		return Record{}, err
	}
	return rec, nil
}

func parseStatus(s string) (int, error) {
	if len(s) != 3 || !allDigits(s) {
		return 0, malformed("status is not three digits")
	}
	status, err := strconv.Atoi(s)
	if err != nil {
		return 0, malformed("status: " + err.Error())
	}
	if err := contract.Require(status >= 100 && status <= 599, "status >= 100 && status <= 599"); err != nil {
		return 0, malformed(err.Error())
	}
	return status, nil
}

func parseDuration(s string) (uint32, error) {
	if s == "" || !allDigits(s) {
		return 0, malformed("duration_ms is not digits")
	}
	d, err := strconv.ParseUint(s, 10, 64)
	if err != nil {
		return 0, malformed("duration_ms: " + err.Error())
	}
	if err := contract.Require(d <= math.MaxUint32, "duration_ms <= math.MaxUint32"); err != nil {
		return 0, malformed(err.Error())
	}
	return uint32(d), nil
}

func isMethod(s string) bool {
	if s == "" || len(s) > 16 {
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
	return true
}

// cardDigits is the length of a card number: a run of at least this many
// ASCII digits is treated as one.
const cardDigits = 16

// MaskCards replaces every run of 16 or more digits with as many `*`.
func MaskCards(s string) string {
	if !HasCardNumber(s) {
		return s
	}
	b := []byte(s)
	for start := 0; start < len(b); {
		end := start
		for end < len(b) && b[end] >= '0' && b[end] <= '9' {
			end++
		}
		if end-start >= cardDigits {
			for i := start; i < end; i++ {
				b[i] = '*'
			}
		}
		if end == start {
			end++
		}
		start = end
	}
	return string(b)
}

// HasCardNumber reports whether s holds a run of 16 or more digits.
func HasCardNumber(s string) bool {
	run := 0
	for i := 0; i < len(s); i++ {
		if s[i] >= '0' && s[i] <= '9' {
			run++
			if run >= cardDigits {
				return true
			}
		} else {
			run = 0
		}
	}
	return false
}
