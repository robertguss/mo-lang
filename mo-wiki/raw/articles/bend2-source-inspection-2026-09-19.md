---
source_url: https://github.com/bendlang/bend/tree/15ae0c86f3193b8f645b4bedbc438655b648d0da
ingested: 2026-09-19
sha256: 46d4b35c5ebbee00cafc7f58c937d6adb30344f88cc1b858412b0937eca04007
---
# Bend2 source inspection excerpts

Pinned commit: `15ae0c86f3193b8f645b4bedbc438655b648d0da`. Selected exact line slices, not full-file captures or a complete source audit. Section headings identify original paths/ranges; file hashes cover complete original bytes. README/paper claims are author claims. Compiler/runtime notes are source inspection, not verified metatheory or GPU measurements.

Copyright 2026 HigherOrderCO. Upstream Apache-2.0 license reproduced below; source excerpts unchanged.

## README.md

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/README.md

Full-file SHA-256: `07cc2b846951aabe60f66add30282b2dfcf885a580e98d87bcdc37657a80d091`

Lines 1–11:

```text
<p align="center"><picture><source media="(prefers-color-scheme: dark)" srcset="media/hero_dark.gif"><img src="media/hero.gif" width="560" alt="Bend: a fast language that blocks AI mistakes via proof"></picture></p>

In the post-AGI economy, humans will eventually stop writing and reading code,
but we still need an ambiguity-free language to communicate our intents to the
AIs building the world around us. Bend is that language.

With **laws**, intents can be more precise than natural language. With
**proofs**, we can mechanically verify the AI implemented our prompts correctly.
And with a **fast compiler**, we can run that code at peak compute.

That's Bend - and nothing else.
```

Lines 41–104:

```text
## Bend BLOCKS mistakes - with proof

PROBLEM: How can you **trust** AI code, without reading it?

SOLUTION: By forcing your AI to write a **correctness proof**.

Bend introduces `LAWS.bend`, a file where you declare rules that your app must
not break. Bend's compiler then **guarantees** that these laws always hold, by
demanding **mathematical proof** whenever your code is edited. For example,
consider a game with one law: *winning is impossible*. Here's how it plays out:

<p align="center"><b>Law</b>: winning is <b>impossible</b><br><img src="media/game_law.gif" width="480" alt="The player walks up and bumps the wall of the flag's room"><br><i>So far, it works!</i></p>

<p align="center"><b>New feature:</b> "Claude, make the board wrap around"</p>

<p align="center"><b>Without LAWS.bend:</b><br><img src="media/game_bug.gif" width="480" alt="The player wraps around the edge and takes the flag"><br><i>Laws broken. AI mistake: <b>merged</b>.</i></p>

<p align="center"><b>With LAWS.bend:</b><br><img src="media/game_law_kept.gif" width="480" alt="A wall on the far edge stops the player"><br><i>Laws intact. AI mistake: <b>blocked</b>!</i></p>

Without `LAWS.bend`, a bug was merged. With it, the AI had to retry, until no
bugs were left! In this case, it added a wall, but it could have moved the flag,
made the room kill you, or whatever. The only thing it can't do is commit a bug,
because it is **mathematically impossible** to break laws in `LAWS.bend`. The
compiler *enforces* it.

Using `LAWS.bend` is simple.

1. Ask your AI to formalize your app's rules in `LAWS.bend`. Example:

    - LAW: *"the sum of all balances must be zero"*

    - LAW: *"players can never pass through solid walls"*

    - LAW: *"list_sort() must always return ascending numbers"*

    - LAW: *"array_set() may never be called out-of-bounds"*

    - LAW: *"winning is impossible"* (the demo above!)

    - And so on. Anything you can spell can become a law.

2. Ask your AI to run `bend PROOF.bend` after editing any code.

3. That's it. Rejoice as your app never again breaks or violates your rules.

You can also edit `LAWS.bend` yourself. Here's how it looks:

```python
# LAWS.bend
law you_cant_win:                           # "winning is impossible"
  for moves: List<Game.Move>                # any sequence of moves
  board = Game.replay(Game.start(), moves)  # replayed from the start
  {Game.is_won(board) == False{} : Bool}    # never leads to victory
```

```python
# PROOF.bend
def Laws.you_cant_win(moves):
  # ... written by the AI
```

In short, `LAWS.bend` is `AGENTS.md` backed by **proof**.

With `LAWS.bend`, *"make no mistakes"* becomes enforceable.
```

Lines 215–254:

```text
# Limitations

```
- Bend 2 is a new language. Bend 1 programs and HVM do not carry over.
- Everything is annotated and nothing is inferred, so code is verbose.
- No type classes, no traits, and no macros beyond compile-time templates.
- Bend has no tactics or proof search; proving theorems takes extra effort.
- Values are affine: closures and arrays cannot be shared.
- Recursion must be terminating. (Use `@unsafe` to disable this checker.)
- Computed matches (`match f(x)`) aren't supported. Must split it manually.
- There is no syntax for if-then-else: a branch is a match on True and False.
- Numbers are Nat, U32 and F32 only: no U64, I64 or F64 (Metal has no f64).
- F32 is axiomatic: nothing about floating point can be proven.
- Strings are linked lists of characters, so text processing is slow.
- Base is small: expect to write helpers other languages ship built in.
- Effects are few: print, env, time, sleep, spawn, channels, files, TCP, UDP.
- No TLS, HTTP library, JSON or regex for now (but you can add them as foreigns).
- Targets are C, Metal, CUDA and JavaScript; Lua, Luau and Python are planned.
- The JavaScript target runs on one core and has no graphics or audio.
- Parallelism requires balanced calls. Flexible parallelism will be added later.
- Sharing arrays with atomics across threads is experimental and needs `@unsafe`.
- One GPU per program, one event loop, and no multi-machine execution yet.
- One C file per program: no separate compilation, no incremental builds.
- Compiling to native is slow (clang/CUDA/Metal). For fast development, use JS.
- The compiler is young and has blind spots (unusually slow programs). Report.
- We don't have as many benchmarks as we'd like yet, especially for the checker.
- The compiler (not kernel) is 99% AI-written and has not been fully audited yet.
- The Lean formalization and bend.ts mismatch. Early consistency bugs may occur.
- A binary needs clang 14+; ! needs 19+, Metal or CUDA 12.
- No Windows (WSL works); on Linux, Window and Audio need X11 and ALSA headers.
- The hub has no names, versions, accounts or search yet. Packages are hashes.
- Error messages are terse; no debugger, profiler or REPL.
- Editor support is limited to formatting; there is no completion, hover or diagnostics LSP.
- No test framework and no documentation beyond the guide.
- And more that escape me. Be patient, report bugs and request features!

Most of these limitations are being addressed and will improve over time!
```

**BEND IS YOUNG. EXPECT BUGS AND [REPORT THEM](https://github.com/bendlang/bend/issues).**
```

## bend2/main.ts

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/main.ts

Full-file SHA-256: `f722bcd7a56807d356aaa8033c3d6bc151f406d9f75c2146baa5b60fef228d4f`

Lines 32–48:

```text
const VERSION = "2.0.16";

const HELP = `Bend ${VERSION}: check, run, build and publish Bend programs.

