---
source_url: https://go.dev/blog/go1.18
ingested: 2026-09-12
sha256: e37f19ba4b3ece57fee85e179cf0b96f1521e16df76cd6add76f001db4a9f045
---
# Go 1.18 is released! - The Go Programming Language

Go 1.18 is released! - The Go Programming Language

# Go 1.18 is released!

 The Go Team 15 March 2022 

Today the Go team is thrilled to release Go 1.18, which you can get by visiting the download page.

Go 1.18 is a massive release that includes new features, performance improvements, and our biggest change ever to the language. It isn’t a stretch to say that the design for parts of Go 1.18 started over a decade ago when we first released Go.

## Generics

In Go 1.18, we’re introducing new support for generic code using parameterized types. Supporting generics has been Go’s most often requested feature, and we’re proud to deliver the generic support that the majority of users need today. Subsequent releases will provide additional support for some of the more complicated generic use cases. We encourage you to get to know this new feature using our generics tutorial, and to explore the best ways to use generics to optimize and simplify your code today. The release notes have more details about using generics in Go 1.18.

## Fuzzing

With Go 1.18, Go is the first major language with fuzzing fully integrated into its standard toolchain. Like generics, fuzzing has been in design for a long time, and we’re delighted to share it with the Go ecosystem with this release. Please check out our fuzzing tutorial to help you get started with this new feature.

## Workspaces

Go modules have been almost universally adopted, and Go users have reported very high satisfaction scores in our annual surveys. In our 2021 user survey, the most common challenge users identified with modules was working across multiple modules. In Go 1.18, we’ve addressed this with a new Go workspace mode, which makes it simple to work with multiple modules.

## 20% Performance Improvements

Apple M1, ARM64, and PowerPC64 users rejoice! Go 1.18 includes CPU performance improvements of up to 20% due to the expansion of Go 1.17’s register ABI calling convention to these architectures. Just to underscore how big this release is, a 20% performance improvement is the fourth most important headline!

For a more detailed description of everything that’s in 1.18, please consult the release notes.

Go 1.18 is a huge milestone for the entire Go community. We want to thank every Go user who filed a bug, sent in a change, wrote a tutorial, or helped in any way to make Go 1.18 a reality. We couldn’t do it without you. Thank you.

Enjoy Go 1.18!
