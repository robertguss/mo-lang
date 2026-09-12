---
source_url: https://bitemyapp.com/blog/moonbit-developers-are-lying-to-you/
ingested: 2026-09-12
sha256: 2c2ccca50d3185b3e3ec72f07043b8918398665b4760ec0d29c20e2233ab6336
---
# Chris Allen -  Moonbit developers are lying to you

Chris Allen - Moonbit developers are lying to you 

# Moonbit developers are lying to you 

 Posted: 2025-09-14 

The Moonbit team recently published a blog post claiming their language runs "30% faster than Rust" for FFT workloads. This is a lie by omission. They benchmarked against a deliberately crippled Rust implementation that no competent programmer would write.

- The Moonbit FFT benchmark used a crippled Rust baseline and used to claim their language was faster than Rust.
- My corrected Rust implementation is 3.2–3.4× faster than Moonbit on the same benchmark.
- In 5 minutes of prompting GPT-5, I produced a Rust version already 2.33× faster than Moonbit.
- Zero PRs merged or replied to by the team at time of writing. There are PRs fixing the Rust benchmark older than their tweet announcing Moonbit was faster than Rust.
- Moonbit devs are programming language developers that have marketed their language aggressively on the basis of performance for awhile now, they know better than this.
- Moonbit should retract or clearly amend their blog post with corrected Rust baseline results. Including the qualification that their benchmark is a naive Cooley-Tukey FFT benchmark and nothing else.

Note: edited on 2025-09-15 to add context about unmerged fixes and official claims.

References:

- Discussion and updates on my Twitter/X: @theodorvaryag
- My PR fixing the Rust implementation: github.com/moonbit-community/benchmark-fft/pull/15
- Moonbit post that cites numbers from the broken Rust baseline: moonbitlang.com/blog/moonbit-value-type
- Open PRs fixing the Rust baseline (unmerged for ~2 weeks): github.com/moonbit-community/benchmark-fft/pulls
- Official Moonbit tweet claiming “30% faster than Rust” (Sep 4): x.com/moonbitlang/status/1963580305102836099

### What the benchmark is

This is a straightforward iterative Cooley–Tukey FFT over a `Complex` struct with `real` and `imag` fields. There's nothing exotic here: it's the kind of benchmark where idiomatic Rust should do very well.

### What was wrong with the Rust baseline

The Rust version Moonbit used in their comparisons was knee‑capped. Concretely:

- Non‑TCO'd recursion, causing unnecessary call overhead.
- Allocating new `Vec` s at every recursion step. This explodes allocations and trashes cache locality.
- No in-place or buffer-reuse strategy for the butterfly stages.
- Missed obvious bound-check factoring opportunities; no build guidance (e.g., `-C target-cpu=native`) to let LLVM auto-vectorize the tight loops.

Reusing buffers/allocations is something I have to do in otherwise ordinary Java web applications and APIs. This isn't fancy, advanced, or specific to Rust in any way.

### What prompted this post (timeline and unmerged fixes)

As of mid‑September 2025, there are multiple PRs open for roughly two weeks that fix the Rust baseline, with no replies or merges:

- A two-line change swapping `Vec` for `SmallVec` that improves Rust performance by >50%: see PRs list and item titled “perf: improve rust performance by >50% with just two lines using SmallVec.”
- Additional fixes like arena allocation and iterative implementations that remove unnecessary allocations and recursion.
- My own PR demonstrates Rust is 3.2–3.4× faster on the same benchmark when implemented idiomatically.

Despite these available fixes, the official Moonbit account continued to promote “30% faster than Rust” on Sep 4. See the open PRs here: https://github.com/moonbit-community/benchmark-fft/pulls and the claim here: https://x.com/moonbitlang/status/1963580305102836099.

### What I changed

In my PR I:

- Switched to an iterative Cooley–Tukey approach with buffer reuse to avoid per-stage reallocation.
- Structured loops to factor out bound checks so LLVM can see and vectorize the hot paths.
- Verified numerics against `rustfft` to confirm correctness of the iterative implementation.
- Documented that enabling `-C target-cpu=native` improves auto‑vectorization further.
- For completeness (not for the "fairness" suite), I showed a Rayon build that is ~2–2.6× faster than single-threaded Rust. The rayon-parallelized version is about 6× faster than Moonbit, but I excluded it from the direct comparison because I didn't want to compare multithreaded Rust to single-threaded Moonbit.

