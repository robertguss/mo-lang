---
source_url: https://docs.internetcomputer.org/guides/canister-calls/inter-canister-calls/
ingested: 2026-09-12
sha256: e386299f050185cd438481b9a151289faf3f28d69918d307499bd6611ad11ae3
---
# Inter-canister calls | ICP Developer Docs

Inter-canister calls | ICP Developer Docs

# Inter-canister calls

Canisters on the Internet Computer communicate by calling each other’s functions. A caller canister sends a request message containing the method name, arguments, and optionally attached cycles. The callee executes the method and returns a response. If the callee cannot be reached or a resource limit is hit, the system produces a reject response instead.

This guide covers making inter-canister calls in both Motoko and Rust, choosing between query and update calls, handling errors, and avoiding common pitfalls. For the messaging model behind these calls, see Canisters.

## Query vs update calls

There are two types of canister methods, and the choice affects latency, cost, and trust:

| | Query | Update |
| --- | --- | --- |
| Latency | ~200ms | ~2s |
| Cycle cost | Free | Costs cycles |
| Execution | Single replica | Full consensus |
| State changes | Not persisted | Persisted |
| Trust model | Caller trusts one replica | Replicated and verifiable |

Use query calls when reading data where the caller trusts the subnet (or will verify the response independently). Queries are fast and free, but the response comes from a single node and is not replicated.

Use update calls when modifying state, transferring cycles, or when the caller needs a consensus-backed guarantee that the call was executed correctly.

To make query responses verifiable without the cost of update calls, see Certified Variables. For running multiple query calls in parallel, see Parallel inter-canister calls.

## Making calls

- Motoko 
- Rust 

Import another canister by name and call its methods with `await`:

> Note: The `canister:name` import syntax is being redesigned for icp-cli compatibility. See Canister discovery for the recommended environment variable approach.

import Counter "canister:counter";

 

persistent actor {

 public func getCount() : async Nat {

 await Counter. get()

 };

 

 public func incrementAndGet() : async Nat {

 await Counter. increment();

 await Counter. get()

 };

};

The Rust CDK provides `Call::unbounded_wait` and `Call::bounded_wait` to call other canisters. Both return a builder that lets you attach arguments, cycles, and timeout settings.

use candid::{Nat, Principal};

use ic_cdk:: call:: Call;

use ic_cdk:: update;

 

#[update]

pub async fn call_get_and_set(counter: Principal, new_value: Nat) -> Nat {

 Call:: unbounded_wait(counter, " get_and_set")

 . with_arg(& new_value)

 . await

 . expect(" Failed to get the old value")

 . candid:: ()

 . expect(" Candid decoding failed")

}

## Error handling

- Motoko 
- Rust 

Wrap inter-canister calls in `try`/`catch` to handle rejects:

import Counter "canister:counter";

import Error "mo:core/Error";

import Result "mo:core/Result";

 

persistent actor {

 public shared ({ caller }) func safeIncrement() : async Result. Result< Nat, Text> {

 try {

 await Counter. increment();

 let count = await Counter. get();

 #ok(count)

 } catch (e) {

 #err("Counter call failed: " # Error. message(e))

 };

 };

};

In Motoko, `public shared ({ caller })` binds the original caller at method entry, so `caller` remains valid after `await` points.

Cleanup with `finally`

Use `try/finally` (with or without `catch`) to guarantee cleanup code runs: even if code after an `await` traps. This is useful for releasing locks or rolling back temporary state:

var locked = false;

 

public shared func guarded() : async () {

 assert not locked;

 locked := true;

 try {

 await Counter. increment();

 // ... more work

 } finally {

 locked := false; // Always runs, even on trap after await

 };

};

The `finally` block must be effect-free: no `await`, no `throw`, no async calls. It must return `()` and should not trap: a trapping `finally` block can prevent future upgrades.

The call returns a `Result` where the error type distinguishes clean rejects (the call definitively did not execute) from non-clean rejects (the outcome is unknown):

use candid:: Principal;

use ic_cdk:: call::{Call, CallErrorExt};

use ic_cdk:: update;

 

#[update]

