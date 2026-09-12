---
source_url: https://blog.rust-lang.org/2026/08/20/Rust-1.98.0/
ingested: 2026-09-12
sha256: 16c350c41f47b985e51129d186187ad64776043d120d39b989f75c7237e54a43
---
# Announcing Rust 1.98.0 | Rust Blog

Announcing Rust 1.98.0 | Rust Blog

## Announcing Rust 1.98.0

Aug. 20, 2026 · The Rust Release Team 

The Rust team is happy to announce a new version of Rust, 1.98.0. Rust is a programming language empowering everyone to build reliable and efficient software.

If you have a previous version of Rust installed via `rustup`, you can get 1.98.0 with:

```
$ rustup update stable
```

If you don't have it already, you can get `rustup` from the appropriate page on our website, and check out the detailed release notes for 1.98.0.

If you'd like to help us out by testing future releases, you might consider updating locally to use the beta channel (`rustup default beta`) or the nightly channel (`rustup default nightly`). Please report any bugs you might come across!

### Algebraic floating-point methods

The floating-point types `f32` and `f64` now have "algebraic" methods for addition, subtraction, multiplication, division, and remainder. These allow optimizations on these operations using the algebraic properties of real numbers, even though these properties do not hold with the limitations of floating-point representations. The exact set of optimizations is not specified, but may be similar to the kind of optimization you would see with the `-ffast-math` option in other languages.

For example, floating-point addition is not associative, so a sum like `a + b + c + d` must be evaluated in the left-associative order in which it is parsed, like `((a + b) + c) + d`. If you write the same sum as a chain of `algebraic_add` calls, then the compiler is free to reorder it, perhaps like `(a + b) + (c + d)` to evaluate the partial sums simultaneously. Broader loop-vectorization is often enabled by using these algebraic methods as well.

These methods are non-deterministic, since the compiler is free to choose different optimizations, but they never cause undefined behavior. See the library documentation and the original API change proposal for more details.

### Buffered integer formatting

All of the primitive integer types now have a `format_into` method that takes a `&mut NumBuffer ` parameter, which is a buffer that is large enough to hold the decimal format of any value of that type. The buffer itself is opaque, but the method returns the formatted `&str` with a lifetime borrowed from that buffer.

This method also bypasses much of the dynamic dispatch that you would get with buffered `write!` formatting, which can be a boon to performance. The `itoa-benchmark` repo now shows that `format_into` performs similarly to `itoa` itself, so this could serve as a standard replacement for that dependency and others like it.

### Fix interaction between `ManuallyDrop` and `Box`

Prior to Rust 1.96.0, there was a bug in the Rust compiler, which made the following code undefined behavior:

```
let mut x = ManuallyDrop::new(Box::new(1));
unsafe { ManuallyDrop::drop(&mut x) }
let x = x; // UB!
```

This is because the compiler considers it undefined behavior to move a `Box` that has been dropped (deallocated), and `ManuallyDrop` used to propagate that, such that moving `ManuallyDrop<Box<_>>` where the box has been dropped would also be considered UB.

In Rust 1.96.0 we fixed this, so this code was no longer UB. In this release we have updated the `ManuallyDrop` documentation, providing a stable guarantee that this code will continue to not be UB in the future. See `ManuallyDrop` docs and the related RFC 3336 for more information.

### Stabilized APIs

- `str::substr_range`
- `[T]::subslice_range`
- `core::fmt::NumBuffer`
- `<{integer}>::format_into`
- `Send/Sync for std::process::CommandArgs`
- `{fN}::algebraic_add`
- `{fN}::algebraic_sub`
- `{fN}::algebraic_mul`
- `{fN}::algebraic_div`
- `{fN}::algebraic_rem`
- `NonZero<{integer}>::from_str_radix`
- `String::from_utf16le`
- `String::from_utf16le_lossy`
- `String::from_utf16be`
- `String::from_utf16be_lossy`
- `[T]::strip_circumfix`
- `str::strip_circumfix`
- `Atomic::from_mut`
- `Atomic::get_mut_slice`
- `Atomic::from_mut_slice`
- `std::range::legacy`

Many people came together to create Rust 1.98.0. We couldn't have done it without all of you. Thanks!
