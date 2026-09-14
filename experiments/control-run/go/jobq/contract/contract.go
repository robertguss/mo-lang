// Package contract is Mo's requires, ensures, and invariant as plain checks.
// A failed check returns an error that carries the condition's text; it
// never panics, so a contract on input is an error the caller handles.
package contract

// Violation is a failed contract: which kind, and the condition's text.
type Violation struct {
	Kind string
	Cond string
}

func (v *Violation) Error() string { return v.Kind + " failed: " + v.Cond }

// Require checks a precondition on a function's input.
func Require(ok bool, cond string) error { return check("requires", ok, cond) }

// Ensure checks a postcondition on a function's result.
func Ensure(ok bool, cond string) error { return check("ensures", ok, cond) }

// Invariant checks a property that holds after every operation.
func Invariant(ok bool, cond string) error { return check("invariant", ok, cond) }

func check(kind string, ok bool, cond string) error {
	if ok {
		return nil
	}
	return &Violation{Kind: kind, Cond: cond}
}
