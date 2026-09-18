---
title: "Program 7: `mored`, a Redis subset against Redis's own tests"
created: 2026-09-18
updated: 2026-09-18
type: spec
tags: [programs, runtime, security, audit]
sources:
  [
    plans/roadmap.md,
    spec/design-v0/01-premise.md,
    deep-dives/bricks-and-the-cost-of-zero-dependencies.md,
    plans/interpreter-step-35.md,
    plans/interpreter-step-36.md,
    plans/interpreter-step-37.md,
  ]
status: sealed
---

# Program 7: `mored`, a Redis subset against Redis's own tests

The spec altitude of program 7, the pre-registered test of the runtime claim
(chapter 1, M-3; `audit/mo-audit-2026-09-17-stopping-rule-runtime.md`) and of
the capabilities claim (`audit/mo-audit-2026-09-17-stopping-rule-capabilities.md`).
Written by Fable, 18 Sep 2026, before any build; sealed by the `ready` record
that names this page at its commit. Two maintainers of the same model, one in
Mo and one in Elixir, each get this page and nothing else of the other's
work; the auditor writes the hidden suites against this page and Fable never
sees them. A change to this page after the seal is a decision-log row and a
new `ready` record, never an edit in place.

## Intent

`mored` is a network key-value server that speaks Redis's wire protocol and
passes the parts of Redis's own test suite that cover its operation set:
strings, keys and expiry, hashes, lists with blocking pops, sets, streams with
blocking reads, publish and subscribe, transactions, sixteen databases, an
append-only file that survives a crash and a restart, users with hashed
passwords and per-user command and key rules, TLS on a second port, and a
Prometheus metrics endpoint. It stresses what the claim is about: many
connections, blocking waits that must stay bounded, state that must survive a
crash byte for byte, a replay that must be exact, and a server whose failures
are diagnosable from the runtime's surface alone.

## The operation set

Every command below, with Redis 7.2's arguments and replies as its
documentation and its test suite define them. Nothing outside this list is
promised; an unknown command is Redis's `ERR unknown command` reply.

- **Connection and server:** `PING`, `ECHO`, `SELECT` (0 to 15), `AUTH`
  (both forms), `HELLO` (protocol 2 only; 3 is `NOPROTO`), `CLIENT ID`,
  `CLIENT SETNAME`, `CLIENT GETNAME`, `CLIENT LIST`, `CLIENT KILL` (by id),
  `QUIT`, `RESET`, `INFO` (the `server`, `clients`, `memory`, `persistence`,
  `stats`, `keyspace` sections, the fields the tests read), `DBSIZE`,
  `FLUSHDB`, `FLUSHALL`, `TIME`, `COMMAND COUNT`, `COMMAND DOCS` (empty is
  allowed), `CONFIG GET` and `CONFIG SET` for `appendfsync`, `maxclients`,
  `timeout`, `lazyfree-lazy-user-del`, `list-max-listpack-size` (accepted and
  ignored), `DEBUG RELOAD` (persist and reload from the file), `DEBUG SLEEP`,
  `DEBUG SET-ACTIVE-EXPIRE`, `DEBUG OBJECT` (only the `serializedlength` and
  `encoding` words, the encoding always `mo`), `SAVE` and `BGSAVE` (an AOF
  rewrite, see persistence), `BGREWRITEAOF`, `LASTSAVE`, `SHUTDOWN`.
- **Keys:** `DEL`, `UNLINK`, `EXISTS`, `TYPE`, `KEYS`, `SCAN` (with `MATCH`,
  `COUNT`, `TYPE`), `RANDOMKEY`, `RENAME`, `RENAMENX`, `EXPIRE`, `PEXPIRE`,
  `EXPIREAT`, `PEXPIREAT` (with `NX`, `XX`, `GT`, `LT`), `TTL`, `PTTL`,
  `EXPIRETIME`, `PEXPIRETIME`, `PERSIST`, `TOUCH`, `COPY`, `MOVE`, `SWAPDB`,
  `OBJECT ENCODING` (always `mo`), `OBJECT IDLETIME`, `OBJECT FREQ` (an error
  as Redis gives without LFU).
