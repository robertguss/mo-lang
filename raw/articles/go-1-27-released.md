---
source_url: https://go.dev/blog/go1.27
ingested: 2026-09-12
sha256: 27234131afab95bc1d07edc0d26be97ad5a281b5ae65b6eb967c10b706ac04da
---
# Go 1.27 is released - The Go Programming Language

Go 1.27 is released - The Go Programming Language

# Go 1.27 is released

 Nicholas Husin, on behalf of the Go team 19 August 2026 

Today the Go team is pleased to release Go 1.27. You can find its binary archives and installers on the download page.

Go 1.27 brings major enhancements across the language, toolchain, runtime, and standard library. Below are some of the key highlights.

## Language changes

Go 1.27 introduces three notable updates to the language specification.

First, generic methods are now supported. For example, see `math/rand/v2.Rand`:

```go
// Prior to Go 1.27, a separate method on Rand had to be added for each type
// (unsigned integer methods omitted for brevity).
func (r *Rand) Int32N(n int32) int32
func (r *Rand) Int64N(n int64) int64
func (r *Rand) IntN(n int) int

// Go 1.27 adds a new generic method that works for all integer types.
func (r *Rand) N[Int intType](n Int) Int

```

Second, a key in a struct literal may now be any valid field selector for the struct type, allowing fields in nested or embedded structs to be initialized directly:

```go
type Habitat struct {
    Burrow string
}

type Gopher struct {
    Name    string
    Habitat // Embedded struct.
}

// Go 1.27 allows using Burrow as a key directly.
g := Gopher{
    Name:   "Gopher",
    Burrow: "Burrow #42",
}

```

Finally, function type inference has been generalized to apply in all assignment contexts. Generic functions can now be used without explicit type arguments in composite literals, type conversions, and channel sends:

```go
func GenericFormatter[T any](v T) string {
    return fmt.Sprintf("value: %v", v)
}

type IntFormatter func(int) string

// Go 1.27 infers T = int in composite literals, conversions, and channel sends.
formatters := []IntFormatter{GenericFormatter}
fn := IntFormatter(GenericFormatter)
ch := make(chan IntFormatter, 1)
ch <- GenericFormatter

```

## Tool improvements

- `go fix` includes several new modernizers: `atomictypes`, `embedlit`, `slicesbackward`, and `unsafefuncs`.
- `go doc` now supports `package@version` queries such as `go doc example.com/pkg@v1.2.3`.
- `go mod tidy` now automatically consolidates multiple `require` blocks in `go.mod` into a standard direct and indirect two-block structure.

## Performance and runtime

- Size-specialized memory allocation reduces small object (<80B) allocation costs by up to 30%, improving overall performance by ~1% for allocation-heavy programs.
- The `goroutineleak` profile in `runtime/pprof` is now generally available, allowing automatic detection of permanently blocked goroutines.

## Standard library additions

- `encoding/json/v2` provides high-level JSON processing with configurable options and stricter defaults, alongside `encoding/json/jsontext` for low-level streaming. The existing `encoding/json` package is now backed by the v2 implementation for faster unmarshaling while maintaining backwards compatibility.
- `crypto/mldsa` implements the post-quantum ML-DSA signature scheme (FIPS 204), integrated into `crypto/x509` and `crypto/tls`.
- `uuid` provides native support for generating and parsing UUIDs.
- `simd` and architecture-specific `simd/archsimd` provide experimental SIMD support.
- `net/http/httptest` adds `NewTestServer`, providing an in-memory fake network suitable for use with the `testing/synctest` package.

Please read the Go 1.27 release notes for the complete list of changes and details.

Over the next few weeks, follow-up blog posts will cover some of the topics relevant to Go 1.27 in more detail. Check back later to read those posts.

Thanks to everyone who contributed to this release by writing code, filing bugs, trying out experimental additions, and testing release candidates. As always, if you notice any problems, please file an issue.

We hope you enjoy using Go 1.27!
