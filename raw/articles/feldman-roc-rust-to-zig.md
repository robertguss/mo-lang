---
source_url: https://rtfeldman.com/rust-to-zig
ingested: 2026-09-12
sha256: e3773fe2fde9c059c02d2c8cdd26b5b05195a04e658f8a6f63b96e6414fbcd80
---
# How Our Rust-to-Zig Rewrite is Going

How Our Rust-to-Zig Rewrite is Going

# How Our Rust-to-Zig Rewrite is Going

 July 15, 2026 

For the past year and a half, the team building Roc's compiler has been rewriting our 300,000 lines of Rust code into Zig, for reasons I'll recap below. We recently passed an exciting milestone: feature parity with the original compiler!

Since the Bun project recently shared an experience report of their rewrite in the other direction (from Zig to Rust, although that's only the tip of the iceberg of differences between our rewrites), this seems like a nice time to reflect on how our move from Rust to Zig is going.

## Passing Feature Parity

Hitting this milestone made it possible to update Brendan Hansknecht's charming 2024 WASM-4 game, Rocci Bird (with art by Luke DeVault) to use the new compiler. It's a nice example because the whole game is under a thousand lines of Roc code, and you can play it on itch.io or right here via WebAssembly:

Click or tap the game, then press Space (or tap) to flap. On mobile you don't have a right arrow key, so refresh the page to restart the game.

Rocci Bird's updated source code is a bit more concise than the original, and `roc build --opt=size` now outputs a 31KB wasm binary. (The original compiler produced a binary more than double that size.) Rocci Bird is by no means a large code base, but getting it to run at all required landing a lot of features in the new compiler. Seeing those chunky purple pixels brought a smile to my face when we finally got there!

To be clear, this is a milestone but not a formal release. (We aim to land version 0.1.0 later this year.) That said, it's a wonderful milestone to have reached, and I'm extremely grateful to all the people who came together to make this happen! I want to thank some in particular who have been especially helpful in getting the language and compiler to this point:

- Anthony Bullard and Sam Mohr for collaborating on the new parser
- Jared Ramirez for the new type-checker (among many other things!)
- Ayaz Hafiz for the new lambda set resolution system, plus tons of the original compiler
- Aurélien Geron for hand-updating 108 (!) beginner exercises in the Roc Exercism course he originally created
- Stephan for getting the compiler's new "echo" platform running in the browser, so that anyone can now write and run basic Roc programs from the roc-lang.org homepage via a 2.5MB WebAssembly binary!
- Niclas Åhdén, Roc's most prolific production user, for patiently filing helpful bug reports and giving actionable feedback about the upgrade process
- JRI98 for methodically reproducing and investigating fuzzer errors and other bugs, closing out issues that no longer reproduced, and more
- Jasper Woudenberg for iterating on API designs for userspace packages using the new compiler
- Folkert de Vries, Brendan Hansknecht, Brian Carroll, Josh Warner, Agus Zubiaga, and Jelle Teeuwissen for building the foundation of the original compiler, without which the new compiler never would have existed
- I've saved the undisputed biggest contributors to the new compiler for last: Anton-4 and Luke Boswell for so many things I can't even keep track of them all—compiler work, builtins, platforms, packages, examples, fixing bugs, helping beginners on Roc Zulip…enumerating it all could take up a whole second post! It's been incredible seeing how much you've built.

Thank you all so much! I feel honored that you've put so much of your valuable time into this project. Also thanks to our past and present sponsors— rwx, Lambda Class, ohne-makler, martian, tweede golf, Vendr, NoRedInk, and many generous individual sponsors—who have helped get us to this point by supporting our contributors.

Speaking of time: our 487-day rewrite took 476 days longer than Bun's 11-day rewrite from their ~500K lines of Zig into Rust. There are many reasons for this difference which have nothing to do with Rust or Zig, including the fact that theirs was a direct port whereas we'd decided to rewrite because of how much we were going to change. The techniques they used wouldn't have worked in our case.

The laundry list of changes we made also means comparing our original Rust code base and new Zig code base won't be apples-to-apples. Still, we've reached a nice point to reflect on how the rewrite has gone, both in terms of what new features it has unlocked for Roc programmers, as well as how our experiences with Rust and Zig have compared.

Let's get into it!

## Hot Code Loading + Cross-Compiled Binaries

Roc's new compiler automatically does hot code loading during development. For example, I can run `roc server.roc` to start a Web server, then change some of its code while it's running. The next time that server handles a request, it'll automatically be handled using the new code. Here it is in action, both in a server and in a simple 2D game:

Hot loading is standard behavior for interpreted languages like Python, but not so much for high-performance compiled languages like Roc. When I'm ready to deploy, `roc build server.roc` gets me an LLVM-optimized, self-contained binary that I can drop onto a machine and run.

Roc also cross-compiles; building a static binary that runs on Alpine Linux is as simple as `roc build --target=x64musl`, and that command will produce the same output bytes (for the same input source code bytes) when run on a Mac or any other system—which not all compilers guarantee.

## Pattern Matching with String Interpolation

The HTTP request-handling logic from that video looks like this:

```
match (verb, path) {
    ("GET", "/users/${id}/${page}") => match page {
        "" | "profile" => ok(id)
        "settings" => ok(with_default(user_agent, id))
        "posts/${post_id}" => ok("Post ID: ${post_id}")
        _ => not_found
    }

    ("GET", "/users/${id}") => ok(id)

    ("POST", "/posts/new") => created(with_default(…))

    _ => not_found
}
```

This uses several features we introduced in the new compiler. For example, that `"/users/${id}"` syntax is not implemented with parsing template strings at runtime, but rather with a new language feature: string interpolation inside pattern matching.

Not only is this type-safe at compile time, this entire code snippet performs zero heap allocations. I'd expect the typical language that ships with hot code loading to average closer to 1 allocation per line of code here…but Roc is aiming high on ergonomics, type safety, and performance!

You can play around with this syntax on the new roc-lang.org homepage - if you scroll down a bit, there's an WebAssembly build of the compiler right there on the page that you can use to try out the language.

> By the way, if you're interested in a post on the technical details of how we used the new compiler's compile-time execution of pure functions to get HTTP request routing down to zero allocations, let me know on Roc Zulip.

## Why a Scratch-Rewrite?

Unlike Rust, C, and Zig, Roc is not a systems language; it has automatic memory management (using reference counting, both to avoid tracing collector pauses and also for Perceus optimizations and opportunistic mutation like Koka's). Roc would have way more heap allocations if it needed one heap allocation per closure capture (like most non-systems languages do), but our closure captures don't heap-allocate because Roc is the first non-academic language to implement polymorphic defunctionalization through lambda set specialization.

This might sound like a niche optimization, but in a functional language like Roc, defunctionalization turns out to be similar to inlining in that it unlocks a treasure trove of follow-up optimizations. Although this system proved incredibly beneficial to Roc's runtime performance, it also proved incredibly difficult for us to implement correctly. We struggled with nasty bugs in the original implementation, and only after Ayaz Hafiz prototyped a new architecture in OCaml were we able to finally get it right in the new compiler.

Ayaz's prototype showed that the root of our problems was architectural across several compiler phases, and fixing it would require rewriting most of the compiler. This was one reason we decided to rewrite in the first place—that, and several contributors independently mentioning they planned to rewrite various parts of the compiler for other reasons. We realized we were about to rewrite almost all of the compiler anyway, so it made sense to consider a full rewrite as an alternative to the Ship of Theseus approach.

Compilers are unusual in that scratch-rewrites are the norm among successful projects. It's often the only way to self-host, although not all compilers rewrite into their own language; see for example TypeScript's rewrite to Go. My position has always been that Roc's compiler should not self-host, so the idea that someday the benefits of a rewrite might seem to outweigh their notorious costs had frankly never occurred to me.

The more we talked about it, the more sense it made to do what basically every mainstream compiler today has done at some point: rewrite from scratch.

## Why Zig?

Once we'd decided to scratch-rewrite, the next question was whether to choose Rust again. Based on our experiences with both Rust and Zig (we were already using Zig for a bunch of primitives in our standard library), we decided to build the entire compiler in Zig this time.

I enjoy Rust, I've taught a course on it, and I happily use it daily for my work at Zed. Despite what Internet comments might have us believe, it's extremely normal for one language to be the best fit for one project, while a different language turns out to be the best fit for a different project. One size does not actually fit all!

I've talked in depth about our reasons for going with Zig elsewhere— in writing, on podcasts, and so on—and we only seriously considered Rust and Zig, because those were the only systems languages our team knew well enough. The biggest considerations on our minds when deciding between Rust and Zig were:

- Build times. Our `cargo` build times were a major pain point, even for incremental builds, and getting worse as our code base grew. We expected build times in a Zig rewrite to be much faster.
- Memory control. We use a variety of different memory allocators throughout compilation, especially arenas, and struct-of-arrays layouts all over the place. Rust's ecosystem consistently assumes one global allocator, including soa_rs. Zig's whole ecosystem assumes granular allocators, and struct-of-arrays support is standard.
- Ecosystem relevance. Rust's ecosystem is much bigger than Zig's overall…but almost no packages in either ecosystem are relevant to our particular needs. For the niche things we wanted to get off the shelf—such as a faster way to emit LLVM bitcode than wrapping LLVM's C++ library—more of that code existed in Zig than in Rust.
- Memory-unsafety assistance. Rust is designed to isolate memory-unsafe code inside rare `unsafe` blocks, and use things like miri or Valgrind to vet those. Memory-unsafe code wasn't rare for us, though (more on this later) and we ended up with about 1,200 uses of `unsafe` (out of our 300K lines of Rust code; compare to about 40,000 uses of `unsafe` in rust's 3.5M lines, and remember that for compilers which emit machine code, like `roc` and `rustc`, doing memory-unsafe things is a big part of the job). Zig has more features than Rust for making memory-unsafe code work correctly, and that was the area where we wanted the most help.

After a year and a half of rewriting, how did our expectations of Zig's benefits line up with the reality of what we got? And which parts of Rust did we end up missing once we no longer had access to them?

## Life Without Borrow-Checking

Let's start with memory safety. There's a famous 2019 Microsoft presentation that says, on slide 10:

> ~70% of the vulnerabilities addressed through a security update each year continue to be memory safety issues.

The presentation's next slide has a breakdown by type of memory safety issue, which paints the following picture when it comes to Rust and Zig specifically:

- 83.6% of vulnerabilities addressed through a security update in 2018 would have been completely unaffected by the choice of Rust or Zig, because both languages handle all of these scenarios (out-of-bounds reads/write, unsafe casts, uninitialized reads, stack overflows, and non-memory-safety issues) in the same way.
- 16.4% of the vulnerabilities were specifically use-after-free errors. These could have been caught by Zig's `ReleaseSafe` runtime memory-safety checks, or Rust's borrow checker, or the checks Fil-C uses...modern languages have a variety of ways to help catch UAFs, although these CVEs from 2018 would have almost certainly been from C or C++ code instead.

`ReleaseSafe` catches use-after-free errors through runtime checks which panic if the program tries to use freed memory. Compared to Rust's safe subset, Zig's checks are less comprehensive, have a runtime cost, and can panic. That said, Zig with `ReleaseSafe` has worked great in practice for the TigerBeetle database, which recently underwent a legendarily meticulous Jepsen report that found only two safety bugs, neither related to memory safety.

`ReleaseFast` skips these checks in production builds to avoid their overhead, but keeps them in debug builds and tests to catch memory-safety issues during development. If your tests covered every possible real-world code path, `ReleaseFast` would give you the same safety as `ReleaseSafe`, but that level of test coverage is rarely practical; the real question is what slips through the coverage cracks in practice. Bun talked about their struggles with use-after-frees, but other widely-used projects building with `ReleaseFast` have had no CVEs caused by memory unsafety in their Zig code. Ghostty is one, and Zig's compiler itself is another.

> If you want to learn more about these projects, I've recorded in-depth conversations with their creators: Joran Greef on TigerBeetle, Mitchell Hashimoto on Ghostty, and Andrew Kelley on Zig.

Rust code has a different source of memory-safety gaps: the `unsafe` sections that nearly every Rust program has somewhere in its dependencies. Unsafe Rust has all the memory unsafety risk of `ReleaseFast` Zig code, but none of the runtime checks to catch issues during development. The Rust ecosytsem has miri to find bugs in non-FFI `unsafe` code, and Valgrind can help too, but few Rust projects use either. That said, the cultural norm of using `unsafe` rarely, and auditing it extra carefully, has worked out well enough to earn Rust a strong reputation for memory safety in practice.

Of course, Rust memory unsafety errors can and do still slip through the cracks. Deno, a Bun competitor which is written in Rust, has had memory-unsafety CVEs including an out-of-bounds read as well as a use-after-free, both involving the use of Unsafe Rust. Rocket, a Rust Web Framework, has had a use-after-free CVE, and Actix has had a variety of memory-unsafety CVEs from a period when its use of `unsafe` was abnormally high.

When we were deciding between Rust and Zig for the new compiler, we were aware of all of this. We knew Rust had a well-deserved reputation for memory safety, but that memory unsafety could still happen, and we'd experienced all of that firsthand with the original compiler. We also knew we'd be using `unsafe` way more than typical Rust projects, and even though we were already using Valgrind, getting help with innately memory-unsafe code from Zig's additional checks sounded appealing. We wanted the hard stuff to get easier, and we weren't worried about use-after-free issues in a compiler where allocations would be overwhelmingly done in arenas with straightforward lifetimes.

We knew high-profile Zig projects had achieved great performance and memory safety in practice, and we decided to aim for becoming another of those success stories.

## Memory Safety Post-Rewrite

It's easy to theorize about how things will go with a particular technology choice, but where the rubber meets the road is what end users encounter in real-world usage. So how has Zig with `ReleaseFast` worked out for us in practice? How many memory corruption incidents—from use-after-frees or any other cause—have we seen since rewriting our compiler from Rust to Zig?

Here's a breakdown of bug reports in Roc's issue tracker, as classified by Claude Opus 4.8:

| Type of bug in Roc's compiler | Rust | Zig |
| --- | --- | --- |
| Bug where memory corruption occurred | 21 | 10 |
| Bug where no memory corruption occurred | 2,575 | 421 |
| Total | 2,596 | 431 |

You might be wondering how the Rust-based compiler had any memory corruption bugs at all, let alone more than double the total count of the Zig-based one. Is it because of that pesky Unsafe Rust again?

Actually, no. None of those 21 memory corruption bugs occurred in the compiler's logic itself, which is a testament to Rust's borrow-checker working as intended. The reason we had memory corruption bugs in our Rust-based compiler is that it's a compiler.

Compilers emit machine instructions. When a machine executes those instructions, they can cause memory corruption, resulting in memory corruption bug reports from the people who experienced them. Regardless of which process had the bug—the compiler or compiled program—in both cases the processor only did the bad thing because the compiler told it to. And in both cases the fix is the same: the compiler's code must change, since that code was what caused the memory corruption.

Just like every compiler, Roc's has had bugs, and some of those have been miscompilations that led to memory corruption. That said, while 8 of the 10 memory corruption bugs in the Zig-based compiler were also miscompilations, the remaining 2 were in the compiler itself. Both were use-after-free bugs in error reporting, with the same symptom: filenames in error messages (one in `roc check` and the other in `roc bundle`) rendered as useless question-mark-in-diamond characters. Rust's borrow checker would have caught both.

Now let's suppose we had instead chosen Rust for our rewrite, or Zig with `ReleaseSafe`. What would have been the impact in practice, holding all else equal?

| Tooling Choice | Memory-safety impact in practice |
| --- | --- |
| Zig`ReleaseFast` | 2 bug reports: some errors fail to render filenames |
| Zig `ReleaseSafe` | 2 bug reports: some errors panic and don't render |
| Rust's borrow checker | neither of these bug reports |

After 18 months of development, hundreds of total bug reports, and hundreds of thousands of lines of code, my main takeaway from retrospecting on this table is that picking a different row would have made no appreciable difference to the project. So far our choice has gotten us the outcome we'd hoped for.

As I noted earlier, every project has different needs. When Bun rewrote in the opposite direction—from Zig to Rust— their accompanying post noted:

> For Bun, correctly handling the lifetimes of garbage-collected values [from JavaScript] and manually-managed values has been a major source of stability issues - most often small memory leaks and occasionally, crashes. Every memory allocation has to be meticulously reviewed. Where do these bytes get freed? How do we ensure it only gets freed once? Did we check for JavaScript exceptions properly? Is this garbage-collected pointer visible to the conservative stack scanner? Is this garbage collected memory or manually managed memory?

Roc's compiler doesn't have these particular challenges because it doesn't interface with JavaScript or any other tracing garbage collector. For Bun, "use-after-free, double-free, and 'forgot to free'" errors have been "a large percentage of bugs," whereas errors like these have been a small percentage of Roc's bugs. And of course Roc's compiler faces other challenges that Bun doesn't. Different projects have different needs!

In our case, I'm not sure how I could look back at what's actually happened and conclude that what we needed was a bigger investment in tooling to prevent memory safety bugs in the compiler itself. There's a much stronger case that we would benefit from better tooling to catch memory safety bugs in our compiled output, which has always been out of scope for the borrow checker.

## Build Times

We wanted faster builds from Zig. Did we get them?

Well, the good news is that `zig build --watch -fincremental` can rebuild a change to our current ~450K lines of Zig code in about 35 milliseconds. That's even faster than what we were hoping for when we considered Zig's build speed a selling point for the rewrite!

The bad news is that Zig's current stable 0.16.0 release has a bug that breaks `-fincremental` on our code base. The fix already landed, but to get it we'd have to build on a nightly 0.17.0 prerelease build (which has breaking language changes), along with vendoring and upgrading our affected dependencies to 0.17.0. We decided to wait for the next stable release instead.

As of the last commit that had Rust sources in our code base, here's a timing comparison on my Intel desktop machine running Ubuntu 26 for building cold (no cache, but packages downloaded locally) compared to doing an incremental rebuild after making a trivial edit to our parser:

| Roc Compiler Version | LoC | Cold Build | Incremental |
| --- | --- | --- | --- |
| Original on Rust 1.85.0 | 354K | 32.4s | 10.0s |
| Original on Rust 1.97.0 | 354K | 25.4s | 3.4s |
| Rewrite at feature parity on Zig 0.16.0 | 320K | 39.6s | 8.6s |
| Rewrite today on Zig 0.17.0 | 464K | 32.1s | 0.035s |

> Note that our Zig build configuration as of the feature-parity commit was rebuilding rarely-changing artifacts on every build that we later decided to rebuild only on demand. That's why today's cold builds are faster than they were back at 300K LoC, even though our lines of code have increased by ~50% since then.

Rust 1.97 is the current stable release today, and 1.85 was the current stable release 487 days ago (the time our rewrite took to reach to feature parity). So if we'd stayed on Rust for the same duration, we could have seen our incremental build times decrease from 10 seconds to 3.4. That's a big jump! I really appreciate all the hard work that Rust contributors have done to improve build times. Eliminating 2/3 of our incremental build times over 18 months would have been a very welcome change if we'd stayed on Rust, and it's a bigger improvement than I would have anticipated in an 18-month period. Bravo!

As impressive as that improvement is, Zig's 35ms is still way ahead. Not only is it 1/100th the build time of 3.4 seconds, it's also in a different performance category—and that 35ms is on a Zig code base with ~50% more lines of code than the Rust one that got 3.4s. I expect Roc's code base to keep growing, and for this gap to keep growing with it; I've never heard of any initiative on Rust's roadmap comparable to `-fincremental`.

So while our decision to remain on stable 0.16.0 (plus how many of our contributors run Mac laptops with ARM processors; `-fincremental` only works on x86-64 CPUs right now) means we haven't yet reaped the anticipated build-time rewards of choosing Zig for the rewrite, we certainly have something to look forward to in the next stable Zig release!

## Memory Control: Zero-Parse Deserialization

Roc's new on-disk caching system uses a technique I first learned about from Zig's compiler, and which Casey Muratori told me is common practice in game programming. It relies on the happy coincidence that if you're organizing your memory in the way that runs fastest on modern hardware anyway, you can also load it from disk directly into memory and start using it without parsing anything.

Here's how it works:

- All of our compiler data structures are represented as arrays with 32-bit indices over pointers (and often in structure-of-arrays form).
- This not only saves memory and runs faster, it also means our data structures can be written directly to disk without needing to be serialized into a different format first.
- The bigger benefit is that this lets us deserialize them back into memory without parsing the on-disk bytes in any way. We load the bytes into memory, do some relocations to point our existing data structures to the newly-loaded arrays, and we're ready to go.
- This means we deserialize at the speed of loading the bytes from disk into memory—so, actually I/O bound. If those bytes are already in the operating system's disk cache, it means we load cached work from previous builds at roughly the speed of memcpy.

When you run `roc check` twice in a row, the first time it caches all of its outputs on disk using this strategy. The second time, if the input source code files haven't changed, all the parsed/type-checked/etc. data structures jump straight from disk into memory. It's extremely fast. `roc test` similarly caches the outcomes for tests of pure functions (which are deterministic), and all of this is done with file-level granularity, so if you change one file you'll only be paying for redoing work of that file and any others that depend on it.

This zero-parse deserialization strategy only works because we're following this programming without pointers style for all of our compiler data structures. If we instead used pointers everywhere (like almost all compilers do), deserialization couldn't be zero-parse.

This approach has safety risks, however. Similarly to how a pointer in memory can point to the wrong address (e.g. leading to a use-after-free), any index can be used as a lookup into the wrong array at runtime, at which point you end up with whatever random bytes happened to be at that location. Rust's borrow checker is designed to help with pointer lifetimes, but it doesn't attempt to answer the question "which index goes with which array?" because that has never been in scope for its design.

If you know exactly how many of these arrays you need up front, the Rust crate `compact_arena` can help you avoid indexing into the wrong array by generating type tags with a macro. Unfortunately, if you can't know exactly how many you need up front (e.g. because it varies by number of modules, as it does in our use case), this technique doesn't work. That's why `compact_arena` marks `SmallArena::new` as `unsafe`.

Personally I wouldn't label `SmallArena::new` as unsafe. `unsafe` is supposed to mark the parts of your code base that should be audited extra-carefully, and creating an empty arena doesn't need auditing because it can't cause unsafety. Unfortunately, the potentially-unsafe operation is indexing into an array, which comes up constantly. "Audit every part of your code base extra carefully" is not great advice, and neither is "avoid this technique that massively improves performance" when Zig itself has shown that a spotless memory-safety CVE record is achievable while doing exactly this.

Safe Rust is effective in practice because it assumes that the amount of Unsafe Rust in your code base is small and isolated, and that assumption holds for the vast majority of Rust code bases. But if `unsafe` is going to be pervasive, like in our case, the assuption no longer holds, and it starts to sound more appealing to choose a language that's safer than Unsafe Rust.

## Ecosystem Relevance

The Bun post talks about how Rust's `Drop` could help with their unusual JavaScript inetrop challenges:

> [...] other users of Zig don't have the bugs we had, and mixing GC with manually-managed memory is an uncommon enough thing for software to need that no language really designs for it. [...] One common way to reduce this class of issue is to ensure cleanup code is always run exactly once for code that needs it. Zig is designed to be a simple language with no hidden control flow, and so it prefers the explicit `defer` keyword to run code at the end of a scope over C++'s implicit ~Destructor or Rust's implicit `Drop`.

We're in the opposite situation: `Drop` has been a pain point for us because the Rust ecosystem is built around the assumption that everyone is using a global allocator and using `Drop` for implicit deallocation. But we want to be doing almost the reverse: separate arenas for each module and stage of compilation. Zig's ecosystem consistently passes around allocators, which is exactly what we want, whereas off-the-shelf Rust crates almost always assume a single global allocator.

Simply put, Rust's ecosystem is optimized for the way Bun wants to be written, whereas Zig's is designed for the way Roc wants to be written.

Separately, there's the question of what relevant code we can access off the shelf. LLVM is a critical dependency for our optimizer (we do our own optimizations, but LLVM does more on top), but it's also a project that makes major breaking API changes on a regular basis. Upgrading to new LLVM versions has been a major source of pain and lost time for Roc, but we keep doing it because we want the new optimizations.

As it turns out, LLVM actually has a stable and backwards-compatible API that can be accessed to bypass this upgrade pain: its serialized "bitcode" format. If you write your own LLVM bitcode serializer, then you can tell each new version of LLVM to consume that, and you're off to the races.

Of course, to access this strategy, you need a handwritten LLVM bitcode serializer that's decoupled from the LLVM C++ library and its breaking changes. I only know of one implementation of such a thing in the wild: Zig's compiler, which of course is written in Zig. And now there are two implementations in the wild, because Roc's new compiler is reusing that same Zig code. (Thanks for sharing it, Zig team!)

You might have noticed that the biggest source of dependencies we're interested in from the Zig ecosystem is the Zig compiler itself. This is unusual, but Roc is an unusual project with unusual needs. When I wrote the first line of code in the compiler back in 2019, I would not have guessed that the following would prove true: "In the future, the richest gold mine of reusable code for this project will be an open-source compiler written in a language you haven't heard of yet."

Life is full of surprises!

## Things I Miss From Rust

Even though I'm no longer using Rust for Roc, I remain immersed in the Rust world because I work at Zed, where we use it for pretty much everything. So when I say I miss something from Rust when building with Zig (or vice versa), it's not just rose-tinted memories of a distant past; it's more like memories from earlier in the same day.

Something I was surprised to find myself missing from Rust is automatic allocation and deallocation in tests.

As discussed earlier, having full control over allocations and deallocations is what I want in our compiler's implementation. And in tests, I also appreciate the testing allocators detecting leaks—it can even detect leaks in compiled Roc code! Unfortunately, to get that benefit requires a lot of "init this, defer deinit" code in tests that has to be correct or else the test fails on a memory leak. None of that is necessary in Rust. I care more about the compiler's implementation being the way I want it than the tests looking nicer, but in a perfect world I could somehow have both.

Both parametric polymorphism and ad hoc polymorphism overlap with `comptime`, so it makes sense that Zig doesn't have them, but I do miss them. For example, Rust's Allocator trait has its allocate function taking "self" at its first argument, whereas in Zig, allocator implementations like ArenaAllocator need to receive an `anyopaque` pointer and then cast it to itself.

I also miss private struct fields. I understand the reasoning for not having them, but I miss getting a compile error if I use something that is marked as "not supposed to be accessed directly like this, even though it can be done if you really want to." This comes up when reviewing a diff, because in the diff I just see the field access; I don't see the docs on the original struct definition, and I don't want to go out of my way to look them up defensively every time.

Occasionally I miss functions and variables and constants all using `snake_case`.

I do miss aspects of `unsafe` and the borrow checker, even though their upsides come packaged with downside I don't miss. I don't think Zig should add either of these, but at the same time there is something calming about only worrying about certain classes of problems inside `unsafe` blocks. I can miss that feeling even while not wanting to pay the corresponding costs in this project.

I'm not sure how much of this is because of the way `comptime` works, but I certainly find myself being surprised to discover dead code in our Zig code base (which was caught by neither Zig's built-in tooling nor TigerBeetle's tidy.zig—by the way, thanks for open-sourcing that, TigerBeetle team!) more often than I'm used to from Rust. Dead Zig code doesn't affect end users because the compiler doesn't even emit it into the binary, but obviously it would be better for our code base if we discovered it earlier.

Finally, the Rust team does an admirable job with backwards compatibility in their releases. Upgrading to new minor releases barely took any effort, and even edition upgrades were mostly painless. Backwards-compatibility is a non-goal for Zig in its current stage of development, which is something we knew about going in and expected. It hasn't been a big problem for us, but do I miss the trivial upgrade process we had in Rust? Of course!

## Things I Enjoy About Zig

I've always enjoyed the subtractive aspect of functional programming. You'd think that subtracting tools from my toolbox that I'm accustomed to reaching for (e.g. mutation, unrestricted side effects, objects and classes) would be frustrating…but once I got used to the different techniques, I really came to enjoy the new properties I had unlocked (cacheability, non-flaking tests, concurrency niceties, reordering operations with no fear that their outputs might change, etc.) and no longer wanted to give those up.

I have similar feelings about Zig. I like that it doesn't have macros. I may miss ad hoc polymorphism, but at the same time I enjoy how many problems (including parametric polymorphism) can be addressed by comptime and/or an ordinary function.

I love the control over data layouts. It's great having out-the-box access to number types that aren't a power of 2, like u7 and u5, without having to do any bit-level work myself. Packed structs out-the-box, the option to inline functions at the call site instead of the declaration site…these are things you can get from Rust crates using macros, but I really like having them available without needing a separate dependency.

Zig's build toolchain is second to none, which is presumably why Uber uses it even though they don't use Zig the language. Building self-contained binaries for things like Alpine Linux and WebAssembly has gone really well, even though we're doing weird stuff like compiling part of our code base (the "builtins"—Roc's standard library, essentially) into an opaque binary blob and including it in the final executable.