- **Strings:** `GET`, `SET` (with `NX`, `XX`, `GET`, `EX`, `PX`, `EXAT`,
  `PXAT`, `KEEPTTL`), `GETEX`, `GETDEL`, `SETNX`, `SETEX`, `PSETEX`, `MGET`,
  `MSET`, `MSETNX`, `GETSET`, `APPEND`, `STRLEN`, `GETRANGE`, `SETRANGE`,
  `INCR`, `DECR`, `INCRBY`, `DECRBY`, `INCRBYFLOAT`, `LCS` (without `IDX`).
- **Hashes:** `HSET`, `HSETNX`, `HGET`, `HMGET`, `HMSET`, `HDEL`, `HEXISTS`,
  `HLEN`, `HKEYS`, `HVALS`, `HGETALL`, `HINCRBY`, `HINCRBYFLOAT`, `HSTRLEN`,
  `HRANDFIELD`, `HSCAN`.
- **Lists:** `LPUSH`, `RPUSH`, `LPUSHX`, `RPUSHX`, `LPOP`, `RPOP` (with a
  count), `LLEN`, `LRANGE`, `LINDEX`, `LSET`, `LINSERT`, `LREM`, `LTRIM`,
  `LPOS`, `LMOVE`, `RPOPLPUSH`, `BLPOP`, `BRPOP`, `BLMOVE`, `BRPOPLPUSH`,
  `LMPOP`, `BLMPOP`.
- **Sets:** `SADD`, `SREM`, `SMEMBERS`, `SISMEMBER`, `SMISMEMBER`, `SCARD`,
  `SPOP`, `SRANDMEMBER`, `SMOVE`, `SDIFF`, `SDIFFSTORE`, `SINTER`,
  `SINTERSTORE`, `SINTERCARD`, `SUNION`, `SUNIONSTORE`, `SSCAN`.
- **Streams:** `XADD` (with `MAXLEN`, `MINID`, `NOMKSTREAM`, `*` and explicit
  ids), `XLEN`, `XRANGE`, `XREVRANGE`, `XDEL`, `XTRIM`, `XREAD` (with `COUNT`
  and `BLOCK`), `XINFO STREAM` (the fields the tests read), `XSETID`. No
  consumer groups.
- **Publish and subscribe:** `SUBSCRIBE`, `UNSUBSCRIBE`, `PSUBSCRIBE`,
  `PUNSUBSCRIBE`, `PUBLISH`, `PUBSUB CHANNELS`, `PUBSUB NUMSUB`, `PUBSUB
  NUMPAT`, `PING` in subscribed state.
- **Transactions:** `MULTI`, `EXEC`, `DISCARD`, `WATCH`, `UNWATCH`, with
  Redis's queueing, error, and abort rules (a command that fails to queue
  aborts the transaction; a runtime error inside `EXEC` does not).
- **Access control:** `ACL SETUSER` (the rules `on`, `off`, `nopass`,
  `>password`, `<password`, `#hash`, `resetpass`, `+command`, `-command`,
  `+@category`, `-@category`, `allcommands`, `nocommands`, `~pattern`,
  `allkeys`, `resetkeys`, `&pattern`, `allchannels`, `resetchannels`,
  `reset`), `ACL DELUSER`, `ACL GETUSER`, `ACL LIST`, `ACL USERS`, `ACL
  WHOAMI`, `ACL CAT`, `ACL LOG` (`RESET` and the entries the tests read),
  `ACL SAVE`, `ACL LOAD`, `ACL GENPASS`, `AUTH`. The categories `@read`,
  `@write`, `@keyspace`, `@string`, `@hash`, `@list`, `@set`, `@stream`,
  `@pubsub`, `@transaction`, `@connection`, `@admin`, `@dangerous`, `@fast`,
  `@slow`, `@all`, with each command of the set in the categories Redis 7.2
  puts it in.

**Out of the set, pre-registered:** sorted sets, HyperLogLog, bitmaps and
bit operations, geo, scripting (`EVAL`, `FUNCTION`), modules, cluster,
replication (`REPLICAOF`, `SYNC`, `WAIT`), keyspace notifications, client
tracking, `OBJECT` encodings other than `mo`, RDB files, `MONITOR`,
`SLOWLOG`, `LATENCY`, `MEMORY` (`MEMORY USAGE` answers a number), consumer
groups, RESP3, `CLIENT PAUSE`, `CLIENT NO-EVICT`, eviction and `maxmemory`.

