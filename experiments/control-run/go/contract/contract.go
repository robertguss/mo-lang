// Package contract checks requires, ensures, and invariants. A failed
// check returns an error that carries the condition's text; it never panics.
package contract

// Violation is a failed contract: which kind, and the condition as written.
type Violation struct {
	Kind string
	Cond string
}

func (v *Violation) Error() string { return v.Kind + " failed: " + v.Cond }

func check(kind string, ok bool, cond string) error {
	if ok {
		return nil
	}
	return &Violation{Kind: kind, Cond: cond}
}

// Require checks a precondition.
func Require(ok bool, cond string) error { return check("requires", ok, cond) }

// Ensure checks a postcondition.
func Ensure(ok bool, cond string) error { return check("ensures", ok, cond) }

// Invariant checks a property that holds after every operation.
func Invariant(ok bool, cond string) error { return check("invariant", ok, cond) }

// Never fails when the thing that must never happen did.
func Never(happened bool, cond string) error { return check("never", !happened, cond) }
