---
source_url: https://verselang.github.io/book/13_effects/
ingested: 2026-09-12
sha256: 136bea8b4b023b5fe6c6445205b483187c61f0aae49202ae2add5baacef1bd71
---
# Effects - Book of Verse

Effects - Book of Verse

# Effects¶

Every function tells two stories. The first story, told through types, describes what data flows in and what data flows out. The second story, told through effects, describes what the function does along the way — whether it reads from memory, writes to storage, might fail, or could suspend execution. While most languages leave this second story implicit, Verse makes it explicit, turning side effects from hidden surprises into documented contracts.

Think about a simple game function that updates a player's score. In most languages, you'd see a signature like `UpdateScore(player, points)` and have to guess what happens inside. Does it modify the player object? Write to a database? Print to a log? Trigger animations? Without reading the implementation, you can't know. In Verse, effects are part of the signature itself, declaring upfront exactly what kinds of operations the function might perform.

This explicitness might seem like extra work at first, but it fundamentally changes how you reason about code. When you see ` ` on a function, you know it observes mutable state. When you see ` `, you know it modifies that state. When you see ` `, you know it might fail. These are not comments or documentation that might be wrong — they are compiler-enforced contracts that must be accurate.

## Understanding Effects¶

Effects represent observable interactions between your code and the world around it. Reading a player's health, updating a score, spawning a particle effect, waiting for an animation to complete — all these operations have effects that ripple beyond simple computation. Verse's effect system captures these interactions, making them visible and verifiable.

Consider this simple function that greets a player:

```verse
GreetPlayer()<transacts>:void =
    set CurrentGreeting = "Hello, adventurer!"
    Print(CurrentGreeting)

```

The ` ` effect tells you immediately that this function modifies mutable state. You do not need to read the implementation to know that calling `GreetPlayer()` will change something in your program's memory. The effect is a promise about behavior, checked and enforced by the compiler.

