---
source_url: https://go.googlesource.com/proposal/+/HEAD/design/43651-type-parameters.md
ingested: 2026-09-12
sha256: 6a3a1953aa9c7ee51242a5bfa3615aefe3619c1eb9710534190f30f9ed17fcc8
---
# Type Parameters Proposal

Type Parameters Proposal

# Type Parameters Proposal

Ian Lance TaylorRobert GriesemerAugust 20, 2021

## Status

This is the design for adding generic programming using type parameters to the Go language. This design has been proposed and accepted as a future language change. We currently expect that this change will be available in the Go 1.18 release in early 2022.

## Abstract

We suggest extending the Go language to add optional type parameters to type and function declarations. Type parameters are constrained by interface types. Interface types, when used as type constraints, support embedding additional elements that may be used to limit the set of types that satisfy the constraint. Parameterized types and functions may use operators with type parameters, but only when permitted by all types that satisfy the parameter's constraint. Type inference via a unification algorithm permits omitting type arguments from function calls in many cases. The design is fully backward compatible with Go 1.

## How to read this proposal

This document is long. Here is some guidance on how to read it.

- We start with a high level overview, describing the concepts very briefly.
- We then explain the full design starting from scratch, introducing the details as we need them, with simple examples.
- After the design is completely described, we discuss implementation, some issues with the design, and a comparison with other approaches to generics.
- We then present several complete examples of how this design would be used in practice.
- Following the examples some minor details are discussed in an appendix.

## Very high level overview

This section explains the changes suggested by the design very briefly. This section is intended for people who are already familiar with how generics would work in a language like Go. These concepts will be explained in detail in the following sections.

Interface types used as type constraints can embed additional elements to restrict the set of type arguments that satisfy the contraint:

- an arbitrary type`T` restricts to that type
- an approximation element`~T` restricts to all types whose underlying type is`T`
- a union element`T1 | T2 | ...` restricts to any of the listed elements

In the following sections we work through each of these language changes in great detail. You may prefer to skip ahead to the examples to see what generic code written to this design will look like in practice.

## Background

There have been many requests to add additional support for generic programming in Go. There has been extensive discussion on the issue tracker and on a living document.

This design suggests extending the Go language to add a form of parametric polymorphism, where the type parameters are bounded not by a declared subtyping relationship (as in some object oriented languages) but by explicitly defined structural constraints.

This version of the design has many similarities to a design draft presented on July 31, 2019, but contracts have been removed and replaced by interface types, and the syntax has changed.

There have been several proposals for adding type parameters, which can be found through the links above. Many of the ideas presented here have appeared before. The main new features described here are the syntax and the careful examination of interface types as constraints.

This design does not support template metaprogramming or any other form of compile time programming.

As the term generic is widely used in the Go community, we will use it below as a shorthand to mean a function or type that takes type parameters. Don't confuse the term generic as used in this design with the same term in other languages like C++, C#, Java, or Rust; they have similarities but are not the same.

## Design

We will describe the complete design in stages based on simple examples.

### Type parameters

Generic code is written using abstract data types that we call type parameters. When running the generic code, the type parameters are replaced by type arguments.

