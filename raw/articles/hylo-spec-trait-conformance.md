---
source_url: https://github.com/hylo-lang/specification/blob/main/spec.md
ingested: 2026-09-12
sha256: 9d2ac02eb2498d865d10afea8969b9333bd76159909fdb3aabf19c21fc76aaa0
---
# Hylo Language Specification — Trait conformance (section excerpt)

### Trait conformance

1. A type `A` *conforms to* a trait `T1` in a lexical scope if a conformance of `A` to `T1` is exposed to that scope and if `T1` and satisfies all the requirements of `T1`, or if `A` conforms to a trait `T2` such that `T2` refines `T1`.

2. (Example)

    ```hylo
    trait T { fun foo() }
    trait U { fun bar() }

    // declares conformance to 'T'
    type A: T {}

    // satisfies conformance to 'T'
    extension A {
      fun foo() {}
    }

    // declares and satisfies conformance to 'U'
    conformance A: U {
      public fun bar() {}
    }
    ```

3. A *source* of conformance denotes a declaration defining the conformance of a type to a trait. A type or conformance declaration is a source of conformance for all the traits that appear in its inheritance list. A source of conformance is conditional if it is a conformance declaration with a where clause. A type may have at most one source of conformance to a specific trait. A type that conforms to a trait `T1` shall not have a source of conformance to a trait `T2` if `T2` refines `T1` and the source of conformance to `T1` is conditional.

4. The conformance of a type `A` to `T` is *exposed* to a lexical scope `l` if and only if `A` is exposed to `l` and the source of the conformance is:

 1. the declaration of `A`; or

 2. a conformance declaration declared in `l` or a lexical scope that contains `l`; or

 3. an external conformance declaration imported from another module.

5. The conformance of a type `A` to a trait `T` shall not be exposed outside of the lexical scope of a module `m` unless at least `A` or `T` is declared in `m`.

6. (Example)

    ```hylo
    import M

    public type A {}
    conformance A: M.T {} // OK: conformance is private

    type B: M.T {}        // OK: 'B' is not exposed outside of the module

    public type C: M.T {} // error: cannot expose conformance to imported trait 'M.T'
    ```

7. A method requirement `r` is satisfied if by a type `A` if `A` has a single method `m` with the same name, type, and kind. `m` may be defined in the type declaration, extension declaration, or a conformance declaration of `A`. If `r` has default implementations, it may be satisfied by `A` if there exists a unique default implementation whose conditions are satisfied by `A`.

