package contract

import (
	"errors"
	"testing"
)

func TestHoldingContractsReturnNil(t *testing.T) {
	for name, err := range map[string]error{
		"require":   Require(true, "x"),
		"ensure":    Ensure(true, "x"),
		"invariant": Invariant(true, "x"),
	} {
		if err != nil {
			t.Errorf("%s(true) = %v, want nil", name, err)
		}
	}
}

func TestFailedContractsCarryKindAndText(t *testing.T) {
	cases := []struct {
		err  error
		want string
	}{
		{Require(false, "n >= 1"), "requires failed: n >= 1"},
		{Ensure(false, "r.Status <= 599"), "ensures failed: r.Status <= 599"},
		{Invariant(false, "errors <= requests"), "invariant failed: errors <= requests"},
	}
	for _, c := range cases {
		var v *Violation
		if !errors.As(c.err, &v) {
			t.Fatalf("%v is not a *Violation", c.err)
		}
		if c.err.Error() != c.want {
			t.Errorf("got %q, want %q", c.err.Error(), c.want)
		}
	}
}
