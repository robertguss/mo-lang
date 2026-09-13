package main

import (
	"strings"
	"testing"
)

func TestMaskCards(t *testing.T) {
	stars := func(n int) string { return strings.Repeat("*", n) }
	cases := map[string]string{
		"/api/cards/4111111111111111/charge": "/api/cards/" + stars(16) + "/charge",
		"/a/411111111111111/b":               "/a/411111111111111/b", // 15 digits stay
		"/a/41111111111111112":               "/a/" + stars(17),      // 17 digits masked
		"4111111111111111-5500000000000004":  stars(16) + "-" + stars(16),
		"/orders/17":                         "/orders/17",
	}
	for in, want := range cases {
		if got := MaskCards(in); got != want {
			t.Errorf("MaskCards(%q) = %q, want %q", in, got, want)
		}
		if HasCard(MaskCards(in)) {
			t.Errorf("HasCard after masking %q", in)
		}
	}
	if !HasCard("x4111111111111111") || HasCard("411111111111111") {
		t.Error("HasCard boundary wrong")
	}
}
