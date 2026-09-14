package contract

import (
	"errors"
	"testing"
)

func TestChecksPassAndFailWithConditionText(t *testing.T) {
	cases := []struct {
		name  string
		check func(bool, string) error
		kind  string
	}{
		{"Require", Require, "requires"},
		{"Ensure", Ensure, "ensures"},
		{"Invariant", Invariant, "invariant"},
		{"Never", func(ok bool, c string) error { return Never(!ok, c) }, "never"},
	}
	for _, c := range cases {
		if err := c.check(true, "x > 0"); err != nil {
			t.Errorf("%s(true) = %v, want nil", c.name, err)
		}
		err := c.check(false, "x > 0")
		var v *Violation
		if !errors.As(err, &v) || v.Kind != c.kind || v.Cond != "x > 0" {
			t.Fatalf("%s(false) = %#v", c.name, err)
		}
		if got, want := err.Error(), c.kind+" failed: x > 0"; got != want {
			t.Errorf("%s message = %q, want %q", c.name, got, want)
		}
	}
}
