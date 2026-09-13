package main

import "testing"

func TestMaskCardNumbers(t *testing.T) {
	cases := []struct{ in, want string }{
		{"/api/users", "/api/users"},
		{"/cards/4111111111111111", "/cards/****************"},
		{"4111111111111111/x", "****************/x"},
		{"/n/411111111111111", "/n/411111111111111"},
		{"/n/41111111111111112", "/n/*****************"},
		{"/a/4111111111111111/b/5500000000000004", "/a/****************/b/****************"},
		{"/a/4111-1111-1111-1111", "/a/4111-1111-1111-1111"},
		{"", ""},
	}
	for _, c := range cases {
		if got := maskCardNumbers(c.in); got != c.want {
			t.Errorf("maskCardNumbers(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}
