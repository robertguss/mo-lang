---
source_url: https://go.dev/doc/go1compat
ingested: 2026-09-12
sha256: 834f579ae2cbbac13e3de0010fb09c023c30532867c2741491cc609c98d019d0
---
# Go 1 and the Future of Go Programs - The Go Programming Language

Go 1 and the Future of Go Programs - The Go Programming Language

1. Documentation
2. Go 1 and the Future of Go Programs

# Go 1 and the Future of Go Programs

## Introduction

The release of Go version 1, Go 1 for short, is a major milestone in the development of the language. Go 1 is a stable platform for the growth of programs and projects written in Go.

Go 1 defines two things: first, the specification of the language; and second, the specification of a set of core APIs, the "standard packages" of the Go library. The Go 1 release includes their implementation in the form of two compiler suites (gc and gccgo), and the core libraries themselves.

It is intended that programs written to the Go 1 specification will continue to compile and run correctly, unchanged, over the lifetime of that specification. At some indefinite point, a Go 2 specification may arise, but until that time, Go programs that work today should continue to work even as future "point" releases of Go 1 arise (Go 1.1, Go 1.2, etc.).

Compatibility is at the source level. Binary compatibility for compiled packages is not guaranteed between releases. After a point release, Go source will need to be recompiled to link against the new release.

The APIs may grow, acquiring new packages and features, but not in a way that breaks existing Go 1 code.

## Expectations

Although we expect that the vast majority of programs will maintain this compatibility over time, it is impossible to guarantee that no future change will break any program. This document is an attempt to set expectations for the compatibility of Go 1 software in the future. There are a number of ways in which a program that compiles and runs today may fail to do so after a future point release. They are all unlikely but worth recording.

- Security. A security issue in the specification or implementation may come to light whose resolution requires breaking compatibility. We reserve the right to address such security issues.
- Unspecified behavior. The Go specification tries to be explicit about most properties of the language, but there are some aspects that are undefined. Programs that depend on such unspecified behavior may break in future releases.
- Specification errors. If it becomes necessary to address an inconsistency or incompleteness in the specification, resolving the issue could affect the meaning or legality of existing programs. We reserve the right to address such issues, including updating the implementations. Except for security issues, no incompatible changes to the specification would be made.
- Bugs. If a compiler or library has a bug that violates the specification, a program that depends on the buggy behavior may break if the bug is fixed. We reserve the right to fix such bugs.
- Struct literals. For the addition of features in later point releases, it may be necessary to add fields to exported structs in the API. Code that uses unkeyed struct literals (such as pkg.T{3, "x"}) to create values of these types would fail to compile after such a change. However, code that uses keyed literals (pkg.T{A: 3, B: "x"}) will continue to compile after such a change. We will update such data structures in a way that allows keyed struct literals to remain compatible, although unkeyed literals may fail to compile. (There are also more intricate cases involving nested data structures or interfaces, but they have the same resolution.) We therefore recommend that composite literals whose type is defined in a separate package should use the keyed notation.
- Methods. As with struct fields, it may be necessary to add methods to non-interface types. Under some circumstances, such as when the type is embedded in a struct along with another type, the addition of the new method may break the struct by creating a conflict with an existing method of the other embedded type. We cannot protect against this rare case and do not guarantee compatibility should it arise.
- Dot imports. If a program imports a standard package using`import . "path"`, additional names defined in the imported package in future releases may conflict with other names defined in the program. We do not recommend the use of`import .` outside of tests, and using it may cause a program to fail to compile in future releases.
- Use of package`unsafe`. Packages that import unsafe may depend on internal properties of the Go implementation. We reserve the right to make changes to the implementation that may break such programs.

Of course, for all of these possibilities, should they arise, we would endeavor whenever feasible to update the specification, compilers, or libraries without affecting existing code.

These same considerations apply to successive point releases. For instance, code that runs under Go 1.2 should be compatible with Go 1.2.1, Go 1.3, Go 1.4, etc., although not necessarily with Go 1.1 since it may use features added only in Go 1.2

Features added between releases, available in the source repository but not part of the numbered binary releases, are under active development. No promise of compatibility is made for software using such features until they have been released.

Finally, although it is not a correctness issue, it is possible that the performance of a program may be affected by changes in the implementation of the compilers or libraries upon which it depends. No guarantee can be made about the performance of a given program between releases.

Although these expectations apply to Go 1 itself, we hope similar considerations would be made for the development of externally developed software based on Go 1.

## Sub-repositories

Code in sub-repositories of the main go tree, such as golang.org/x/net, may be developed under looser compatibility requirements. However, the sub-repositories will be tagged as appropriate to identify versions that are compatible with the Go 1 point releases.

## Operating systems

It is impossible to guarantee long-term compatibility with operating system interfaces, which are changed by outside parties. The syscall package is therefore outside the purview of the guarantees made here. As of Go version 1.4, the`syscall` package is frozen. Any evolution of the system call interface must be supported elsewhere, such as in the go.sys subrepository. For details and background, see this document.

## Tools

Finally, the Go toolchain (compilers, linkers, build tools, and so on) is under active development and may change behavior. This means, for instance, that scripts that depend on the location and properties of the tools may be broken by a point release.

These caveats aside, we believe that Go 1 will be a firm foundation for the development of Go and its ecosystem.
