# Fixed registry (22 groups)

Frozen before final evidence. `local.py --groups` accepts a nonempty comma-separated
unique subset of these names, rejecting invalid selection before any test setup,
output creation, listener, owner or machine activity. The guarded wrapper creates
its own evidence directory to retain the rejected invocation and real exit.

| Group | Local control | Required real-machine extension |
|---|---|---|
| six-tools | six calls via HTTP and owner subprocess | all six actual Workspace tools |
| output-encoding | Unicode, binary, bad base64, actual exit metadata | Unicode and binary actual command |
| schema | duplicates, nonfinite, surrogates, types, extras | no dispatch on rejection |
| framing | method/path/version, framing/header rejection | same HTTP parser |
| byte-bounds | header/body/response caps | actual controller result_too_large |
| identities-capability | token/binding/private modes | exact Workspace binding |
| duplicate-calls | repeated/conflicting IDs execute once | core call count |
| concurrent-admission | second request refused, no queue | running actual command |
| file-refusals | completed refusal survives | containment/edit refusals |
| deadlines | file wait expires, late completed result retained | candidate/lease deadlines |
| disconnect | close during operation; owner cleans | actual candidate |
| frontend-death | SIGKILL actual frontend process, surviving owner | actual running candidate |
| owner-death | proved child death, explicit recovery API boundary | actual cleanup-only recovery |
| lost-response | effect/outcome retained, delivery unknown | actual lost result after effect |
| owner-stall | live owner retained after timeout, explicit owned stop | bounded stall/unresolved |
| startup-failure | no readiness, cleanup attempted | actual rejected creation |
| shutdown | owner exits with proof | actual resource absence |
| protected-verifier | fixed checks via private API | frozen snapshot/protected canaries |
| application-binding | candidate cannot choose selection | actual application image/toolchain |
| cleanup-outcome | original timeout separate from cleanup | positive proof/unknown transport |
| invalid-selection | refusal before directory creation | no remote effects |
| journal-order-bound | intent ordering, IDs, count cap | source hashes/order/core counts |

Inherited local59 and machine workspace22/executor17/lifecycle1/application23 are
separate regression counts, not added to these 22 groups. Full compiler commands
remain separately gated. All attempts are sequential, numerically guarded, with
real exits and owned group absence retained. No tests run outside the owned pane.
