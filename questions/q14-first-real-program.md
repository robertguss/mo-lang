---
title: "Q14: The first real program"
created: 2026-09-12
updated: 2026-09-12
type: question
tags: [roadmap]
sources: [raw/notion/open-questions-2026-09-12.md]
number: 14
status: pending
answer: pending
asked: 2026-09-12
---

# Q14: The first real program

**Options** (from session 1): agent harness / backend service with a DB / infrastructure component (queue, KV store, proxy) / the Mo toolchain itself.
**Recommendation:** **a durable job queue with a small HTTP API.** Enqueue jobs, workers pull them, retries with backoff, dead-letter, exactly-once delivery as a `never`.
**Why:** It exercises every distinctive feature at once: processes with real state, supervision, deadlines, capabilities (DB, network, clock), `never` clauses that matter (never lose a job, never run one twice), simulation with fault injection, and events. It's small enough to finish and real enough that people would use it. It's also the backbone of an agent harness, so it leads naturally to option one without betting on it.
✍️ **Robert (in / no / counter):**

## Related
- [[roadmap]]
- [[d01-agents-write-the-code]]