## The protocol

RESP2 over TCP and over TLS, exactly as Redis 7.2 speaks it: inline commands
(a line of words) and multibulk commands; the five reply types; a pipelined
client gets its replies in order; a command whose bulk length or array length
is malformed gets Redis's `Protocol error` reply and the connection is
closed; a single command may not exceed 512 MB and a bulk 512 MB (the tests
use far less; the program caps a bulk at 64 MiB and a multibulk at 1,024
elements times that, and says so in `INFO`). A stream that ends without
`close_notify` on TLS, or without a FIN on TCP, mid-command is a dropped
client: the partial command is discarded, nothing of it executes, and
`rejected_connections` and `total_connections_received` count as Redis does
(the decision-log row of 18 Sep 2026 on truncation). A client that sends
nothing for `timeout` seconds (0 by default, never) is closed.

## The test suite

Redis's own test suite at tag `7.2.4`, run in `--host` mode against a
`mored` started by the test runner's script, with `--singledb` off (the tests
`SELECT 9` freely) and the test files below. **The suite is the operation
set's definition where the two disagree.**

- `unit/type/string.tcl`, `unit/type/incr.tcl`, `unit/type/hash.tcl`,
  `unit/type/list.tcl`, `unit/type/list-2.tcl`, `unit/type/list-3.tcl`,
  `unit/type/set.tcl`, `unit/type/stream.tcl` (the non-group tests),
  `unit/expire.tcl`, `unit/keyspace.tcl`, `unit/scan.tcl`, `unit/multi.tcl`,
  `unit/pubsub.tcl`, `unit/auth.tcl`, `unit/acl.tcl`, `unit/acl-v2.tcl`,
  `unit/info.tcl`, `unit/introspection.tcl`, `unit/introspection-2.tcl`,
  `unit/other.tcl`, `unit/protocol.tcl`, `unit/tls.tcl`, `unit/aofrw.tcl`,
  `integration/aof.tcl`, `integration/aof-multi-part.tcl` (only the tests
  that load and replay; the multi-part manifest format is out).