Effects compose naturally through function calls. If function A calls function B, and B has certain effects, then A must declare at least those same effects (with some exceptions we'll explore). This propagation ensures that effects can't be hidden or laundered through intermediate functions — the true nature of an operation is always visible at every level of the call stack.

Why Effects Matter

Making effects explicit serves both human understanding and compiler optimization. For developers, effects act as documentation that can't lie. When you are debugging why a value changed unexpectedly, you can trace through the call chain looking only at functions with ` `. When you are trying to understand why a function might fail, you look for ` `. This is not guesswork — it is guaranteed by the type system.

For the compiler, explicit effects enable powerful optimizations and safety guarantees. Pure functions marked ` ` can be memoized, their results cached because they'll always return the same output for the same input. Functions without ` ` can be safely executed in parallel without locks. Functions without ` ` can be called without failure handling.

The effect system also enforces architectural decisions. Want to ensure your math library remains pure? Mark its functions ` `. Building a predictive client system that must run on players' machines? Use ` ` to ensure no server-only operations sneak in. These are not just conventions — they are compiler-enforced guarantees.

## Effect Families and Specifiers¶

Verse organizes effects into families, each tracking a specific aspect of computation. Each family contains fundamental effects, and effect specifiers declare which effects a function may perform.

The six effect families are:

- Cardinality: Whether and how a function returns
- Heap: Access to mutable memory
- Suspension: Whether a function may suspend execution
- Divergence: Whether a function may run forever
- Prediction: Where a function runs
- Internal: Reserved for internal use

Some effects have no specifier, while some specifiers imply multiple effects. For instance, ` ` implies `reads`, `writes` and `allocates`, and belongs to the Heap family.

Effect specifiers can be further divided into exclusive specifiers (` `, ` `, ` `) and additive specifiers (` `, ` `, ` `, ` `, ` `). A function may have at most one exclusive specifier but can combine multiple additive ones. For example, ` ` is valid (pure computation that may fail), but ` ` is an error (cannot have two exclusive effects).

| Fundamental Effect | Effect Specifier | Effect Family | Effects implied by Specifier | Notes |
| --- | --- | --- | --- | --- |
| succeeds | | Cardinality | | No specifier; Must Succeed |
| fails | | Cardinality | | No specifier; Can Fail |
| | ` ` | Cardinality | `{succeeds, fails}` | Cannot combine with ` ` |
| reads | ` ` | Heap | `{reads}` | Allows reading mutable states |
| writes | ` ` | Heap | `{writes}` | Allows writing mutable states |
| allocates | ` ` | Heap | `{allocates}` | Allows allocation of mutable memory |
| | ` ` | Heap | `{reads, writes, allocates}` | Exclusive; default |
| | ` ` | Heap | `{}` | Exclusive; Pure computation |
| suspends | ` ` | Suspension | `{suspends}` | Cannot combine with ` ` |
| diverges | | Divergence | `{diverges}` | No specifier; May run forever |
| | ` ` | Divergence | `{}` | Exclusive; Native functions, abstract methods, type signatures |
| dictates | | Prediction | `{dictates}` | No specifier; Server Authority |
| | ` ` | Prediction | `{}` | Allows Client Prediction |
| no_rollback | | Internal | `{no_rollback}` | To be deprecated; Transactions disallowed |

The following restrictions are in effect:

- ` ` and ` ` cannot be combined on the same function,
- ` ` is only allowed on ` ` functions, abstract methods, and type signatures,
- duplicate specifiers (e.g., ` `) are errors.

## How Effects Compose¶

Think of effect specifiers as setting bits in a bit vector: one bit per fundamental effect. Without any annotation, a function such as `GameUpdate` has the following effects:

```verse
GameUpdate():void = ...  # No explicit effects specified

```

| dictates | suspends | reads | writes | allocates | succeeds | fails |
| --- | --- | --- | --- | --- | --- | --- |
| ✔️ | ❌ | ✔️ | ✔️ | ✔️ | ✔️ | ❌ |

This means it has effects `dictates`, `reads`, `writes`, `allocates` and `succeeds`. It's almost like writing ` ` except we lack a way to say the function cannot fail.

As an aside: the absence of specifiers for `fails` and `succeeds` can be explained by the fact that a specifier like ` ` means the function always fails, never returns a value, and cannot have observable side effects (they would be undone by failure). The `succeeds` effect is implicit.

Annotating a function only affects the bits in that specifier's family. For example, function `CheckPlayerStatus` with the ` ` and ` ` specifier:

```verse
CheckPlayerStatus()<reads><predicts>:string = ...

```

has the following effects:

| dictates | suspends | reads | writes | allocates | succeeds | fails |
| --- | --- | --- | --- | --- | --- | --- |
| ❌ | ❌ | ✔️ | ❌ | ❌ | ✔️ | ❌ |

Specifying ` ` clears the `writes` and `allocates` bits, and ` ` clears the `dictates` bit, everything else is unchanged.

### Cardinality effects¶

The cardinality family deals with whether functions return values successfully. Every function either succeeds (returning its declared type) or fails (producing no value). Most functions always succeed — they are deterministic transformations that always produce output. But functions marked with ` ` can fail, turning failure into a control flow mechanism.

```verse
ValidateHealth(Health:float)<transacts><decides>:void =
    Health > 0.0      # Fails if health is zero or negative
    Health <= 100.0   # Fails if health exceeds maximum

# Usage
if (ValidateHealth[Player.Health]):
    # Health is valid, continue processing
    StartCombat()

```

The beauty of the decides effect is that it unifies validation with control flow. You do not check conditions and then act on them — the check itself drives the program's path.

### Heap effects¶

The heap family governs access to mutable memory. This is perhaps the most important family for understanding program behavior, as it determines whether functions can observe or modify state.

The ` ` specifier marks pure functions — those that neither read nor write mutable state. These functions are deterministic: given the same inputs, they always produce the same outputs. They're the mathematical ideal of computation, transforming data without side effects.

```verse
CalculateDamage(BaseDamage:float, Multiplier:float)<computes>:float =
    BaseDamage * Multiplier

```

The ` ` effect allows functions to observe mutable state. They can see the current values of variables and mutable fields, but cannot modify them. This is useful for queries and calculations based on current game state.

```verse
player := class:
    Name:string
    var Health:float = 100.0
    var Score:int = 0

GetPlayerStatus(P:player)<reads>:string =
    if (P.Health > 50.0):
        "Healthy"
    else if (P.Health > 0.0):
        "Injured"
    else:
        "Defeated"

```

The ` ` effect permits modification of mutable state. Functions with this effect can use `set` to update variables and mutable fields. ` ` often requires ` ` as well, for instance when modification involves reading the current value.

In fact, the `set` instruction is by default ` ` due to the addition of live variables to the language. A live variable is variable whose value depends on other variables; when one of those variables is updated by a `set` the live variable will be evaluated with potentially some `reads` and `allocates`.

```verse
HealPlayer(P:player, Amount:float)<transacts>:void =
    NewHealth := P.Health + Amount
    set P.Health = Min(NewHealth, 100.0)

```

The ` ` effect indicates functions that create observably unique values — either objects marked ` ` or values containing mutable fields. Each call to such a function returns a distinct value, even if the inputs are identical.

```verse
game_entity := class<allocates>:
    ID:id
    var Position:vector3

CreateEntity(Pos:vector3)<allocates>:game_entity =
    game_entity{ID := GenerateID(), Position := Pos}

```

The ` ` is the default for functions. 

### Suspension effects¶

The suspension family contains a single effect: ` `. Functions with this effect can pause their execution and resume later, potentially across multiple game frames. This is essential for operations that take time: animations, cooldowns, waiting for player input, or any multi-frame behavior.

```verse
PlayVictorySequence()<suspends>:void =
    PlayAnimation(VictoryDance)
    Sleep(2.0)  # Wait 2 seconds
    PlaySound(VictoryFanfare)
    Sleep(1.0)
    ShowRewardsScreen()

```

The `suspends` effect is viral — any function that calls a suspending function must itself be marked ` `. This ensures you always know which functions might take time to complete.

While ` ` and ` ` cannot be combined on the same function, they have specific rules for how they interact across function calls. A ` ` function can call a ` ` function, but only within a failure context using the square bracket `[]` syntax -- this ensures that the failure is handled locally and does not propagate as a failure effect:

```verse
ValidateInput(Value:int)<decides><computes>:void =
    Value > 0
    Value < 100

ProcessAsync(Value:int)<suspends>:void =
    # Valid: calling decides function in failure context
    if (ValidateInput[Value]):
        # Process valid input
        DoAsyncWork()

# Invalid: calling decides function outside failure context
# ProcessAsync(Value:int)<suspends>:void =
#     ValidateInput(Value)  # ERROR: must use [] syntax

```

A ` ` function can call another ` ` function, but must not use failure-handling syntax like `?`:

```verse
AsyncOp()<suspends>:?int = false

CallAsync()<suspends>:void =
    # Valid: calling suspends function normally
    X := AsyncOp()

    # Invalid: cannot use ? with suspends in suspends context
    # if (Value := AsyncOp()?):

```

The asymmetry exists because ` ` and ` ` represent fundamentally different control flow mechanisms—suspension is about time, while failure is about success/failure. Mixing their syntactic forms creates ambiguity about what's being handled.

### Internal effects¶

[Pre-release]: The `<no_rollback>` effect is deprecated.

#### Prediction effects¶

Unreleased Feature

The ` ` effect is not yet released.

The prediction family determines where code runs in a client-server architecture. By default, functions have the `dictates` effect, meaning they run authoritatively on the server. The ` ` specifier allows functions to run predictively on clients for responsiveness, with the server later validating and potentially correcting the results.

```verse
HandleJumpInput()<predicts>:void =
    # Runs immediately on the client for responsiveness
    StartJumpAnimation()
    PlayJumpSound()

    # Server will validate and correct if needed
    PerformJump()

```

This enables responsive gameplay even with network latency, as players see immediate feedback for their actions while the server maintains authoritative state.

#### Divergence effects¶

Currently in planning, the divergence family will track whether functions are guaranteed to terminate. The ` ` specifier marks functions that provably complete in finite time, while functions without it might run forever. This is particularly important for constructors and initialization code.

The ` ` specifier can be used on:

- ` ` functions that are guaranteed to terminate
- Abstract method signatures in classes and interfaces
- Function signatures in type expressions

Regular function implementations cannot use ` ` — only their declarations in abstract contexts or as native functions.

## Effect Composition¶

Effects generally propagate up the call chain — a function must declare all the effects of the functions it calls. However, certain language constructs can hide specific effects, preventing them from propagating further.

An `if` expression hides `fails` effects in its failure context, thus failure failure in a condition does not propagate to the enclosing function:

```verse
SafeMod(A:int, B:int)<computes>:int =
    if (V:= Mod[A,B])  then V else 0

```

The `spawn` expression hides the `suspends` effect, allowing immediate functions to start asynchronous operations that continue independently:

```verse
Play()<suspends>:void =
        loop:
            PlayTrack(GetNextTrack())
            Sleep(180.0)  

StartBackgroundMusic():void =  # No <suspends>
    spawn:
        Play() # Suspends effect hidden by spawn

```

As mentioned above failure is not allowed within ` ` code including `spawn`. One way around this restriction is to use the `option` expression to convert failure into an optional value, transforming the `fails` effect into a regular value that can be handled without ` `:

```verse
TryGetItem(Items:[]item, Index:int):?item =
    option{Items[Index]}  # Array access might fail, option catches it

```

The `defer` expression provides cleanup code that runs when exiting a scope, but has strict effect limitations:

- Cannot contain ` ` operations—deferred code must execute synchronously
- Cannot contain ` ` operations—deferred code must always succeed

```verse
AcquireResource()<transacts>:resource = GetResource()
ReleaseResource(R:resource)<transacts>:void = {}

ProcessResource()<suspends>:void =
    R := AcquireResource()
    defer:
        ReleaseResource(R)  # Valid: transacts allowed in defer

    # Process resource with async operations
    DoAsyncWork()

```

These constraints ensure that cleanup code executes predictably and completely, without the possibility of suspension or failure that could leave resources in an inconsistent state.

## Subtyping and Type Compatibility¶

Effect annotations create a subtyping relationship between function types. Understanding how effects interact with type compatibility is essential when storing functions in variables, passing them as parameters, or choosing between different implementations.

A function with fewer effects can be used where a function with more effects is expected. This is effect subtyping—a function that does less is compatible with a context that allows more:

```verse
# Pure function with only computes
PureAdd(X:int)<computes>:int = X + 1

# Variable that expects computes and decides
F:type{_(:int)<computes><decides>:int} = PureAdd

# Calling through the variable
Result := F[5]  # Must use [] syntax since type has <decides>
# Returns 6 since PureAdd never fails

```

In this example, `PureAdd` has only ` `, but it can be assigned to a variable expecting ` `. The pure function is a valid implementation of the failable interface—it simply never exercises the failure capability.

This principle applies to all effects:

```verse
# Function with <computes>
Compute(X:int)<computes>:int = X * 2

# Can assign to types expecting more effects
F1:type{_(:int)<computes><decides>:int} = Compute
F2:type{_(:int)<transacts>:int} = Compute
F3:type{_(:int)<reads>:int} = Compute

# All valid - Compute does less than what's allowed

```

When deciding subtyping, effects have the following impact:

- ` ` is a subtype of ` `, ` `, and any combination with ` `
- ` ` is a subtype of ` `
- Functions without ` ` are subtypes of functions with ` `
- Functions without ` ` are subtypes of functions with ` ` (when compatible)

While you can add effects through subtyping, you cannot remove effects that a function actually has:

```verse
Validate(X:int)<computes><decides>:int =
    X > 0
    X

# ERROR: Cannot assign to type without <decides>
# F:type{_(:int)<computes>:int} = Validate
# The function CAN fail, but the type does not allow it

```

Similarly, functions with heap effects cannot be assigned to pure types:

```verse
counter := class:
    var Count:int = 0

Increment(C:counter)<transacts>:int =
    set C.Count = C.Count + 1
    C.Count

# ERROR: Cannot assign transacts function to computes type
# F:type{_(:counter)<computes>:int} = Increment
# The function writes state, type does not permit it

```

This restriction ensures type safety—the type signature is a promise about what effects the function might perform, and the actual function must honor that promise.

When you conditionally select between functions with different effects, the resulting expression has the union of all possible effects. This is effect joining—the compiler conservatively assumes the result might perform any effect that any branch could perform:

```verse
# Functions with different effects
PureFunction(X:int)<computes>:int = X + 1
FailableFunction(X:int)<computes><decides>:int =
    X > 0
    X + 1

# Conditional selection joins effects
SelectFunction(UseFailable:logic):type{_(:int)<computes><decides>:int} =
    if (UseFailable?):
        FailableFunction  # Has <computes><decides>
    else:
        PureFunction      # Has <computes>
    # Result type must account for both: <computes><decides>

# The returned function might fail (from FailableFunction)
# or might not (from PureFunction), so type must include <decides>
F := SelectFunction(true)
Result := F[5]  # Must use [] because result type has <decides>

```

Effect joining applies to all control flow that selects between functions:

```verse
Identity(X:int)<computes>:int = X

DecidesIdentity(X:int)<computes><decides>:int =
    X > 0
    X

TransactsIdentity(X:int)<transacts>:int = X

# Joining <computes> and <computes><decides>
F1:type{_(:int)<computes><decides>:int} =
    if (true?):
        Identity
    else:
        DecidesIdentity
# Result: <computes><decides> (union of effects)

# Joining <computes><decides> and <transacts>
F2:type{_(:int)<decides><transacts>:int} =
    if (true?):
        DecidesIdentity  # <computes><decides>
    else:
        TransactsIdentity  # <transacts>
# Result: <decides><transacts> (union of effects)

```

Effect subtyping enables flexible function parameters:

```verse
# Accepts any function that does not exceed <transacts><decides>
ProcessValues(
    Data:[]int,
    Transform(:int)<transacts><decides>:int
):[]int =
    for (Value:Data, Result := Transform[Value]):
        Result

# Can pass pure functions
ProcessValues(array{1, 2, 3}, PureAdd)

# Can pass failable functions
ProcessValues(array{1, 2, 3}, Validate)

# Can pass transactional functions
ProcessValues(array{1, 2, 3}, Increment)

```

Effect subtyping makes function composition work naturally:

```verse
Compose(
    F(:int)<computes>:int,
    G(:int)<computes>:int
):type{_(:int)<computes>:int} =
    Local(X:int)<computes>:int = G(F(X))
    Local

# If we want to allow more effects:
ComposeFlexible(
    F(:int)<transacts><decides>:int,
    G(:int)<transacts><decides>:int
):type{_(:int)<transacts><decides>:int} =
    Local(X:int)<transacts><decides>:int =
        if (IntermediateResult := F[X]):
            G[IntermediateResult]
        else:
            1=2; 0
    Local

# Can pass functions with fewer effects
ComposeFlexible(PureFunction, PureFunction)
ComposeFlexible(PureFunction, FailableFunction)

```

The following table summarize the interaction of effects and types:

| Scenario | Valid? | Explanation |
| --- | --- | --- |
| Assign ` ` to ` ` type | ✓ | Adding effects via subtyping |
| Assign ` ` to ` ` type | ✓ | Pure is subtype of transactional |
| Assign ` ` to ` ` type | ✓ | Reads is subtype of transactional |
| Assign ` ` to ` ` type | ✗ | Cannot remove ` ` |
| Assign ` ` to ` ` type | ✗ | Cannot remove heap effects |
| Select between ` ` and ` ` | Result: ` ` | Effect joining |
| Select between ` ` and ` ` | Result: ` ` | Effect joining |

These rules ensure that effect annotations remain trustworthy contracts—functions can do less than declared (subtyping), but never more, and conditional selection conservatively accounts for all possibilities (joining).

## Effects on Data Types¶

Classes, structs, and interfaces can be annotated with effect specifiers, which apply to their constructors. This is particularly useful for ensuring that creating certain objects remains pure or has limited effects:

```verse
# Pure data structure - constructor has no effects
vector3 := struct<computes>:
    X:float = 0.0
    Y:float = 0.0
    Z:float = 0.0

# Entity that requires allocation due to unique identity
monster := class<unique><allocates>:
    Name:string
    var Health:float = 100.0

```

Classes, interfaces, and structs cannot be marked with ` ` or ` `:

```verse
# Valid effect specifiers for classes/interfaces/structs:
valid_class := class<computes>{}
valid_interface := interface<computes>{}
valid_struct := struct<transacts>{}

# Invalid: async and failable effects not allowed
# invalid_class := class<suspends>{}      # ERROR
# invalid_interface := interface<decides>{}  # ERROR
# invalid_struct := struct<decides>{}     # ERROR

```

This restriction applies to the class/struct declaration itself — the archetype constructor `my_class{...}` cannot be failable or suspending. However, constructor functions can use ` `:

```verse
# The class declaration cannot be <decides>
my_class := class:
    Value:int

# But a constructor function CAN be <decides>
MakeMyClass<constructor>(V:int)<transacts><decides> := my_class:
    Value := block:
        V > 0      # Fails if V <= 0
        V < 100    # Fails if V >= 100
        V

```

This provides failable construction when needed — the object either exists fully formed or the constructor function fails and no object is created.

Field default values and block clauses in classes have strict effect requirements:

```verse
# Field initializers must use pure functions
HelperFunction()<transacts>:int = 42

# Invalid: field initializers cannot call transacts functions
# bad_class := class:
#     Value:int = HelperFunction()  # ERROR

# Block clauses must respect class effects
valid_class := class<transacts>:
    var Counter:int = 0
    block:
        set Counter = 1  # Valid: class has transacts

# Invalid: block effect exceeds class effect
# bad_class := class<computes>:
#     var Counter:int = 0
#     block:
#         set Counter = 1  # ERROR: computes class cannot write

```

Class member initializers and block clauses are implicitly restricted to have no more effects than what the class declares. This ensures that constructing an instance of the class respects the class's effect contract.

Limiting constructor effects helps maintain architectural boundaries. Data transfer objects can be kept pure with ` `, ensuring they are just data carriers. Game entities might require ` ` for unique identity, while service objects might need full ` ` to initialize their state.

### Interface Construction Effect Constraints¶

When classes or interfaces inherit from interfaces with construction effects, they must declare at least the same construction effects:

```verse
# Interface with transacts effect
transacting_interface := interface<transacts>{}

# Valid: class has at least transacts
valid_class := class<transacts>(transacting_interface){}

# Invalid: class has less effects than interface requires
# invalid_class := class<computes>(transacting_interface){}  # ERROR

```

Interface field initializers must also respect the interface's declared construction effects:

```verse
transacting_class := class<transacts>{}

# Valid: interface has transacts, field initializer has transacts
valid_interface := interface<transacts>:
    Instance:transacting_class = transacting_class{}

# Invalid: interface has computes, but field initializer has transacts
# invalid_interface := interface<computes>:
#     Instance:transacting_class = transacting_class{}  # ERROR

```

These constraints ensure that construction effects flow correctly through inheritance hierarchies. A class inheriting an interface must be able to construct all interface fields, which requires having at least the same construction effects.

## Working with Effects¶

When designing functions, start with the minimal effects needed and expand only when necessary. Pure functions with ` ` are the easiest to test, reason about, and compose. Add ` ` when you need to observe state, ` ` when you need to modify it, and ` ` when you need failure-based control flow.

Effects are part of your API contract. Once published, removing effects is a backwards-compatible change (your function does less than before), but adding effects is breaking (your function now does more than callers might expect). Design your effect signatures thoughtfully, as they become promises to your users.

Remember that over-specifying effects is allowed and sometimes beneficial. A function marked ` ` can be implemented as pure ` ` internally. This provides flexibility for future changes without breaking existing callers.

```verse
# API promises it might read state
GetDefaultWeapon<public>()<reads>:weapon =
    # But current implementation is pure
    weapon{Type := weapon_type.Sword, Dammage := 10}

```

Effect over-specification can future-proof APIs and avoid breaking changes later. For example, marking a currently pure function as ` ` allows you to add state observation in the future without breaking compatibility.

## Backwards Compatibility¶

The effects of a function are part of what is checked for backwards compatibility. When updating a function that is part of a published API, the new version can have "fewer bits" but not more. So, a function that was marked as ` ` in a previous version cannot be changed to ` `, but it can be refined to ` `.

Effects transform side effects from hidden gotchas into visible, verifiable contracts. By making the implicit explicit, Verse helps you write more predictable, maintainable, and correct code. The effect system is not a burden — it is a tool that helps you express your intent clearly and have the compiler verify that your implementation matches that intent.
