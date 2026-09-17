---
title: "Agents and verification: the 2025-2026 evidence"
created: 2026-09-13
updated: 2026-09-17
type: concept
tags: [research, verification, contracts]
sources: [raw/research-runs/2026-09-13-papers-llm-facing.pplx.md]
confidence: high
---

# Agents and verification: the 2025-2026 evidence

What the recent literature measures when LLMs are asked to write contracts, invariants, proofs, and the tests that guard them. Every number below is from the linked page.

## The verifier decides the outcome, not the model

Vericoding means generating formally verified code from a formal specification, as opposed to prose. The benchmark holds 12,504 specifications and reports, verbatim: "We find vericoding success rates of 27% in Lean, 44% in Verus/Rust and 82% in Dafny using off-the-shelf LLMs" ([arXiv:2509.22908](https://arxiv.org/abs/2509.22908)).

An independent benchmark holds the specification fixed across 77 classical algorithms and reproduces the ordering: 40.3% Dafny for Gemini-3 Flash, 24.7% Verus, 7.8% Lean, with iterative repair tripling Dafny pass rates ([arXiv:2602.09464](https://arxiv.org/abs/2602.09464)).

| Verifier style | Best reported success | Source |
|---|---|---|
| SMT-automated (Dafny) | 82% / 40.3% | [2509.22908](https://arxiv.org/abs/2509.22908), [2602.09464](https://arxiv.org/abs/2602.09464) |
| Systems + ownership (Verus) | 44% / 24.7% | same two |
| Interactive proof (Lean) | 27% / 7.8% | same two |

Judgment: this is the empirical case for Mo keeping SMT-shaped contracts inside `mo check` and pushing interactive proving into a separate tool.

## Specification, not proof, is the bottleneck

A benchmark that scores code, spec, and proof separately reports for its best model: "72.6% code correctness rate, 52.3% for specification soundness and completeness, and a mere 4.9% proof success rate (based on one trial per task)" over 189 Lean tasks ([arXiv:2505.23135](https://arxiv.org/abs/2505.23135)).

Specification failures have a shape. On 581 Verus spec-writing tasks, generated specs omit input assumptions, accept incorrect outputs, or reject valid ones; the best model reaches 77.8%, open models 21.5-25.5%, and an LLM judge misses 26% of the failures ([arXiv:2605.26457](https://arxiv.org/abs/2605.26457)).

The sharpest number: five open code LLMs pass 75-82% of functional tests while satisfying 0% of the implicit input contracts, rising only to 23-41% when contracts are stated in the prompt ([arXiv:2510.12047](https://arxiv.org/abs/2510.12047)).

Judgment: functional correctness carries almost no information about contract compliance, so the guard has to be a language rule rather than a prompt.

## Local success does not compose

Frontier models exceed 99% syntactic well-formedness and above 58% end-to-end verification on single-function Dafny benchmarks, but reach near-zero on 400 compositional programs of 2-5 dependent functions, attributed to specification fragility, implementation-proof misalignment, and reasoning instability ([ICLR 2026](https://iclr.cc/virtual/2026/poster/10006597)).

Repository context is the same problem seen from the tooling side. Dependency-aware retrieval reaches 51.0% on repository-level Verus tasks against 4.5% for multi-round prompting, and produced upstream-accepted proofs for 23 previously unverified functions in a Rust OS memory module ([arXiv:2605.03822](https://arxiv.org/abs/2605.03822)). A 500-obligation Lean benchmark finds curated dependency-closure context beats exposing the whole repository ([arXiv:2602.18307](https://arxiv.org/abs/2602.18307)).

Judgment: Mo's many-small-functions laws walk straight into the composition frontier. The unit of context to hand an agent is the dependency closure of a declaration, not a file.

## Loops beat one-shot generation

- Agentic co-evolution of code, invariants and proofs solves 74% of Verina and 62% of Clever tasks ([arXiv:2603.29088](https://arxiv.org/abs/2603.29088)), against 4.9% proof success one-shot a year earlier ([arXiv:2505.23135](https://arxiv.org/abs/2505.23135)).
- Verifier-guided repair reaches 92.7% on DafnyBench, 6.5 points above the strongest prior baseline ([arXiv:2606.32007](https://arxiv.org/abs/2606.32007)).
- Planning program and proof together adds 4.6-11.2 points over the stronger baseline while cutting API cost by up to about 40% ([arXiv:2608.09277](https://arxiv.org/abs/2608.09277)).
- A reasoning model plus Z3 covered 133 of 133 loop-invariant tasks with 1-2 proposals and 14-55 seconds per instance ([arXiv:2508.00419](https://arxiv.org/abs/2508.00419)).
- Proof generation for Rust reached "more than 90%" of 150 tasks, half in under 30 seconds or 3 LLM calls ([arXiv:2409.13082](https://arxiv.org/abs/2409.13082)).

Judgment: the invariant result weakens the verification argument for banning `while`. The legibility argument stands on its own.

17 Sep 2026: ruled **agree** on 13 Sep ([[research-agenda-2026-09-response]]), and round 5 ran.

## Diagnostics are a measurable interface

An eBPF study reproduced 235 verifier rejections and found "47% of rejections return only EINVAL, one error string maps to as many as nine distinct root causes." Replacing the raw log with a reconstructed, Rust-styled localization improved LLM repair by 11-21 percentage points on a 75-task benchmark where models scored 0-37% one-shot ([arXiv:2607.02748](https://arxiv.org/abs/2607.02748)).

A PL-side ablation reports "concrete evidence that more detailed error messages improve an agent's ability to fix type errors," and that a type system helps more than test-suite failures alone ([arXiv:2606.01522](https://arxiv.org/abs/2606.01522)).

The human side does not replicate. LLM-rewritten messages beat conventional compiler messages in only 1 of 6 tasks with n=106 students, and hand-written expert messages beat both ([arXiv:2409.18661](https://arxiv.org/abs/2409.18661)); a second study with N=103 found improved perceptions with no significant objective debugging gains ([arXiv:2608.20896](https://arxiv.org/abs/2608.20896)).

Judgment: Mo's coded `what`/`why`/`fix` diagnostics are supported for agents and unproven for humans. Hand-authored beats generated.

## Vacuous tests are solvable by generating the fault first

Meta's mutation-guided pipeline ran over 10,795 Kotlin classes, produced 9,095 mutants, and landed 571 engineer-accepted tests: "After the improvements described in this paper, ACH's test acceptance rate rose to 73%," with mutant precision improving from 0.79 to 0.95 ([arXiv:2501.12862](https://arxiv.org/abs/2501.12862)).

Models cannot judge this for themselves. On 2,636 repository mutants across 9 languages, the best model scored 10.20% on mutant verification, and detection fell from 71.04% same-file to 39.81% cross-file ([arXiv:2605.22175](https://arxiv.org/abs/2605.22175)).

One benchmark already scores vacuity as a first-class axis: 67.1% module compile rate, with 82.1% of assertions in evaluable runs proving non-vacuously ([arXiv:2606.13706](https://arxiv.org/abs/2606.13706)).

Property-based tests and example-based tests each caught 68.75% of studied edge-case bugs; together they caught 81.25% ([arXiv:2510.25297](https://arxiv.org/abs/2510.25297)). Asked to invent properties unaided, the best 2023 configuration produced "21% valid, non-trivial PBTs" ([arXiv:2307.04346](https://arxiv.org/abs/2307.04346)).

## Editing by structure, not text

AST-entity edits gave pass@1 improvements of 1.2-5.0% with 12-38% fewer output tokens, and cut a small model's empty-patch rate from 46.6% to 7.2% ([arXiv:2604.05407](https://arxiv.org/abs/2604.05407)). Edit success is separately trainable: +12.5 points edit success, +2.1 points resolve, -17.9% cost ([arXiv:2604.26102](https://arxiv.org/abs/2604.26102)). Agents already locate the right files in 72-81% of tasks even when the patch fails ([arXiv:2511.00197](https://arxiv.org/abs/2511.00197)). Letting the agent choose between diff and whole-file rewrite cut latency and cost by more than 30% ([arXiv:2604.27296](https://arxiv.org/abs/2604.27296)).

```ruby
# The shape the evidence favors: name the declaration, replace it whole.
edit "mo:pay/charge#3" do
  requires amount > 0
  ensures result.settled?
end
```

## What Mo could take

| idea | maps to | status |
|---|---|---|
| Keep SMT contracts in check, proving in a separate tool | [[d32-proving-is-a-separate-tool]] | strengthens Mo |
| Contracts are not redundant with tests (0% contract satisfaction at 75-82% pass@1) | [[d19-negative-space-is-the-contract]] | strengthens Mo |
| Generate the fault, then require the test that kills it | [[q08-verification-tiers]] | strengthens Mo |
| Never let a model judge whether a test is vacuous | [[q08-verification-tiers]] | new idea for Mo |
| Hand the agent a declaration's dependency closure, not the file | [[d29-edit-by-declaration-id]] | strengthens Mo |
| Module-level composition story for contracts | [[q08-verification-tiers]] | new idea for Mo |
| Invariant synthesis is cheap, so verifiability is a weak reason to ban `while` | [[q16-escape-hatch]] | contradicts Mo |
| Coded, localized, hand-written diagnostics | [[q09-compiler-diagnostics]] | already in Mo |
| Offer a whole-declaration rewrite channel alongside ID edits | [[d29-edit-by-declaration-id]] | new idea for Mo |

17 Sep 2026: the `while` row above was ruled **agree** on 13 Sep — see [[research-agenda-2026-09-response]].
| Roundtrip and ambiguity checks on `never` sentences | [[d19-negative-space-is-the-contract]] | new idea for Mo |

## Related

- [[q08-verification-tiers]]
- [[q09-compiler-diagnostics]]
- [[d19-negative-space-is-the-contract]]
- [[d32-proving-is-a-separate-tool]]
- [[d29-edit-by-declaration-id]]
- [[spark-ada-and-dafny]]
- [[prompts-research-agenda-2026-09]]
- [[research-agenda-2026-09-response]]