- **The skip list.** A test in those files is skipped only if it is on
  `examples/programs/mored/tests/skips.txt`, one test name per line with the
  reason (an out-of-set command, an encoding assertion, a Redis-internal
  `DEBUG` subcommand, RESP3, a `config set` the set does not carry, a timing
  assumption about Redis's own C implementation). The Mo maintainer writes
  the list **before its first commit**, from reading the test files, and
  commits it; the Elixir maintainer gets the same list. A test added to the
  list after the first commit is a decision-log row with the reason and
  counts against the maintainer in the auditor's ledger (the "tests skipped
  late" number). The number the reading reports is *tests passed of tests
  not skipped*, and *tests skipped*, separately.
- **How it runs.** `examples/programs/mored/tests/run.sh` clones Redis at
  the tag into `zig-out/redis` (dev-time tooling, never linked), builds
  nothing of Redis but its test client needs (`tclsh` 8.6 from the system),
  generates the test CA and pairs into `tests/tls/` with Ed25519 keys (Redis's
  `utils/gen-test-certs.sh` writes RSA keys, which the TLS brick's cut does
  not verify; the script is replaced, the tests' trust file is our CA), starts
  `mored` on a free port and a free TLS port with `tls-auth-clients no` (the
  brick has no client certificates; the deviation is pre-registered here and
  in the decision log), and runs `./runtest --host 127.0.0.1 --port <p>
  --single <file>` for each file, then the same with `--tls`. It prints the
  pass, fail, and skip counts per file and in total.

## Persistence

An append-only file, `<dir>/appendonly.aof`, of RESP multibulk commands, one
per write that changed the keyspace (a `SET` that changed nothing still
appends, as Redis does; expiries are written as `PEXPIREAT` with the absolute
time; a key expired by the sweeper is written as `DEL`). `appendfsync
everysec` by default, `always` and `no` accepted. On start the file is
replayed; a truncated last command is dropped and reported once to stderr and
in `INFO persistence` as `aof_last_bgrewrite_status:ok` with
`aof_truncated_tail:1`; a corrupt command in the middle refuses to start with
exit 1 and the offset on stderr. `BGREWRITEAOF`, `SAVE`, and `BGSAVE` rewrite
the file to one command per live key (strings as `SET` with `PXAT`, hashes as
one `HSET`, lists as one `RPUSH`, sets as one `SADD`, streams as `XADD` per
entry with explicit ids and a final `XSETID`), atomically (write beside,
fsync, rename), while serving. `DEBUG RELOAD` rewrites, drops the keyspace,
and replays.

## Access control

Users live in `<dir>/users.acl`, one `user` line per user in Redis's ACL file
syntax, except that a password is stored as an Argon2id PHC string from the
crypto brick's `Password.hash` (`#<hash>` in the file, where Redis stores
SHA-256; `ACL GETUSER` shows the PHC string in `passwords`). `AUTH` verifies
with `Password.verify?` and takes at least the hash's time on a wrong
password too. The `default` user exists with `nopass` and `allcommands
allkeys allchannels` unless the file says otherwise. `ACL SAVE` writes the
file atomically; `ACL LOAD` replaces every user from it or fails whole. A
denied command answers `NOPERM` with Redis's wording and lands in `ACL LOG`.
`requirepass` in the configuration is `ACL SETUSER default >pass` as in
Redis.

## TLS

`--tls-port <p> --tls-cert-file <pem> --tls-key-file <pem>` from the TLS
brick: TLS 1.3, the two suites, the chain as given, `tls-auth-clients no`.
`--port 0` with a TLS port is TLS only. A connection on the TLS port that
does not complete its handshake within 10 seconds is dropped and counted in
`rejected_connections`. `INFO server` reports `tls_port` and the
handshakes served.

## Metrics

`--metrics-port <p>`: `GET /metrics` on that port, plain HTTP, Prometheus
text format, no authentication: `mored_commands_total{cmd="get"}` per
command, `mored_connected_clients`, `mored_blocked_clients`,
`mored_keys{db="0"}`, `mored_expired_keys_total`, `mored_evicted_keys_total`
(always 0), `mored_aof_size_bytes`, `mored_aof_rewrites_total`,
`mored_uptime_seconds`, `mored_pubsub_channels`, `mored_tls_handshakes_total`,
`mored_rejected_connections_total`, and a `# HELP` and `# TYPE` line for
each. Any other path is `404`. This endpoint is where the P4 modification is
expected to land (the auditor names the modification; the likely shape is a
change to the exposition format or to how a metric is labelled, which in
Elixir would be a `hex update` of the metrics library).

## Usage

```
mored [--dir <dir>] [--port 6379] [--tls-port 0 --tls-cert-file <pem> --tls-key-file <pem>]
      [--metrics-port 0] [--appendfsync everysec|always|no] [--maxclients 10000]
      [--timeout 0] [--aclfile <path>] [--requirepass <pass>] [--daemonize no]
mored --check-aof <file>      validates a file, prints the command count or the offset of the first bad command, exit 0 or 1
mored --version
```

Exit 2 on a usage error, 1 when `<dir>` cannot be opened, a port cannot be
bound, the PEM does not parse, or the AOF is corrupt. `SHUTDOWN` fsyncs and
exits 0. `SIGTERM` is `SHUTDOWN`.

## Nevers

- A reply is never sent for a write before its AOF line is durable under
  `appendfsync always`, and never more than one second after under `everysec`.
- A key is never visible after its expiry time to any command but `TTL`'s
  family (which answer -2), restart or not.
- A blocked client (`BLPOP`, `BRPOP`, `BLMOVE`, `BLMPOP`, `XREAD BLOCK`,
  `WAIT`-free) never waits past its timeout; `0` means forever but is still
  woken by `CLIENT KILL`, `SHUTDOWN`, and a closed socket.
- A transaction's commands never interleave with another client's.
- A user never runs a command or touches a key or channel its rules deny.
- The keyspace after replay equals the keyspace before the stop, key for
  key, value for value, expiry for expiry, for every write the server
  acknowledged under `always`, and for every write older than one second
  under `everysec`.
- A connection never blocks another connection's command from completing
  (a slow client, a blocked client, a subscribed client, a client mid-`MULTI`).
- An id from `XADD *` never goes backwards, restart or not.

## Contracts the reader expects to see

`requires` on every argument shape with its `rejects`; `ensures` on each
write that a subsequent read returns what was written; `invariant`s on the
keyspace process (no key with an expiry in the past is present after a sweep;
the blocked-client table holds only clients with a live connection; the AOF
offset only grows between rewrites); the ACL rules as a pure function from
(user, command, keys, channels) to allowed or a `NOPERM` reason, with its
`never`s; the RESP parser's contracts on lengths; the recipes' own contracts.

## Recipes

At least three non-trivial recipes (the capabilities rule's P2), written as
recipes first, in `examples/recipes/`, and implemented in the program:
`Recipes.Resp` (the wire protocol: parse and print, with lengths, `needs`
nothing), `Recipes.AppendLog` (an append-only log with fsync policy, a
truncated-tail rule, an atomic rewrite, `needs Fs`), `Recipes.Acl` (users,
rules, categories, the decision function, the file syntax, `needs` nothing;
the hashing is the program's, through the crypto brick), and
`Recipes.Metrics` (counters and gauges with labels, the Prometheus text
exposition, `needs` nothing). Each with `intent`, signatures with contracts,
`never`s, and tests, so that `mo check --recipe` has something to catch when
the auditor's drift seeds go in.

## Tests the reader expects to see

Unit tests per command group in the program's own files; the recipes' tests
passing on the implementations; a property that any write then read
round-trips under any key and value of the allowed shapes; a replay test that
writes, stops, starts, and compares keyspaces; a crash test that kills the
server mid-write (`--sim --faults`) and replays; a `--sim` run under 100
seeds with injected `Fs` and `Net` faults in which every reply was either
correct or an error with the keyspace unchanged; the Redis suite's counts as
`tests/run.sh` prints them, under both runtimes; and the `verified:` lines.

## Measured

What the runtime rule and the capabilities rule read, taken on the same rig
for both builds, three trials, the median, the load average beside each
number:

- **R1 to R7, RC1 to RC4** (the runtime rule): the hidden suite's count, the
  MTTR under `--faults 0.05 --until 0.5`, the wait probe, the drift budget
  across the maintainer's edits, 100 replays byte for byte, the outside
  session's diagnosis from `platform.runtime` alone, the single binary's size
  and cold boot; maintainer time; throughput and p99 on `redis-benchmark -t
  set,get,lpush,lpop,sadd,hset,incr -c 50 -n 1000000 -P 16` and the same with
  `-P 1`, plain and over TLS (`--tls` with our CA); steady and peak RSS at
  1,000,000 keys; the dependency count.
- **P1 to P4** (the capabilities rule): the lockfile's count, the drift seeds
  caught, the abuse suite's escapes, the maintainer's time on the named
  modification.
- **The suite's counts** as `run.sh` prints them: passed of not skipped,
  skipped, and skipped late.

## The Elixir counterpart

The same page, given to a fresh session of the same model at the same effort
in a worktree of its own, Elixir 1.17 on OTP 27, `mix` and `hex` allowed
without limit (the point of the comparison), `:ssl` for TLS (OTP-native,
counted as first party), `argon2_elixir` or whatever the maintainer picks for
the hashes (counted). The same `run.sh` shape, the same skip list, the same
rig, the same fault rig at the same rate on the same actions. Neither
maintainer sees the other's tree, the hidden suites, or this page's
decision-log rows.

## Pre-registered deviations from Redis

Written here before any build so that they are not excuses after: RESP2
only; `OBJECT ENCODING` always `mo` and every encoding assertion skipped by
name; `DEBUG` limited to the four subcommands named; client certificates
off; the test CA regenerated with Ed25519 keys; no consumer groups, no
sorted sets, no scripting, no replication, no cluster, no RDB; bulk cap 64
MiB; `INFO` limited to the fields the tests read. Anything else the suite
wants and `mored` does not do is a failure, not a skip.

## Related

- [[roadmap]]
- [[01-premise]]
- [[bricks-and-the-cost-of-zero-dependencies]]
- [[interpreter-step-37]]
- [[the-audit-workflow]]