pub async fn call_increment(counter: Principal) -> Result<(), String> {

 match Call:: unbounded_wait(counter, " increment"). await {

 Ok(_) => Ok(()),

 Err(e) if ! e. is_clean_reject() => {

 Err(format!(" Non-clean reject: {:?}. Outcome unknown.", e))

 }

 Err(e) => {

 Err(format!(" Clean reject: {:?}. Counter was not incremented.", e))

 }

 }

}

The distinction matters for correctness:

- Clean reject: the callee never executed the method. Safe to retry.
- Non-clean reject: the callee may or may not have executed. Use idempotent APIs or provide a separate endpoint to query the outcome.

## Canister discovery

Before making an inter-canister call, your canister needs the `Principal` of the target canister. Canister IDs are assigned at deployment time and differ between environments (local, staging, mainnet), so hardcoding them creates portability problems.

### Environment variables (recommended)

`icp deploy` automatically injects `PUBLIC_CANISTER_ID: ` environment variables into every canister in the environment. This means each canister can discover any other canister’s ID at runtime without hardcoding:

- Motoko 
- Rust 

import Runtime "mo:core/Runtime";

import Principal "mo:core/Principal";

 

let ?counterIdText = Runtime. envVar< system>("PUBLIC_CANISTER_ID:counter") else {

 return #err("counter canister ID not set");

};

let counterId = Principal. fromText(counterIdText);

use candid:: Principal;

 

let counter_id = Principal:: from_text(

 & ic_cdk:: api:: env_var_value(" PUBLIC_CANISTER_ID:counter")

). unwrap();

Deployment order does not matter: `icp deploy` creates all canisters first, then injects variables, then installs code. Variables are only updated for the canisters being deployed, so run `icp deploy` (without arguments) when adding new canisters to update all of them.

> Tip: For Rust canisters that make inter-canister calls, `ic-cdk-bindgen` can generate type-safe call stubs from `.did` files: so you call typed functions instead of manually constructing `Call::unbounded_wait` with string method names. See Binding generation for details.

### Alternative approaches

Init arguments. Accept the target `Principal` as an `#[init]` argument and store it. This avoids the environment variable lookup at call time but requires passing the ID at every deploy and upgrade:

Terminal window

TARGET_ID=$(icp canister id counter)

icp deploy my_canister --argument "(principal \"$TARGET_ID\")"

Hardcoded principal. Acceptable for well-known system canisters (like the management canister `aaaaa-aa` or the NNS ledger). Avoid for application canisters.

> Motoko named imports: Motoko’s `import Counter "canister:counter"` syntax resolves canister IDs at compile time. This syntax is currently being redesigned to work with icp-cli’s environment-based discovery model. Use environment variables for now if you are building with icp-cli.

## Bounded vs unbounded wait

Every inter-canister call must choose a wait strategy. By default, calls use unbounded wait: the caller waits indefinitely until the callee responds. Bounded wait (also called best-effort messaging) adds a timeout: if the callee hasn’t responded by the deadline, the system returns a `SYS_UNKNOWN` response.

- Motoko 
- Rust 

By default, `await` uses unbounded wait. Add a `timeout` parenthetical (in seconds) to use bounded wait:

// Unbounded wait (default): guaranteed response

let result = await Counter. get();

 

// Bounded wait: best-effort response with 25-second deadline

let result = await (with timeout = 25) Counter. get();

 

// Reusable timeout configuration

let boundedWait = { timeout = 25 };

let result = await (boundedWait) Counter. get();

 

// Combine timeout with cycles

let result = await (boundedWait with cycles = 1_000_000) Counter. get();

The Rust CDK provides separate constructors for each strategy:

use ic_cdk:: call:: Call;

 

// Unbounded wait: guaranteed response

Call:: unbounded_wait(callee, " method")

 . await

 

// Bounded wait: best-effort response with 5-second timeout

Call:: bounded_wait(callee, " method")

 . change_timeout(5) // timeout in seconds

 . await

When to use each:

- Unbounded wait: the callee is guaranteed to respond (including rejects). Use for calls to canisters you control and trust to respond promptly.
- Bounded wait: the caller may receive `SYS_UNKNOWN` after the timeout or if the subnet runs low on resources. Use for calls to third-party or untrusted canisters.

Upgrade safety: unbounded wait calls may prevent your canister from upgrading until the callee responds. If the callee is unresponsive or malicious, your canister could be stuck indefinitely. Prefer bounded wait when calling canisters you do not control.

