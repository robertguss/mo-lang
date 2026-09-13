package main

// cardDigits is the length of a digit run treated as a card number.
const cardDigits = 16

// MaskCards replaces every run of 16 or more consecutive ASCII digits with
// the same number of '*'. Shorter runs are left alone.
func MaskCards(s string) string {
	b := []byte(s)
	start := -1
	for i := 0; i <= len(b); i++ {
		if i < len(b) && b[i] >= '0' && b[i] <= '9' {
			if start < 0 {
				start = i
			}
			continue
		}
		if start >= 0 && i-start >= cardDigits {
			for j := start; j < i; j++ {
				b[j] = '*'
			}
		}
		start = -1
	}
	return string(b)
}

// HasCard reports whether s still contains a run of 16 or more digits.
func HasCard(s string) bool {
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
