# Owner/IPC outline for release review

1. Operator validates selection/source/verifier before output creation, creates
   private state, generates external workspace identity and capability, and starts
   a single owner via socketpair. Only child endpoint is inherited; both processes
   close their unused endpoint. The child stays in the owned guarded process group
   but survives death of its immediate frontend parent.
2. Owner persists known ownership receipt path and generated core run identity;
   constructs Workspace locally; persists actual core workspace identity and
   create call identity; then calls create. Only success publishes readiness.
3. Frontend bounds sockets to four and uses one nonblocking admission mutex. No
   queued work. Owner serially checks duplicate/count/journal/lease limits, reserves
   worst-case response space, persists hash/mapped call/intent, then dispatches.
4. Owner persists private raw result and bounded projected outcome after the effect
   and before notification. Result send is bounded to 2s. No ACK is required.
5. Frontend waits at most 2s for files or 300s for commands, capped by admission
   lease. Observed EOF, expiry or unknown outcome permanently closes admission and
   IPC; a late owner result cannot reopen it. HTTP delivery uncertainty lives in
   a separate record and cannot overwrite the original execution outcome.
6. Owner finishes the synchronous call before acting on EOF. Failed notification,
   EOF or lease expiry enters normal collect/delete cleanup. Cleanup remains
   unresolved until the accepted API supplies positive deletion proof. A stalled
   owner cannot clean concurrently. Remote reapers remain independently active.
7. Freeze/verify are operator-only serialized controls with admission closed first.
   Verifier source/checks were fixed before provisioning. Close never kills on its
   wait deadline. Explicit stop targets only retained child Popen, proves its exit,
   and explicit recovery invokes accepted recover(receipt, seconds=60), cleanup
   only. Neither exit nor recovery confirmation reconstructs execution success.

The 900s lease is admission expiry. Candidate registration may establish a later
runtime deadline. Configured waits, local launch/I/O and inherited locks prevent
an unconditional finite execution/cleanup wall guarantee. Normal cleanup uses
configured collection waits and delete with at most a 55s request allowance plus its configured 5s transport margin; if collection
is blocked, the frontend reports unresolved. Recovery is a separate 60s attempt.

Local controls use a separate test-only subprocess entry point and WorkspaceDouble.
Production owner imports Workspace directly and exposes no HTTP injection or
fallback. Local green is not machine isolation, real cleanup or Mo E2E evidence.
