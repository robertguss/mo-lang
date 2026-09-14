package main

import "testing"

func TestMaskCards(t *testing.T) {
	cases := []struct{ in, want string }{
		{"/api/users", "/api/users"},
		{"/orders/17", "/orders/17"},
		{"/c/4111111111111111/charge", "/c/****************/charge"},
		{"/c/411111111111111/charge", "/c/411111111111111/charge"},
		{"/c/41111111111111112", "/c/*****************"},
		{"4111111111111111", "****************"},
		{"/a/4111111111111111/b/5500000000000004", "/a/****************/b/****************"},
		{"/ü/4111111111111111", "/ü/****************"},
	}
	for _, c := range cases {
		if got := MaskCards(c.in); got != c.want {
			t.Errorf("MaskCards(%q) = %q, want %q", c.in, got, c.want)
		}
		if HasCard(MaskCards(c.in)) {
			t.Errorf("MaskCards(%q) still holds a card number", c.in)
		}
	}
}

func TestHasCard(t *testing.T) {
	if !HasCard("x4111111111111111") {
		t.Error("16 digits not seen")
	}
	if HasCard("411111111111111-1") {
		t.Error("15 digits and a dash seen as a card")
	}
}
