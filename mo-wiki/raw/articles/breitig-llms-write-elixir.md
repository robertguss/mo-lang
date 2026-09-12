---
source_url: https://lukabreitig.com/blog/llms-write-elixir
ingested: 2026-09-12
sha256: 02e6b13f4eb9644bf07cba9749ed9bf820c7d385c694f6eb94e8ea46dc479010
---
# Do LLMs Write Better Elixir Than Python?
     · Luka Breitig

Do LLMs Write Better Elixir Than Python? · Luka Breitig

# Do LLMs really write better Elixir than Python? 

 April 02, 2026 

 Luka Breitig 

A few months ago, a benchmark from Tencent's AI lab made the rounds in the Elixir community. Their AutoCodeBench study tested over 30 large language models across 20 programming languages — and Elixir came out on top.

The numbers were striking. Claude Opus 4 scored 80.3% accuracy on Elixir tasks, compared to 55.9% for Java and just 40.3% for Python. The collective "upper bound" — the share of problems solved by at least one model — hit 97.5% for Elixir. Highest of any language tested.

I build production systems in Elixir. I train developers on AI-assisted coding. So naturally, I wanted this to be true.

But I also wanted to understand why.

## The benchmark is real. The comparison is not.

Let me be upfront: these numbers are not apples-to-apples. Three compounding issues inflate Elixir's score, and you should know about all of them.

First, the problems were translated from Python. Only six of the twenty languages got natively designed problems. The other fourteen — Elixir included — received translations. Think about what that means: a problem designed around Python's paradigm can become trivially simple when expressed as a pure-function transformation. None of these problems test GenServers, supervision trees, or OTP patterns. They test algorithmic Elixir, not real Elixir.

Second, the difficulty filter broke for small languages. The researchers used a smaller model to remove easy problems, but acknowledged it "struggles to filter out simple problems in low-resource language scenarios." For Python, 25.1% of problems were removed as too easy. For Elixir? That filter likely caught far fewer.

This alone could explain a significant chunk of the score gap.

Third, no human ever verified the Elixir test cases. Manual checking only covered the six natively generated languages, where it found 87.6% accuracy. Whether translation artefacts or broken test expectations exist in the Elixir set — nobody knows.

And that 97.5% upper bound? It is itself a red flag. It means the 30+ models could collectively solve nearly every Elixir problem. Python's upper bound was 63.3% — genuinely hard problems that stumped every model. The Elixir problem set was almost certainly easier, not better suited to LLMs.

So: modern LLMs handle Elixir competently. Elixir is not "too niche" for AI coding tools. But claiming LLMs write Elixir twice as well as Python? That conclusion does not follow from this data.

## Why Elixir feels easier for LLMs

Here is where it gets more interesting. Even if the benchmark overstates things, there are genuine structural reasons why Elixir reduces the number of things an LLM can get wrong. José Valim laid these out in his February 2026 blog post, and I think the core argument holds up.

### No hidden state. Anywhere.

In an object-oriented language, calling `project.updateVersion()` could silently change any object reachable from `project` — including objects the LLM has never seen. The model either needs to pull in more context to reason about side effects, or it guesses.

Guessing is how bugs happen.

In Elixir, `project = Project.update_version(project)` makes the data flow visible. Everything a function needs is in its arguments. Everything it produces is in its return value. There is no hidden mutation, no shared mutable state, no "spooky action at a distance."

For an LLM working within a finite context window, that matters. Less hidden state means fewer opportunities to be wrong.

### Pattern matching forces your hand

Consider this:

```
def process({:ok, data}), do: transform(data)
def process({:error, reason}), do: log_error(reason)
elixir
```

The contract is right there in the function heads. An LLM generating this code is constrained by the pattern — it has to handle each case explicitly. In Python, the equivalent `if result[0] == "ok"` relies on the model remembering to check all branches.

Missed branches are one of the most common LLM coding errors. Pattern matching makes them structurally harder to produce.

### Pipes think the way LLMs think

Elixir's `|>` operator creates left-to-right, top-to-bottom data flow:

```
data
|> transform()
|> filter()
|> format()
elixir
```

LLMs generate tokens sequentially. Left to right. This linear structure aligns naturally with how the model works. Nested calls like `format(filter(transform(data)))` require the model to plan inside-out — architecturally harder for sequential token generation.

It is a small thing. But small things compound.

### Fewer footguns, fewer mistakes

Python offers list comprehensions, `map()`, generator expressions, and explicit loops — all for the same task. JavaScript has callbacks, promises, and async/await, plus four different `this`-binding behaviours. An LLM trained on all these competing patterns can easily blend incompatible approaches in a single function.

Elixir's standard library is deliberately small. Roughly 120 core modules versus Python's approximately 15,000 public functions. No implicit `this`. No variable hoisting. No mutable closures. No class inheritance.

Entire categories of bugs that LLMs routinely produce in JavaScript and Python simply cannot exist here.

## The documentation advantage

This is the part I find most compelling, because there is actual hard evidence.

Elixir treats documentation as a first-class language feature. The `@doc` and `@moduledoc` attributes are stored in compiled bytecode, not in comments. Every package on Hex gets standardised documentation on HexDocs — one format, one platform, consistently structured. Compare that to Python's fragmented landscape of Sphinx, MkDocs, ReadTheDocs, and three competing docstring formats.

