package main

import (
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
	"unicode/utf8"
)

// Record is one well-formed log line. Its Path and AtText are already
// masked: a card number never lives in a Record.
type Record struct {
	At     time.Time
	AtText string
	Method string
	Path   string
	Status uint16
	Ms     uint32
}

// ErrMalformed wraps every reason a line does not fit the format.
var ErrMalformed = errors.New("malformed line")

const cardDigits = 16

func malformed(format string, args ...any) error {
	return fmt.Errorf("%w: %s", ErrMalformed, fmt.Sprintf(format, args...))
}

// ParseLine requires a line of exactly five single-space-separated fields:
// an RFC 3339 timestamp, an upper-case method, a path starting with '/',
// a three-digit status in 100..599, and a duration that fits a uint32.
// Anything else is ErrMalformed.
func ParseLine(line string) (Record, error) {
	if !utf8.ValidString(line) {
		return Record{}, malformed("not valid UTF-8")
	}
	fields := strings.Split(line, " ")
	if len(fields) != 5 {
		return Record{}, malformed("want 5 fields, got %d", len(fields))
	}
	return parseFields(fields)
}

func parseFields(f []string) (Record, error) {
	at, err := parseTimestamp(f[0])
	if err != nil {
		return Record{}, err
	}
	status, err := parseStatus(f[3])
	if err != nil {
		return Record{}, err
	}
	ms, err := parseDuration(f[4])
	if err != nil {
		return Record{}, err
	}
	if err := checkMethod(f[1]); err != nil {
		return Record{}, err
	}
	if err := checkPath(f[2]); err != nil {
		return Record{}, err
	}
	return Record{At: at, AtText: MaskCards(f[0]), Method: f[1], Path: MaskCards(f[2]), Status: status, Ms: ms}, nil
}

// ParseTimestamp reads the RFC 3339 profile of ISO-8601, the one the
// format's example uses. It is shared by lines and --since.
func ParseTimestamp(s string) (time.Time, error) {
	return time.Parse(time.RFC3339, s)
}

func parseTimestamp(s string) (time.Time, error) {
	t, err := ParseTimestamp(s)
	if err != nil {
		return time.Time{}, malformed("bad timestamp")
	}
	return t, nil
}

func parseStatus(s string) (uint16, error) {
	if len(s) != 3 {
		return 0, malformed("status must be three digits")
	}
	n, err := strconv.ParseUint(s, 10, 16)
	if err != nil || n < 100 || n > 599 {
		return 0, malformed("status outside 100..599")
	}
	return uint16(n), nil
}

func parseDuration(s string) (uint32, error) {
	n, err := strconv.ParseUint(s, 10, 32)
	if err != nil {
		return 0, malformed("duration is not a uint32")
	}
	return uint32(n), nil
}

func checkMethod(s string) error {
	if s == "" {
		return malformed("empty method")
	}
	for i := 0; i < len(s); i++ {
		if s[i] < 'A' || s[i] > 'Z' {
			return malformed("method must be upper-case letters")
		}
	}
	return nil
}

func checkPath(s string) error {
	if !strings.HasPrefix(s, "/") {
		return malformed("path must start with /")
	}
	for _, r := range s {
		if r < 0x20 || r == 0x7f {
			return malformed("control character in path")
		}
	}
	return nil
}

// MaskCards replaces every run of 16 or more ASCII digits with '*', one
// per digit, so a card number never reaches output.
func MaskCards(s string) string {
	if !ContainsCard(s) {
		return s
	}
	b := []byte(s)
	forEachCardRun(s, func(start, end int) {
		for i := start; i < end; i++ {
			b[i] = '*'
		}
	})
	return string(b)
}

// ContainsCard reports whether s holds a run of 16 or more ASCII digits.
func ContainsCard(s string) bool {
	found := false
	forEachCardRun(s, func(int, int) { found = true })
	return found
}

func forEachCardRun(s string, visit func(start, end int)) {
	start := -1
	for i := 0; i <= len(s); i++ {
		digit := i < len(s) && s[i] >= '0' && s[i] <= '9'
		if digit && start < 0 {
			start = i
		}
		if !digit && start >= 0 {
			if i-start >= cardDigits {
				visit(start, i)
			}
			start = -1
		}
	}
}
