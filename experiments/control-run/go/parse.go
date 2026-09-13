package main

import (
	"errors"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// Record is one well-formed log line. Path is already redacted, so a card
// number never leaves ParseLine.
type Record struct {
	At       time.Time
	Stamp    string // the timestamp exactly as written in the log
	Method   string
	Path     string
	Status   int
	Duration uint32
}

// ErrMalformed is wrapped by every error ParseLine returns.
var ErrMalformed = errors.New("malformed line")

type malformedError struct{ reason string }

func (e malformedError) Error() string { return "malformed line: " + e.reason }
func (e malformedError) Unwrap() error { return ErrMalformed }

func malformed(reason string) error { return malformedError{reason} }

// ParseLine parses one line, given without its line ending.
//
// Requires, each one a malformed error when broken:
//   - the line is valid UTF-8
//   - exactly five fields separated by single spaces
//   - the timestamp is RFC 3339 (the ISO-8601 profile with a zone)
//   - the method is one or more ASCII capital letters
//   - the path starts with '/' and holds no control or space characters
//   - the status is ASCII digits with a value from 100 to 599
//   - the duration is ASCII digits with a value that fits uint32
func ParseLine(line string) (Record, error) {
	if !utf8.ValidString(line) {
		return Record{}, malformed("not valid UTF-8")
	}
	f := strings.Split(line, " ")
	if len(f) != 5 {
		return Record{}, malformed("want 5 fields separated by single spaces")
	}
	at, err := time.Parse(time.RFC3339, f[0])
	if err != nil {
		return Record{}, malformed("timestamp is not RFC 3339")
	}
	if !isMethod(f[1]) {
		return Record{}, malformed("method is not ASCII capital letters")
	}
	if !isPath(f[2]) {
		return Record{}, malformed("path must start with '/' and hold no control or space characters")
	}
	status, err := parseDigits(f[3], 16)
	if err != nil || status < 100 || status > 599 {
		return Record{}, malformed("status is not a number from 100 to 599")
	}
	ms, err := parseDigits(f[4], 32)
	if err != nil {
		return Record{}, malformed("duration is not a number that fits uint32")
	}
	return Record{At: at, Stamp: f[0], Method: f[1], Path: Redact(f[2]), Status: int(status), Duration: uint32(ms)}, nil
}

// IsError reports whether a status counts as an error: 500 to 599.
func IsError(status int) bool { return status >= 500 && status <= 599 }

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

func isPath(s string) bool {
	if !strings.HasPrefix(s, "/") {
		return false
	}
	for _, r := range s {
		if unicode.IsControl(r) || unicode.IsSpace(r) {
			return false
		}
	}
	return true
}

// parseDigits accepts only ASCII digits; strconv alone would also take a sign.
func parseDigits(s string, bits int) (uint64, error) {
	if s == "" {
		return 0, errors.New("empty number")
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return 0, errors.New("not a digit")
		}
	}
	return strconv.ParseUint(s, 10, bits)
}

// CardDigits is the length of a digit run that counts as a card number.
const CardDigits = 16

// Redact replaces every digit of every run of CardDigits or more ASCII digits
// with '*'. A longer run is masked whole, since it contains a card number.
func Redact(s string) string {
	b := []byte(s)
	for i := 0; i < len(b); {
		j := i
		for j < len(b) && b[j] >= '0' && b[j] <= '9' {
			j++
		}
		if j-i >= CardDigits {
			for k := i; k < j; k++ {
				b[k] = '*'
			}
		}
		i = max(j, i+1)
	}
	return string(b)
}
