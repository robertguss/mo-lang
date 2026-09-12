# Corpus gaps

Each line names a missing or conflicting rule and the default used; these are open decisions, not additions to Mo.

- `basics/numbers.mo`: Numeric method signatures and the float type name are not specified; use the brief's named arithmetic, `Option(UInt32)` for checked addition, and provisional `Float64` at a declared boundary.
- `basics/strings.mo`: The result type of `bytes` is unspecified; use a byte sequence with `.size` rather than invent a byte-count API.
- All `.mo` files: The toolchain currently documents unimplemented stages; examples are source fixtures checked against the draft, not claimed compiled or executed.