Here is a function that prints out each element of a slice, where the element type of the slice, here called`T`, is unknown. This is a trivial example of the kind of function we want to permit in order to support generic programming. (Later we'll also discuss generic types).

```
// Print prints the elements of a slice.
// It should be possible to call this with any slice value.
func Print(s []T) { // Just an example, not the suggested syntax.
	for _, v := range s {
		fmt.Println(v)
	}
}

```

With this approach, the first decision to make is: how should the type parameter`T` be declared? In a language like Go, we expect every identifier to be declared in some way.

Here we make a design decision: type parameters are similar to ordinary non-type function parameters, and as such should be listed along with other parameters. However, type parameters are not the same as non-type parameters, so although they appear in the list of parameters we want to distinguish them. That leads to our next design decision: we define an additional optional parameter list describing type parameters.

This type parameter list appears before the regular parameters. To distinguish the type parameter list from the regular parameter list, the type parameter list uses square brackets rather than parentheses. Just as regular parameters have types, type parameters have meta-types, also known as constraints. We will discuss the details of constraints later; for now, we will just note that`any` is a valid constraint, meaning that any type is permitted.

```
// Print prints the elements of any slice.
// Print has a type parameter T and has a single (non-type)
// parameter s which is a slice of that type parameter.
func Print[T any](s []T) {
	// same as above
}

```

This says that within the function`Print` the identifier`T` is a type parameter, a type that is currently unknown but that will be known when the function is called. The`any` means that`T` can be any type at all. As seen above, the type parameter may be used as a type when describing the types of the ordinary non-type parameters. It may also be used as a type within the body of the function.

Unlike regular parameter lists, in type parameter lists names are required for the type parameters. This avoids a syntactic ambiguity, and, as it happens, there is no reason to ever omit the type parameter names.

Since`Print` has a type parameter, any call of`Print` must provide a type argument. Later we will see how this type argument can usually be deduced from the non-type argument, by using type inference. For now, we'll pass the type argument explicitly. Type arguments are passed much like type parameters are declared: as a separate list of arguments. As with the type parameter list, the list of type arguments uses square brackets.

```
	// Call Print with a []int.
	// Print has a type parameter T, and we want to pass a []int,
	// so we pass a type argument of int by writing Print[int].
	// The function Print[int] expects a []int as an argument.
	Print[int]([]int{1, 2, 3})

	// This will print:
	// 1
	// 2
	// 3

```

### Constraints

Let‘s make our example slightly more complicated. Let’s turn it into a function that converts a slice of any type into a`[]string` by calling a`String` method on each element.

```
// This function is INVALID.
func Stringify[T any](s []T) (ret []string) {
	for _, v := range s {
		ret = append(ret, v.String()) // INVALID
	}
	return ret
}

```

This might seem OK at first glance, but in this example`v` has type`T`, and`T` can be any type. This means that`T` need not have a`String` method. So the call to`v.String()` is invalid.

Naturally, the same issue arises in other languages that support generic programming. In C++, for example, a generic function (in C++ terms, a function template) can call any method on a value of generic type. That is, in the C++ approach, calling`v.String()` is fine. If the function is called with a type argument that does not have a`String` method, the error is reported when compiling the call to`v.String` with that type argument. These errors can be lengthy, as there may be several layers of generic function calls before the error occurs, all of which must be reported to understand what went wrong.

The C++ approach would be a poor choice for Go. One reason is the style of the language. In Go we don't refer to names, such as, in this case,`String`, and hope that they exist. Go resolves all names to their declarations when they are seen.

Another reason is that Go is designed to support programming at scale. We must consider the case in which the generic function definition (`Stringify`, above) and the call to the generic function (not shown, but perhaps in some other package) are far apart. In general, all generic code expects the type arguments to meet certain requirements. We refer to these requirements as constraints (other languages have similar ideas known as type bounds or trait bounds or concepts). In this case, the constraint is pretty obvious: the type has to have a`String() string` method. In other cases it may be much less obvious.

We don‘t want to derive the constraints from whatever`Stringify` happens to do (in this case, call the`String` method). If we did, a minor change to`Stringify` might change the constraints. That would mean that a minor change could cause code far away, that calls the function, to unexpectedly break. It’s fine for`Stringify` to deliberately change its constraints, and force callers to change. What we want to avoid is`Stringify` changing its constraints accidentally.

This means that the constraints must set limits on both the type arguments passed by the caller and the code in the generic function. The caller may only pass type arguments that satisfy the constraints. The generic function may only use those values in ways that are permitted by the constraints. This is an important rule that we believe should apply to any attempt to define generic programming in Go: generic code can only use operations that its type arguments are known to implement.

### Operations permitted for any type

Before we discuss constraints further, let's briefly note what happens when the constraint is`any`. If a generic function uses the`any` constraint for a type parameter, as is the case for the`Print` method above, then any type argument is permitted for that parameter. The only operations that the generic function can use with values of that type parameter are those operations that are permitted for values of any type. In the example above, the`Print` function declares a variable`v` whose type is the type parameter`T`, and it passes that variable to a function.

The operations permitted for any type are:

- Type inference permits omitting the type arguments of a function call in common cases.
- declare variables of those types
- assign other values of the same type to those variables
- pass those variables to functions or return them from functions
- take the address of those variables
- convert or assign values of those types to the type`interface{}`
- convert a value of type`T` to type`T`(permitted but useless)
- use a type assertion to convert an interface value to the type
- use the type as a case in a type switch
- define and use composite types that use those types, such as a slice of that type
- pass the type to some predeclared functions such as`new`

It's possible that future language changes will add other such operations, though none are currently anticipated.

### Defining constraints

Go already has a construct that is close to what we need for a constraint: an interface type. An interface type is a set of methods. The only values that can be assigned to a variable of interface type are those whose types implement the same methods. The only operations that can be done with a value of interface type, other than operations permitted for any type, are to call the methods.

Calling a generic function with a type argument is similar to assigning to a variable of interface type: the type argument must implement the constraints of the type parameter. Writing a generic function is like using values of interface type: the generic code can only use the operations permitted by the constraint (or operations that are permitted for any type).

Therefore, in this design, constraints are simply interface types. Satisfying a constraint means implementing the interface type. (Later we'll restate this in order to define constraints for operations other than method calls, such as binary operators).

For the`Stringify` example, we need an interface type with a`String` method that takes no arguments and returns a value of type`string`.

```
// Stringer is a type constraint that requires the type argument to have
// a String method and permits the generic function to call String.
// The String method should return a string representation of the value.
type Stringer interface {
	String() string
}

```

(It doesn‘t matter for this discussion, but this defines the same interface as the standard library’s`fmt.Stringer` type, and real code would likely simply use`fmt.Stringer`.)

### The any constraint

Now that we know that constraints are simply interface types, we can explain what`any` means as a constraint. As shown above, the`any` constraint permits any type as a type argument and only permits the function to use the operations permitted for any type. The interface type for that is the empty interface:`interface{}`. So we could write the`Print` example as

```
// Print prints the elements of any slice.
// Print has a type parameter T and has a single (non-type)
// parameter s which is a slice of that type parameter.
func Print[T interface{}](s []T) {
	// same as above
}

```

However, it‘s tedious to have to write`interface{}` every time you write a generic function that doesn’t impose constraints on its type parameters. So in this design we suggest a type constraint`any` that is equivalent to`interface{}`. This will be a predeclared name, implicitly declared in the universe block. It will not be valid to use`any` as anything other than a type constraint.

(Note: clearly we could make`any` generally available as an alias for`interface{}`, or as a new defined type defined as`interface{}`. However, we don't want this design, which is about generics, to lead to a possibly significant change to non-generic code. Adding`any` as a general purpose name for`interface{}` can and should be discussed separately).

### Using a constraint

For a generic function, a constraint can be thought of as the type of the type argument: a meta-type. As shown above, constraints appear in the type parameter list as the meta-type of a type parameter.

```
// Stringify calls the String method on each element of s,
// and returns the results.
func Stringify[T Stringer](s []T) (ret []string) {
	for _, v := range s {
		ret = append(ret, v.String())
	}
	return ret
}

```

The single type parameter`T` is followed by the constraint that applies to`T`, in this case`Stringer`.

### Multiple type parameters

Although the`Stringify` example uses only a single type parameter, functions may have multiple type parameters.

```
// Print2 has two type parameters and two non-type parameters.
func Print2[T1, T2 any](s1 []T1, s2 []T2) { ... }

```

Compare this to

```
// Print2Same has one type parameter and two non-type parameters.
func Print2Same[T any](s1 []T, s2 []T) { ... }

```

In`Print2``s1` and`s2` may be slices of different types. In`Print2Same``s1` and`s2` must be slices of the same element type.

Just as each ordinary parameter may have its own type, each type parameter may have its own constraint.

```
// Stringer is a type constraint that requires a String method.
// The String method should return a string representation of the value.
type Stringer interface {
	String() string
}

// Plusser is a type constraint that requires a Plus method.
// The Plus method is expected to add the argument to an internal
// string and return the result.
type Plusser interface {
	Plus(string) string
}

// ConcatTo takes a slice of elements with a String method and a slice
// of elements with a Plus method. The slices should have the same
// number of elements. This will convert each element of s to a string,
// pass it to the Plus method of the corresponding element of p,
// and return a slice of the resulting strings.
func ConcatTo[S Stringer, P Plusser](s []S, p []P) []string {
	r := make([]string, len(s))
	for i, v := range s {
		r[i] = p[i].Plus(v.String())
	}
	return r
}

```

A single constraint can be used for multiple type parameters, just as a single type can be used for multiple non-type function parameters. The constraint applies to each type parameter separately.

```
// Stringify2 converts two slices of different types to strings,
// and returns the concatenation of all the strings.
func Stringify2[T1, T2 Stringer](s1 []T1, s2 []T2) string {
	r := ""
	for _, v1 := range s1 {
		r += v1.String()
	}
	for _, v2 := range s2 {
		r += v2.String()
	}
	return r
}

```

### Generic types

We want more than just generic functions: we also want generic types. We suggest that types be extended to take type parameters.

```
// Vector is a name for a slice of any element type.
type Vector[T any] []T

```

A type‘s type parameters are just like a function’s type parameters.

Within the type definition, the type parameters may be used like any other type.

To use a generic type, you must supply type arguments. This is called instantiation. The type arguments appear in square brackets, as usual. When we instantiate a type by supplying type arguments for the type parameters, we produce a type in which each use of a type parameter in the type definition is replaced by the corresponding type argument.

```
// v is a Vector of int values.
//
// This is similar to pretending that "Vector[int]" is a valid identifier,
// and writing
//   type "Vector[int]" []int
//   var v "Vector[int]"
// All uses of Vector[int] will refer to the same "Vector[int]" type.
//
var v Vector[int]

```

Generic types can have methods. The receiver type of a method must declare the same number of type parameters as are declared in the receiver type's definition. They are declared without any constraint.

```
// Push adds a value to the end of a vector.
func (v *Vector[T]) Push(x T) { *v = append(*v, x) }

```

The type parameters listed in a method declaration need not have the same names as the type parameters in the type declaration. In particular, if they are not used by the method, they can be`_`.

A generic type can refer to itself in cases where a type can ordinarily refer to itself, but when it does so the type arguments must be the type parameters, listed in the same order. This restriction prevents infinite recursion of type instantiation.

```
// List is a linked list of values of type T.
type List[T any] struct {
	next *List[T] // this reference to List[T] is OK
	val  T
}

// This type is INVALID.
type P[T1, T2 any] struct {
	F *P[T2, T1] // INVALID; must be [T1, T2]
}

```

This restriction applies to both direct and indirect references.

```
// ListHead is the head of a linked list.
type ListHead[T any] struct {
	head *ListElement[T]
}

// ListElement is an element in a linked list with a head.
// Each element points back to the head.
type ListElement[T any] struct {
	next *ListElement[T]
	val  T
	// Using ListHead[T] here is OK.
	// ListHead[T] refers to ListElement[T] refers to ListHead[T].
	// Using ListHead[int] would not be OK, as ListHead[T]
	// would have an indirect reference to ListHead[int].
	head *ListHead[T]
}

```

(Note: with more understanding of how people want to write code, it may be possible to relax this rule to permit some cases that use different type arguments.)

The type parameter of a generic type may have constraints other than`any`.

```
// StringableVector is a slice of some type, where t
