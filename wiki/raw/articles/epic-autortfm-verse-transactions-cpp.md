---
source_url: https://www.unrealengine.com/tech-blog/bringing-verse-transactional-memory-semantics-to-c
ingested: 2026-09-12
sha256: 5c4192ab870b87b3f0cd2f3c59df81df7465583fc1da6281a3b4f240497f7ba0
---
# Bringing Verse Transactional Memory Semantics to C++ - Unreal Engine

Bringing Verse Transactional Memory Semantics to C++ - Unreal Engine

# Bringing Verse Transactional Memory Semantics to C++

### Phil Pizlo

March 15, 2024

---

Starting in Fortnite version 28.10, some of our servers—large C++ executables based on Unreal Engine—are compiled with a new compiler that gives C++ transactional memory semantics that are compatible with Verse. This is a first step towards exposing even more Unreal Engine functionality to Verse while preserving Verse semantics. The Verse programming language has transactional memory as a first-class feature. Here's an example:`var``X``= ``0``if``:``set ``X``= ``42``# this gets rolled back because of the``# next line``X``>``100         ``# this fails, causing a rollback``X``=``0``# X is back to 0 thanks to rollback` This behavior holds for any effect, not just the`set` operation in Verse. For example, we could have instead called a C++ function, which modified some mutable variable using C++ (i.e. storing to a pointer), and then we could have used other C++ functions to read the mutable variable:`SetSomething``(``0``)``# implemented in C++, sets a C++``# variable``if``:``SetSomething``(``42``) ``# this gets rolled back because of``# the next line`` GetSomething``()``>``100``# this fails, causing a rollback``GetSomething``()``=``0         ``# back to 0 thanks to rollback` Hence, to support proper Verse semantics, we need C++ to obey Verse's transactional rules by recording all effects so that they can be rolled back. Verse code is always running within a transaction and transactions either complete successfully or abort. Transactions that abort are "invisible"—they undo all their effects so it is as if nothing happened. Aside from the implications for concurrency, Verse's transactional model says that:

- A runtime error in Verse should abort the entire transaction, since Verse doesn't allow for committing a transaction that didn't succeed.
- Verse failure contexts, such as the condition of an`if` statement, are nested transactions, which commit if the condition succeeds and abort otherwise. Conditional expressions are allowed to have effects. If the condition fails, it's as if the effects never happened.
- All effects are transactionalized, even those that happen in native code. If a Verse program asks C++ to do something and then encounters a runtime error in the same transaction, then whatever C++ did must be undone. If a Verse program asks C++ to do something from a failure context and then the condition fails, then whatever C++ did must also be undone.
- Verse transactions are coarse-grained. Verse code is always in a transaction by default, and the scope of that transaction is determined by the outermost caller into Verse. Since most Verse APIs are implemented in C++, this means that aborting a Verse transaction almost always implies having to undo some C++ state changes.

The initial Verse implementation addressed this by:

- Punting on Verse runtime error semantics. Currently, Verse runtime errors do not correctly rollback the aborted transaction. This is something we need to fix.
- Disallowing many APIs from being called in a failure context, contrary to Verse semantics. This is surfaced in the language as the`<no_rollback>` effect, which we will deprecate as soon as this issue is fixed.
- Having C++ code that supports transactions manually register undo handlers for any effects it performs. This is tricky enough that it does not scale (hence the`<no_rollback>` effect) and it is error-prone, leading to hard-to-debug crashes, like if an undo handler is registered for something that gets deleted.

Starting in Fortnite version 28.10, some of our servers are compiled with a new clang-based C++ compiler, which we call AutoRTFM (Automatic Rollback Transactions for Failure Memory). This compiler automatically transforms C++ code to precisely register undo handlers for each effect (including every store instruction) so that they can be undone in case of a Verse rollback. AutoRTFM achieves this with zero performance overhead to any C++ code not running inside a transaction. This is true even if the same C++ function is used both in transactions and outside them; the overhead only kicks in when the running thread is within a transaction scope. Furthermore, while some C++ code does have to be modified to work within AutoRTFM, we only had to make a total of 94 code changes to the Fortnite codebase to adapt it to AutoRTFM, and as we'll show in this post, even those changes are shockingly simple. In this post, we will go into the details of how this compiler and its runtime work and forecast a bit of our vision for how this will impact the Verse ecosystem.

