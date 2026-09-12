---
source_url: https://www.anup.io/til-markov-language/
ingested: 2026-09-12
sha256: a799d6ebe41a8b8e39377732df4fb9b8d345113f423bb209029194dcb4863294
---
# TIL: Markov Language

TIL: Markov Language

 Feb 15, 2026 

# TIL: Markov Language

#### by Anup Jadhav 

Programming languages were designed to make code easy for humans to write. But Davis Haupt argues we've been optimising for the wrong thing. His proposal for an agent-oriented language called Markov starts from a simple observation: Rust's `fn` keyword saves a programmer two keystrokes, but it costs an LLM extra tokens because common English words tokenise more efficiently than short abbreviations. Optimise for the machine's fluency, and you accidentally make code more readable for humans too. That's a genuinely surprising inversion. It's backed up by early evidence: TOON, a token-optimised alternative to JSON, already shows better LLM comprehension accuracy with roughly 40% fewer tokens.

The deeper move, though, is what Haupt does with compiler errors. Today, compilers speak to humans through ASCII arrows and terse error codes. Haupt wants Markov's compiler to speak to agents through prompts and diffs. Strong static types and exhaustive pattern matching become guardrails that keep an LLM on task, not just tools for catching human mistakes. Armin Ronacher arrived at similar conclusions independently, and academic projects like Quasar are formalising this with features like automated parallelisation baked into the language itself. 

There's a real trend forming here. But the skeptic in me notes that every one of these proposals faces the same cold-start problem: LLMs perform dramatically better on languages already in their training data, and a brand-new language has none. Haupt acknowledges this tension without fully resolving it.

The single idea I keep coming back to: we spent decades making languages that are easy to write and hard to read. A language designed for agents might finally break that trade-off.

Source: Ideas for an Agent-Oriented Programming Language