Calling third-party canisters: When calling canisters outside your control, always use bounded wait and design for uncertainty. The callee may be upgraded, become unresponsive, or behave unexpectedly. Use idempotent operations where possible and provide a way to query the outcome of a call separately, so your canister can recover from ambiguous responses.

## Calls with attached cycles

Some canister methods require cycles to be attached to the incoming call as a per-request fee. The exchange rate canister is a common example: each request costs one XDR’s worth of cycles, which must arrive with the call.

This is distinct from a canister’s ongoing operational balance. The cycles ledger cannot forward calls with cycles attached, so you must attach them explicitly at the call site.

### Sending cycles

- Motoko 
- Rust 

Use the `(with cycles = amount)` parenthetical on any `await` expression:

import Cycles "mo:core/Cycles";

 

persistent actor {

 let target = actor ("rrkah-fqaaa-aaaaa-aaaaq-cai") : actor {

 someMethod : () -> async ();

 };

 

 public func callWithCycles() : async () {

 await (with cycles = 500_000_000) target. someMethod();

 };

}

Chain `.with_cycles()` on the `Call` builder before awaiting:

use candid:: Principal;

use ic_cdk:: call:: Call;

use ic_cdk:: update;

 

#[update]

async fn call_with_cycles() {

 Call:: unbounded_wait(

 Principal:: from_text(" rrkah-fqaaa-aaaaa-aaaaq-cai"). unwrap(),

 " someMethod",

 )

 . with_cycles(500_000_000u128)

 . await

 . expect(" call failed");

}

The cycles come from the calling canister’s own balance, not the cycles ledger. Top up the calling canister with `icp canister top-up` before using this pattern.

### Charging a cycle fee

A canister that charges per-call defines a required fee, rejects calls that don’t meet it, and accepts exactly that amount before doing its work. Any cycles above the fee are returned to the caller automatically:

- Motoko 
- Rust 

import Cycles "mo:core/Cycles";

import Runtime "mo:core/Runtime";

 