See the PR and discussion: github.com/moonbit-community/benchmark-fft/pull/15

The benchmark is a straightforward Cooley–Tukey FFT over a `Complex { real, imag }` type. Fixing the obviously suboptimal Rust baseline flips the story completely:

- Moonbit: baseline
- Their original, crippled Rust: ≈30% slower (as claimed)
- Correct Rust: 3.2–3.4× faster than Moonbit's baseline

That gap is not noise; it’s the difference between a fair comparison and a misrepresentation.

### Why this matters

Publishing language marketing posts that rely on an unfair and unrealistic baseline undermines trust. The benchmark in question is simple enough that a competent Rust baseline is trivial to produce. Using a recursively allocating implementation as the "Rust" side of a performance comparison is not credible.

Moonbit's blog post cites numbers derived from this broken baseline and makes a very broad claim on that basis. Those numbers do not reflect the typical performance characteristics of Rust on this task and should not be used to draw conclusions about relative performance.

Even a perfect FFT benchmark isn't a justifiable basis for a broad claim about the runtime performance of two programming languages. It's a single benchmark, for pete's sake.

### You shouldn't trust Moonbit

One of the main developers behind Moonbit is Hongbo Zhang, the author of Bucklescript. This is an experienced programming language developer. Moonbit has been aggressively marketed on the basis of performance prior to this recent FFT benchmark. They haven't replied to nor merged any of the GitHub PRs fixing the performance of the benchmarks to be more representative over the last two weeks. They found time to post about it on social media and their website though. This is not honest or conscientious behavior.

Software performance is difficult to analyze and refine even when your baseline comparison is the same application in the same programming language. Cross-programming language comparisons require extreme care and a high priority placed on what is actually representative of what a developer working in that application domain would be likely to do. It often requires fanning out across different angles on the same solution space for each programming language. For example, it doesn't necessarily make sense to compare a non-allocating Rust application with an allocating Golang application. If it's possible to write a non-allocating Golang version why not comparing allocating and non-allocating variants for Rust and Golang each? Yeah, probably the Golang version is more likely to be written in the allocating-style in the wild, but it's worth knowing how they'd compare anyway. Sometimes Golang is faster in micro-benchmarks because the GC doesn't bother freeing any memory!

Every benchmark Moonbit developers publish should be regarded as suspect. They have similarly specious claims that they've published in the past but this was the first one that hit on a domain that I know very well and that got flagged up to me on Twitter. Every performance claim should be independently verified. Every comparison should be assumed to be rigged given the fact pattern. I work on perf engineering and evaluation in my professional roles regularly.

### Benchmark fairness and comparison fidelity

I want to note that I was very conscious of not making the Rust implementation dissimilar to the other implementations.

- I deliberately did not include multithreading (Rayon) in the head-to-head because the original suite wasn't multithreaded for Moonbit. If Moonbit wants to compare parallel implementations, great. Let's make that a separate, clearly-labeled variant and compare like-for-like.
- I verified my iterative Cooley–Tukey implementation numerically against `rustfft` for peace of mind.
- Flags like `-C target-cpu=native` are standard for serious local performance measurements and simply let LLVM use the hardware available; this isn't "cheating," it's the norm. If you want cross‑machine comparability, pin the flags and specify them in the write‑up.

Again: the core issue is not that Rust "wins"; it's that the original Rust baseline was obviously broken, and Moonbit's post relied on it. Fix the baseline, fix the conclusions.

### Check my work

Run the benchmarks from the PRs (not just mine!) yourself. See the difference. Judge for yourself.

### Take-away

When someone shows you benchmark results that seem too good to be true, they probably are. When a new language claims to beat established, heavily-optimized languages by significant margins, check their work.

And when you catch someone lying with benchmarks, call them out. Software developers deserve better than this.

> I know this blog is a bit of a mess, but if you like my content and would like to learn more Haskell you should check out the Haskell Book!

 2011-2021 Chris Allen (license/info). Site generated with Zola. Source is hosted at Gitlab.