But the real killer feature is doctests:

```
@doc """
Adds two numbers.

    iex> Math.add(1, 2)
    3
"""
def add(a, b), do: a + b
elixir
```

That `iex>` example runs as a unit test. If it produces the wrong output, your test suite fails. This means the code examples in Elixir's training data are verified to be correct.

No comparable mechanism exists at ecosystem scale in Python or JavaScript. Documentation examples in those ecosystems routinely drift out of date. In Elixir, they cannot — the compiler catches them.

That is not a theoretical advantage. That is cleaner training data, at scale.

## Twelve years of stability

Here is a problem that does not get enough attention.

A 2025 study published at ICSE evaluated seven LLMs on deprecated Python API usage. The finding: all models produced deprecated API calls 70–90% of the time when given outdated code context. Even with current context, 9–18% deprecated usage persisted. The GitChameleon 2.0 benchmark found that top models achieved only about 50% success on version-specific Python generation tasks.

Think about what that means. The LLM has absorbed twelve years of the Python 2-to-3 transition, multiple TensorFlow rewrites, and constant churn in packaging tools (pip, pipenv, poetry, PDM, uv). It has learned conflicting patterns for the same tasks. When it generates Python code, it is navigating a minefield of outdated knowledge.

Now consider Elixir.

Elixir v1.0 shipped on 18 September 2014. It is still on v1.x. Phoenix has been on v1.x since its first release. Ecto's last major version landed in 2018. As Valim puts it: "Everything written about Elixir or Phoenix in the last decade still works."

No confusion. No version conflicts. No deprecated-versus-current guessing game.

When every code example from the last twelve years uses the same APIs, the LLM does not need to figure out which version of reality is current. I think this is actually the strongest argument in Elixir's favour — not any benchmark score, but the documented, measurable cost of ecosystem instability that Elixir simply avoids.

## The honest counterarguments

I would be doing you a disservice if I only presented the good parts. There are real weaknesses in this narrative.

Training data scarcity. Elixir likely represents 0.05–0.2% of files in major training datasets — roughly 50 to 100 times less than Python. A 2025 study found that LLMs overwhelmingly default to Python even when other languages would be more appropriate, choosing it 58% of the time. That is not a minor bias.

Functional is not automatically better. The "Perish or Flourish" study found compilation error rates of 43% for OCaml and 25% for Haskell versus just 4.6% for Java. LLMs exhibit what researchers call "imperative bias" — they generate mutable-variable patterns even in ostensibly functional code. Elixir's Ruby-influenced syntax likely shields it from the worst of this. But the principle stands: being functional does not, by itself, help.

The benchmark does not test real work. AutoCodeBench evaluates isolated algorithmic problems. Not Phoenix LiveView components. Not Ecto changesets. Not supervision tree design. Zach Daniel, creator of the Ash Framework, noted that LLMs were "practically useless for Ash development" without specialised context files — though he also demonstrated how targeted tooling dramatically changed that picture.

The evidence base is thin. Outside AutoCodeBench, only MultiPL-E explicitly includes Elixir among major code generation benchmarks. HumanEval, MBPP, SWE-bench, BigCodeBench — none of them test Elixir. One benchmark with significant methodological issues is not a strong foundation for sweeping claims.

## What I actually see day-to-day

I work with LLMs and Elixir daily — building production systems, writing training materials, pairing with AI tools on client projects. My experience tracks with the structural arguments more than the benchmark scores.

LLMs produce clean, idiomatic Elixir for data transformations, pattern-matching logic, and pipeline-style code. They handle the standard library well. They rarely produce code that would not compile.

Where they struggle: framework-specific patterns. Combining multiple libraries. Niche packages. The kind of work that makes up most of real-world application development.

The stability advantage, though — that one is noticeable every day. I almost never see an LLM suggest a deprecated Elixir function. In Python projects, it happens regularly.

Microsoft Research showed with their phi-1 model that a tiny model trained on curated "textbook quality" data could outperform models ten times its size. The principle — data quality compensating for data quantity — maps directly onto Elixir's ecosystem of tested documentation and consistent APIs.

Whether that is enough to close a 50–100x gap in training data volume remains an open question. But the evidence is at least pointing in the right direction.

## Where this leaves us

The claim that Elixir is the best language for LLM code generation rests on a convergence of real properties: immutability, explicit data flow, pattern matching, tested documentation, extreme API stability. Each factor is individually plausible. Together, they form a coherent case.

But the most-cited benchmark is significantly confounded. The #1 ranking overstates reality.

What we actually need: a benchmark with natively conceived Elixir problems, verified test cases, difficulty-matched across languages, covering real framework patterns. Not algorithmic exercises translated from Python.

Until that exists, the honest position is this: Elixir has genuine structural properties that should help LLMs generate correct code. The limited evidence is consistent with that hypothesis. But the hypothesis remains undertested.

I find the structural arguments convincing enough to keep building with this stack. The AI tooling around Elixir is improving fast. But I would rather make the honest case than oversell a benchmark.

### Luka Breitig 

AI Coding Trainer & Software Engineer
