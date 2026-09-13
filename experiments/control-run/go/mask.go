package main

// cardDigits is how many consecutive digits make a card number.
const cardDigits = 16

// maskCardNumbers replaces each digit of every run of cardDigits or more
// consecutive ASCII digits in s with '*'. Longer runs are masked whole so
// no 16-digit window of them survives.
func maskCardNumbers(s string) string {
	b := []byte(s)
	start := -1
	for i := 0; i <= len(b); i++ {
		if i < len(b) && isDigit(b[i]) {
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

func isDigit(c byte) bool {
	return c >= '0' && c <= '9'
}
