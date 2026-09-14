package main

// cardDigits is the length of a digit run treated as a card number.
const cardDigits = 16

// MaskCards replaces every run of 16 or more consecutive ASCII digits with
// the same number of '*'. Runs longer than 16 are masked whole, so no card
// number hides inside a longer run.
func MaskCards(s string) string {
	if !HasCard(s) {
		return s
	}
	b := []byte(s)
	run := 0
	for i := 0; i <= len(b); i++ {
		if i < len(b) && isDigit(b[i]) {
			run++
			continue
		}
		if run >= cardDigits {
			for j := i - run; j < i; j++ {
				b[j] = '*'
			}
		}
		run = 0
	}
	return string(b)
}

// HasCard reports whether s holds a run of 16 or more consecutive digits.
func HasCard(s string) bool {
	run := 0
	for i := 0; i < len(s); i++ {
		if !isDigit(s[i]) {
			run = 0
			continue
		}
		run++
		if run >= cardDigits {
			return true
		}
	}
	return false
}

func isDigit(c byte) bool { return c >= '0' && c <= '9' }
