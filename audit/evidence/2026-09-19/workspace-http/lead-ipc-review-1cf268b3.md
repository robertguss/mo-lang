# Lead IPC correction review

Immutable1cf268b356a63665214ca8331bfc55828b643603, parentcacb09c3; both actual
Astra author/committer. Only workspace_http scope. Production changes are the
receive helper and its existing callers. No core/Mo/compiler or wire schema edits.

receive now computes remaining time before every header/body recv and rejects
completion after the supplied absolute deadline. All production callers pass
startup40s, the actual tool deadline, shared operator300s (including send), or
the owner's admission lease. Blocking sockets without a supplied deadline are
rejected. The frontend also checks the tool deadline before returning success.
Bounded fragmented-valid/incomplete local controls preserve the owner's recorded
completed result and confirmed cleanup separately from wire504/unknown.

Independent identical probe SHA256
60e3df17e993b961c9ea8c01ab8132178f50ab2802c26eb4e6139c9d7813aafb:
old83a72 returned200/success at2.413118s; corrected1cf268 returned504/unknown
at2.003429s, admission closed. New ipc-deadline-green-01 exit0/group1957 absent;
20-file snapshot unchanged. This is local socketpair proof, not real Workspace
acceptance. Source review finds the demonstrated deadline defect corrected.

Lead released only fresh readiness, corrected HTTP22 on each existing profile,
review-live2, and final resource/policy/shared5 proof to the worker. Machine
exclusive, no source edits during runs. Existing pre-correction full243/243 stays
labeled as such; independent integrated tests and acceptance remain outstanding.