## AutoRTFM Compiler and Runtime

AutoRTFM is designed to make it easy to take existing C++ code—which was never designed to have any transactional semantics—and make it transactional just by using an alternate compiler. For example, AutoRTFM enables you to write code like:`void ``Foo``()
{
    TArray`` Array ``=``{``1``, ``2``,`` 3``};``   AutoRTFM::``Transact``(``[``&``] ()``    {
        ``Array``.``Push``(``42``);``  //`` Array is {1, 2, 3, 42} here.``    AutoRTFM::``Abort``();``   });``  // ``Array is {1, 2, 3} here, due to the Abort.``}` This works without any changes to`TArray`. This works even if`TArray` needs to reallocate its backing store inside`Push`.`TArray` is not even special in this regard; AutoRTFM can do this for`std::vector`/`std::map` as well as a plethora of other data structures and functions in Unreal Engine and the C++ standard library. The only changes required to make this work are AutoRTFM's integration with low-level memory allocators and the garbage collector (GC), and as we'll show in this section, even those changes are small (they are purely additive and only a handful of lines; we've added them to all of Unreal Engine's many mallocs, Unreal Engine's GC, and system malloc/new). On top of that, AutoRTFM achieves this with zero performance regression for those code paths that run outside of a transaction (so outside the dynamic scope of a`Transact` call). Crucially, even if a code path (like`TArray` and many others) is used from within transactions, those uses outside transactions incur no cost. When code is executing inside a transaction, the overhead is high (we've seen 4x on some internal benchmarks), but not high enough to hurt the Fortnite server's tick rate. This section explains how this feat is possible. First we describe the overall architecture. Then we describe the new LLVM compiler pass, which, rather than instrumenting code directly, creates a transactional clone of all code that could possibly ever participate in a transaction, and then instruments just the clone. Next we describe the runtime and its API, which make it easy to integrate AutoRTFM into existing C++ code (including the more fun bits, like allocators). The next two sections explain these two components respectively.

#### AutoRTFM Architecture

Long term, we want to use transactional memory to achieve parallelism. Transactional memory implementations that achieve parallelism tend to maintain a read-write set, which tracks the snapshot of the heap's state that the transaction is running in. So, we would have to instrument both writes and reads; otherwise we would not know if a transaction that only read some location encountered a race due to concurrent commits. But short term, we need to accomplish two goals:

- Transactional semantics for Verse code, even if that Verse code calls into C++. This does not require parallelism but it does require transactional memory.
- Normalize compiling the Fortnite server—a very large and mature piece of C++ code—with a new compiler that adds transactional memory semantics.

Therefore, our first step is not AutoSTM (software transactional memory), but AutoRTFM (rollback transactions for failure memory), which just implements single-threaded transactions. AutoRTFM deals with a strictly simpler problem. Because there is no concurrency (the gameplay code that Verse would call is already expected to be main-thread-only), we only have to record writes. Ignoring reads means lower overhead in the initial bringup, and it means fewer bugs, since any code that just reads the heap just works in AutoRTFM. AutoRTFM's architecture is conceptually simple. The AutoRTFM runtime maintains a log of memory locations and their old values. The compiler instruments code to call functions in the AutoRTFM runtime anytime memory is written. The next two sections go into the details of the compiler and then the runtime.

#### LLVM Compiler Pass