usage:
  bend <file.bend> [args]     check the file, then run main with args
                              (IO.args; a "--" ends bend's own options)
  bend <file.bend> -o <out>   build a binary; <out>.c emits C, <out>.js JS
  bend <file.bend> --checkup  check and run each import alone
  bend <file.bend> --publish  publish the file and its imports to the hub
  bend <page.html> -o <dir>   bundle a page that imports .bend files
  bend base [--types|<name>]  print Base, its types, or a name and its subnames
  bend guide                  print the Bend guide
  bend update                 install the latest bend (curl | sh, shown first)
  bend --version              print the version

Read the guide (\`bend guide\`) before writing Bend code.
```

Lines 112–119:

```text
// cli_guide prints guide/<NAME>.md: the guide, or a named extra.
function cli_guide(name: string): void {
  const file = path.join(GUIDE, name.toUpperCase() + ".md");
  if (!fs.existsSync(file)) {
    cli_fail("no guide named " + name);
  }
  cli_say(1, fs.readFileSync(file, "utf8"));
}
```

Lines 367–393:

```text
// cli_base prints the base library; with --types, its type declarations
// (every `type`, and every law whose result is a kind); with a name, the
// blocks declaring it or a name under it (its law, its def, its @unsafe).
function cli_base(what?: string): void {
  const src = fs.readFileSync(BASE, "utf8");
  if (what === undefined) {
    return cli_say(1, src);
  }
  const want: string[] = [];
  for (const text of src.split(/\n(?=type |law |def |@)/)) {
    const m = /^(type|law|def) ([^\s(<:]+)/m.exec(text);
    if (m === null) {
      continue;
    }
    const s = text.replace(/(\n(#[^\n]*)?)+$/, "");
    const last = s.slice(s.lastIndexOf("\n") + 1);
    const ok = what === "--types"
      ? m[1] === "type" || (m[1] === "law" && /^ *(Type|Data|Kind\(.*\))$/.test(last))
      : m[2] === what || m[2].startsWith(what + ".");
    if (ok) {
      want.push(s);
    }
  }
  if (want.length === 0) {
    cli_fail("Base has no " + what);
  }
  cli_say(1, want.join("\n\n") + "\n");
```

Lines 490–540:

```text
// cli_report prints the unsafe count: the verdict of a check on stdout, a
// note before a run, an emit or a publish on stderr (silent at zero).
function cli_report(book: Bend.Book, fd: number): void {
  const uns  = Object.entries(book.tlds).filter(([k, t]) =>
    t.$ === "Def" && (t.u === true || k.includes("~"))).length;
  if (uns > 0) {
    cli_say(fd, `All terms check, with ${uns} unsafe annotation`
      + `${uns === 1 ? "" : "s"}.\n`);
  } else if (fd === 1) {
    cli_say(1, "All terms check.\n");
  }
}

function cli_say(fd: number, text: string): void {
  try {
    fs.writeSync(fd, text);
  } catch (e) {
    if ((e as NodeJS.ErrnoException).code !== "EPIPE") {
      throw e;
    }
    process.exit(0);
  }
}

function cli_fail(msg: string): never {
  cli_say(2, "bend: " + msg + " (see bend --help)\n");
  process.exit(1);
}

// Book
// ====

async function book_read(file: string, base?: Bend.Book,
  seen = new Map<string, string | null>()): Promise<Bend.Book> {
  const book = base === undefined ? Bend.book_nil() : book_seed(base);
  if (base !== undefined) {
    seen.set(BASE, "");
  }
  await Bend.book_load(book, file, "", seen);
  const laws = path.join(path.dirname(file), "LAWS.bend");
  if (path.basename(file) === "PROOF.bend" && fs.existsSync(laws)
    && !seen.has(fs.realpathSync(laws))) {
    cli_fail("PROOF.bend must import ./LAWS.bend");
  }
  Bend.book_valid(book, base?.order.length ?? 0);
  const hols = book.hols + book.open;
  if (hols > 0) {
    throw "Error: " + String(hols) + " TODO" + (hols === 1 ? "" : "s")
      + " found.\nThe code is incomplete, and not a valid proof yet.";
  }
  return book;
```

## bend2/bend.ts

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/bend.ts

Full-file SHA-256: `47e1b06e2fa4466bad702f86d8cbce03f40e833a8ba8eaa1e04297fa46dc94a9`

Lines 584–618:

```text
export function quant_add(a: Quant, b: Quant): Quant {
  if (a.$ === "None") {
    return b;
  }
  if (b.$ === "None") {
    return a;
  }
  return Many();
}

export function quant_join(a: Quant, b: Quant): Quant {
  if (a.$ === "Many" || b.$ === "Many") {
    return Many();
  }
  if (a.$ === "None") {
    return b;
  }
  return a;
}

export function quant_dem(q: Quant, qt: Quant): Quant {
  if (q.$ === "None") {
    return None();
  }
  return qt;
}

export function quant_used(book: Book, ctx: Ctx, k: Name, q: Quant, u: Quant, s: Span | undefined, def?: Name): void {
  if (quant_join(u, q).$ !== q.$) {
    let obs = quant_show(u) + k;
    if (u.$ === "Many") {
      obs = k + " (consumed more than once)";
    }
    throw Err(book, ctx, quant_show(q) + k, obs, s, def);
  }
```

Lines 653–655:

```text
export function lhs_kind(lhs: LHS, q: Quant): Quant {
  return lhs.u === true && q.$ === "Many" ? Lone() : q;
}
```

Lines 3321–3336:

```text
          if (tm.k === lhs.def && lhs.u !== true) {
            const cols = term_unapply(lhs.t)[1];
            let ord: Cmp = "EQ";
            for (let j = 0; j < cols.length && j < sp.length && ord === "EQ"; j++) {
              ord = term_descend(lhs.qs[j], sp[j], cols[j]);
            }
            if (ord !== "LT") {
              throw Err(book, ctx, "a decreasing self-call (arguments are read left to right: each passed unchanged until one shrinks)", tm, tm.s, lhs.def);
            }
          }
          if (tm.k === lhs.def) {
            return Infer(Ref(tm.k, tm.s, tm.b), tld.T, uses_nil());
          }
          if (tld.$ === "Def" && tld.v === null && tld.b !== true && !tld.i) {
            throw Err(book, ctx, "a filled definition (an unfilled law is a dead claim: live code cannot use it)", tm, tm.s, lhs.def);
          }
```

Lines 3622–3639:

```text
    case "Rfl": {
      const t_wnf = term_wnf(book, ty);
      if (t_wnf.$ !== "Eql") {
        throw Err(book, ctx, ty, typeless_show(book, ctx, tm), tm.s, lhs.def);
      }
      if (!term_compare("EQ", book, t_wnf.a, t_wnf.b, d)) {
        throw Err(book, ctx, t_wnf.a, t_wnf.b, tm.s, lhs.def);
      }
      return Check(Rfl(tm.s), ty, uses_nil());
    }
    // T
    // ------------------- check-hol
    // Γ ⊢ ?TODO : T ~ {}
    case "Hol": {
      if (tm.k === "TODO") {
        return Check(Hol(tm.k, tm.s), ty, uses_nil());
      }
      throw Err(book, ctx, ty, tm, tm.s, lhs.def);
```

## bend2/bend.lean

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/bend.lean

Full-file SHA-256: `fa8bc26b4c3b31986401852c97976a7d1aa1dafe11357028d58336523ff5ef7d`

Lines 1–110:

```text
-- NOTE: this file has two parts:
-- 1. the specification, which is what humans must read and audit
-- 2. the proofs, which were written by AI, and checked by Lean
-- Even though we've reviewed the spec carefully, it doesn't fully match the
-- implementation (bend.ts) yet. Bugs in the implementation COULD result in
-- inconsistencies. Independent audits are needed to increase our confidence on
-- bend.ts even further, and will be done over time. 
-- 
-- ============================================================================
-- BEND-CORE — the bend2 calculus, as bend.ts implements it
-- ============================================================================
--
-- A model of the Bend core: the language (bend.ts's Types through Valid),
-- its reduction, typing, descent and validation, and the five claims the
-- bend.ts header trusts. PART I is the SPEC — the part a human must read.
-- PART II is the metatheory proving the claims.
--
-- THE HEADLINE. A dependent calculus with Type : Type, impredicativity and
-- negative recursive types, made consistent not by a universe hierarchy or a
-- positivity check but by a usage wall. Two checking demands, None (dead)
-- and Lone (live); binders graded None, Lone or Many; a Many binder forms
-- only at a Data type, and no function type is Data. So a live function
-- value is consumed at most once: self-replicating lambdas (omega, Curry,
-- Hurkens) contract a live function-valued binding and do not type. The
-- other way to loop is recursion, and every live self-call descends on a
-- strict subterm of the definition's own case-tree columns. Dead code is
-- specification, not proof: it may diverge and may inhabit Empty, and the
-- claims are stated for the live fragment only.
--
-- THE MAP. Part I mirrors bend.ts's core, section by section:
--
--   bend.ts section    | here          | contents
--   -------------------|---------------|------------------------------------
--   Types              | §1 Types      | Quant, Uses, Term, Bind, Ctx, DefD,
--                      |               | CtrD, AdtD, TLD, Book, LHS
--   Quant              | §2 Quant      | add, join, mul, le, dem
--   Uses               | §3 Uses       | zero, one, add, join, tail
--   Term, LHS          | §4 Term       | apps/spine, shift, subst, Closed,
--                      |               | the J motive, the lhs algebra
--   Ctx, Ctrs, Book    | §5 Ctx/Book   | get, δ (let expansion), tld, adt,
--                      |               | defn, ctr, LHS walks
--   Compare (descend)  | §6 Descent    | PEq/PLt (EQ/LT verdicts), SpineLt
--   Tele               | §7 Tele       | telescope shapes and openings
--   WNF, SNF, Compare  | §8 Equal      | Step/Red (wnf/snf), Value, Conv
--                      |               | (compare EQ), Le (compare LE)
--   Check              | §9 Check      | the one judgment: infer and check,
--                      |               | with the descent test at infer-ref
--   Valid              | §10 Valid     | Book.Ok (book_valid)
--   (header claims)    | §11 Claims    | the five claims as Props
--
-- THE ENCODING. Terms are de Bruijn and first-order; bend.ts's binder ids
-- and HOAS bodies are its way of being capture-free, and a de Bruijn index
-- is the same fact. Its Ann is inference's only help and has no rule here:
-- {x : T} is x checked at T, which the declarative judgment can always do
-- (cnv). Its Hol is ?TODO, which marks a book incomplete, and its Sub is a
-- flattener node: neither reaches a checked book. Its n-ary ADT and Ctr
-- nodes are application spines headed by Adt a r and Ctr a c, always full
-- in a parsed book; a constructor spine carries the family's parameters
-- as erased leading arguments (check-ctr reads them off the goal, and the
-- elaborated node records them in its Ann). Its parallel let x y = a b; f
-- is nested Lets, each value checked in the outer scope. The surface
-- syntax (match, case, do, the sugars) desugars and flattens into this
-- core at parse time; the flattener's output is a tree of Lam, Mat and
-- Efq over the definition's columns, in binder order (Tree, §10), and
-- check-mat's column peel is sound only for such a body, so Book.Ok
-- states the shape def_valid trusts.
--
-- LETS ARE TRANSPARENT. A let binds x with its value: the checker types x
-- from the context and counts its uses, while reduction, conversion and
-- descent step through x to the value (bend.ts's Var carries v). Here a
-- Bind carries the optional value, and Ctx.δ expands every let-bound
-- variable in a term (§5); every comparison the judgment makes (cnv, rfl,
-- the descent test) compares δ-expanded terms. Reduction itself is
-- context-free: a closed let fires by substitution.
--
-- THE MODEL ACCEPTS EVERY BOOK bend.ts ACCEPTS with a clean verdict, and
-- some more. The extra permissions are harmless for the claims, which are
-- negative, and are listed here so nobody reads the model as the checker:
--   (a) the judgment is declarative: a term may be checked at any type
--       that its inferred type fits (cnv anywhere), where bend.ts converts
--       only at check-any, rfl and rwt, and normalizes goals by wnf;
--   (b) a family or constructor head may be applied to fewer arguments
--       than its arity, where bend.ts spells only full nodes;
--   (c) a residual family Adt a r may be written anywhere, where bend.ts
--       mints residuals only in match goals;
--   (d) (x => f)(a) types by the app rule too when the lambda is typed,
--       where bend.ts takes one beta step first (both are here);
--   (e) check-efq reads a binding's type up to conversion, where bend.ts
--       reads its weak head normal form (the same verdict on every type
--       bend.ts normalizes; conversion is what a let value's reduction
--       preserves, which subject reduction under a let needs).
-- Two premises the declarative form needs that bend.ts gets for free from
-- its pipeline: check-lam kinds the binder's domain at the binder's
-- quantity (bend.ts kinded it when the arrow was formed, and every goal
-- it meets was formed), and a constructor head's parameter binders are
-- erased (a bend.ts value never carries them). Each keeps a Many binder
-- from ever copying a function: what the Data layer's soundness rests on.
-- THE MODEL REFUSES what bend.ts accepts outside the theory: a book with
-- an @unsafe def or a surviving ?TODO (bend.ts reports both in its
-- verdict, and the claims are for clean verdicts); a definition with no
-- body (a law bend.ts's base file leaves unfilled, such as F32.add, or a
-- body it imports from C); and a live call to a definition that comes
-- later in the file. bend.ts refuses that call too, except from the base
-- file, where a helper may call a law that is filled below it and calls
-- the helper back: that pair is mutual recursion the checker never tests
-- (descent is tested on self-calls only). The theory has no such call.
--
-- NOT MODELED. Char, PMap, the number sections, Show, Parse, Flatten,
-- imports and the error window are pipeline and presentation concerns.
-- Literals are base.bend constructors, not calculus.
```

## bend2/comp.ts

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/comp.ts

Full-file SHA-256: `0939b98d013ab58d82619e35c0d4900b72c9d8e5b478f0e1df7822fe713c9b48`

Lines 1056–1076:

```text
function ctr_build(fl: File, k: Bend.Name, exprs: string[],
  stat = false): string {
  const cid = cid_mac(k);
  const node = lay_node(fl.book, k);
  if (exprs.length === 0 || (node.ks.length === 1 && node.ks[0] === "w32")) {
    return `term_pak(${cid}, ${exprs[0] ?? 0})`;
  }
  if (stat) {
    fl.stat.add(k);
    const at = memo(fl.lits, exprs.join(", "), () =>
      fl.img.push(...exprs) - exprs.length);
    return `term_ctr(${cid}, STAT_OFF + ${at})`;
  }
  const alloc = `heap_alloc(e, cls_fit(${exprs.length}))`;
  const at = fl.spares.findIndex((s) =>
    cls_fit(s.words) === cls_fit(exprs.length));
  const s = at < 0 ? null : fl.spares.splice(at, 1)[0];
  const got = s === null ? alloc
    : s.z ? `${s.name} >= HEAP_OFF ? ${s.name} : ${alloc}` : s.name;
  return `term_ctr(${cid}, ${node_fill(fl, "nd", got, exprs,
    fl.hot.has(k))})`;
```

Lines 2484–2572:

```text
// A fork: in parallel a join task and a kid per call, or, for one call (a
// cut), its continuation as the lane's task ahead of the jump; in sequence
// (the emitter wound back) one frame read in place by every step, each
// pushing its result, the last jumping into the joiner (a cut's one step
// is its continuation). What the parallel join holds (hold) every step
// holds too, so both paths open one joiner.
function emit_fork(fl: File, x: HLet, ers: HTerm[]): void {
  const o = term_open(x);
  const calls = x.v.map((v) => call_kind(fl, v) as Call);
  const fork = calls.length > 1;
  const name = seg_name(fl, "j");
  let hold: Probe[] = [];
  if (fork) {
    spare_flush(fl);
    fl.seg.fork = true;
    const uses = new Map(fl.uses);
    block(fl, "if (!seq) {", () => {
      const margs = calls.map((c, j) => {
        fl.rest = [...x.v.filter((_, i) => i !== j), o.b];
        return emit_args(fl, c, false, true);
      });
      const live = [...fl.uses].filter(([p, b]) =>
        !val_brw(fl, b.val) || rest_use(fl, [o.b], p) > 0);
      hold = live.map(([p]) => p);
      const caps = live.flatMap(([, b]) => b.val.ws);
      spare_flush(fl);
      const jn = emit_task(fl, seg_fid(name), calls.length, caps);
      const jt = `term_tsk(${seg_fid(name)}, ${jn})`;
      let idx = caps.length;
      calls.forEach((c, j) => {
        const fj = seg_fid(c.k);
        file_push(fl, `e.mem[${jn} + ${idx}] = term_tsk(${fj}, ${
          emit_task(fl, fj, 0, margs[j], jt, idx)});`);
        idx += sig_def(fl, c.k).ret.ks.length;
      });
      file_push(fl, `return ${jt};`);
    });
    fl.uses = uses;
  }
  const chain = calls.map(() => o.b);
  for (let j = calls.length - 2; j >= 0; j -= 1) {
    chain[j] = let_open([o.ps[j + 1]], [x.v[j + 1]], chain[j + 1]);
  }
  const rests = chain.map((c) => [...hold, c]);
  const pos = new Map<Probe, number>();
  let depth = 0;
  calls.forEach((c, i) => {
    fl.rest = [chain[i]];
    const cargs = emit_args(fl, c);
    const vs = i === 0 ? [...fl.uses]
      : [[o.ps[i - 1], fl.uses.get(o.ps[i - 1]) as Bind] as [Probe, Bind]];
    const kn = seg_name(fl, "k");
    spare_flush(fl);
    const ws = vs.flatMap(([p, b]) =>
      (pos.set(p, depth), depth += b.val.ws.length, b.val.ws));
    const frame = () => emit_frame(fl, ws, seg_fid(kn));
    if (fork) {
      frame();
    } else {
      emit_chain(fl, () => "seq", [frame, () => {
        file_push(fl, `WL_CONT = term_tsk(${seg_fid(kn)}, ${
          emit_task(fl, seg_fid(kn), 1, ws)});`);
        file_push(fl, `WL_IDX = ${ws.length};`);
        if (c.bang) {
          file_push(fl, `return term_tsk(${seg_fid(c.k)}, ${
            emit_task(fl, seg_fid(c.k), 0, cargs)});`);
        }
      }]);
    }
    emit_jump(fl, cargs, c.k);
    const last = i === calls.length - 1;
    const held = [...fl.uses].filter(([p]) => pos.has(p));
    const at = held.flatMap(([p, b]) => b.val.ws.map((_, j) =>
      (pos.get(p) as number) + j - (last ? 0 : depth)));
    const ret = sig_def(fl, c.k).ret;
    const rs = seg_open(fl, kn, fl.seg.ret, { pop: last ? depth : 0, at },
      held, o.ps[i].k, ret.ks, rests[i]);
    bind_uses(fl, o.ps[i], val_new(rs, ret), rests[i], ty_ann(x.v[i]));
  });
  if (fork) {
    const live = [...fl.uses];
    if (live.map(([p]) => p.i).join() !== [...hold, ...o.ps].map((p) => p.i)
      .join()) {
      die("a fork's paths hold different values");
    }
    emit_jump(fl, live.flatMap(([, b]) => b.val.ws), name);
    seg_open(fl, name, fl.seg.ret, null, live, "", [], [o.b]);
  }
  emit_body(fl, o.b, null, ers, [], null);
```

Lines 5789–5832:

```text
// A channel is Data: its handle is copied and may outlive the row, so it
// names the row by index and generation, a freed row waits on a list and
// comes back one generation up, and a stale copy finds no row (closed).
static ChanRow* chan_rows;
static u32      chan_len;
static u32      chan_idle = ~0u;

#define chan_some(e, v) io_box(e, CID_SOME, v, IO_HOTS & 32)
#define chan_bool(b)    term_pak((b) ? CID_TRUE : CID_FALSE, 0)

static Term chan_open(u32 room) {
  u32 i = chan_idle;
  if (i != ~0u) {
    chan_idle = chan_rows[i].next;
  } else {
    if (chan_len == 1u << 24) {
      err_fail("more than 16777216 channels at once");
    }
    if ((chan_len & (chan_len - 1)) == 0) {
      chan_rows = io_mem(realloc(chan_rows,
        (chan_len == 0 ? 1 : 2 * chan_len) * sizeof(ChanRow)));
    }
    i = chan_len;
    chan_len += 1;
    chan_rows[i].gen = 0;
  }
  ChanRow* row = &chan_rows[i];
  row->gen  += 1;
  row->room  = room;
  row->size  = 0;
  row->head  = 0;
  row->live  = 1;
  row->shut  = 0;
  row->ring  = room == 0 ? NULL : io_mem(malloc(room * sizeof(Term)));
  row->wait.head = NULL;
  row->wait.last = NULL;
  return io_hand(((u64)row->gen << 24) | i);
}

static ChanRow* chan_at(Term t) {
  u64      v   = io_hand_v(t);
  u32      i   = (u32)v & 0xFFFFFF;
  ChanRow* row = i < chan_len ? &chan_rows[i] : NULL;
  return row != NULL && row->live && row->gen == (u32)(v >> 24) ? row : NULL;
```

## gates/test.ts

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/gates/test.ts

Full-file SHA-256: `7cc110e76a6112a3030d8c7142979d31031d1273e5cc35034a86660157cb668f`

Lines 48–95:

```text
function test_read(dir: string, file: string): Test {
  const src = fs.readFileSync(path.join(TESTS, dir, file), "utf8");
  const want = src.split("\n").filter((l) => l.startsWith("#|"))
    .map((l) => l.slice(2)).join("\n");
  const effs = [...src.matchAll(/^\s*import "\.\/[a-z0-9_]+\.(c|js)"$/gm)]
    .map((m) => m[1]);
  // A program compiles only over Base (its IO runs main): a test without
  // it checks and interprets alone.
  const lanes = ["js", "c"].filter((l) => /^import Base$/m.test(src)
    && (effs.length === 0 || effs.includes(l)));
  return { name: dir + "_" + path.basename(file, ".bend"), src,
    want: tidy(want), main: /^(def|law) main(\(|:)/m.test(src), lanes };
}

function tidy(text: string): string {
  return text.replace(/[ \t]+$/gm, "").trim();
}

function test_path(t: Test): string {
  return t.name.replace("_", "/") + ".bend";
}

function test_runs(shard: Test[]): Test[] {
  return shard.filter((t) => t.main && t.lanes.length > 0
    && !t.want.startsWith("Error:"));
}

function test_probes(t: Test, got: Got): string[] {
  if (!t.main || t.want.startsWith("Error:")) {
    return ["check"];
  }
  const shown = !/^Error: main's type .* cannot be printed/m.test(got.left ?? "");
  return ["check", "interp", ...shown ? t.lanes : []];
}

function test_judge(t: Test, got: Got): Fail[] {
  const fails: Fail[] = [];
  for (const probe of test_probes(t, got)) {
    const seen = got[probe === "interp" ? "check" : probe] ?? got.left
      ?? "(no answer from the node)";
    const ok = probe === "check" && t.main && !t.want.startsWith("Error:")
      ? !seen.startsWith("Error:") : seen === t.want;
    if (!ok) {
      fails.push({ name: t.name, probe, want: t.want, got: seen });
    }
  }
  return fails;
}
```

Lines 138–187:

```text
// A build that fails leaves its message in <name>.left: the test's lanes
// then read it as their answer, so a program the compiler cannot build
// fails the gate.
function shard_script(shard: Test[], tag: number): string {
  const runs = test_runs(shard);
  const bangs = runs.filter((t) => /!\(/.test(t.src)).map((t) => t.name);
  const probe = (kind: string, cmd: string): string =>
    `echo "${MARK} ${kind} $m"; perl -e 'alarm 5; exec @ARGV' ${cmd} 2>&1;`
    + ` echo "${MARK} exit $?";`;
  return `export BUN_JSC_maxPerThreadStackUsage=33554432;`
    + ` d=$HOME/bend-test/${tag}; rm -rf $d; mkdir -p $d; cd $d; tar -xzf -;`
    + ` echo "${MARK} checkup"; ${BUN} bend2/main.ts main.bend --checkup 2>&1;`
    + ` xargs -P 10 -L 1 sh -c 'm=$1; shift; ${BUN} bend2/main.ts "$@"`
    + ` > $m.left 2>&1 && rm $m.left' -- < build.txt; echo "${MARK} built";`
    + ` for m in ${bangs.join(" ")}; do perl -e 'alarm 60; exec @ARGV' ./$m`
    + ` >/dev/null 2>&1; done; for m in ${runs.map((t) => t.name).join(" ")};`
    + ` do if [ -f $m.left ]; then echo "${MARK} left $m"; cat $m.left;`
    + ` else ${probe("c", "./$m")} ${probe("js", BUN + " $m.js")} fi; done;`
    + ` cd; rm -rf $d`;
}

function shard_parse(shard: Test[], out: string): Map<string, Got> {
  const gots = new Map<string, Got>(shard.map((t) => [t.name, {}]));
  const parts = out.split(new RegExp("^" + MARK + " ", "m")).slice(1);
  let last: [Got, string] | null = null;
  for (const part of parts) {
    const nl = part.indexOf("\n");
    const head = part.slice(0, nl).trim().split(" ");
    const body = part.slice(nl + 1);
    if (head[0] === "checkup") {
      const secs = body.split(/^--- \.\/tests\/([a-z0-9_/]+)\.bend ---\n/m);
      for (let i = 1; i + 1 < secs.length; i += 2) {
        const got = gots.get(secs[i].replace("/", "_"));
        if (got !== undefined) {
          got.check = tidy(secs[i + 1]);
        }
      }
    } else if (head[0] === "c" || head[0] === "js" || head[0] === "left") {
      const got = gots.get(head[1]);
      last = got === undefined || head[0] === "left" ? null : [got, head[0]];
      if (got !== undefined) {
        got[head[0]] = tidy(body);
      }
    } else if (head[0] === "exit" && last !== null && head[1] !== "0") {
      const [got, kind] = last;
      const tail = head[1] === "142" ? "timeout" : "exit " + head[1];
      got[kind] = got[kind] === "" ? tail : got[kind] + "\n" + tail;
    }
  }
  return gots;
```

## gates/perf.ts

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/gates/perf.ts

Full-file SHA-256: `280595f59233caace52c530e019dff93693731806449c130307457c02240cadc`

Lines 54–76:

```text
const HW = "apple_m4";

export const MODES = ["SEQ-CPU", "PAR-CPU", "PAR-GPU"];

export const CC = "cc -std=c11 -O3";

export const BUILD = [CC + " main.c -lpthread", CC + " main.c -lpthread",
  CC + " -DBEND_METAL=1 -x objective-c -fobjc-arc main.c -lpthread"
  + " -framework Metal -framework Foundation"];

const THREADS = "nt=1; while [ $nt -lt $(getconf _NPROCESSORS_ONLN) ] &&"
  + " [ $nt -lt 256 ]; do nt=$((nt*2)); done;";

export const FLAGS = ["--threads 1 --gpu off", "--threads $nt --gpu off",
  "--gpu $gm"];

export const MEMORY: Record<string, string> = {
  "tree-bitonic": "768MB", gameoflife: "512MB", kmeans: "768MB",
  mandelbrot: "512MB", merkle: "768MB", nbody: "768MB",
  queens: "512MB", raytrace: "512MB", symreg: "512MB", terrain: "1GB",
};

const SLACK = 1.15;
```

Lines 264–280:

```text
  c.comp = Number(built[3]) - Number(built[2]);
  if (built[1] !== "0" || ran === null || ran[1] !== "0") {
    c.note = c.bench + " " + MODES[c.mode] + ": " + (built[1] !== "0"
      ? "build: " : "exit " + String(ran?.[1] ?? "?") + ": ")
      + cell_note(got.out);
    return;
  }
  const tail = got.out.split(new RegExp("^" + MARK + " ran .*\n", "m"))[1];
  const [body, time] = (tail ?? "").split(MARK + " time\n");
  const rss = /(\d+)\s+maximum resident set size/.exec(time ?? "");
  c.out = body.split("\n").map((l) => l.trim()).filter((l) => l !== "")
    .pop() ?? "";
  c.secs = Number(ran[3]) - Number(ran[2]);
  c.mem = rss === null ? null : Number(rss[1]) / (1 << 20);
  if (c.mem === null) {
    c.note = c.bench + " " + MODES[c.mode] + ": unreadable time output";
  }
```

Lines 286–302:

```text
async function chk_run(c: Chk, node: number): Promise<void> {
  const script = `d=$HOME/bend-perf/chk-${c.bench}; rm -rf $d; mkdir -p $d;`
    + ` cd $d; tar -xzf -; for i in 1 2 3; do t0=$(${CLOCK}); ${lib.BUN}`
    + ` bend2/main.ts main.bend > out.txt 2>&1; e=$?; t1=$(${CLOCK}); echo`
    + ` "${MARK} check $e $t0 $t1"; cat out.txt; done; cd; rm -rf $d`;
  const got = await lib.ssh(node, script, cell_pack(path.join(CHECKER,
    c.bench)), 20 * 60 * 1000);
  const runs = [...got.out.matchAll(new RegExp("^" + MARK
    + " check (\\d+) ([\\d.]+) ([\\d.]+)$", "gm"))];
  if (runs.length === 0) {
    throw new Error("node", { cause: got.err });
  }
  if (runs.some((r) => r[1] !== "0") || !got.out.includes("All terms check.")) {
    c.note = c.bench + ": " + cell_note(got.out);
    return;
  }
  c.secs = Math.min(...runs.map((r) => Number(r[3]) - Number(r[2])));
```

Lines 351–377:

```text
  const fits = (got: number | null, pin: number | undefined): boolean =>
    got !== null && (PIN || pin !== undefined && got <= pin * SLACK);
  let pass = 0;
  for (const c of cells) {
    const pin = pins.get(c.bench);
    if (!PIN && pin !== undefined && c.out !== pin.out && c.secs !== null) {
      c.note = c.bench + " " + MODES[c.mode] + ": output " + c.out
        + " differs from the pinned " + pin.out;
      c.secs = null;
    }
    pass += Number(fits(c.secs, pin?.secs[c.mode]))
      + Number(fits(c.mem, pin?.mems[c.mode]));
    if (c.mode === 0) {
      const comps = cells.filter((o) => o.bench === c.bench).map((o) => o.comp)
        .filter((x) => x !== null).sort((x, y) => x - y);
      pass += Number(fits(comps[Math.floor(comps.length / 2)] ?? null,
        pin?.comp));
    }
  }
  for (const c of chks) {
    pass += Number(fits(c.secs, cpins.get(c.bench)));
  }
  draw();
  if (!lib.GATE && process.stdout.isTTY !== true) {
    console.log(VIEW.join("\n"));
  }
  lib.verdict(pass, cells.length * 2 + benches.length + chks.length);
```

## gates/repo.ts

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/gates/repo.ts

Full-file SHA-256: `31d8c42180631c11fd769d37d7bf1bd63507fb29fec132e665652c599651bc70`

Lines 26–76:

```text
function allow(at: string | RegExp, cap: number, bytes = false): void {
  RULES.push({ at: typeof at === "string" ? new RegExp("^" + at
    .replace(/[.]/g, "\\.") + "$") : at, cap, bytes });
}

allow(/^\.github\/ISSUE_TEMPLATE\/(bug|feature|config)\.yml$/, 600);
allow(".gitattributes", 200);
allow(".gitignore", 100);
allow("AGENTS.md", 2000);
allow("CHANGELOG.md", 6000);
allow("README.md", 3000);
allow("WONTFIX.txt", 1500);
allow("LICENSE", 4000);
allow("flake.nix", 1500);
allow("bend2/base.bend", 32000);
allow("bend2/bend.lean", 400000);
allow("bend2/bend.ts", 41000);
allow("bend2/comp.ts", 62000);
allow("bend2/main.ts", 10000);
allow(/^bend2\/effs\/[a-z0-9_]+\.(c|js)$/, 4000);
allow(/^bend2\/pack\/(\.gitignore|package\.json|tsconfig\.json|bun\.lock)$/, 1000);
allow(/^bend2\/docs\/(BendRT|BendTT)\/(main\.typ|refs\.bib)$/, 60000);
allow("bend2/docs/bend.sublime-syntax", 1000);
allow("bend2/docs/gen_anim.ts", 7500);
allow("bend2/docs/gen_charts.ts", 4000);
allow("bend2/docs/gen_gifs.ts", 4000);
allow("bend2/docs/gen_pins.ts", 4100);
allow(/^bend2\/docs\/intro\/[a-z.]+$/, 20000);
allow(/^bench\/checker\/[a-z]+_[0-9]+\/main\.(bend|agda|lean|thy|v)$/, 3000000);
allow(/^bench\/checker\/_pin_\/[a-z0-9_]+\.txt$/, 2000);
allow(/^bench\/runtime\/[a-z-]+\/main\.(bend|c|lean|ts)$/, 8000);
allow(/^bench\/runtime\/_pin_\/[a-z0-9_]+\.txt$/, 2000);
allow(/^demos\/[a-z0-9_]+\/[A-Za-z0-9_]+\.bend$/, 64000);
allow(/^demos\/[a-z0-9_]+\/[A-Za-z_]+\.(c|sh|md)$/, 4000);
allow(/^demos\/[a-z0-9_]+\/web\/(index\.html|main\.js|bunfig\.toml)$/, 4000);
allow("guide/GUIDE.md", 12000);
allow("guide/EFFECTS.md", 1600);
allow("guide/SHADERS.md", 4200);
allow(/^paper\/(BendRT|BendTT)\.pdf$/, 400000, true);
allow(/^media\/intro\.(gif|mp4)$/, 25000000, true);
allow(/^media\/(runtime|checker|parallel)\.gif$/, 6000000, true);
allow(/^media\/hero(_dark)?\.gif$/, 200000, true);
allow(/^media\/logo_(bend|hoc)\.png$/, 100000, true);
allow(/^media\/game_[a-z_]+\.gif$/, 2000000, true);
allow(/^media\/slash_boss_3d\/[a-z_]+\.wav$/, 400000, true);
allow(/^gates\/(_lib|_run|perf|ping|repo|test)\.ts$/, 6000);
allow(/^tests\/[a-z]+\/[a-z0-9_]+\.bend$/, 16000);
allow(/^tests\/[a-z]+\/[a-z0-9_]+\.(c|js)$/, 8000);
allow(/^tools\/bend-fmt-lsp\/(\.gitignore|README\.md|package\.json|package-lock\.json|tsconfig\.json)$/, 4000);
allow(/^tools\/bend-fmt-lsp\/src\/(formatter|server)\.ts$/, 8000);
allow(/^tools\/bend-fmt-lsp\/src\/test\/[a-z_]+\.test\.ts$/, 4000);
```

## bend2/docs/BendTT/main.typ

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/docs/BendTT/main.typ

Full-file SHA-256: `6aa6bde23b721a26509b1c78973b6cf0328b0863e76efa0e48242756ff907fbd`

Lines 110–123:

```text
BendTT is the type theory of the Bend programming language. It has one
sort with #Ty : #Ty, no universe hierarchy and datatypes with no
positivity restriction, and it is consistent. What holds it up is a
usage discipline: a value is consumed at most once unless the _kind_ of
its type says otherwise. A binder marked `+` may be consumed any number
of times, and it forms only at the kind #Da. A function type is never
#Da, and a datatype earns #Da at every constructor. So no closure is
ever copied, and every known paradox of #Ty : #Ty or of negative
datatypes copies a closure. Recursion passes one syntactic descent
test. Erased code is free and may diverge; nothing promotes it to
live. Proofs are ordinary definitions: the match
is the eliminator and there are no tactics. We state the calculus, show
how each attack dies, and describe the core's Lean 4 mechanization.
```

Lines 472–500:

```text
For a book that validates, the theory claims subject reduction,
progress, weak normalization of closed live terms, and no closed live
inhabitant of `Empty`. The last three are stated at the live demand
because dead code may rest on an axiom, diverge, or inhabit `Empty` by
design: erased code is specification, not proof. Conversion, and so the
checker, is a semi-decision procedure, as it already is in theories
with divergent types @coquand1991: a hang is "inconclusive", never
"accepted". The stance is soundness on accept, not checker totality, in
the line of NuPRL and Zombie @constablesmith1987 @casinghino2014.

Certify-once has a price. Term-substitution reduction does not preserve
the usage measure: unfold `f(+x)` at `f(y)` and `y` counts twice under
its plain binder. So subject reduction for usage is claimed for weak
by-value reduction of closed terms, the only reduction the machine
performs: when `f` unfolds, `y` is a value whose resources were consumed
once, and the copy is #Da, which owns nothing. Three invariants outside
the checker carry this. No pass duplicates a term: the evaluator shares
every argument, let value and field in a memoized cell, and the
compiler is strict. A type with runtime ownership (a file, a socket, an
array) is declared #Ty, never #Da\; this is a property of the base
library, not a rule. A compiler may drop a copy the source spelled,
never add one @bendrt2026. QTT avoids the question by scaling the
argument's measure, which it can afford because $omega$ is its default;
with $1$ as the default, scaling would leave only closed data reusable.

One escape hatch exists and is always disclosed. A definition marked
`@unsafe` skips descent and forms its `+` binders at any kind; the
checker reports every book that uses one, so a clean report means none
of the claims above is waived.
```

Lines 559–621:

```text
has one owner, so a match frees its scrutinee as it opens it, arrays
update in place, and a forked task carries no lock. Where a `+`
licensed reuse the compiler places a counted share or a borrow, and
nowhere else: reuse was derived from the kind of a type, never proved
by a term, so the runtime never runs a copy the source did not spell.

= The Mechanization <sec:mech>

`bend2/bend.lean` mechanizes the core in Lean 4 @demoura2021: about
twenty thousand lines, no `sorry`, no axiom declarations. A de Bruijn
specification mirrors `bend.ts` section by section; the proofs are
confluence (#co[church_rosser_holds]), subject reduction for weak
reduction (#co[subject_reduction_holds]) and, at the live demand,
progress (#co[progress_holds]), weak normalization
(#co[normalization_holds]) and consistency (#co[consistency_holds]).

The model covers the core of @sec:kinds, with the `+` binder, kinds,
#Da and the meet, but it does not yet fully match the shipped checker:
the file lists where `bend.ts` and the model differ, and we are
resyncing the two. What the file proves stands: a
calculus with #Ty : #Ty and negative datatypes, consistent and
normalizing, guarded by affinity alone. Normalization and consistency are proven with
recursive definitions included, by a Dershowitz--Manna multiset measure
@dershowitzmanna1979 over pending references. The dead boundary is
a witness, not a caveat: in a
well-formed book with a negative type, Curry's self-application term
checks _dead_ at an empty family and, by #co[consistency_holds],
never live.

= Discussion <sec:discussion>

_What affinity takes away._ Contraction on closures. The standard
`map` is ill-typed: `f` is applied once per element, so it would need
`+`, and no function type is #Da. Code is free, so a top-level
definition may be called any number of times, and maps over a named
function cover the common cases; the closure-heavy style of Haskell
does not transfer. Bend accepts this on purpose: the runtime wants the
same restriction @bendrt2026.

_What it keeps._ On the program side the baseline is C: first-order
data, machine words, arrays updated in place, code called by name. That
fragment passes through affinity untouched. On the proof side the reach
is larger: statements are erased and cost nothing, and live proofs draw
their reuse from #Da, which is where induction lives. A universe
hierarchy could be added later; but Bend needs affinity anyway, and
#Ty : #Ty buys impredicative encodings and type-computing definitions
no predicative hierarchy accepts.

_Related work._ Linear and dependent types meet in LLF
@cervesatopfenning2002 and in @krishnaswami2015; the quantitative line
@mcbride2016 @atkey2018 @brady2021 and the graded line @moon2021
@abel2023graded are closest in mechanism, and all keep a universe
hierarchy. Recent linear dependent theories still add universe levels
to avoid Girard's paradox @fuxi2023, or reach an impredicative universe
through a model rather than #Ty : #Ty @speight2026. To our knowledge
none uses the absence of contraction _for_ consistency. Among
mechanized metatheories of practical kernels @abel2018 @sozeau2020
@carneiro2024, ours proves normalization rather than assuming it.

_Limitations._ The consistency result is syntactic, relative to Lean's
own foundation, with no semantic model. The mechanization
lags the shipped checker (@sec:mech). Equality is intensional, with no extensionality
principle. And the theorems are about the calculus, not the code.
```

## bend2/docs/BendRT/main.typ

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/docs/BendRT/main.typ

Full-file SHA-256: `7416bdd19b6f9db3e94082362ca1456a59f047a4cd3f6da93e3d5b6f4b3fba02`

Lines 122–143:

```text
Bend's type system, developed in a companion paper @bendtt2026, is
affine: a live value is consumed at most once unless its binder is
marked `+`, and a `+` binder forms only at the kind `Data`, which
excludes functions, arrays and handles. The theory paper argues that
this wall makes the language consistent. This paper argues that it
also makes the language fast. The costs that runtimes for functional
languages pay most for all come from not knowing who owns a value, and
affinity settles ownership at compile time. Other runtimes need a
garbage collector because nobody knows when a value's last owner
leaves; in Bend the one owner is the match that consumes it, so
deallocation is compiled code. They need work stealing because tasks
are cheap to make and hard to place; in Bend a task owns its
arguments, so a fork moves memory and never shares it, and the only
cross-thread protocol is delivering an answer into a join. They stay
off the GPU, which wants flat memory, no recursion and no runtime;
Bend's evaluator needs no collector, and with one discipline on calls
no C stack either, so the C file is also the shader.

We follow one program from source to C, to tasks, to the GPU dispatch
that runs it. Readers of the author's earlier runtimes may expect
interaction nets @lafont1997 @taelin2024hvm2 here; there are none
(@sec:related).
```

Lines 459–465:

```text
The price is written into the language. Work stealing @blumofe1999
@frigo1998 repairs an unequal split at run time; the cube does not. If
a program forks unequal parts, lanes idle at the end of a work turn,
and the runtime declines to correct that: balance is the program's
job. The idioms are teachable: fork equal halves of the data or the
index space, sequence full-width phases instead of forking phases
against each other, keep light work out of forks.
```

Lines 487–497:

```text
The mark `f!(x)` is honored by the event loop (@sec:io) at a
sequential program point, where nothing else runs. The solo thread
detaches the marked call whole, makes its continuation the root, seeds
it into ring zero and runs the phase loop on the device until the root
delivers; then it hands the answer into the original continuation and
continues on the CPU. Met anywhere else the mark degrades: in the
parallel world it spawns a task rather than nesting, in the sequential
world it is inert, and without a device it is inert everywhere. The
CPU and the GPU never compute at the same time. Floats follow one
semantics on every executor (contraction off, safe math on the
device), and the harness checks that all three print the same bytes.
```

Lines 604–614:

```text
= Limitations <sec:limits>

The equal-parts contract is unverified: a skewed program silently
loses its parallelism. The CPU and the GPU never compute together, and
a mark is honored only at a sequential point. A ring holds 1024 tasks,
a count saturates at $2^24$, a natural at $2^48$, a block at depth 31;
each overflow is a numbered fail-stop, not a fallback. The Metal lane
is measured; the CUDA lane is in the source and not measured here. The
C runtime is unverified: the correctness argument is the checksum
discipline plus the type system's guarantees, and the companion
paper's theorems stop at the calculus.
```

## demos/proof_insertion_sort/LAWS.bend

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/demos/proof_insertion_sort/LAWS.bend

Full-file SHA-256: `e629a1db78d61c3ce926fdc51b6519a9b29262ffa85a1ca05deadd32ceac00ac`

Lines 1–17:

```text
# proof_insertion_sort: the laws. The human states them; PROOF.bend
# must prove them. A permutation is stated by counts.

import Base
import ./main.bend as Sort

# LAW: the output of sort is sorted: it ascends, starting at 0n
law sort_sorted:
  for +xs: List<&2, Nat>
  Sort.Sorted(Sort.sort(xs))

# LAW: sort permutes its input: every value x occurs in sort(xs) as
# often as it occurs in xs
law sort_perm:
  for +x  : Nat
  for +xs : List<&2, Nat>
  {Sort.count(x, Sort.sort(xs)) == Sort.count(x, xs) : Nat}
```

## demos/proof_insertion_sort/PROOF.bend

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/demos/proof_insertion_sort/PROOF.bend

Full-file SHA-256: `7ff555b2a8c2d65427ffd18b1539b69860b59a34e7dd76d931b97f7ba0f2761b`

Lines 26–39:

```text
def sorted_ins(xs: List<&2, Nat>, -lo: Nat, +x: Nat) -> Sort.Sorted.from(lo, xs) -> Sort.LE(lo, x) -> Sort.Sorted.from(lo, Sort.insert(x, xs)):
  match xs:
    case Nil{}:
      sx => lx => (lx, Unit{})
    case h <> t:
      sx => lx => sorted_ins.fin(lo, x, h, t, sx, lx, sorted_ins(t, h, x), Sort.le_case(x, h))

# sort(h <> t) inserts h into the sorted sort(t); 0n bounds everything
def Laws.sort_sorted(xs):
  match xs:
    case Nil{}:
      Unit{}
    case h <> t:
      sorted_ins(Sort.sort(t), 0n, h)(Laws.sort_sorted(t), Unit{})
```

Lines 58–83:

```text
def count_ins.fin(+x: Nat, y: Nat, h: Nat, -t: List<&2, Nat>, rec: {Sort.count(x, y <> t) == Sort.count(x, Sort.insert(y, t)) : Nat}, c: Or(Sort.LE(y, h), Sort.LE(h, y)))
  -> {Sort.count(x, y <> h <> t) == Sort.count(x, Sort.dec(y, h, t, Sort.insert(y, t), c)) : Nat}:
  match c:
    case Inl{e}:
      {==}
    case Inr{e}:
      %rec : {Sort.count(x, y <> h <> t) == Sort.bump(Cmp.is_eq(Nat.cmp(x, h)), _) : Nat}
      bump_swap(Cmp.is_eq(Nat.cmp(x, y)), Cmp.is_eq(Nat.cmp(x, h)), Sort.count(x, t))

def count_ins(+x: Nat, +y: Nat, +xs: List<&2, Nat>) -> {Sort.count(x, y <> xs) == Sort.count(x, Sort.insert(y, xs)) : Nat}:
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      count_ins.fin(x, y, h, t, count_ins(x, y, t), Sort.le_case(y, h))

# count(x, sort(h <> t)) is count(x, insert(h, sort(t))): count_ins
# turns it into count(x, h <> sort(t)), and the IH closes the tail
def Laws.sort_perm(x, xs):
  match xs:
    case Nil{}:
      {==}
    case h <> t:
      %count_ins(x, h, Sort.sort(t)) : {_ == Sort.bump(Cmp.is_eq(Nat.cmp(x, h)), Sort.count(x, t)) : Nat}
      %Laws.sort_perm(x, t) : {Sort.bump(Cmp.is_eq(Nat.cmp(x, h)), Sort.count(x, Sort.sort(t))) == Sort.bump(Cmp.is_eq(Nat.cmp(x, h)), _) : Nat}
      {==}
```

## bend2/effs/file_read.c

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bend2/effs/file_read.c

Full-file SHA-256: `4ec0b13491c0d9564836ad23b5a65aec930d84bd19e36c90e20e9c34211a7e2b`

Lines 1–24:

```text
// File
// ====

static void file_read_call(IoWork* w) {
  int fd = (int)w->hand;
  w->size = io_sys_end(w, read(fd, w->data, w->word));
}

static Term file_read_pack(Env e, IoWork* w) {
  Term r = w->code ? io_fail(e, w->code, NULL)
    : io_done(e, io_str(e, w->data, w->size));
  free(w->data);
  return io_tup(e, io_hand(w->hand), r);
}

Term file_read_run(Env e, Term* f, IoWork* w) {
  w->hand = (intptr_t)io_hand_v(f[0]);
  w->word = f[1] < INT32_MAX ? f[1] : INT32_MAX;
  w->data = io_mem(malloc(w->word + 1));
  return io_work(w, file_read_call, file_read_pack);
}

static void __attribute__((constructor)) file_read_use(void) {
  io_eff(CID_FILE_READ, file_read_run, 0);
```

## bench/runtime/_pin_/apple_m4_max.txt

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/bench/runtime/_pin_/apple_m4_max.txt

Full-file SHA-256: `6b3462529e11b1c114b4b4bf5220665701efd571ee819d2c19109197f14d9ffa`

Lines 1–21:

```text
# Runtime
# 2026-09-17 d0db7b3e bun bend2/docs/gen_pins.ts runtime

| bench        | SEQ-CPU         | PAR-CPU         | PAR-GPU         | C        | TS       | Lean     |
|--------------|-----------------|-----------------|-----------------|----------|----------|----------|
| bfs          |   3.918s   2.0M |   0.343s   2.7M |   0.207s  16.8M |   3.585s |   6.534s |   9.274s |
| editdist     |   2.559s   2.0M |   0.236s   3.1M |   0.144s  16.8M |   2.002s |   5.290s |   4.799s |
| gameoflife   |   7.803s   2.1M |   0.647s   2.7M |   0.063s  16.7M |   6.776s |  18.754s |  13.849s |
| hashmap      |   2.741s   2.4M |   0.238s   9.0M |   0.521s  16.8M |   0.622s |   0.892s |   1.526s |
| kmeans       |   2.069s  23.5M |   0.268s  24.1M |   0.191s  17.1M |   2.062s |  17.455s |   5.686s |
| lexer        |   2.144s   2.0M |   0.198s   3.0M |   1.075s  16.9M |   1.036s |   3.543s |   4.487s |
| mandelbrot   |   4.473s   2.3M |   0.395s   2.9M |   0.057s  16.9M |   3.750s |   3.837s |   4.575s |
| merkle       |   4.222s   130M |   0.422s   131M |   0.071s  17.5M |   3.423s |   7.227s |   5.986s |
| nbody        |   5.758s   2.2M |   0.516s   2.7M |   0.059s  16.8M |   5.126s |   5.332s |   5.387s |
| queens       |   5.406s   2.0M |   0.455s   2.5M |   0.933s  16.8M |   3.599s |   6.979s |   7.704s |
| raytrace     |   4.616s   2.1M |   0.396s   2.6M |   0.151s  17.0M |   3.646s |  23.039s |  10.825s |
| symreg       |   3.014s   2.1M |   0.266s   3.1M |   0.529s  17.1M |   2.208s |   5.924s |   2.457s |
| terrain      |   2.225s   2.1M |   0.197s   3.3M |   0.106s  16.9M |   2.198s |   5.746s |   8.039s |
| tree-bitonic |   6.043s   146M |   0.799s   156M |   0.450s  17.0M |   5.719s |  33.910s |  38.123s |
| tree-matmul  |   2.064s   2.8M |   0.226s  14.8M |   0.231s  17.3M |   2.964s |  11.379s |   7.758s |
| tree-radix   |   4.083s   651M |   0.445s   617M |   0.314s  17.0M |   2.791s |   6.244s |   6.500s |
```

## LICENSE

Source: https://github.com/bendlang/bend/blob/15ae0c86f3193b8f645b4bedbc438655b648d0da/LICENSE

Full-file SHA-256: `0beb288abd3d067e231f3fbe7df1f8ee37344061fc67f22018150a19e4b26c35`

Lines 1–202:

```text

                                 Apache License
                           Version 2.0, January 2004
                        http://www.apache.org/licenses/

   TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION

   1. Definitions.

      "License" shall mean the terms and conditions for use, reproduction,
      and distribution as defined by Sections 1 through 9 of this document.

      "Licensor" shall mean the copyright owner or entity authorized by
      the copyright owner that is granting the License.

      "Legal Entity" shall mean the union of the acting entity and all
      other entities that control, are controlled by, or are under common
      control with that entity. For the purposes of this definition,
      "control" means (i) the power, direct or indirect, to cause the
      direction or management of such entity, whether by contract or
      otherwise, or (ii) ownership of fifty percent (50%) or more of the
      outstanding shares, or (iii) beneficial ownership of such entity.

      "You" (or "Your") shall mean an individual or Legal Entity
      exercising permissions granted by this License.

      "Source" form shall mean the preferred form for making modifications,
      including but not limited to software source code, documentation
      source, and configuration files.

      "Object" form shall mean any form resulting from mechanical
      transformation or translation of a Source form, including but
      not limited to compiled object code, generated documentation,
      and conversions to other media types.

      "Work" shall mean the work of authorship, whether in Source or
      Object form, made available under the License, as indicated by a
      copyright notice that is included in or attached to the work
      (an example is provided in the Appendix below).

      "Derivative Works" shall mean any work, whether in Source or Object
      form, that is based on (or derived from) the Work and for which the
      editorial revisions, annotations, elaborations, or other modifications
      represent, as a whole, an original work of authorship. For the purposes
      of this License, Derivative Works shall not include works that remain
      separable from, or merely link (or bind by name) to the interfaces of,
      the Work and Derivative Works thereof.

      "Contribution" shall mean any work of authorship, including
      the original version of the Work and any modifications or additions
      to that Work or Derivative Works thereof, that is intentionally
      submitted to Licensor for inclusion in the Work by the copyright owner
      or by an individual or Legal Entity authorized to submit on behalf of
      the copyright owner. For the purposes of this definition, "submitted"
      means any form of electronic, verbal, or written communication sent
      to the Licensor or its representatives, including but not limited to
      communication on electronic mailing lists, source code control systems,
      and issue tracking systems that are managed by, or on behalf of, the
      Licensor for the purpose of discussing and improving the Work, but
      excluding communication that is conspicuously marked or otherwise
      designated in writing by the copyright owner as "Not a Contribution."

      "Contributor" shall mean Licensor and any individual or Legal Entity
      on behalf of whom a Contribution has been received by Licensor and
      subsequently incorporated within the Work.

   2. Grant of Copyright License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      copyright license to reproduce, prepare Derivative Works of,
      publicly display, publicly perform, sublicense, and distribute the
      Work and such Derivative Works in Source or Object form.

   3. Grant of Patent License. Subject to the terms and conditions of
      this License, each Contributor hereby grants to You a perpetual,
      worldwide, non-exclusive, no-charge, royalty-free, irrevocable
      (except as stated in this section) patent license to make, have made,
      use, offer to sell, sell, import, and otherwise transfer the Work,
      where such license applies only to those patent claims licensable
      by such Contributor that are necessarily infringed by their
      Contribution(s) alone or by combination of their Contribution(s)
      with the Work to which such Contribution(s) was submitted. If You
      institute patent litigation against any entity (including a
      cross-claim or counterclaim in a lawsuit) alleging that the Work
      or a Contribution incorporated within the Work constitutes direct
      or contributory patent infringement, then any patent licenses
      granted to You under this License for that Work shall terminate
      as of the date such litigation is filed.

   4. Redistribution. You may reproduce and distribute copies of the
      Work or Derivative Works thereof in any medium, with or without
      modifications, and in Source or Object form, provided that You
      meet the following conditions:

      (a) You must give any other recipients of the Work or
          Derivative Works a copy of this License; and

      (b) You must cause any modified files to carry prominent notices
          stating that You changed the files; and

      (c) You must retain, in the Source form of any Derivative Works
          that You distribute, all copyright, patent, trademark, and
          attribution notices from the Source form of the Work,
          excluding those notices that do not pertain to any part of
          the Derivative Works; and

      (d) If the Work includes a "NOTICE" text file as part of its
          distribution, then any Derivative Works that You distribute must
          include a readable copy of the attribution notices contained
          within such NOTICE file, excluding those notices that do not
          pertain to any part of the Derivative Works, in at least one
          of the following places: within a NOTICE text file distributed
          as part of the Derivative Works; within the Source form or
          documentation, if provided along with the Derivative Works; or,
          within a display generated by the Derivative Works, if and
          wherever such third-party notices normally appear. The contents
          of the NOTICE file are for informational purposes only and
          do not modify the License. You may add Your own attribution
          notices within Derivative Works that You distribute, alongside
          or as an addendum to the NOTICE text from the Work, provided
          that such additional attribution notices cannot be construed
          as modifying the License.

      You may add Your own copyright statement to Your modifications and
      may provide additional or different license terms and conditions
      for use, reproduction, or distribution of Your modifications, or
      for any such Derivative Works as a whole, provided Your use,
      reproduction, and distribution of the Work otherwise complies with
      the conditions stated in this License.

   5. Submission of Contributions. Unless You explicitly state otherwise,
      any Contribution intentionally submitted for inclusion in the Work
      by You to the Licensor shall be under the terms and conditions of
      this License, without any additional terms or conditions.
      Notwithstanding the above, nothing herein shall supersede or modify
      the terms of any separate license agreement you may have executed
      with Licensor regarding such Contributions.

   6. Trademarks. This License does not grant permission to use the trade
      names, trademarks, service marks, or product names of the Licensor,
      except as required for reasonable and customary use in describing the
      origin of the Work and reproducing the content of the NOTICE file.

   7. Disclaimer of Warranty. Unless required by applicable law or
      agreed to in writing, Licensor provides the Work (and each
      Contributor provides its Contributions) on an "AS IS" BASIS,
      WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
      implied, including, without limitation, any warranties or conditions
      of TITLE, NON-INFRINGEMENT, MERCHANTABILITY, or FITNESS FOR A
      PARTICULAR PURPOSE. You are solely responsible for determining the
      appropriateness of using or redistributing the Work and assume any
      risks associated with Your exercise of permissions under this License.

   8. Limitation of Liability. In no event and under no legal theory,
      whether in tort (including negligence), contract, or otherwise,
      unless required by applicable law (such as deliberate and grossly
      negligent acts) or agreed to in writing, shall any Contributor be
      liable to You for damages, including any direct, indirect, special,
      incidental, or consequential damages of any character arising as a
      result of this License or out of the use or inability to use the
      Work (including but not limited to damages for loss of goodwill,
      work stoppage, computer failure or malfunction, or any and all
      other commercial damages or losses), even if such Contributor
      has been advised of the possibility of such damages.

   9. Accepting Warranty or Additional Liability. While redistributing
      the Work or Derivative Works thereof, You may choose to offer,
      and charge a fee for, acceptance of support, warranty, indemnity,
      or other liability obligations and/or rights consistent with this
      License. However, in accepting such obligations, You may act only
      on Your own behalf and on Your sole responsibility, not on behalf
      of any other Contributor, and only if You agree to indemnify,
      defend, and hold each Contributor harmless for any liability
      incurred by, or claims asserted against, such Contributor by reason
      of your accepting any such warranty or additional liability.

   END OF TERMS AND CONDITIONS

   APPENDIX: How to apply the Apache License to your work.

      To apply the Apache License to your work, attach the following
      boilerplate notice, with the fields enclosed by brackets "[]"
      replaced with your own identifying information. (Don't include
      the brackets!)  The text should be enclosed in the appropriate
      comment syntax for the file format. We also recommend that a
      file or class name and description of purpose be included on the
      same "printed page" as the copyright notice for easier
      identification within third-party archives.

   Copyright 2026 HigherOrderCO

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
```
