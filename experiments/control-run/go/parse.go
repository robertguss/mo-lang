package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// Record is one well-formed log line. Path and AtText are already masked, so
// a card number never gets past parsing.
type Record struct {
	At       time.Time
	AtText   string
	Method   string
	Path     string
	Status   int
	Duration uint32
}

// ErrMalformed is wrapped by every parse failure.
var ErrMalformed = errors.New("malformed line")

const (
	minStatus    = 100
	maxStatus    = 599
	maxMethodLen = 16
	fieldCount   = 5
)

func malformed(reason string) error { return fmt.Errorf("%w: %s", ErrMalformed, reason) }

// ParseLine parses one line without its newline; a trailing CR is dropped.
//
// Contract: it returns a Record with 100 <= Status <= 599 and a Duration that
// fits uint32, or an error wrapping ErrMalformed. Nothing else.
func ParseLine(line string) (Record, error) {
	line = strings.TrimSuffix(line, "\r")
	if !utf8.ValidString(line) {
		return Record{}, malformed("not UTF-8")
	}
	fields := strings.Split(line, " ")
	if len(fields) != fieldCount {
		return Record{}, malformed("want 5 fields separated by single spaces")
	}
	at, err := time.Parse(time.RFC3339, fields[0])
	if err != nil {
		return Record{}, malformed("bad timestamp")
	}
	if !validMethod(fields[1]) {
		return Record{}, malformed("bad method")
	}
	if !validPath(fields[2]) {
		return Record{}, malformed("bad path")
	}
	status, err := parseStatus(fields[3])
	if err != nil {
		return Record{}, err
	}
	duration, err := parseDuration(fields[4])
	if err != nil {
		return Record{}, err
	}
	return Record{
		At:       at,
		AtText:   MaskCards(fields[0]),
		Method:   fields[1],
		Path:     MaskCards(fields[2]),
		Status:   status,
		Duration: duration,
	}, nil
}

// validMethod accepts 1 to 16 uppercase ASCII letters.
func validMethod(s string) bool {
	if s == "" || len(s) > maxMethodLen {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 'A' || s[i] > 'Z' {
			return false
		}
	}
	return true
}

// validPath accepts a string starting with '/' and holding no control characters.
func validPath(s string) bool {
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

// parseStatus requires exactly three digits in 100..599.
func parseStatus(s string) (int, error) {
	if len(s) != 3 || !allDigits(s) {
		return 0, malformed("status is not three digits")
	}
	n, err := strconv.Atoi(s)
	if err != nil {
		return 0, malformed("status is not a number")
	}
	if n < minStatus || n > maxStatus {
		return 0, malformed("status outside 100..599")
	}
	return n, nil
}

// parseDuration requires plain digits whose value fits uint32.
func parseDuration(s string) (uint32, error) {
	if s == "" || !allDigits(s) {
		return 0, malformed("duration is not a whole number")
	}
	n, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return 0, malformed("duration does not fit UInt32")
	}
	return uint32(n), nil
}

func allDigits(s string) bool {
	for i := 0; i < len(s); i++ {
		if !isDigit(s[i]) {
			return false
		}
	}
	return true
}