persistent actor {

 let fee : Nat = 100_000_000;

 

 public func compute() : async () {

 let available = Cycles. available();

 if (available < fee) {

 Runtime. trap("Insufficient cycles: requires " # debug_show fee)

 };

 ignore Cycles. accept< system>(fee); // accept exactly the fee; excess is returned automatically

 // ... do work here

 };

}

use ic_cdk:: update;

 

const FEE: u128 = 100_000_000;

 

#[update]

fn compute() {

 let available = ic_cdk:: api:: msg_cycles_available();

 if available < FEE {

 ic_cdk:: trap(" Insufficient cycles");

 }

 ic_cdk:: api:: msg_cycles_accept(FEE); // accept exactly the fee; excess is returned automatically

 // ... do work here

}

### Attaching cycles from the CLI

The CLI cannot attach cycles directly to a canister call. Two approaches address this:

Top up the target canister first (preferred when you control it): transfer cycles to the target using `icp canister top-up`, then call the method normally. The canister uses its own balance when the method runs.

Terminal window

# Transfer 1T cycles to the target canister

icp canister top-up rrkah-fqaaa-aaaaa-aaaaq-cai --amount 1T -n ic

 

# Then call the method as normal

icp canister call rrkah-fqaaa-aaaaa-aaaaq-cai someMethod '()' -n ic

Proxy canister (required when you cannot top up the target, or need cycles attached to each individual call): deploy a proxy canister that forwards calls with cycles attached.

Terminal window

# Deploy the proxy canister using the provided template

icp new proxy --subfolder proxy

cd proxy

icp deploy -e ic

 

# Get the proxy canister ID

export PROXY_ID=$(icp canister status -e ic --id-only proxy)

 

# Call any canister through the proxy with cycles attached

icp canister call --proxy "$PROXY_ID" rrkah-fqaaa-aaaaa-aaaaq-cai someMethod '()' -n ic

The proxy canister template is available at icp-cli-templates/proxy. It deploys the proxy-canister, which is automatically provisioned on local networks but must be deployed manually on mainnet.

## Pub/sub pattern

The publisher/subscriber pattern is a natural fit for inter-canister communication on ICP. A publisher canister maintains a list of subscribers and notifies them when events occur. Unlike traditional pub/sub systems, ICP’s reliable message delivery means subscribers are guaranteed to receive notifications (as long as both canisters have sufficient cycles).

- Motoko 
- Rust 

Publisher

The publisher stores subscriber callbacks and invokes them when publishing:

import List "mo:core/List";

 

persistent actor Publisher {

 

 type Event = { topic : Text; value : Nat };

 

 type Subscriber = {

 topic : Text;

 callback : shared Event -> ();

 };

 

 var subscribers = List. empty< Subscriber>();

 

 public func subscribe(subscriber : Subscriber) {

 List. add(subscribers, subscriber);

 };

 

 public func publish(event : Event) {

 for (sub in List. values(subscribers)) {

 if (sub. topic == event. topic) {

 sub. callback(event);

 };

 };

 };

};

The subscriber registers a callback with the publisher using an inter-canister call:

import Publisher "canister:pub";

 

persistent actor Subscriber {

 

 type Event = { topic : Text; value : Nat };

 

 var count : Nat = 0;

 

 public func init(topic : Text) {

 Publisher. subscribe({

 topic;

 callback = onEvent;

 });

 };

 

 public func onEvent(event : Event) {

 count += event. value;

 };

 

 public query func getCount() : async Nat { count };

};

The key mechanism is passing a shared function reference (`callback`) across canisters. When the publisher calls `sub.callback(event)`, it makes an inter-canister call back to the subscriber.

> Note: The subscriber uses `canister:pub` to import the publisher. See Canister discovery for the note on this syntax and the recommended environment variable alternative.

The same pattern works in Rust using Candid’s `Func` type to pass callback references between canisters. The publisher stores `candid::Func` values and invokes them with `Call::unbounded_wait`; the subscriber registers its own method as a callback.

A Rust pub/sub example is not yet available in the examples repo. See the Motoko tab for the full pattern. The architecture is identical.

### 2 MB payload limit

Request and response payloads are each limited to 2 MB. For larger data transfers, chunk the payload across multiple calls.

### Non-atomic execution across await

Update methods that make inter-canister calls are not executed atomically. Code before `await` runs as one atomic message; code after `await` runs as a separate message. If the callback traps after `await`:

- State changes made before`await` are persisted
- State changes made after`await` are rolled back

This means a trap in your callback does not undo work done before the call. Design accordingly: use idempotent operations and check postconditions.

### Caller identity across await (Rust)

In Rust, `ic_cdk::api::msg_caller()` returns the caller of the current message, not the original ingress caller. After an `await`, the “caller” is the callee returning a response. Always bind the caller to a local variable before the first `await`:

#[update]

pub async fn transfer(ledger: Principal, to: Principal, amount: Nat) -> Result<(), String> {

 let caller = ic_cdk:: api:: msg_caller(); // Bind BEFORE await

 

 Call:: unbounded_wait(ledger, " transfer")

 . with_arg(&(caller, to, amount))

 . await

 . map_err(| e| format!(" Transfer failed: {:?}", e))?;

 

 ic_cdk:: println!(" Transfer initiated by {}", caller); // Safe: captured before await

 Ok(())

}

In Motoko, `public shared ({ caller })` captures the original caller at method entry, so this issue does not apply.

### Reentrancy

Inter-canister calls are not atomic, which creates reentrancy risks. Between your outgoing call and the callback, other messages (including calls from the same canister) can execute and modify state. This can lead to double-spending or other inconsistencies.

Mitigate with locking patterns: set a flag before the call, clear it in the callback. For detailed guidance, see Inter-Canister Call Security.

### canister_inspect_message does not apply

The `canister_inspect_message` hook is only called for ingress messages (calls from external users). It is not called for inter-canister calls. Do not rely on it for access control between canisters: perform authorization checks inside the method body instead.

### Cross-subnet latency

Calls between canisters on the same subnet complete within a single round. Cross-subnet calls require 2-3 consensus rounds and are noticeably slower. Keep this in mind when designing multi-canister architectures.

## Next steps

- Parallel inter-canister calls: make multiple calls concurrently and use composite queries for efficient read patterns
- Paginating query results: cursor-based pagination for mutable datasets that avoids duplicates and skipped items
- Candid: define the interface your canister exposes for inter-canister calls
- Cycles Management: acquire cycles, monitor balances, and set freezing thresholds
- Certified Variables: make query responses verifiable without update call overhead
- Inter-Canister Call Security: reentrancy guards, async safety patterns, and trust considerations
