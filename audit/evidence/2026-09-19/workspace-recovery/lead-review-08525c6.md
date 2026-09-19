# Initial cleanup recovery reading

Open after your own source reading. Immutable source 08525c614b32b71b4f6101ecc93eb6e8f6d68797,
base 90858791. Not accepted; final worker regressions and corrections remain.

Lead read the four existing-module diffs, complete host and machine recovery
implementation, README and live controls. A separate Astra/low reviewer owns
receipt/identity/validation coverage; this reading focuses on lifecycle order.

The object-lifetime kernel lock covers split start/collect calls. Receipt is
written before remote create, execution intent before reserve, dispatch intent
before start. Recovery takes global registration then workspace lock, installs
a separate terminal barrier and preserves proof before disposal. Late bootstrap
checks the barrier before creating its root. Original outcomes stay unknown;
recovery does not run candidate scripts or add a machine-stop fallback.

Corrections identified before acceptance:

1. Worker found partial bootstrap root before manifest and partial workspace root
   before initial state are not yet recoverable. Lead approved narrow pre-root
   identity evidence and reserved-not-started authority paths, without legacy
   adoption. A missing root alone is not evidence of no remote effect.
2. Worker found a receipt can omit completed remote execution identities; exact
   remote completed-ID accounting must precede cleanup side effects.
3. Lead found ordinary command success then Workspace.delete loses completed
   proof: the retired tombstone contains only the delete response. Later recover
   sees dispatched intents with neither execution root nor state proof and
   remains unresolved. Requested retained red and proof retention through the
   ordinary delete path, within the existing repeat/disposal control groups.
4. Lead requested the dispatch-intent-before-transport interruption explicitly.
   Existing registration-before-reaper test already has a manifest; it does not
   prove this earlier state. Terminal barrier and exact ownership evidence must
   prevent late effects before reporting confirmed cleanup.

All were sent to the existing worker with instructions to finish the active
regression unchanged, preserve 08525c6 and failed attempts, then correct source
before starting the final compiler run. No HTTP, policy, compiler or example
scope was added. A clean full suite cannot substitute for these lifecycle checks.

Planned independent extra after corrected integration: lose the recovery reply
after actual remote cleanup has completed, then explicitly invoke cleanup again.
Require unknown original execution, terminal identity/proof reuse, no dispatch
replay and positive absence. The initial worker unknown-transport group throws
before the remote call, so it does not cover this post-effect response loss.
