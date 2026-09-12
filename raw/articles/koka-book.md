---
source_url: https://koka-lang.github.io/koka/doc/book.html
ingested: 2026-09-12
sha256: 8f742efa928d61d81f7b4a0f9c1e95e75750bc6d7397817866edebf12f75f0d9
---
# The Koka Programming Language

The Koka Programming Language

# 1. Getting started

Welcome to Koka – a strongly typed functional-style language with effect types and handlers. 

Note: Koka v3 is a research language that is currently under development and not ready for production use. Nevertheless, the language is stable and the compiler implements the full specification. The main things lacking at the moment are (async) libraries and package management. 

News: 

- 2026-03-17: Koka v3.2.3 released. Improved implicits and overloading support corresponding to the technical report “ Syntactic Implicits with Static Overloading”, Daan Leijen and Tim Whiting (pdf, conditionally accepted at PLDI'26). 
- 2025-07-22: Koka v3.2.2 released. Bug fix release. 
- 2025-07-17: Koka v3.2.0 released. Now uses the keyword `hole` to denote holes in a constructor context, while underscore is now used to automatically eta-expand arguments (e.g. `[1].map(inc(_)))`). Implicit resolving requires unique solutions now, but takes scoping into account. No more qualified types but we use instead implicit phantom parameters that are resolved by the compiler. See the whatsnew for more information. 
- 2025-07-17: Two of the distinguished paper awards at PLDI'25 went to papers that use Koka: “ Practical Type Inference with Levels”, Andong Fan, Han Xu, and Ningning Xie (pdf), and “ Principal Type Inference under a Prefix”, Daan Leijen and Wenjia Ye (pdf). The latter formalizes the static overloading resolution used in the Koka language. 
- 2025-07-03: Koka v3.1.3 released. Add applier syntax `.()` where `x.f.(42)` is sugar for `(x.f)(42)` which can be convenient when calling functions selected from a struct. Also adds support for lazy constructors – see “ First-order Laziness” by Anton Lorenzen, Daan Leijen, Wouter Swierstra, and Sam Lindley (ICFP'25, distinguished paper) pdf. 
- 2024-05-30: Koka v3.1.2 released which fixes Koka installs outside a VS Code workspace. 
- 2024-05-30: Read the paper on “ The Functional Essence of Binary Search Trees” by Anton Lorenzen, Daan Leijen, Sam Lindley, and Wouter Swierstra to be presented at PLDI'24 on June 27. 
- 2024-05-30: View the talk on the design and compilation of efficient effect handlers in Koka as part of Xavier Leroy's beautiful lecture series on control structures and algebraic effects at the Collège de France (with many other invited talks available online). 
- 2024-03-04: Koka v3.1.1 released with a language server crash fix. 
- 2024-02-14: Koka v3.1.0 released with a concurrent build system and improved language service over the stdio protocol. Redesign of named effect typing to match the formal system more closely. See `samples/handlers/named` for examples. 
- 2024-01-25: Koka v3.0.4 released with improved VS Code hover and inlay information. Splits `std/core` in multiple modules, fixes bug in infinite expansion for implicits and various other small improvements. 
- 2024-01-13: Koka v3.0.1 released with improved VS Code integration and inlay hints. Initial support for locally qualified names and implicit parameters (see the `samples/syntax`). Various small bug fixes. 
- 2023-12-30: Koka v2.6.0 released with VS Code language integration with type information, jump to definition, run test functions directly from the editor, automatic Koka installation, and many more things. Special thanks to Tim Whiting and Fredrik Wieczerkowski for all their work on making this possible! 
- 2023-12-27: Update of the technical report on " The functional essence of binary trees" where we use fully-in-place programming and the new hole contexts to create fully verified functional implementations of binary search tree algorithms with performance on par with imperative C implementations. 
- 2023-07-03: Koka v2.4.2 released: add support for `fip` and `fbip` keywords described in “FP 2: Fully in-Place Functional Programming” (ICFP'23) [pdf]. Various fixes and performance improvements. 
- 2021-02-04 (pinned) The Context Free youtube channel posted a short and fun video about effects in Koka (and 12 (!) other languages). 
- 2021-09-01 (pinned) The ICFP'21 tutorial “ Programming with Effect Handlers and FBIP in Koka” is now available on youtube. 
- 2022-02-07: Koka v2.4.0 released: improved specialization and `int` operations, add `rbtree-fbip` sample, improve grammar (`pub` (instead of `public`, remove private (as everything is private by default now)), `final ctl` (instead of `brk`), underscores in number literals, etc), rename `double` to `float64`, various bug fixes. 
- 2021-12-27: Koka v2.3.8 released: improved `int` performance, various bug fixes, update wasm backend, initial conan support, fix js backend. 
- 2021-11-26: Koka v2.3.6 released: `maybe`-like types are already value types, but now also no longer need heap allocation if not nested (and `[Just(1)]` uses the same heap space as `[1]`), improved atomic refcounting (by Anton Lorenzen), improved specialization (by Steven Fontanella), various small fixes, add `std/os/readline`, fix build on freeBSD 
- 2021-10-15: Koka v2.3.2 released, with initial wasm support (use `--target=wasm`, and install emscripten and wasmtime), improved reuse specialization (by Anton Lorenzen), and various bug fixes. 
- 2021-09-29: Koka v2.3.1 released, with improved TRMC optimizations, and improved reuse (the rbtree benchmark is as fast as C++ now), and faster effect operations. Experimental: allow elision of `->` in anonymous function expressions (e.g. `xs.map( fn(x) x + 1 )`) and operation clauses. Command line options changed a bit with `.koka` as the standard output directory. 
- 2021-09-20: Koka v2.3.0 released, with new brace elision and if/match conditions without parenthesis. Updated the javascript backend using ES6 modules and BigInt. new `module std/num/int64`, improved effect operation performance. 
- 2021-09-05: Koka v2.2.1 released, with initial parallel tasks, the binary-trees benchmark, and brace elision. 
- 2021-08-26: Koka v2.2.0 released, improved simplification (by Rashika B), cross-module specialization (Steven Fontanella), and borrowing annotations with improved reuse analysis (Anton Lorenzen). 
- 2021-08-26: At 12:30 EST was the live Koka tutorial at ICFP'21, see it on youtube. 
- 2021-08-23: “ Generalized Evidence Passing for Effect Handlers”, by Ningning Xie and Daan Leijen presented at ICFP'21. See it on youtube or read the paper. 
- 2021-08-22: “ First-class Named Effect Handlers”, by Youyou Cong, Ningning Xie, and Daan Leijen presented at HOPE'21. See it on youtube or read the paper. 
- 2021-06-23: Koka v2.1.9 released, initial cross-module specialization (by Steven Fontanella). 
- 2021-06-17: Koka v2.1.8 released, initial Apple M1 support. 
- The Perceus paper won a distinguished paper award at PLDI'21! 
- 2021-06-10: Koka v2.1.6 released. 
- 2021-05-31: Koka v2.1.4 released. 
- 2021-05-01: Koka v2.1.2 released. 
- 2021-03-08: Koka v2.1.1 released. 
- 2021-02-14: Koka v2.0.16 released. 
- 2020-12-12: Koka v2.0.14 released. 
- 2020-12-02: Koka v2.0.12 released. 
- 2020-11-29: Perceus technical report published (pdf). 

### 1.1.1. Install with the VS Code editor

 

The easiest way to start with Koka is to use the excellent VS Code editor and install the Koka extension. Go to the extension panel, search for `Koka` and install the official extension as shown on the right. 

Installing the extension also prompts to install the latest Koka compiler on your platform (available for Windows x64, MacOS x64 and arm64, and Linux x64). 

Once installed, the samples directory is opened. You can also open this manually from the command panel (`Ctrl/Cmd+Shift+P`), and running the `Koka: Open samples` command (when you start typing the command will surface to the top). Open for example the `basic/caesar.kk` file: When you click `run debug` (or `optimized`) Koka compiles and runs the function, showing the output in the VS Code terminal. 

 

Press and hold `ctrl+alt` (or `ctrl+option` on MacOS) to show inlay hints – showing inferred types, fully qualified names, and implicit arguments. 

 

 versus 

### 1.1.2. Manual Installation

On Windows (x64), open a `cmd` prompt and use: 

```
curl -sSL -o %tmp%\install-koka.bat https://github.com/koka-lang/koka/releases/latest/download/install.bat && %tmp%\install-koka.bat
```

On Linux (x64) and macOS (x64, arm64 (M1/M2)), you can install Koka using: 

```
curl -sSL https://github.com/koka-lang/koka/releases/latest/download/install.sh | sh
```

(If you previously installed Koka on macOS using `brew`, do an `brew uninstall koka` first). On other platforms it is usually easy to build Koka from source instead. 

After installation, verify if Koka installed correctly: 

```
$ koka
 _         _
| |       | |
| | _ ___ | | _ __ _
| |/ / _ \| |/ / _' |  welcome to the koka interactive compiler
|   ( (_) |   ( (_| |  version 2.4.0, Feb  7 2022, libc x64 (gcc)
|_|\_\___/|_|\_\__,_|  type :? for help, and :q to quit

loading: std/core
loading: std/core/types
loading: std/core/hnd
>
```

Type `:q` to exit the interactive environment. 

For detailed installation instructions and other platforms see the releases page. It is also straightforward to build the compiler from source. 

## 1.2. Running the compiler

 

Note that when using the VS Code editor, you can directly compile and run public functions that are named `main`, `example...`, or `test...` from the editor environment. 

Of course, we can also run the compiler directly from a command line or use the interactive environment. 

### 1.2.1. Command line usage

You can compile a Koka source as (note that all `samples` are pre-installed): 

```
$ koka samples/basic/caesar.kk
compile: samples/basic/caesar.kk
loading: std/core
loading: std/core/types
...
check  : samples/basic/caesar
linking: samples_basic_caesar
created: .koka/v2.3.1/gcc-debug/samples_basic_caesar
```

and run the resulting executable: 

```
$ .koka/v2.3.1/gcc-debug/samples_basic_caesar
plain  : Koka is a well-typed language
encoded: Krnd lv d zhoo-wbshg odqjxdjh
cracked: Koka is a well-typed language
```

The `-O2` flag builds an optimized program. Let's try it on a purely functional implementation of balanced insertion in a red-black tree (`rbtree.kk`): 

```
$ koka -O2 -o kk-rbtree samples/basic/rbtree.kk
...
linking: samples_basic_rbtree
created: .koka/v2.3.1/gcc-drelease/samples_basic_rbtree
created: kk-rbtree

$ time ./kk-rbtree
420000
real    0m0.626s
```

(On Windows you can give the `--kktime` option to see the elapsed time). We can compare this against an in-place updating C++ implementation using `stl::map` (`rbtree.cpp`) (which also uses a red-black tree internally): 

```
$ clang++ --std=c++17 -o cpp-rbtree -O3 /usr/local/share/koka/v2.3.1/lib/samples/basic/rbtree.cpp
$ time ./cpp-rbtree
420000
real    0m0.667s
```

The excellent performance relative to C++ here (on Ubuntu 20.04 with an AMD 5950X) is the result of Perceus automatically transforming the fast path of the pure functional rebalancing to use mostly in-place updates, closely mimicking the imperative rebalancing code of the hand optimized C++ library. 

### 1.2.2. Running the interactive compiler

Without giving any input files, the interactive environment runs by default: 

```
$ koka
 _         _
| |       | |
| | _ ___ | | _ __ _
| |/ / _ \| |/ / _' |  welcome to the koka interactive compiler
|   ( (_) |   ( (_| |  version 2.3.1, Sep 21 2021, libc x64 (clang-cl)
|_|\_\___/|_|\_\__,_|  type :? for help, and :q to quit

loading: std/core
loading: std/core/types
loading: std/core/hnd
>
```

Now you can test some expressions: 

```
> println("hi koka")
check  : interactive
check  : interactive
linking: interactive
created: .koka\v2.3.1\clang-cl-debug\interactive

hi koka

> :t "hi"
string

> :t println("hi")
console ()
```

Or load a demo (use `tab` completion to avoid typing too much): 

```
> :l samples/basic/fibonacci
> main()
...

The 10000th fibonacci number is 33644764876431783266621612005107543310302148460680063906564769974680081442166662368155595513633734025582065332680836159373734790483865268263040892463056431887354544369559827491606602099884183933864652731300088830269235673613135117579297437854413752130520504347701602264758318906527890855154366159582987279682987510631200575428783453215515103870818298969791613127856265033195487140214287532698187962046936097879900350962302291026368131493195275630227837628441540360584402572114334961180023091208287046088923962328835461505776583271252546093591128203925285393434620904245248929403901706233888991085841065183173360437470737908552631764325733993712871937587746897479926305837065742830161637408969178426378624212835258112820516370298089332099905707920064367426202389783111470054074998459250360633560933883831923386783056136435351892133279732908133732642652633989763922723407882928177953580570993691049175470808931841056146322338217465637321248226383092103297701648054726243842374862411453093812206564914032751086643394517512161526545361333111314042436854805106765843493523836959653428071768775328348234345557366719731392746273629108210679280784718035329131176778924659089938635459327894523777674406192240337638674004021330343297496902028328145933418826817683893072003634795623117103101291953169794607632737589253530772552375943788434504067715555779056450443016640119462580972216729758615026968443146952034614932291105970676243268515992834709891284706740862008587135016260312071903172086094081298321581077282076353186624611278245537208532365305775956430072517744315051539600905168603220349163222640885248852433158051534849622434848299380905070483482449327453732624567755879089187190803662058009594743150052402532709746995318770724376825907419939632265984147498193609285223945039707165443156421328157688908058783183404917434556270520223564846495196112460268313970975069382648706613264507665074611512677522748621598642530711298441182622661057163515069260029861704945425047491378115154139941550671256271197133252763631939606902895650288268608362241082050562430701794976171121233066073310059947366875
```

You can also set command line options in the interactive environment using `:set `. For example, we can load the `rbtree` example again and print out the elapsed runtime with `--showtime`: 

```
> :set --showtime
> :l samples/basic/rbtree.kk
> main()
...

420000
info: elapsed: 4.104s, user: 4.046s, sys: 0.062s, rss: 231mb
```

and then enable optimizations with `-O2` and run again (on Windows with an AMD 5950X): 

```
> :set -O2
> :r
> main()
...

420000
info: elapsed: 0.670s, user: 0.656s, sys: 0.015s, rss: 198mb
```

And finally we quit the interpreter: 

```
> :q

I think of my body as a side effect of my mind.
  -- Carrie Fisher (1956)
```

What next? 

Basic Koka syntax Browse the Library documentation 

# 2. Why Koka?

There are many new languages being designed, but only few bring fundamentally new concepts – like Haskell with pure versus monadic programming, or Rust with borrow checking. Koka distinguishes itself through effect typing, effect handlers, and Perceus memory management: 

Minimal but General The core of Koka consists of a small set of well-studied language features, like first-class functions, a polymorphic type- and effect system, algebraic data types, and effect handlers. Each of these is composable and avoid the addition of “special” extensions by being as general as possible. 

Effect Types Koka tracks the (side) effects of every function in its type, where pure and effectful computations are distinguished. The precise effect typing gives Koka rock-solid semantics backed by well-studied category theory, which makes Koka particularly easy to reason about for both humans and compilers. 

Effect Handlers Effect handlers let you define advanced control abstractions, like exceptions, async/await, or probabilistic programs, as a user library in a typed and composable way. 

Perceus Reference Counting Perceus is an advanced compilation method for reference counting. This lets Koka compile directly to C code without needing a garbage collector or runtime system! This also gives Koka excellent performance in practice. 

Reuse Analysis Through Perceus, Koka can do reuse analysis and optimize functional-style programs to use in-place updates. 

## 2.1. Minimal but General

Koka has a small core set of orthogonal, well-studied language features – but each of these is as general and composable as possible, such that we do not need further “special” extensions. Core features include first-class functions, a higher-rank impredicative polymorphic type- and effect system, algebraic data types, and effect handlers. 

```
fun hello-ten()
  var i := 0
  while { i < 10 }
    println("hello")
    i := i + 1
fun hello-ten()
  var i := 0
  while { i < 10 }
    println("hello")
    i := i + 1

```

As an example of the min-gen design principle, Koka implements most control-flow primitives as regular functions. An anonymous function can be written as `fn(){ }`; but as a syntactic convenience, any function without arguments can be shortened further to use just braces, as `{ }`. Moreover, using brace elision, any indented block automatically gets curly braces. 

We can write a `whilestd/core/while: forall (predicate : () -> <div|e> bool, action : () -> <div|e> ()) -> <div|e> ()` loop now using regular function calls as shown in the example, where the call to `whilestd/core/while: forall (predicate : () -> <div|e> bool, action : () -> <div|e> ()) -> <div|e> ()` is desugared to `whilestd/core/while: forall (predicate : () -> <div|e> bool, action : () -> <div|e> ()) -> <div|e> ()( fn(){ i < 10 }, fn(){ ... } )`. 

This also naturally leads to consistency: an expression between parenthesis is always evaluated before a function call, whereas an expression between braces (ah, suspenders!) is suspended and may be never evaluated or more than once (as in our example). This is inconsistent in most other languages where often the predicate of a `whilestd/core/while: forall (predicate : () -> <div|e> bool, action : () -> <div|e> ()) -> <div|e> ()` loop is written in parenthesis but may be evaluated multiple times. 

## 2.2. Effect Typing

Koka infers and tracks the effect of every function in its type – and a function type has 3 parts: the argument types, the effect type, and the type of the result. For example: 

```
fun sqr    : (int) -> total int       // total: mathematical total function    
fun divide : (int,int) -> exn int     // exn: may raise an exception (partial)  
fun turing : (tape) -> div int        // div: may not terminate (diverge)  
fun print  : (string) -> console ()   // console: may write to the console  
fun rand   : () -> ndet int           // ndet: non-deterministic  
fun sqr    : (intstd/core/types/int: V) -> totalstd/core/types/total: E intstd/core/types/int: V       // total: mathematical total function    
fun divide : (intstd/core/types/int: V,intstd/core/types/int: V) -> exnstd/core/exn/exn: (E, V) -> V intstd/core/types/int: V     // exn: may raise an exception (partial)  
fun turing : (tape) -> divstd/core/types/div: X intstd/core/types/int: V        // div: may not terminate (diverge)  
fun print  : (stringstd/core/types/string: V) -> consolestd/core/console/console: X ()   // console: may write to the console  
fun rand   : () -> ndetstd/core/types/ndet: X intstd/core/types/int: V           // ndet: non-deterministic  

```

The precise effect typing gives Koka rock-solid semantics and deep safety guarantees backed by well-studied category theory, which makes Koka particularly easy to reason about for both humans and compilers. (Given the importance of effect typing, the name Koka was derived from the Japanese word for effective (効果, こうか, Kōka)). 

A function without any effect is called `totalstd/core/types/total: E` and corresponds to mathematically total functions – a good place to be. Then we have effects for partial functions that can raise exceptions (`exnstd/core/exn/exn: (E, V) -> V`), and potentially non-terminating functions as `divstd/core/types/div: X` (divergent). The combination of `exnstd/core/exn/exn: (E, V) -> V` and `divstd/core/types/div: X` is called `purestd/core/pure: E` as that corresponds to Haskell's notion of purity. On top of that we find mutability (as `ststd/core/types/st: H -> E`) up to full non-deterministic side effects in `iostd/core/io: E`. 

Effects can be polymorphic as well. Consider mapping a function over a list: 

```
fun map( xs : list<a>, f : a -> e b ) : e list<b> 
  match xs
    Cons(x,xx) -> Cons( f(x), map(xx,f) )
    Nil        -> Nil  
fun map( xs : liststd/core/types/list: V -> V<a>, f : a -> e b ) : e liststd/core/types/list: V -> V<b> 
  match xs
    Consstd/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>(x,xx) -> Consstd/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>( f(x), map(xx,f) )
    Nilstd/core/types/Nil: forall<a> list<a>        -> Nilstd/core/types/Nil: forall<a> list<a>  

```

Single letter types are polymorphic (aka, generic), and Koka infers that you map from a list of elements `a` to a list of elements of type `b`. Since `map` itself has no intrinsic effect, the effect of applying `map` is exactly the effect of the function `f` that is applied, namely `e`. 

## 2.3. Effect Handlers

Another example of the min-gen design principle: instead of various special language and compiler extensions to support exceptions, generators, async/await etc., Koka has full support for algebraic effect handlers – these lets you define advanced control abstractions like async/await as a user library in a typed and composable way. 

Here is an example of an effect definition with one control (`ctl`) operation to yield `intstd/core/types/int: V` values: 

```
effect yield
  ctl yield( i : int ) : bool
effectwhy/yield: (E, V) -> V yieldwhy/yield: (E, V) -> V
  ctl yield( ii: int : intstd/core/types/int: V ) : boolstd/core/types/bool: V

```

Once the effect is declared, we can use it for example to yield the elements of a list: 

```
fun traverse( xs : list<int> ) : yield () 
  match xs 
    Cons(x,xx) -> if yield(x) then traverse(xx) else ()
    Nil        -> ()
fun traversewhy/traverse: (xs : list<int>) -> yield ()( xsxs: list<int> : liststd/core/types/list: V -> V<intstd/core/types/int: V> )result: -> yield () : yieldwhy/yield: (E, V) -> V (std/core/types/unit: V)std/core/types/unit: V 
  match xsxs: list<int> 
    Consstd/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>(xx: int,xxxx: list<int>) -> if yieldwhy/yield: (i : int) -> yield bool(xx: int) then traversewhy/traverse: (xs : list<int>) -> yield ()(xxxx: list<int>) else (std/core/types/Unit: ())std/core/types/Unit: ()
    Nilstd/core/types/Nil: forall<a> list<a>        -> (std/core/types/Unit: ())std/core/types/Unit: ()

```

The `traversewhy/traverse: (xs : list) -> yield ()` function calls `yieldwhy/yield: (i : int) -> yield bool` and therefore gets the `yieldwhy/yield: (E, V) -> V` effect in its type, and if we want to use `traversewhy/traverse: (xs : list) -> yield ()`, we need to handle the `yieldwhy/yield: (E, V) -> V` effect. This is much like defining an exception handler, except we can receive values (here an `intstd/core/types/int: V`), and we can resume to the call-site with a result (here, with a boolean that determines if we keep traversing): 

```
fun print-elems() : console () 
  with ctl yield(i)
    println("yielded " ++ i.show)
    resume(i<=2)
  traverse([1,2,3,4])
fun print-elemswhy/print-elems: () -> console ()()result: -> console () : consolestd/core/console/console: X (std/core/types/unit: V)std/core/types/unit: V 
  withhandler: (() -> <yield,console> ()) -> console () ctl yieldyield: (i : int, resume : (bool) -> console ()) -> console ()(ii: int)
    printlnstd/core/console/string/println: (s : string) -> console ()("yielded "literal: stringcount= 8 ++std/core/types/(++): (x : string, y : string) -> console string ii: int.showstd/core/int/show: (i : int) -> console string)
    resumeresume: (bool) -> console ()(ii: int<=std/core/int/(<=): (x : int, y : int) -> console bool2literal: intdec  = 2hex8 = 0x02bit8 = 0b00000010)
  traversewhy/traverse: (xs : list<int>) -> <yield,console> ()([std/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>1literal: intdec  = 1hex8 = 0x01bit8 = 0b00000001,2literal: intdec  = 2hex8 = 0x02bit8 = 0b00000010,3literal: intdec  = 3hex8 = 0x03bit8 = 0b00000011,4literal: intdec  = 4hex8 = 0x04bit8 = 0b00000100]std/core/types/Nil: forall<a> list<a>)

```

The `with` statement dynamically binds the handler for `yieldwhy/yield: (i : int) -> yield bool` control operation over the rest of the scope, in this case `traversewhy/traverse: (xs : list) -> yield ()([1,2,3,4])`. Every time `yieldwhy/yield: (i : int) -> yield bool` is called, our control handler is called, prints the current value, and resumes to the call-site with a boolean result. The dynamic binding here is quite safe since we still use static typing! Indeed, the handler discharges the `yieldwhy/yield: (E, V) -> V` effect – and replaces it with a `consolestd/core/console/console: X` effect (due to `println`). When we run the example, we get: 

```
yielded: 1
yielded: 2
yielded: 3
```

## 2.4. Perceus Optimized Reference Counting

 

Perceus is the compiler optimized reference counting technique that Koka uses for automatic memory management [13, 22]. This (together with evidence passing [23– 25]) enables Koka to compile directly to plain C code without needing a garbage collector or runtime system. 

Perceus uses extensive static analysis to aggressively optimize the reference counts. Here the strong semantic foundation of Koka helps a lot: inductive data types cannot form cycles, and potential sharing across threads can be reliably determined. 

Normally we need to make a fundamental choice when managing memory: 

- We either use manual memory management (C, C++, Rust) and we get the best performance but at a significant programming burden, 
- Or, we use garbage collection (OCaml, C#, Java, Go, etc.) but but now we need a runtime system and pay a price in performance, memory usage, and unpredictable latencies. 

 

With Perceus, we hope to cross this gap and our goal is to be within 2x of the performance of C/C++. Initial benchmarks are encouraging and show Koka to be close to C performance on various memory intensive benchmarks. 

## 2.5. Reuse Analysis

Perceus also performs reuse analysis as part of reference counting analysis. This pairs pattern matches with constructors of the same size and reuses them in-place if possible. Take for example, the `map` function over lists: 

```
fun map( xs : list<a>, f : a -> e b ) : e list<b>
  match xs
    Cons(x,xx) -> Cons( f(x), map(xx,f) )
    Nil        -> Nil
fun map( xs : liststd/core/types/list: V -> V<a>, f : a -> e b ) : e liststd/core/types/list: V -> V<b>
  match xs
    Consstd/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>(x,xx) -> Consstd/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>( f(x), map(xx,f) )
    Nilstd/core/types/Nil: forall<a> list<a>        -> Nilstd/core/types/Nil: forall<a> list<a>

```

Here the matched `Consstd/core/types/Cons: forall (head : a, tail : list) -> list ` can be reused by the new `Consstd/core/types/Cons: forall (head : a, tail : list) -> list ` in the branch. This means if we map over a list that is not shared, like `list(1,100000).map(sqr).sumstd/core/list/sum: (xs : list) -> int`, then the list is updated in-place without any extra allocation. This is very effective for many functional style programs. 

```cpp
void map( list_t xs, function_t f, 
          list_t* res) 
{
  while (is_Cons(xs)) {
    if (is_unique(xs)) {    // if xs is not shared..
      box_t y = apply(dup(f),xs->head);      
      if (yielding()) { ... } // if f yields to a general ctl operation..
      else {
        xs->head = y;      
        *res = xs;          // update previous node in-place
        res = &xs->tail;    // set the result address for the next node
        xs = xs->tail;      // .. and continue with the next node
      }
    }
    else { ... }            // slow path allocates fresh nodes
  }
  *res = Nil;  
}
```

Moreover, the Koka compiler also implements tail-recursion modulo cons (TRMC) [11, 12] and instead of using a recursive call, the function is eventually optimized into an in-place updating loop for the fast path, similar to the C code example on the right. 

Importantly, the reuse optimization is guaranteed and a programmer can see when the optimization applies. This leads to a new programming technique we call FBIP: functional but in-place. Just like tail-recursion allows us to express loops with regular function calls, reuse analysis allows us to express many imperative algorithms in a purely functional style. 

## 2.6. Specialization

As another example of the effectiveness of Perceus and the strong semantics of the Koka core language, we can look at the red-black tree example and look at the code generated when folding a binary tree. The red-black tree is defined as: 

```
type color  
  Red
  Black

type tree<k,a> 
  Leaf
  Node(color : color, left : tree<k,a>, key : k, value : a, right : tree<k,a>)
type colorwhy/color: V  
  Redwhy/Red: color
  Blackwhy/Black: color

type treewhy/tree: (V, V) -> V<kk: V,aa: V> 
  Leafwhy/Leaf: forall<a,b> tree<a,b>
  Nodewhy/Node: forall<a,b> (color : color, left : tree<a,b>, key : a, value : b, right : tree<a,b>) -> tree<a,b>(color : colorwhy/color: V, left : treewhy/tree: (V, V) -> V<kk: V,aa: V>, key : kk: V, value : aa: V, right : treewhy/tree: (V, V) -> V<kk: V,aa: V>)

```

We can generically fold over a tree `t` with a function `f` as: 

```
fun fold(t : tree<k,a>, acc : b, f : (k, a, b) -> b) : b
  match t
    Node(_,l,k,v,r) -> r.fold( f(k,v,l.fold(acc,f)), f)
    Leaf            -> acc
fun foldwhy/fold: forall<a,b,c> (t : tree<c,a>, acc : b, f : (c, a, b) -> b) -> b(tt: tree<$619,$617> : treewhy/tree: (V, V) -> V<kk: V,aa: V>, accacc: $618 : bb: V, ff: ($619, $617, $618) -> $618 : (kk: V, aa: V, bb: V) -> bstd/core/types/total: E)result: -> total 718 : bstd/core/types/total: E
  match tt: tree<$619,$617>
    Nodewhy/Node: forall<a,b> (color : color, left : tree<a,b>, key : a, value : b, right : tree<a,b>) -> tree<a,b>(_,ll: tree<$619,$617>,kk: $619,vv: $617,rr: tree<$619,$617>) -> rr: tree<$619,$617>.foldwhy/fold: (t : tree<$619,$617>, acc : $618, f : ($619, $617, $618) -> $618) -> $618( ff: ($619, $617, $618) -> $618(kk: $619,vv: $617,ll: tree<$619,$617>.foldwhy/fold: (t : tree<$619,$617>, acc : $618, f : ($619, $617, $618) -> $618) -> $618(accacc: $618,ff: ($619, $617, $618) -> $618)), ff: ($619, $617, $618) -> $618)
    Leafwhy/Leaf: forall<a,b> tree<a,b>            -> accacc: $618

```

This is used in the example to count all the `Truestd/core/types/True: bool` values in a tree `t : treewhy/tree: (V, V) -> V<k,boolstd/core/types/bool: V>` as: 

```
val count = t.fold(0, fn(k,v,acc) if v then acc+1 else acc)
val count = t.fold(0, fn(k,v,acc) if v then acc+1 else acc)

```

This may look quite expensive where we pass a polymorphic first-class function that uses arbitrary precision integer arithmetic. However, the Koka compiler first specializes the `fold` definition to the passed function, then simplifies the resulting monomorphic code, and finally applies Perceus to insert reference count instructions. This results in the following internal core code: 

```
fun spec-fold(t : tree<k,bool>, acc : int) : int
  match t
    Node(_,l,k,v,r) -> 
      if unique(t) then { drop(k); free(t) } else { dup(l); dup(r) } // perceus inserted
      val x = if v then 1 else 0
      spec-fold(r, spec-fold(l,acc) + x) 
    Leaf -> 
      drop(t)
      acc

val count = spec-fold(t,0)
fun spec-fold(t : treewhy/tree: (V, V) -> V<k,boolstd/core/types/bool: V>, acc : intstd/core/types/int: V) : intstd/core/types/int: V
  match t
    Nodewhy/Node: forall<a,b> (color : color, left : tree<a,b>, key : a, value : b, right : tree<a,b>) -> tree<a,b>(_,l,k,v,r) -> 
      if uniquestd/core/unique: () -> ndet int(t) then { drop(k); free(t) } else { dup(l); dup(r) } // perceus inserted
      val x = if v then 1 else 0
      spec-fold(r, spec-fold(l,acc) + x) 
    Leafwhy/Leaf: forall<a,b> tree<a,b> -> 
      drop(t)
      acc

val count = spec-fold(t,0)

```

When compiled via the C backend, the generated assembly instructions on arm64 become: 

```arm64
spec_fold:
  ...                       
  LOOP0:   
    mov  x21, x0              ; x20 is t, x21 = acc (x19 = koka context _ctx)
  LOOP1:                      ; the "match(t)" point
    cmp  x20, #9              ; is t a Leaf?
    b.eq LBB15_1              ;   if so, goto Leaf brach
  LBB15_5:                    ;   otherwise, this is the Node(_,l,k,v,r) branch
    mov  x23, x20             ; load the fields of t:
    ldp  x22, x0, [x20, #8]   ;   x22 = l, x0 = k   (ldp == load pair)
    ldp  x24, x20, [x20, #24] ;   x24 = v, x20 = r  
    ldr  w8, [x23, #4]        ;   w8 = reference count (0 is unique)
    cbnz w8, LBB15_11         ; if t is not unique, goto cold path to dup the members
    tbz  w0, #0, LBB15_13     ; if k is allocated (bit 0 is 0), goto cold path to free it
  LBB15_7:                   
    mov  x0, x23              ; call free(t)  
    bl   _mi_free
  LBB15_8:              
    mov  x0, x22              ; call spec_fold(l,acc,_ctx)
    mov  x1, x21              
    mov  x2, x19
    bl   spec_fold
    cmp  x24, #1              ; boxed value is False? 
    b.eq LOOP0                ;   if v is False, the result in x0 is the accumulator
    add  x21, x0, #4          ; otherwise add 1 (as a small int 4*n)
    orr  x8, x21, #1          ;   check for bigint or overflow in one test 
    cmp  x8, w21, sxtw        ;   (see kklib/include/integer.h for details)
    b.eq LOOP1                ; and tail-call into spec_fold if no overflow or bigint
    mov  w1, #5               ; otherwise, use generic bigint addition              
    mov  x2, x19
    bl   _kk_integer_add_generic
    b    LOOP0   
  ...
```

The polymorphic `fold` with its higher order parameter is eventually compiled into a tight loop with close to optimal assembly instructions. 

advanced Here we see too that the node `t` is freed explicitly as soon as it is no longer live. This is usually earlier than scope-based deallocation (like RAII) and therefore Perceus can guarantee to be garbage-free where in a (cycle-free) program objects are always immediatedly deallocated as soon as they become unreachable [13– 15, 22]. Moreover, it is deterministic and behaves just like regular malloc/free calls. Reference counting may still seem expensive compared to trace-based garbage collection which only (re)visits all live objects and never needs to free objects explicitly. However, Perceus usually frees an object right after its last use (like in our example), and thus the memory is still in the cache reducing the cost of freeing it. Also, Perceus never (re)visits live objects arbitrarily which may trash the caches especially if the live set is large. As such, we think the deterministic behavior of Perceus together with the garbage-free property may work out better in practice.

# 3. A Tour of Koka

This is a short introduction to the Koka programming language. 

Koka is a function-oriented language that separates pure values from side-effecting computation (Given the importance of effect typing, the name Koka was derived from the Japanese word for effective (効果, こうか, Kōka)). 

### 3.1.1. Hello world

As usual, we start with the familiar Hello world program: 

```
fun main()
  println("Hello world!") // println output
fun maintour/main: () -> console ()()result: -> console ()
  printlnstd/core/console/string/println: (s : string) -> console ()("Hello world!"literal: stringcount= 12) // println output

```

Functions are declared using the `fun` keyword (and anonymous functions with `fn`). Due to brace elision, any indented blocks implicitly get curly braces, and the example can also be written as: 

```
fun main() {
  println("Hello world!") // println output
}
fun maintour/main: () -> console ()() {
  println("Hello world!") // println output
}

```

using explicit braces. Here is another short example program that encodes a string using the Caesar cipher, where each lower-case letter in a string is replaced by the letter three places up in the alphabet: 

```
fun main() { println(caesar("koka is fun")) }

fun encode( s : string, shift : int )
  fun encode-char(c)
    if c < 'a' || c > 'z' then return c
    val base = (c - 'a').int
    val rot  = (base + shift) % 26
    (rot.char + 'a')
  s.map(encode-char)

fun caesar( s : string ) : string
  s.encode( 3 )
fun encodetour/encode: (s : string, shift : int) -> string( ss: string : stringstd/core/types/string: V, shiftshift: int : intstd/core/types/int: V )result: -> total string
  fun encode-charencode-char: (c : char) -> char(cc: char)result: -> total char
    if cc: char <std/core/char/(<): (char, char) -> bool 'a'literal: charunicode= u0061 ||std/core/types/(||): (x : bool, y : bool) -> bool cc: char >std/core/char/(>): (char, char) -> bool 'z'literal: charunicode= u007A then returnreturn: char cc: char
    val basebase: int = (cc: char -std/core/char/(-): (c : char, d : char) -> char 'a'literal: charunicode= u0061).intstd/core/char/int: (char) -> int
    val rotrot: int  = (basebase: int +std/core/int/(+): (x : int, y : int) -> int shiftshift: int) %std/core/int/(%): (int, int) -> int 26literal: intdec  = 26hex8 = 0x1Abit8 = 0b00011010
    (rotrot: int.charstd/core/char/int/char: (i : int) -> char +std/core/char/(+): (c : char, d : char) -> char 'a'literal: charunicode= u0061)
  ss: string.mapstd/core/list/string/map: (s : string, f : (char) -> char) -> string(encode-charencode-char: (c : char) -> char)

fun caesartour/caesar: (s : string) -> string( ss: string : stringstd/core/types/string: V )result: -> total string : stringstd/core/types/string: V
  ss: string.encodetour/encode: (s : string, shift : int) -> string( 3literal: intdec  = 3hex8 = 0x03bit8 = 0b00000011 )

```

In this example, we declare a local function `encode-char` which encodes a single character `c`. The final statement `s.map(encode-char)` applies the `encode-char` function to each character in the string `s`, returning a new string where each character is Caesar encoded. The result of the final statement in a function is also the return value of that function, and you can generally leave out an explicit `return` keyword. 

### 3.1.2. Dot selection

Koka is a function-oriented language where functions and data form the core of the language (in contrast to objects for example). In particular, the expression `s.encode(3)` does not select the `encode` method from the `stringstd/core/types/string: V` object, but it is simply syntactic sugar for the function call `encode(s,3)` where `s` becomes the first argument. Similarly, `c.int` converts a character to an integer by calling `int(c)` (and both expressions are equivalent). The dot notation is intuïtive and quite convenient to chain multiple calls together, as in: 

```
fun showit( s : string )
  s.encode(3).count.println
fun showittour/showit: (s : string) -> console ()( ss: string : stringstd/core/types/string: V )result: -> console ()
  ss: string.encodetour/encode: (s : string, shift : int) -> console string(3literal: intdec  = 3hex8 = 0x03bit8 = 0b00000011).countstd/core/string/chars/count: (s : string) -> console int.printlnstd/core/console/default/show/println: (x : int, @implicit/show : (int) -> console string) -> console ()?show=int/show

```

for example (where the body desugars as `println(count(encode(s,3)))`). An advantage of the dot notation as syntactic sugar for function calls is that it is easy to extend the ‘primitive’ methods of any data type: just write a new function that takes that type as its first argument. In most object-oriented languages one would need to add that method to the class definition itself which is not always possible if such class came as a library for example. 

### 3.1.3. Type Inference

Koka is also strongly typed. It uses a powerful type inference engine to infer most types, and types generally do not get in the way. In particular, you can always leave out the types of any local variables. This is the case for example for `base` and `rot` values in the previous example; hover with the mouse over the example to see the types that were inferred by Koka. Generally, it is good practice though to write type annotations for function parameters and the function result since it both helps with type inference, and it provides useful documentation with better feedback from the compiler. 

For the `encode` function it is actually essential to give the type of the `s` parameter: since the `map` function is defined for both `liststd/core/types/list: V -> V` and `stringstd/core/types/string: V` types and the program is ambiguous without an annotation. Try to load the example in the editor and remove the annotation to see what error Koka produces. 

### 3.1.4. Anonymous Functions and Trailing Lambdas

Koka also allows for anonymous function expressions using the `fn` keyword. For example, instead of declaring the `encode-char` function, we can also pass it directly to the `map` function as a function expression: 

```
fun encode2( s : string, shift : int )
  s.map( fn(c)
    if c < 'a' || c > 'z' then return c
    val base = (c - 'a').int
    val rot  = (base + shift) % 26
    (rot.char + 'a')
  )
fun encode2tour/encode2: (s : string, shift : int) -> string( ss: string : stringstd/core/types/string: V, shiftshift: int : intstd/core/types/int: V )result: -> total string
  ss: string.mapstd/core/list/string/map: (s : string, f : (char) -> char) -> string( fnfn: (c : char) -> char(cc: char)
    if cc: char <std/core/char/(<): (char, char) -> bool 'a'literal: charunicode= u0061 ||std/core/types/(||): (x : bool, y : bool) -> bool cc: char >std/core/char/(>): (char, char) -> bool 'z'literal: charunicode= u007A then returnreturn: char cc: char
    val basebase: int = (cc: char -std/core/char/(-): (c : char, d : char) -> char 'a'literal: charunicode= u0061).intstd/core/char/int: (char) -> int
    val rotrot: int  = (basebase: int +std/core/int/(+): (x : int, y : int) -> int shiftshift: int) %std/core/int/(%): (int, int) -> int 26literal: intdec  = 26hex8 = 0x1Abit8 = 0b00011010
    (rotrot: int.charstd/core/char/int/char: (i : int) -> char +std/core/char/(+): (c : char, d : char) -> char 'a'literal: charunicode= u0061)
  )

```

It is a bit annoying we had to put the final right-parenthesis after the last brace in the previous example. As a convenience, Koka allows anonymous functions to follow the function call instead – this is also known as trailing lambdas. For example, here is how we can print the numbers `1` to `10`: 

```
fun main() { print10() }

fun print10()
  for(1,10) fn(i)
    println(i)
fun print10tour/print10: () -> console ()()result: -> console ()
  forstd/core/range/for: (start : int, end : int, action : (int) -> console ()) -> console ()(1literal: intdec  = 1hex8 = 0x01bit8 = 0b00000001,10literal: intdec  = 10hex8 = 0x0Abit8 = 0b00001010) fnfn: (i : int) -> console ()(ii: int)
    printlnstd/core/console/default/show/println: (x : int, @implicit/show : (int) -> console string) -> console ()?show=int/show(ii: int)

```

which is desugared to `for( 1, 10, fn(i){ println(i) } )`. (In fact, since we pass the `i` argument directly to `println`, we could have also passed the function itself directly as `for(1,10,println)`.) 

Anonymous functions without any arguments can be shortened further by leaving out the `fn` keyword as well and just use braces directly. Here is an example using the `repeat` function: 

```
fun main() { printhi10() }

fun printhi10()
  repeat(10)
    println("hi")
fun printhi10tour/printhi10: () -> console ()()result: -> console ()
  repeatstd/core/repeat: (n : int, action : () -> console ()) -> console ()(10literal: intdec  = 10hex8 = 0x0Abit8 = 0b00001010)
    printlnstd/core/console/string/println: (s : string) -> console ()("hi"literal: stringcount= 2)

```

where the body desugars to `repeat( 10, { println(``histd/num/int32/hi: (i : int32) -> int32``) } )` which desugars further to `repeat( 10, fn(){ println(``histd/num/int32/hi: (i : int32) -> int32``)} )`. The is especially convenient for the `whilestd/core/while: forall (predicate : () -> <div|e> bool, action : () -> <div|e> ()) -> <div|e> ()` loop since this is not a built-in control flow construct but just a regular function: 

```
fun main() { print11() }

fun print11()
  var i := 10
  while { i >= 0 }
    println(i)
    i := i - 1
fun print11tour/print11: () -> <console,div> ()()result: -> <console,div> ()
  var ii: local-var<$1279,int> := 10literal: intdec  = 10hex8 = 0x0Abit8 = 0b00001010
  whilestd/core/while: (predicate : () -> <div,local<$1279>,console> bool, action : () -> <div,local<$1279>,console> ()) -> <div,local<$1279>,console> () { ii: int?hdiv=iev@1305 >=std/core/int/(>=): (x : int, y : int) -> <local<$1279>,div,console> bool 0literal: intdec  = 0hex8 = 0x00bit8 = 0b00000000 }
    printlnstd/core/console/default/show/println: (x : int, @implicit/show : (int) -> <console,local<$1279>,div> string) -> <console,local<$1279>,div> ()?show=int/show(ii: int?hdiv=iev@1388)
    ii: local-var<$1279,int> :=std/core/types/local-set: (v : local-var<$1279,int>, assigned : int) -> <local<$1279>,console,div> () ii: int?hdiv=iev@1460 -std/core/int/(-): (x : int, y : int) -> <local<$1279>,console,div> int 1literal: intdec  = 1hex8 = 0x01bit8 = 0b00000001

```

Note how the first argument to `whilestd/core/while: forall (predicate : () -> <div|e> bool, action : () -> <div|e> ()) -> <div|e> ()` is in braces instead of the usual parenthesis. In Koka, an expression between parenthesis is always evaluated before a function call, whereas an expression between braces (ah, suspenders!) is suspended and may be never evaluated or more than once (as in our example). 

### 3.1.5. With Statements

To the best of our knowledge, Koka was the first language to have generalized trailing lambdas. It was also one of the first languages to have dot notation (This was independently developed but it turns out the D language has a similar feature (called UFCS) which predates dot-notation). Another novel syntactical feature is the `with` statement. With the ease of passing a function block as a parameter, these often become nested. For example: 

```
fun twice(f)
  f()
  f()

fun test-twice()
  twice
    twice
      println("hi")
fun twicetour/twice: forall<a,e> (f : () -> e a) -> e a(ff: () -> _1488 _1489)result: -> 1499 1498
  ff: () -> _1488 _1489()
  ff: () -> _1488 _1489()

fun test-twicetour/test-twice: () -> console ()()result: -> console ()
  twicetour/twice: (f : () -> console ()) -> console ()
    twicetour/twice: (f : () -> console ()) -> console ()
      printlnstd/core/console/string/println: (s : string) -> console ()("hi"literal: stringcount= 2)

```

where `"hi"` is printed four times (note: this desugars to `twicetour/twice: forall<a,e> (f : () -> e a) -> e a( fn(){ twicetour/twice: forall<a,e> (f : () -> e a) -> e a( fn(){ println("hi") }) })`). Using the `with` statement we can write this more concisely as: 

```
pub fun test-with1()
  with twice
  with twice
  println("hi")
pub fun test-with1tour/test-with1: () -> console ()()result: -> console ()
  withwith: () -> console () twicetour/twice: (f : () -> console ()) -> console ()
  withwith: () -> console () twicetour/twice: (f : () -> console ()) -> console ()
  printlnstd/core/console/string/println: (s : string) -> console ()("hi"literal: stringcount= 2)

```

The `with` statement essentially puts all statements that follow it into an anonymous function block and passes that as the last parameter. In general: 

```
with f(e1,...,eN)
<body>
with f(e1,...,eN)
<body>

```

```
f(e1,...,eN, fn(){ <body> })
f(e1,...,eN, fn(){ <body> })

```

Moreover, a `with` statement can also bind a variable parameter as: 

translation

```
with x <- f(e1,...,eN)
<body>
with x <- f(e1,...,eN)
<body>

```

```
f(e1,...,eN, fn(x){ <body> })
f(e1,...,eN, fn(x){ <body> })

```

Here is an example using `foreach` to span over the rest of the function body: 

```
pub fun test-with2() {
  with x <- list(1,10).foreach
  println(x)
}
pub fun test-with2tour/test-with2: () -> console ()()result: -> console () {
  withwith: (x : int) -> console () xx: int <- liststd/core/list/range/list: (lo : int, hi : int) -> console list<int>(1literal: intdec  = 1hex8 = 0x01bit8 = 0b00000001,10literal: intdec  = 10hex8 = 0x0Abit8 = 0b00001010).foreachstd/core/list/foreach: (xs : list<int>, action : (int) -> console ()) -> console ()
  printlnstd/core/console/default/show/println: (x : int, @implicit/show : (int) -> console string) -> console ()?show=int/show(xx: int)
}

```

which desugars to `list(1,10).foreach( fn(x){ println(x) } )`. This is a bit reminiscent of Haskell `do` notation. Using the `with` statement this way may look a bit strange at first but is very convenient in practice – it helps thinking of `with` as a closure over the rest of the lexical scope. 

#### With Finally

As another example, the `finallystd/core/hnd/finally: forall<a,e> (fin : () -> e (), action : () -> e a) -> e a` function takes as its first argument a function that is run when exiting the scope – either normally, or through an “exception” (i.e. when an effect operation does not resume). Again, `with` is a natural fit: 

```
fun test-finally()
  with finally{ println("exiting..") }
  println("entering..")
  throw("oops") + 42
fun test-finallytour/test-finally: () -> <console,exn> int()result: -> <console,exn> int
  withwith: () -> <console,exn> int finallystd/core/hnd/finally: (fin : () -> <console,exn> (), action : () -> <console,exn> int) -> <console,exn> int{ printlnstd/core/console/string/println: (s : string) -> <console,exn> ()("exiting.."literal: stringcount= 9) }
  printlnstd/core/console/string/println: (s : string) -> <console,exn> ()("entering.."literal: stringcount= 10)
  throwstd/core/exn/throw: (message : string, info : ? exception-info) -> <exn,console> int("oops"literal: stringcount= 4) +std/core/int/(+): (x : int, y : int) -> <exn,console> int 42literal: intdec  = 42hex8 = 0x2Abit8 = 0b00101010

```

which desugars to `finallystd/core/hnd/finally: forall<a,e> (fin : () -> e (), action : () -> e a) -> e a(fn(){ println(...) }, fn(){ println("entering"); throwstd/core/exn/throw: forall (message : string, info : ? exception-info) -> exn a("oops") + 42 })`, and prints: 

```
entering..
exiting..
uncaught exception: oops
```

This is another example of the min-gen principle: many languages have special built-in support for this kind of pattern, like a `defer` statement, but in Koka it is all just function applications with minimal syntactic sugar. 

#### With Handlers

The `with` statement is especially useful in combination with effect handlers. An effect describes an abstract set of operations whose concrete implementation can be dynamically bound by a handler. Here is an example of an effect handler for emitting messages: 

```
// declare an abstract operation: emit, how it emits is defined dynamically by a handler.
effect fun emit(msg : string) : ()

// emit a standard greeting.
fun hello() : emit ()
  emit("hello world!")

// emit a standard greeting to the console.
pub fun hello-console1() : console ()
  with handler
    fun emit(msg) println(msg)
  hello()
// declare an abstract operation: emit, how it emits is defined dynamically by a handler.
effecttour/emit: (E, V) -> V fun emittour/emit: (E, V) -> V(msgmsg: string : stringstd/core/types/string: V) : (std/core/types/unit: V)std/core/types/unit: V

// emit a standard greeting.
fun hellotour/hello: () -> emit ()()result: -> emit () : emittour/emit: (E, V) -> V (std/core/types/unit: V)std/core/types/unit: V
  emittour/emit: (msg : string) -> emit ()("hello world!"literal: stringcount= 12)

// emit a standard greeting to the console.
pub fun hello-console1tour/hello-console1: () -> console ()()result: -> console () : consolestd/core/console/console: X (std/core/types/unit: V)std/core/types/unit: V
  withwith: () -> <emit,console> () handlerhandler: (() -> <emit,console> ()) -> console ()
    fun emitemit: (msg : string) -> console ()(msgmsg: string) printlnstd/core/console/string/println: (s : string) -> console ()(msgmsg: string)
  hellotour/hello: () -> <emit,console> ()()

```

In this example, the `with` expression desugars to `(handler{ fun emittour/emit: (msg : string) -> emit ()(msg){ println(msg) } })( fn(){ hellotour/hello: () -> emit ()() } )`. Generally, a `handler{ }` expression takes as its last argument a function block so it can be used directly with `with`. 

Moreover, as a convenience, we can leave out the `handler` keyword for effects that define just one operation (like `emittour/emit: (E, V) -> V`): 

translation

```
with val op = <expr>
with fun op(x){ <body> }
with ctl op(x){ <body> }
with val op = <expr>
with fun op(x){ <body> }
with ctl op(x){ <body> }

```

```
with handler{ val op = <expr> }
with handler{ fun op(x){ <body> } }
with handler{ ctl op(x){ <body> } }
with handler{ val op = <expr> }
with handler{ fun op(x){ <body> } }
with handler{ ctl op(x){ <body> } }

```

Using this convenience, we can write the previous example in more concisely as: 

```
pub fun hello-console2()
  with fun emit(msg) println(msg)
  hello()
pub fun hello-console2()
  with fun emittour/emit: (msg : string) -> emit ()(msg) println(msg)
  hellotour/hello: () -> emit ()()

```

Intuitively, we can view the handler `with fun emittour/emit: (msg : string) -> emit ()` as a (statically typed) dynamic binding of the function `emittour/emit: (msg : string) -> emit ()` over the rest of the scope. 

### 3.1.6. Optional and Named Parameters

Being a function-oriented language, Koka has powerful support for function calls where it supports both optional and named parameters. For example, the function `replace-allstd/core/string/replace-all: (s : string, pattern : string, repl : string) -> string` takes a string, a pattern (named `pattern`), and a replacement string (named `repl`): 

```
fun main() { println(world()) }

fun world()
  replace-all("hi there", "there", "world")  // returns "hi world"
fun worldtour/world: () -> string()result: -> total string
  replace-allstd/core/string/replace-all: (s : string, pattern : string, repl : string) -> string("hi there"literal: stringcount= 8, "there"literal: stringcount= 5, "world"literal: stringcount= 5)  // returns "hi world"

```

Using named parameters, we can also write the function call as: 

```
fun main() { println(world2()) }

fun world2()
  "hi there".replace-all( repl="world", pattern="there" )
fun world2tour/world2: () -> string()result: -> total string
  "hi there"literal: stringcount= 8.replace-allstd/core/string/replace-all: (s : string, pattern : string, repl : string) -> string( repl="world"literal: stringcount= 5, pattern="there"literal: stringcount= 5 )

```

Optional parameters let you specify default values for parameters that do not need to be provided at a call-site. As an example, let's define a function `sublisttour/sublist: forall (xs : list, start : int, len : ? int) -> list ` that takes a list, a `start` position, and the length `len` of the desired sublist. We can make the `len` parameter optional and by default return all elements following the `start` position by picking the length of the input list by default: 

```
fun main() { println( ['a','b','c'].sublist(1).string ) }

fun sublist( xs : list<a>, start : int, len : int = xs.length ) : list<a>
  if start <= 0 return xs.take(len)
  match xs
    Nil        -> Nil
    Cons(_,xx) -> xx.sublist(start - 1, len)
fun sublisttour/sublist: forall<a> (xs : list<a>, start : int, len : ? int) -> list<a>( xsxs: list<$2188> : liststd/core/types/list: V -> V<aa: V>, startstart: int : intstd/core/types/int: V, lenlen: ? int : intstd/core/types/int: V = xsxs: list<$2188>.lengthstd/core/list/length: (xs : list<$2188>) -> int )result: -> total list<2296> : liststd/core/types/list: V -> V<aa: V>
  if startstart: int <=std/core/int/(<=): (x : int, y : int) -> bool 0literal: intdec  = 0hex8 = 0x00bit8 = 0b00000000 returnreturn: list<$2188> xsxs: list<$2188>.takestd/core/list/take: (xs : list<$2188>, n : int) -> list<$2188>(lenlen: int)std/core/types/Unit: ()
  match xsxs: list<$2188>
    Nilstd/core/types/Nil: forall<a> list<a>        -> Nilstd/core/types/Nil: forall<a> list<a>
    Consstd/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>(_,xxxx: list<$2188>) -> xxxx: list<$2188>.sublisttour/sublist: (xs : list<$2188>, start : int, len : ? int) -> list<$2188>(startstart: int -std/core/int/(-): (x : int, y : int) -> int 1literal: intdec  = 1hex8 = 0x01bit8 = 0b00000001, lenlen: int)

```

Hover over the `sublisttour/sublist: forall (xs : list, start : int, len : ? int) -> list ` identifier to see its full type, where the `len` parameter has gotten an optional `intstd/core/types/int: V` type signified by the question mark: `? intstd/core/types/int: V`. 

### 3.1.7. A larger example: cracking Caesar encoding

Here is a slightly larger program inspired by an example in Graham Hutton's most excellent " Programming in Haskell" book: 

```
import std/num/float64
import std/num/float64std/num/float64

```

```
fun main()
  test-uncaesar()

fun encode( s : string, shift : int )
  fun encode-char(c)
    if c < 'a' || c > 'z' return c
    val base = (c - 'a').int
    val rot  = (base + shift) % 26
    (rot.char + 'a')
  s.map(encode-char)

// The letter frequency table for English
val english = [8.2,1.5,2.8,4.3,12.7,2.2,
               2.0,6.1,7.0,0.2,0.8,4.0,2.4,
               6.7,7.5,1.9,0.1, 6.0,6.3,9.1,
               2.8,1.0,2.4,0.2,2.0,0.1]

// Small helper functions
fun percent( n : int, m : int )
  100.0 * (n.float64 / m.float64)

fun rotate( xs : list<a>, n : int ) : list<a>
  xs.drop(n) ++ xs.take(n)

// Calculate a frequency table for a string
fun freqs( s : string ) : list<float64>
  val lowers = list('a','z')
  val occurs = lowers.map( fn(c) s.count(c.string) )
  val total  = occurs.sum
  occurs.map( fn(i) percent(i,total) )

// Calculate how well two frequency tables match according
// to the _chi-square_ statistic.
fun chisqr( xs : list<float64>, ys : list<float64> ) : float64
  zipwith(xs,ys, fn(x,y) ((x - y)^2.0)/y ).foldr(0.0,(+))

// Crack a Caesar encoded string
fun uncaesar( s : string ) : string
  val table  = freqs(s)                   // build a frequency table for `s`
  val chitab = list(0,25).map fn(n)       // build a list of chisqr numbers for each shift between 0 and 25
                 chisqr( table.rotate(n), english )

  val min    = chitab.minimum()           // find the mininal element
  val shift  = chitab.index-of( fn(f) f == min ).negate  // and use its position as our shift
  s.encode( shift )

fun test-uncaesar()
  println( uncaesar( "nrnd lv d ixq odqjxdjh" ) )
// The letter frequency table for English
val englishtour/english: list<float64> = [std/core/types/Cons: forall<a> (head : a, tail : list<a>) -> list<a>8.2literal: float64hex64= 0x1.0666666666666p3,1.5literal: float64hex64= 0x1.8p0,2.8literal: float64hex64= 0x1.6666666666666p1,4.3literal: float64hex64= 0x1.1333333333333p2,12.7literal: float64hex64= 0x1.9666666666666p3,2.2literal: float64hex64= 0x1.199999999999ap1,
               2.0literal: float64hex64= 0x1p1,6.1literal: float64hex64= 0x1.8666666666666p2,7.0literal: float64hex64= 0x1.cp2,0.2literal: float64hex64= 0x1.999999999999ap-3,0.8literal: float64hex64= 0x1.999999999999ap-1,4.0literal: float64hex64= 0x1p2,2.4literal: float64hex64= 0x1.3333333333333p1,
               6.7literal: float64hex64= 0x1.acccccccccccdp2,7.5literal: float64hex64= 0x1.ep2,1.
