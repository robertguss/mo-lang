---
source_url: https://motoko-book.dev/advanced-concepts/async-programming.html
ingested: 2026-09-12
sha256: 0139a89cbfc796f86d2f40cd200ae78b61f78e274dc9b86f85b0a0362328442d
---
# Async Programming - The Motoko Programming Language Book

Async Programming - The Motoko Programming Language Book

- Light
- Rust
- Coal
- Navy
- Ayu

# The Motoko Programming Language Book

Print this book Git repository Suggest an edit

# Async Programming

The asynchronous programming paradigm of the Internet Computer is based on the [actor model] (https://en.wikipedia.org/wiki/Actor_model).

Actors are isolated units of code and state that communicate with each other by calling each others' shared functions where each shared function call triggers one or more messages to be sent and executed.

To master Motoko programming on the IC, we need to understand how to write asynchronous code, how to correctly handle async calls using try-catch and and how to safely modify state in the presence of concurrent activity.

NOTE From now on, we will drop the optional`shared` keyword in the declaration of shared functions and refer to these functions as simply 'shared functions'.

### On this page

Async and Await

Inter-Canister Calls Importing other actors Inter-Canister Query Calls

Messages and Atomicity Atomic functions Shared functions that`await` Atomic functions that send messages State commits and message sends Messaging restrictions Message ordering

Errors and Traps Errors Traps

Async* and Await*`await` and`await*` Atomic`await*` Non-atomic`await*` Keeping track of state commits and message sends

Table of asynchronous functions in Motoko

Try-Catch Expressions

## Async and Await

A call to a shared function immediately returns a future of type async T, where T is a shared type.

A future is a value representing the (future) result of a concurrent computation. When the computation completes (with either a value of type`T` or an error), the result is stored in the future.

A future of type`async T` can be awaited using the`await` keyword to retrieve the value of type`T`. Execution is paused at the await until the future is complete and produces the result of the computation, by returning the value of type`T` or throwing the error.

- Shared function calls and awaits are only allowed in an asynchronous context.
- Shared function calls immediately return a future but, unlike ordinary function calls, do not suspend execution of the caller at the call-site.
- Awaiting a future using`await` suspends execution until the result of the future, a value or error, is available.

NOTE While execution of a shared function call is suspended at an`await` or`await*`, other messages can be processed by the actor, possibly changing its state.

Actors can call their own shared functions. Here is an actor calling its own shared function from another shared function:

```
actor A {
    public query func read() : async Nat { 0 };

    public func call_read() : async Nat {
        let future : async Nat = read();

        let result = await future;

        result + 1
    };
};

```

The first call to`read` immediately returns a future of type`async Nat`, which is the return type of our shared query function`read`. This means that the caller does not wait for a response from`read` and immediately continues execution.

To actually retrieve the`Nat` value, we have to`await` the future. The actor sends a message to itself with the request and halts execution until a response is received.

The result is a`Nat` value. We increment it in the code block after the`await` and use as the return value for`call_read`.

NOTE Shared functions that`await` are not atomic.`call_read()` is executed as several separate messages, see shared functions that`await`.

## Inter-Canister Calls

Actors can also call the shared functions of other actors. This always happens from within an asynchronous context.

### Importing other actors

To call the shared functions of other actors, we need the actor type of the external actor and an actor reference.

```
actor B {
    type ActorA = actor {
        read : query () -> async Nat;
    };

    let actorA : ActorA = actor ("7po3j-syaaa-aaaal-qbqea-cai");

    public func callActorA() : async Nat {
        await actorA.read();
    };
};

```

The actor type we use may be a supertype of the external actor type. We declare the actor type`actor {}` with only the shared functions we are interested in. In this case, we are importing the actor from the previous example and are only interested in the query function`read`.

We declare a variable`actorA` with actor type`ActorA` and assign an actor reference`actor()` to it. We supply the principal id of actor A to reference it. We can now refer to the shared function`read` of actor A as`actorA.read`.

Finally, we`await` the shared function`read` of actor A yielding a`Nat` value that we use as a return value for our update function`callActorA`.

### Inter-Canister Query Calls

Calling a shared function from an actor is currently (May 2023) only allowed from inside an update function or oneway function, because query functions don't yet have message send capability.

'Inter-Canister Query Calls' will be available on the IC in the future. For now, only ingress messages (from external clients to the IC) can request a fast query call (without going through consensus).

## Messages and atomicity

From the official docs: A message is a set of consecutive instructions that a subnet executes for a canister.

We will not cover the terms 'instruction' and 'subnet' in this book. Lets just remember that a single call to a shared function can be split up into several messages that execute separately.

A call to a shared function of any actor A, whether from an external client, from itself or from another actor B (as an Inter-Canister Call), results in an incoming message to actor A.

A single message is executed atomically. This means that the code executed within one message either executes successfully or not at all. This also means that any state changes within a single message are either all committed or none of them are committed.

These state changes also include any messages sent as calls to shared functions. These calls are queued locally and only sent on successful commit.

An`await` ends the current message and splits the execution of a function into separate messages.

### Atomic functions

An atomic function is one that executes within one single message. The function either executes successfully or has no effect at all. If an atomic function fails, we know for sure its state changes have not been committed.

If a shared function does not`await` in its body, then it is executed atomically.

```
actor {
    var state = 0;

    public func atomic() : async () {
        state += 11; // update the state

        let result = state % 2; // perform a computation

        state := result; // update state again
    };

    public func atomic_fail() : async () {
        state += 1; // update the state

        let x = 0 / 0; // will trap

        state += x; // update state again
    };
};

```

Our function`atomic` mutates the state, performs a computation and mutates the`state` again. Both the computation and the state mutations belong to the same message execution. The whole function either succeeds and commits its final state or it fails and does not commit any changes at all. Moreover, the intermediate state changes are not observable from other messages. Execution is all or nothing (i.e. transactional).

The second function`atomic_fail` is another atomic function. It also performs a computation and state mutations within one single message. But this time, the computation traps and both state mutations are not committed, even though the trap happened after the first state mutation.

Unless an`Error` is thrown intentionally during execution, the order in which computations and state mutations occur is not relevant for the atomicity of a function. The whole function is executed as a single message that either fails or succeeds in its entirety.

### Shared functions that await

The async-await example earlier looks simple, but there is a lot going on there. The function call is executed as several separate messages:

The first line`let future : async Nat = read()` is executed as part of the first message.

The second line`let result = await future;` keyword ends the first message and any state changes made during execution of the message are committed. The`await` also calls`read()` and suspends execution until a response is received.

The call to`read()` is executed as a separate message and could possibly be executed remotely in another actor, see inter-canister calls. The message sent to`read()` could possibly result in several messages if the`read()` function also`await` s in its body.

In this case`read()` can't`await` in its body because it is a query function, but if it were an update or oneway function, it would be able to send messages.

If the sent message executes successfully, a callback is made to`call_read` that is executed as yet another message as the last line`result + 1`. The callback writes the result into the future, completing it, and resumes the code that was waiting on the future, i.e. the last line`result + 1`.

In total, there are three messages, two of which are executed inside the calling actor as part of`call_read` and one that is executed elsewhere, possibly a remote actor. In this case`actor A` sends a message to itself.

NOTE Even if we don't`await` a future, a message could still be sent and remote code execution could be initiated and change the state remotely or locally, see state commits.

### Atomic functions that send messages

An atomic function may or may not mutate local state itself, but execution of that atomic function could still cause multiple messages to be sent (by calling shared functions) that each may or may not execute successfully. In turn, these callees may change local or remote state, see state commits.

```
actor {
    var s1 = 0;
    var s2 = 0;

    public func incr_s1() : async () {
        s1 += 1;
    };

    public func incr_s2() : async () {
        s2 += 1;
        ignore 0 / 0;
    };

    // A call to this function executes succesfully 
    // and increments `s1`, but not `s2`
    public func atomic() : async () {
        ignore incr_s1();
        ignore incr_s2();
    };
};

```

We have two state variables`s1` and`s2` and two shared functions that mutate them. Both functions`incr_s1` and`incr_s2` are each executed atomically as single messages. (They do not`await` in their body).

`incr_s1` should execute successfully, while`incr_s2` will trap and revert any state mutation.

A call to`atomic` will execute successfully without mutating the state during its own execution. When`atomic` exits successfully with a result, the calls to`incr_s1` and`incr_s2` are committed (without`await`) and two separate messages are sent, see state commits.

Now,`incr_s1` will mutate the state, while`incr_s2` does not. The values of`s1` and`s2`, after the successful atomic execution of`atomic` will be`1` and`0` respectively.

These function calls could have been calls to shared function in remote actors, therefore initiating remote execution of code and possible remote state mutations.

NOTE We are using the`ignore` keyword to ignore return types that are not the empty tuple`()`. For example,`0 / 0` should in principle return a`Nat`, while`incr_s1()` returns a future of type`async ()`. Both are ignored to resume execution.

### State commits and message sends

There are several points during the execution of a shared function at which state changes and message sends are irrevocably committed:

1. Implicit exit from a shared function by producing a result The function executes until the end of its body and produces the expected return value with which it is declared. If the function did not`await` in its body, then it is executed atomically within a single message and state changes will be committed once it produces a result.

```
    var x = 0;

    public func mutate_atomically() : async Text {
        x += 1;
        "changed state and executed till end";
    };

```

1. Explicit exit via return Think of an early return like:

```
    var y = 0;

    public func early_return(b : Bool) : async Text {
        y += 1; // mutate state

        if (b) return "returned early";

        y += 1; // mutate state

        "executed till end";
    };

```

If condition`b` is`true`, the`return` keyword ends the current message and state is committed up to that point only. If`b` is true,`y` will only be incremented once.

Explicit throw expressions When an error is thrown, the state changes up until the error are committed and execution of the current message is stopped.

Explicit await expressions As we have seen in the shared functions that`await` example, an`await` ends the current message, commits state up to that point and splits the execution of a function into separate messages.

### Messaging Restrictions

The Internet Computer places restrictions on when and how canisters are allowed to communicate. In Motoko this means that there are restrictions on when and where the use of async expressions is allowed.

An expression in Motoko is said to occur in an asynchronous context if it appears in the body of an`async` or`async*` expression.

Therefore, calling a shared function from outside an asynchronous context is not allowed, because calling a shared function requires a message to be sent. For the same reason, calling a shared function from an actor class constructor is also not allowed, because an actor class is not an asynchronous context and so on.

Examples of messaging restrictions:

Canister installation can execute code (and possibly trap), but not send messages.

A canister query method cannot send messages (yet)

The`await` and`await*` constructs are only allowed in an asynchronous context.

The`throw` expression (to throw an error) is only allowed in an asynchronous context.

The`try-catch` expression is only allowed in an asynchronous context. This is because error handling is supported for messaging errors only and, like messaging itself, confined to asynchronous contexts.

### Message ordering

Messages in an actor are always executed sequentially, meaning one after the other and never in parallel. As a programmer, you have no control over the order in which incoming messages are executed.

You can only control the order in which you send messages to other actors, with the guarantee that, for a particular destination actor, they will be executed in the order you sent them. Messages sent to different actors may be executed out of order.

You have no guarantee on the order in which you receive the results of any messages sent.

Consult the official docs for more information on this topic.

## Errors and Traps

During the execution of a message, an error may be thrown or a trap may occur.

### Errors

An Error is thrown intentionally using the`throw` keyword to inform a caller that something is not right.

- State changes up until an error within a message are committed.
- Code after an error within a message is NOT executed, therefore state changes after an error within a message are NOT committed.
- Errors can be handled using`try-catch` expressions.
- Errors can only be thrown in an asynchronous context.
- To work with errors we use the Error module in the base library.

```
import Error "mo:base/Error";

actor {
    var state = 0;

    public func incrementAndError() : async () {
        state += 1;
        throw Error.reject("Something is not quite right, but I'm aware of it");
        state += 1;
    };
};

```

We import the Error module.

We have a shared functions`incrementAndError` that mutates`state` and throws an`Error`. We increment the value of`state` once before and once after the error throw. The function does not return`()`. Instead it results in an error of type`Error`(see Error module).

The first state mutation is committed, but the second is not.

After`incrementAndError`, our mutable variable`state` only incremented once to value`1`.

### Traps

A trap is an unintended non-recoverable runtime failure caused by, for example, division-by-zero, out-of-bounds array indexing, numeric overflow, cycle exhaustion or assertion failure.

- A trap during the execution of a single message causes the entire message to fail.
- State changes before and after a trap within a message are NOT committed.
- A message that traps will return a special error to the sender and those errors can be caught using`try-catch`, like other errors, see catching a trap.
- A trap may occur intentionally for development purposes, see Debug.trap()
- A trap can happen anywhere code runs in an actor, not only in an asynchronous context.

```
import Debug "mo:base/Debug";

actor {
    var state = 0;

    public func incrementAndTrap() : async () {
        state += 1;
        Debug.trap("Something happpened that should not have happened");
        state += 1;
    };
};

```

We import the Debug module.

The shared function`incrementAndTrap` fails and does not return`()`. Instead it causes the execution to trap (see Debug module).

Both the first and second state mutation are NOT committed.

After`incrementAndTrap`, our mutable variable`state` is not changed at all.

NOTE Usually a trap occurs without`Debug.trap()` during execution of code, for example at underflow or overflow of bounded types or other runtime failures, see traps.

Assertions also generate a trap if their argument evaluates to`false`.

## Async* and Await*

Recall that 'ordinary' shared functions with`async` return type are part of the actor type and therefore publicly visible in the public API of the actor. Shared functions provide an asynchronous context from which other shared functions can be called and awaited, because awaiting a shared function requires a message to be sent.

Private non-shared functions with`async*` return type provide an asynchronous context without exposing the function as part of the public API of the actor.

A call to an`async*` function immediately returns a delayed computation of type`async* T`. Note the`*` that distinguishes this from the future`async T`. The computation needs to be awaited using the`await*` keyword (in any asynchronous context`async` or`async*`) to produce a result. This was not the case with un-awaited`async` calls, see atomic functions that send messages.

For demonstration purposes, lets look at an example of a private`async*` function, that does not use its asynchronous context to call other`async` or`async*` functions, but instead only performs a delayed computation:

```
actor {
    var x = 0;

    // non-shared private func with `async*` return type
    private func compute() : async* Nat {
        x += 1001;
        x %= 3;
        x;
    };

    // non-shared private func that `await*` in its body
    private func call_compute() : async* Nat {
        let future = compute(); // future has no effect until `await*`
        await* future; // computation is performed here
    };

    // public shared func that `await*` in its body
    public func call_compute2() : async Nat {
        await* compute(); // computation is performed here
    };
};

```

`compute` is a private function with`async* Nat` return type. Calling it directly yields a computation of type`async* Nat` and resumes execution without blocking. This computation needs to be awaited using`await*` for the computation to actually execute (unlike the case with 'ordinary'`async` atomic functions that send messages).

`await*` also suspends execution, until a result is obtained. We could also pass around the computation within our actor code and only`await*` it when we actually need the result.

We`await*` our function`compute` from within an asynchronous context.

We`await*` our function`compute` from within an 'ordinary' shared`async` function`call_compute` or from within another private`async*` like`call_compute2`.

In the case of`call_compute` we obtain the result by first declaring a future and then`await*` ing it. In the case of
