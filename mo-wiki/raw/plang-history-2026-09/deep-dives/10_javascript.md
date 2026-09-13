# JavaScript — Ten Days that Ate the World

## Origin story

### Designer, institution, year

**Brendan Eich** created JavaScript at **Netscape Communications Corporation** starting in **April 1995** ([Wikipedia: Brendan Eich](https://en.wikipedia.org/wiki/Brendan_Eich)). Eich was 33, coming from seven years at Silicon Graphics working on OS and network code.

The famous facts:

- "He originally intended to put **Scheme 'in the browser.'**"
- "His Netscape managers insisted that the language's syntax resemble Java's syntax."
- Eich devised a language combining "much of the functionality of Scheme, the object-orientation of **Self**, the syntax of Java."
- "He completed the first version in **ten days** to accommodate the Navigator 2.0 Beta release schedule."
- Named **Mocha**, then **LiveScript** (September 1995), then **JavaScript** in a joint Sun/Netscape announcement in **December 1995**.

([Wikipedia: Brendan Eich](https://en.wikipedia.org/wiki/Brendan_Eich))

Simultaneously Eich designed the **SpiderMonkey** engine in C to execute the new language in Navigator. He would continue to "own" SpiderMonkey until 2011.

### The motivating problem

Netscape wanted a scripting language in the browser to complement Java applets — dynamic behavior for HTML pages that would be programmable by web designers, not systems programmers. Sun was pushing Java as the applet language; Netscape wanted a small dynamic sibling. Marc Andreessen and Bill Joy signed off on the arrangement.

### Initial reception

JavaScript shipped in Netscape Navigator 2.0 (September 1995). Microsoft rapidly cloned it as **JScript** in IE 3.0 (August 1996). Netscape submitted JavaScript to **Ecma International** in November 1996; **ECMA-262 (ECMAScript) 1st Edition** was published in June 1997.

The next decade produced ECMAScript 3 (1999) and the doomed ECMAScript 4 process (2003–2008), abandoned in favor of the smaller **ES5 (2009)**. Then **ES6 / ES2015** (June 2015) was the language's watershed modernization — classes, modules, promises, arrow functions, `let`/`const`, template literals, destructuring, generators.

## Design philosophy

### Core principles (retrofitted)

- **Everything runs.** JavaScript's error tolerance is famous. Missing semicolons are inserted (ASI); references to undefined values return `undefined`; the language rarely crashes at parse time.
- **First-class functions** and closures (Scheme heritage).
- **Prototype-based object orientation** (Self heritage) — even after ES6 classes, the underlying model remains prototypal.
- **Dynamic and mutable.** Objects gain and lose properties at will.

### What JavaScript rejected (initially)

- **Static typing** — Java's type system was the visual reference; the semantics were not.
- **Class-based inheritance** — Self's prototype model was the semantic basis (ES6 `class` is syntactic sugar).
- **Threads.** Single-threaded event loop from the start.
- **A large standard library.**

### Cultural values

Pragmatism, backward compatibility ("don't break the web"), incremental evolution, and — since ES2015 — a rapid annual release train.

## Language features

### Syntax

C-family; semicolons optional (with well-known hazards); `var`/`let`/`const`; arrow functions; template literals; destructuring; spread/rest; async/await; classes; modules (import/export); tagged templates; optional chaining (`?.`); nullish coalescing (`??`).

### Type system

Dynamic, weakly typed with famously surprising coercions (`[] + []`, `NaN !== NaN`, `null == undefined`). TC39 defers all typing concerns to external tools — most notably **TypeScript** (see below) and Flow.

### Memory model

Garbage collected. Modern engines use generational, incremental, concurrent collectors. V8's collector history: incremental (2011), concurrent marking (2016), Orinoco (2016–2017: concurrent marking, concurrent sweeping, parallel scavenging, parallel compaction) ([V8 10 years](https://v8.dev/blog/10-years)).

### Concurrency

Single-threaded event loop with microtasks (promises) and macrotasks (setTimeout, I/O). **Web Workers** provide message-passing parallelism; **SharedArrayBuffer** and **Atomics** enable shared-memory concurrency (with Spectre-related restrictions). Node.js adds worker_threads. `async`/`await` (ES2017) is the dominant style.

### Error handling

`try`/`catch`/`finally`; `throw` any value; unhandled promise rejections trigger events. No checked exceptions.

### Metaprogramming

`Proxy` and `Reflect` (ES6); `Symbol`; property descriptors; `eval` (discouraged); dynamic `import()`. Decorators are Stage 3 as of 2024–2025.

### Module system

Three eras:
1. **CommonJS** (Node.js, 2009+) — `require`, `module.exports`.
2. **AMD** (RequireJS) — browser async loading.
3. **ES Modules** (ES2015, browser-supported ~2018) — `import`/`export`, static analysis. Now the standard.

### Notable innovations (contributed to mainstream)

- Promises A+ specification.
- Async iterators and generators.
- Structured cloning.
- Optional chaining.
- Prototypes → classes evolution.

## Implementation

### Reference engine

There is no reference; the four major JavaScript engines are:

- **V8** (Google) — Chrome, Node.js, Deno (Node.js "grew into one of the most popular JavaScript ecosystems"; V8 "officially recognized Node.js as a first-class V8 embedder alongside Chromium" in 2017 — [V8 10 years](https://v8.dev/blog/10-years)).
- **SpiderMonkey** (Mozilla) — Firefox; Eich's original.
- **JavaScriptCore / Nitro** (Apple) — Safari; also powers Bun.
- **ChakraCore** (Microsoft, historical, discontinued 2021 after Edge switched to Chromium).

### V8 history

The V8 team was hired by Google in **autumn 2006** under **Lars Bak**, working from an outbuilding on Bak's farm in Aarhus, Denmark. "The initial V8 commit dates back to **June 30, 2008**. V8 went open source on the same day Google Chrome launched, September 2, 2008" ([V8 10 years](https://v8.dev/blog/10-years)).

Compiler generations:
- **Original** (2008) — simple JIT.
- **Crankshaft** (2010) — "machine code that was twice as fast and 30% smaller."
- **TurboFan** (initial 2014, default 2017).
- **Ignition** interpreter (2015; default on low-end Android 2016).
- **Sparkplug** (2021) — a fast tier between Ignition and TurboFan.
- **Maglev** (2023) — mid-tier optimizing JIT.

### Lexer, parser, IR, backend

V8 has a hand-written recursive-descent parser; produces AST; Ignition compiles to bytecode; TurboFan / Sparkplug / Maglev optimize; produces machine code for ia32, x64, ARM, ARM64, MIPS, PPC, S390 ([V8 10 years](https://v8.dev/blog/10-years)).

### Runtime and GC

Precise generational GC with concurrent/incremental marking. Handles gigabyte heaps with sub-millisecond pauses in Chrome.

### Bootstrapping

V8 is written in C++; SpiderMonkey in C++; JavaScriptCore in C++.

### Alternative implementations

- **Bun** (Zig, on JavaScriptCore) — Node-alternative runtime with built-in bundler, transpiler, package manager.
- **Deno** (Rust, on V8) — Ryan Dahl's Node successor.
- **QuickJS** (Fabrice Bellard) — small embedded engine.
- **Hermes** (Meta) — React Native's engine, AOT bytecode.

## Ecosystem

### Package manager

**npm** — the Node package registry (2010) is the largest package repository in the world. **yarn** (Meta, 2016) and **pnpm** and **bun** compete on speed/correctness. **jsr** (Deno-led, 2024) is an emerging ES-Modules-native alternative.

### Standard library

Minimal historically; ECMAScript proper defines only the core. Web APIs (DOM, fetch, Streams, WebSocket, WebGPU) live in browser specs. Node.js adds `fs`, `net`, `http`, `stream`, etc. **WinterCG** attempts to standardize a common runtime API across Node/Deno/Bun/Workers.

### Tooling

**TypeScript** (below) for typing; **Babel** for transpilation; **Webpack** / **Rollup** / **Vite** / **esbuild** / **swc** / **turbopack** for bundling; **ESLint** for linting; **Prettier** for formatting; **Vitest** / **Jest** / **Playwright** for testing.

### Governance

**TC39** (Ecma Technical Committee 39) governs ECMAScript. Meetings quarterly; proposals move through five stages (0 Strawman → 4 Finished). Annual releases since 2015 (ES2015, ES2016, ..., ES2024, ES2025).

## TypeScript

Given its impact, TypeScript deserves its own treatment here.

- Developed by Microsoft; "Designed by Microsoft, **Anders Hejlsberg**, Luke Hoban" ([Wikipedia: TypeScript](https://en.wikipedia.org/wiki/TypeScript)).
- First appeared **1 October 2012**, released publicly October 2012 with version 0.8, "following two years of internal development at Microsoft."
- Hejlsberg is "the lead architect of C# and the creator of Delphi and Turbo Pascal" ([Wikipedia: Anders Hejlsberg](https://en.wikipedia.org/wiki/Anders_Hejlsberg)).
- Typing model: "Duck, gradual, strong, structural." Structural typing is the distinctive design choice.
- TypeScript is "a superset of JavaScript." Existing JavaScript can be adapted; TypeScript programs can consume JavaScript.
- Definition files (`.d.ts`) provide types for third-party JavaScript libraries: "jQuery, MongoDB, D3.js" and Node.js.
- **TypeScript 2.0** (September 2016) added **null- and undefined-aware types** (strictNullChecks) — a major inflection point.
- **TypeScript 4.1** (November 2020) added **template literal types** — enabled the type-level programming community.
- **The Go rewrite:** "On 11 March 2025, Anders Hejlsberg announced on the TypeScript blog that the team was working on a Go port of the TypeScript compiler. The Go port was planned for release as TypeScript 7.0 later in 2025. The Go port was expected to feature a **10x speedup**" ([Wikipedia: TypeScript](https://en.wikipedia.org/wiki/TypeScript)).
- **TypeScript 6.0** (23 March 2026) "was released as the last version with a compiler and language service based on JavaScript before the rewrite to Go."
- **TypeScript 7.0** released 8 July 2026 with the Go rewrite ([Wikipedia: TypeScript](https://en.wikipedia.org/wiki/TypeScript)).

## Adoption

### Where JavaScript dominates

- **The web** — the only client-side language of the browser. TypeScript owns the frontend developer experience.
- **Node.js server-side** — Netflix, LinkedIn, PayPal, Uber all have significant Node backends.
- **Mobile via React Native, Expo, Ionic** — cross-platform.
- **Desktop via Electron** — VS Code, Slack, Discord, Figma, Notion, WhatsApp Desktop, Microsoft Teams.
- **Serverless** — AWS Lambda, Cloudflare Workers, Vercel/Netlify functions.
- **Build tools and CLIs** — npm ecosystem hosts almost every JS dev tool.

### Where JavaScript never won

- Systems programming.
- CPU-bound numerical computing (though asm.js and WebAssembly help).
- Games (though HTML5/Three.js/WebGPU exist).

### Current momentum (2026)

Dominant on the client; enormous on the server. TypeScript overwhelmingly wins new projects — the developer survey consensus for years. Bun and Deno challenge Node's runtime monoculture. WebAssembly is complementary rather than competitive.

## Criticism and open problems

- **Type coercion weirdness** — the language's most-mocked feature. `[] + [] === ""`, `[] + {} === "[object Object]"`, etc.
- **`this` semantics** — arrow functions, `bind`, `call`, `apply`, method shorthand — the complexity is legendary.
- **No standard library** — the ecosystem fills every gap, causing supply-chain risk (left-pad incident, 2016; regular malicious npm packages).
- **Node.js API vs. Web API divergence** — WinterCG is progress.
- **Bundle size** — the primary front-end performance concern.
- **Spectre / Meltdown (2018)** — as the V8 blog notes, "an industry-wide CPU information-security event. V8 engineers conducted extensive offensive research to understand the threat to managed languages and develop mitigations" ([V8 10 years](https://v8.dev/blog/10-years)). SharedArrayBuffer was constrained across origins as a result.
- **Type erasure at runtime** — TypeScript's types disappear at compile time, unlike C# or Java generics.

## Influence on other languages

- **ActionScript** (Adobe/Macromedia Flash) — ECMAScript 4 dialect.
- **CoffeeScript**, **LiveScript**, **Elm**, **PureScript**, **ClojureScript**, **ReasonML/ReScript**, **Fable (F#)** — compile-to-JS languages.
- **Dart** (Google) — replaced JavaScript for Flutter.
- **Kotlin/JS**, **Scala.js**.
- **AssemblyScript** — TypeScript-like syntax compiling to WebAssembly.
- The **npm** model has been imitated by Rust's Cargo, Python's uv, Ruby's Bundler, etc.

## Key sources

- Brendan Eich, "JavaScript at Ten Years," HOPL III essay, 2007.
- Allen Wirfs-Brock and Brendan Eich, ["JavaScript: The First 20 Years"](https://dl.acm.org/doi/10.1145/3386327), HOPL IV, 2020.
- Douglas Crockford, *JavaScript: The Good Parts*, O'Reilly, 2008.
- [V8 10 years blog](https://v8.dev/blog/10-years) — comprehensive V8 history.
- [Wikipedia: Brendan Eich](https://en.wikipedia.org/wiki/Brendan_Eich).
- [Wikipedia: TypeScript](https://en.wikipedia.org/wiki/TypeScript).
- [Wikipedia: Anders Hejlsberg](https://en.wikipedia.org/wiki/Anders_Hejlsberg).
- TC39 proposal repo: [github.com/tc39/proposals](https://github.com/tc39/proposals).
- Node.js documentation: [nodejs.org](https://nodejs.org).