I also really like Zig's error-handling strategy, and especially how failed heap allocations are normal userspace errors. Roc has a similar "errors naturally accumulate" strategy (except using anonymous sum types that can have payloads), and I like both of those strategies better than anyerror, thiserror, or vanilla no-dependency error handling in Rust with Result. (That said, I do prefer Rust's postfix unary ? operator over Zig's `try` keyword, which is why we adopted the postfix unary ? operator in Roc.)

Then of course there's all the project-specific stuff which I mentioned earlier: allocator-based APIs everywhere, an ecosystem of high-performance compiler goodies that we can't find anywhere else, and so on. I won't rehash them all here, but I very much enjoy them in addition to appreciating the benefits they've had to the project.

I've had a very positive experience with Zig all around, and looking back I'm really happy that we chose it for our rewrite!

## What's Next for Roc

We aim to land version 0.1.0 of the new compiler later this year, which will be Roc's first-ever numbered release. You're welcome to try out a Nightly build before then, although in its current state you can still expect a variety of bugs, incomplete features, and unfinished docs. I have a lot of documentation to write between now and then!

By the way, the Roc Programming Language Foundation is a 501(c)(3) nonprofit, so if you'd like to make a donation it will be tax-deductible in the US, and we use donations primarily to compensate contributors. If you know of an organization that would like to sponsor our work, financially or in other ways, please get in touch! (Separately, if you know anyone at GitHub who could get us into GH for Nonprofits, that would be a huge help with our CI backlog.)

Thank you again to everyone who has helped the language reach this milestone. I couldn't be more excited for the next one: our first-ever numbered release! If you'd like to follow along, ask questions, or just come say hi, feel free to come chat with us on Roc Zulip.