The`AutoRTFMPass`'s job is to instrument all code so that it can obey Verse's transactional semantics. But the same code in Fortnite may be used in some places where there is no Verse code on the stack and Verse's semantics are unnecessary, and in other places where Verse is on the stack and a rollback is possible. Rather than emitting code like "if current thread is in transaction then log write", the AutoRTFTM compiler is built around cloning. Being in a transaction is represented entirely by executing in the transactional clone. Effectively, the`bCurrentThreadIsInTransaction` bit is encoded in the program counter. From the compiler's standpoint, this is simple—it just clones all of your code, gives the cloned functions mangled names, and then instruments only the clones. The original code stays uninstrumented and never does any logging or anything else special, so running that code incurs zero cost. The cloned code gets instrumentation and definitely knows that it is in a transaction, which even enables us to play VM-like tricks, such as playing with alternate calling conventions. Because code is cloned, we need to also instrument indirect function code in the clones. If a function performs an indirect call, then the pointer it will be trying to call will be a pointer to the original version of the callee. So, inside the cloned code, all indirect calls first ask the AutoRTFM runtime for the cloned version of that function. Like all of AutoRTFM's instrumentation, this makes cloned code more expensive but has no effect on the original code.`AutoRTFMPass` runs at the same point in the LLVM pipeline as sanitizers—i.e., after all IR optimizations have happened and just before sending the code to the backend. This has important implications, like that even in the instrumented clones, the only loads and stores that get instrumentation are the ones that survived optimization. So, while assigning to a non-escaping local variable in C++ is a "store" in the abstract sense (and clang would represent it that way when creating the unoptimized LLVM IR for that program), the store will be totally gone by the time`AutoRTFMPass ` does its thing. Most likely, it'll be replaced by SSA dataflow, which AutoRTFM has no need to muck with. We have also implemented a few small optimizations based on existing LLVM static analyses to avoid instrumenting stores when we can prove that we don't need to. The use of function cloning means that if you compile some C++ code with our compiler but never call any AutoRTFM runtime API, then the clones will never get invoked, and so you will never experience any overhead other than whatever it costs to have a larger binary with a bunch of dead code (so not exactly zero, but close). The next section goes into how the AutoRTFM runtime makes the instrumented clones sing.

#### The AutoRTFM Runtime

AutoRTFM's runtime is integrated into Unreal Engine Core, so from the standpoint of a Unreal Engine program such as Fortnite, it's always available. The key function from AutoRTFM that makes the magic happen is`AutoRTFM::Transact`. Calling this function with a lambda causes the runtime to set up a transaction object that contains the log data structures and other transaction state. Then,`Transact` calls the lambda's clone. This is exactly like the lambda, but has transactional instrumentation and obeys the AutoRTFM ABI. Currently, we call`Transact` in response to Verse entering a failure context, such as an if condition. In the future, we will call`Transact` before entering any Verse execution. The runtime has to handle, and provide APIs to handle, the following cases:

- What if the lambda passed to Transact, or some function it transitively calls, has no clone? This happens for system library functions or any function from a module not compiled with AutoRTFM.
- What if the transactionalized code needs to perform something that is not transaction-safe, like using atomics to perform a lock-free addition of a command to a physics command buffer? AutoRTFM provides multiple APIs for taking manual control of the transaction. The most commonly executed instance of this issue is`malloc/free` and related functions (like custom allocators).

Whenever AutoRTFM is asked to do a cloned function lookup and the clone isn't found, AutoRTFM will abort the transaction with an error. This ensures safety because it makes it impossible to accidentally call into not-transaction-safe code. Either the callee has been transactionalized, and the clone is present and called, or the callee isn't, and you get an abort due to a missing function. So, calling something like`WriteFile` in a transaction is an error by default. That's desirable default behavior, since`WriteFile` cannot be reliably undone—even if we tried to undo the write later, some other thread (either in our process or another process) could have seen the write and done something else unrecoverable based on that. This makes it practical to take an existing C++ program, compile it with AutoRTFM, and try to do a`Transact`. Either it will work correctly, or you will get an error saying that you called a not-transaction-safe function, along with a message about how to find that function and its callsite. The toughest part to get right is`malloc` and related functions. AutoRTFM takes the approach of not transactionalizing the implementation of`malloc`, but forcing callers to wrap calls to`malloc` with AutoRTFM API. This is especially straightforward in programs like Unreal Engine, where there is already a facade API that wraps the actual`malloc` implementation. It's best to understand what we do by looking at the code. Before AutoRTFM,`FMemory::Malloc` was something like:`void*`` FMemory::``Malloc``(SIZE_T ``Count``, uint32 ``Alignment``)
{
    ``return ``GMalloc``->``Malloc``(Count, Alignment);
}` Note that we removed a bunch of details to show just the important bit. With AutoRTFM, we do this instead:`void*``FMemory::``Malloc``(SIZE_T ``Count``, uint32 ``Alignment``)
{
    ``void*`` Ptr;
  ``  UE_AUTORTFM_OPEN``(
    {
        Ptr = ``GMalloc``->``Malloc``(Count, Alignment);
    });
    AutoRTFM::``OnAbort``([``Ptr``]
    {
        ``Free``(Ptr);
    });
    ``return ``AutoRTFM::``DidAllocate``(Ptr, Count);
}` Let's walk through what is happening step by step.

