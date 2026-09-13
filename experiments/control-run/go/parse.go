package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// Record is one well-formed log line.
type Record struct {
	At       time.Time
	AtText   string
	Method   string
	Path     string
	Status   uint16
	Duration uint32
}

// ErrMalformed is wrapped by every parse failure.
var ErrMalformed = errors.New("malformed line")

func malformed(reason string) error {
	return fmt.Errorf("%w: %s", ErrMalformed, reason)
}

// ParseLine requires: valid UTF-8; exactly five fields separated by single
// spaces; an RFC 3339 timestamp; an upper-case ASCII method; a path starting
// with "/"; a three-digit status from 100 to 599; a decimal duration that fits
// uint32. Anything else is an error wrapping ErrMalformed.
func ParseLine(line string) (Record, error) {
	if !utf8.ValidString(line) {
		return Record{}, malformed("not UTF-8")
	}
	f := strings.Split(line, " ")
	if len(f) != 5 {
		return Record{}, malformed("want 5 space-separated fields")
	}
	at, err := ParseTimestamp(f[0])
	if err != nil {
		return Record{}, malformed("bad timestamp")
	}
	if !isMethod(f[1]) {
		return Record{}, malformed("bad method")
	}
	if !strings.HasPrefix(f[2], "/") {
		return Record{}, malformed("path must start with /")
	}
	status, err := parseStatus(f[3])
	if err != nil {
		return Record{}, err
	}
	ms, err := parseDuration(f[4])
	if err != nil {
		return Record{}, err
	}
	return Record{At: at, AtText: f[0], Method: f[1], Path: f[2], Status: status, Duration: ms}, nil
}

// ParseTimestamp accepts the RFC 3339 profile of ISO 8601, zone required.
func ParseTimestamp(s string) (time.Time, error) {
	return time.Parse(time.RFC3339, s)
}

func isMethod(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 'A' || s[i] > 'Z' {
			return false
		}
	}
	return true
}

func isDigits(s string) bool {
	if s == "" {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func parseStatus(s string) (uint16, error) {
	if len(s) != 3 || !isDigits(s) {
		return 0, malformed("status must be three digits")
	}
	n, err := strconv.ParseUint(s, 10, 16)
	if err != nil || n < 100 || n > 599 {
		return 0, malformed("status must be 100 to 599")
	}
	return uint16(n), nil
}

func parseDuration(s string) (uint32, error) {
	if !isDigits(s) {
		return 0, malformed("duration must be decimal digits")
	}
	n, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return 0, malformed("duration does not fit uint32")
	}
	return uint32(n), nil
}
