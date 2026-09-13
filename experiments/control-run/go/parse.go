package main

import (
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"
)

// Record is one well-formed log line. Path already has card numbers masked.
type Record struct {
	At       time.Time
	Method   string
	Path     string
	Status   int
	Duration uint32
}

// MalformedError says why a line is not a log line. The reason never
// quotes the line, so a card number cannot leak through it.
type MalformedError struct {
	Reason string
}

func (e *MalformedError) Error() string {
	return "malformed line: " + e.Reason
}

func malformed(format string, args ...any) error {
	return &MalformedError{Reason: fmt.Sprintf(format, args...)}
}

const (
	minStatus = 100
	maxStatus = 599
)

// parseLine turns one line, without its line ending, into a Record or a
// *MalformedError.
//
//	requires: the line is valid UTF-8
//	requires: exactly five fields separated by single spaces
//	requires: the timestamp is RFC 3339
//	requires: the method is one or more ASCII capital letters
//	requires: the path starts with '/' and has no control characters
//	requires: the status is decimal digits in 100..599
//	requires: the duration is decimal digits that fit uint32
func parseLine(line string) (Record, error) {
	if !utf8.ValidString(line) {
		return Record{}, malformed("not UTF-8")
	}
	fields := strings.Split(line, " ")
	if len(fields) != 5 {
		return Record{}, malformed("%d fields, want 5", len(fields))
	}
	at, err := parseTimestamp(fields[0])
	if err != nil {
		return Record{}, err
	}
	if err := checkMethod(fields[1]); err != nil {
		return Record{}, err
	}
	if err := checkPath(fields[2]); err != nil {
		return Record{}, err
	}
	status, err := parseStatus(fields[3])
	if err != nil {
		return Record{}, err
	}
	duration, err := parseDuration(fields[4])
	if err != nil {
		return Record{}, err
	}
	return Record{At: at, Method: fields[1], Path: maskCardNumbers(fields[2]), Status: status, Duration: duration}, nil
}

// parseTimestamp reads an RFC 3339 timestamp, the ISO-8601 profile logstat
// accepts both in log lines and in --since.
func parseTimestamp(s string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return time.Time{}, malformed("timestamp is not RFC 3339")
	}
	return t, nil
}

func checkMethod(s string) error {
	if s == "" {
		return malformed("empty method")
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 'A' || s[i] > 'Z' {
			return malformed("method is not ASCII capital letters")
		}
	}
	return nil
}

func checkPath(s string) error {
	if !strings.HasPrefix(s, "/") {
		return malformed("path does not start with /")
	}
	for _, r := range s {
		if unicode.IsControl(r) {
			return malformed("path has a control character")
		}
	}
	return nil
}

func parseStatus(s string) (int, error) {
	n, err := strconv.ParseUint(s, 10, 16)
	if err != nil {
		return 0, malformed("status is not a number")
	}
	if n < minStatus || n > maxStatus {
		return 0, malformed("status %d outside %d..%d", n, minStatus, maxStatus)
	}
	return int(n), nil
}

func parseDuration(s string) (uint32, error) {
	n, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return 0, malformed("duration is not a uint32")
	}
	return uint32(n), nil
}
