# docs/

Design artifacts, in the order they will appear:

1. `design-v0.md` — the Mo design document, v0. A ~15-page narrative: philosophy, laws, semantics, syntax, with the refund example as the running thread. (Part D, step 1)
2. `grammar.md` — the formal grammar, small enough to print on two pages. (Part D, step 4)
3. `laws.md` — the compiler-enforced laws with their numbers.
4. `diagnostics/` — the error catalog: one entry per code (`MO0412`), with `what`, `why`, and fix templates. Per Q9, this is where the language teaches its philosophy.

`programs/`: the spec altitude of each program on the menu, written for a worker to implement without further design help.