1. We use`UE_AUTORTFM_OPEN` to say that the enclosed block (which gets turned into a lambda) should run with no transaction instrumentation. This is simple for the runtime and compiler to implement: it just means that we emit a call to the original (uncloned) version of the lambda. This means that`GMalloc->Malloc` runs inside the transaction, but without any transactional instrumentation. We call this "running in the open" (as opposed to running closed, which means running the transactionalized clone). So, after this`UE_AUTORTFM_OPEN` returns, the malloc call would have run to completion immediately without any rollbacks registered. That maintains transactional semantics because malloc is already thread-safe, and so the fact that this thread did a malloc is not observable to other threads until the pointer to the malloc'd object leaks out of the transaction. The pointer won't leak out of the transaction until we commit, since the only places where`Ptr` can be stored are either other newly allocated memory or memory that AutoRTFM will transactionalize by logging the write.
2. Next we register an on-abort handler to free the object using`AutoRTFM::OnAbort`. If the transaction commits, then this handler does not run, so the malloc'd object survives. But if the transaction aborts, we will free the object. This ensures that there are no memory leaks from aborting.
3. Finally we inform AutoRTFM that this slab of memory is newly allocated, which means that the runtime does not have to log writes to this memory. Not logging writes to the memory makes it easier to run the`OnAbort`, since we don't have to worry about AutoRTFM trying to overwrite the contents of the object back to some previous state after we've already freed it. Also, not logging writes to newly allocated memory is a useful optimization.

If this code runs outside a transaction (i.e. all of this code was called from the open), then:

- `UE_AUTORTFM_OPEN` just runs the code block.
- `AutoRTFM::OnAbort` is a no-op; the passed-in lambda is just ignored.
- `AutoRTFM::DidAllocate` is a no-op.

Next let's look at what happens on free. Again, we've removed some details that are not interesting for this discussion.`void ``FMemory::``Free``(``void*``Original``)
{
  ``  UE_AUTORTFM_ONCOMMIT``(
    {
        ``GMalloc``->``Free``(Original);
    });
}` The`UE_AUTORTFM_ONCOMMIT` function has this behavior:

- In transactionalized code: this registers an on-commit handler to call the given lambda in the open. So, when and if the transaction commits, the object is freed. It's not freed immediately. If the transaction aborts, the object is not freed.
- In open code: runs the lambda immediately, so the object is freed immediately.

This style of instrumentation—malloc mallocs immediately but on-aborts a free while free on-commits the free—is applied to all of our allocators. The AutoRTFM runtime even installs its own handlers for malloc/free/new/delete via function lookup and compiler hacks, so you get the right behavior even if you use system allocators. The Unreal Engine GC does something similar, except there is no free function, and we run GC increments at the end of level tick—so outside of any transaction. The combination of compiler, runtime, and the malloc/GC instrumentation using`Open/OnCommit/OnAbort` APIs gives us everything we need to run C++ code in a transaction so long as that code does not use atomics, locks, system calls, or calls into those parts of the Unreal Engine codebase that we chose not to transactionalize at all (like the rendering and physics engines, currently). This has led to 94 total uses of the`Open` APIs in all of Fortnite. Those uses involve wrapping existing code with`Open` and friends at the appropriate granularity rather than changing algorithms or data structures.

## Verse Ecosystem Impact

AutoRTFM is a first step towards exposing more Verse semantics to UEFN. With AutoRTFM we will be able to:

- Implement cleaner runtime error behavior so that a game can keep running even after errors happen. AutoRTFM enables us to restore to a known state even if the runtime error was detected deep in C++ code.
- Remove the`<no_rollback>` effect, so that more code can be called from`if` and`for`. That effect is only there—polluting a lot of function signatures—because most C++ code cannot be transactional. AutoRTFM fixes that problem.
- Expose global transactional semantics, so that database accesses can be written as just Verse code and global variables. AutoRTFM means that Verse code can be run speculatively. This allows for exciting opportunities, such as having Verse participate in a transaction that spans the network, since we will be able to perform speculation to amortize the cost of remote data accesses.

## Get Unreal Engine today!

Get the world’s most open and advanced creation tool. With every feature and full source code access included, Unreal Engine comes fully loaded out of the box.

Get started now
