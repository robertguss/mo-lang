# Step 39, work in progress (the first session stopped for a pause, 18 Sep 2026, 12:35 PM ET)

The brief is `mo-wiki/plans/interpreter-step-39.md`. This session did part A's
core and stopped at the lead's word (the Mac sleeps at 12:45). A fresh session
continues from here.

## Done in part A

- **The chain check** (`toolchain/src/bricks/tls.zig`, "the chain a client
  checks"). The brick now reads every certificate's extensions itself
  (`readExtensions`: basicConstraints with its pathLenConstraint, keyUsage's
  first byte, extendedKeyUsage, nameConstraints, and a flag for any other
  critical extension; an extension twice, or one it reads that does not parse,
  is `Bad`), and `checkChain` calls `extensionsAllow` on every certificate from
  the leaf up, **the root included** (OpenSSL checks the root too; see below),
  after the path is found and the issuers are CAs, before the host and the
  signatures. `isCa` now uses the same reader.
- The rules and their alerts (each OpenSSL 3.6.4's own alert for the same chain
  unless said):
  - pathLenConstraint exceeded (non-self-issued CAs below, RFC 5280 6.1.4 (l)):
    `unknown_ca`
  - an issuer (intermediate or root) with keyUsage and no keyCertSign, an empty
    keyUsage too: `unknown_ca`
  - extendedKeyUsage present without serverAuth, on any certificate in the path;
    `anyExtendedKeyUsage` alone does not count (OpenSSL's `sslserver` purpose
    refuses it, leaf and CA alike): `unsupported_certificate`
  - the leaf's keyUsage without digitalSignature (RFC 8446 4.4.2.2):
    `unsupported_certificate`. **Stricter than OpenSSL**, which accepts this
    chain.
  - a critical extension the brick does not read: `unsupported_certificate`.
    **OpenSSL sends `certificate_unknown` (46)** for this; the brief asks for 42
    or 43, and 43 says what it is (a kind of certificate the brick does not
    support).
  - nameConstraints on any certificate, critical or not:
    `unsupported_certificate`. **Stricter than OpenSSL**, which checks them (and
    accepts a leaf inside them).
  - an extension twice, a pathLenConstraint on a certificate that is no CA, a
    malformed extension the brick reads: `bad_certificate`.
  - dates: unchanged, both ends inclusive (RFC 5280 4.1.2.5), now tested at the
    boundary second. **OpenSSL counts notAfter itself as expired**
    (`X509_cmp_time` is -1 on equality); the brick follows the RFC. Only a
    boundary-second chain can tell them apart.
- **Brick tests** ("the chain made here", two tests): a DER writer in the test
  code makes every chain in Zig, Ed25519 and P-256, signed with deterministic
  keys, and runs a real brick-to-brick handshake on each (server and client
  built directly from DER). 11 accepted shapes (bare, the limits met exactly, a
  self-issued intermediate under pathLen 0, EKU with serverAuth among others, an
  unknown non-critical extension on each certificate, the boundary seconds) and
  22 refused ones (each rule above, on the leaf, the intermediate and the root
  where it applies, the lead's pathLen 1 with two below and the empty key usage
  among them). Both green; with the `extensionsAllow` call disabled the refusal
  test goes red (checked by hand, 12:10 PM).
- **Both copies of the auditor's `chain-checks.py`, unedited**, against a fresh
  ReleaseSafe `/tmp/libmo-audit-tls.so`: control ready/ready; pathlen 48,
  ca-keyusage 48, eku-client-only 43, unknown-critical 43, all four not ready on
  either side. `alpn-65` is still 120 (part B). Before the change (same script,
  main at `d6534b3`): all four were ready/ready, as the auditor filed.
- **Fixtures**: `examples/effects/tls/gen-constrained.sh` (OpenSSL `ca`, beside
  gen.sh, which it leaves alone) wrote `c-root`, `c-limit` (accepted),
  `c-refuse-pathlen`, `c-refuse-pathlen1`, `c-refuse-keyusage`, `c-refuse-eku`,
  `c-refuse-critical`, `c-refuse-names`, each with its key, both key types.
  `openssl verify -purpose sslserver` at 2026-01-01 agrees on every one: OK for
  `c-limit` and `c-refuse-names`, refused for the other five.
- **x509-limbo**: cloned at `118721335e67` (14 Sep 2026) into
  `toolchain/bench/step39/work/` (ignored). `bench/step39/limbo.py` picks the
  cases in the cut (SERVER, every key and signature Ed25519 or P-256, no CRL, no
  max depth, no asked-for key usage, EKU none or serverAuth, a DNS or IP peer
  name) and hands each chain, leaf first as a server sends it, to the brick's
  own `checkChain` through a new tool, `mo-tls-limbo` (`bench/step39/limbo.zig`,
  built by `zig build tls-tools`; `checkChain` is now `pub`). Of 9,793 cases,
  about 9,738 are SERVER and in the algorithms; most are name-constraint cases.
  **Not yet run to the end**: see the log line in "What is left".
- The alerts table above came from `alerts.py` (scratch, not committed):
  Python's cryptography builds each chain, `openssl s_server` presents it,
  `openssl s_client -verify_return_error` refuses it, and the alert is read off
  `-msg`.

## What std.crypto.Certificate's parser gives and skips (Zig 0.16.0)

`Certificate.parse` keeps the subject, issuer, validity, the public key and its
algorithm, the signature and its algorithm, the common name, and **the subject
alternative names alone** among the extensions. Every other extension is
skipped: an unrecognized OID with `continue`, and a recognized one
(basicConstraints, keyUsage, extKeyUsage, ...) also with `continue` after its
criticality is read and thrown away. So nothing about paths, usages, or
criticality survives the parse; the brick has to walk the extensions itself (it
already walked them in `certShape` for their shape). A SAN given twice: the
parser keeps the last one; the brick now refuses the certificate.
`Parsed.verify` is not used (RSA's code, compile time; see `signedBy`).

## What the auditor's chain-checks.py does

It builds `tls.zig` as a ReleaseSafe shared library at the fixed path
`/tmp/libmo-audit-tls.so` (so a run must rebuild that file from the tree under
test first:
`zig build-lib toolchain/src/bricks/tls.zig -dynamic -lc -O ReleaseSafe -femit-bin=/tmp/libmo-audit-tls.so`),
makes Ed25519 chains with Python's `cryptography` (every certificate with
basicConstraints critical, the leaf with cA false; the key usage case is
`digital_signature` only, critical; the unknown extension is `1.2.3.4.5.6`
critical with value `05 00`), drives `mo_tls_connect` at `1767225600`
(2026-01-01) against `mo_tls_conn_new` in memory for 20 rounds, and prints
ready, ready, and the client's alert beside `openssl verify` (it runs `openssl`
from PATH: here Homebrew OpenSSL 3.6.4, since `/usr/bin/openssl` on this Mac is
LibreSSL 3.3.6). The `alpn-65` case offers `p0`..`p64` against a server
accepting `p64` alone. The two copies are byte-identical.

## What is left in part A

1. **The suite, and the commit**: `zig build test --summary all` was started at 12:19 PM under
   guard and had not finished by 12:32 PM (the machine loaded, the limbo run beside it), so it was
   killed and **part A is not on main**: everything above is in `wip-part-a.patch` beside this
   file (`git apply toolchain/bench/step39/wip-part-a.patch` from the repository root; it holds
   the diffs of `tls.zig` and `build.zig` and the new files `limbo.py`, `limbo.zig`, `gen-constrained.sh`, and the 28 `c-*.pem` fixtures). The tree was put back to
   main. Only `zig test src/bricks/tls.zig -lc --test-filter "chain made here"` (2 of 2) and the
   auditor's scripts were run on it; the whole brick test and the suite are owed.
2. **The limbo run to the end** (`uv run`/`python3 limbo.py` from
   `bench/step39/`; slow in Python, several minutes: it parses every certificate
   three times; cache the parsed certificates). Report:
   accepted-but-should-reject must be 0; rejected-but-should-accept listed with
   reasons (most will be name constraints, refused by design; also expect cases
   where limbo's intermediate pool holds several paths).
3. **Both runtimes over a real socket**: a `# run:` line of
   `examples/effects/tls-client.mo` whose main serves each `c-*` chain from
   `tls/` on a real listener and connects with a `TlsClient` trusting
   `c-root.pem`, printing each outcome (`c-limit`: a line back; the six
   refusals: `Untrusted`), its `tls-client-2.expected` pinning the output (the
   corpus runs it under `mo run` and as a binary). Not written yet.
4. **The differential generator**: `bench/step37/diff.py`'s `CHAINS` gains the
   `c-*` chains. OpenSSL's alert and the brick's differ for two of them, so the
   table needs one alert per verifier: when `s_client` verifies (the brick's
   server) OpenSSL's own (`c-refuse-critical` 46, `c-refuse-names` accepted);
   when the brick verifies, the brick's (43 for both). The oracle is not
   changed: OpenSSL's column is what OpenSSL does.
5. The spec paragraph (`## Tls`, "What the client checks") and `PRELUDE.md` if a
   row's wording changes; the numbers (chain check cost before and after; the
   before tree is the worktree `../mo-lang-step39-before` at `d6534b3`, made by
   this session and not yet built).

Then parts B to F as the brief has them. Two things found for them:

- **Part B**: `alpnNames` keeps the first 64 names and the server searches that;
  the fix is to search the validated list in place (no copy, no cap).
- **Part E** has a conflict the brief does not settle: the corpus runs every
  process test under 100 seeds with faults and requires `fault_free_only == 0`
  (`corpus.zig`), so a test with no fault allowance fails the corpus as soon as
  a seed injects a fault into its handshake, and a test cannot tell whether its
  run injected one. The session's leaning: a test-only row that says how many
  faults the simulator has injected in this run (0 in the fixed-order run), so
  the allowance applies only when a fault was injected; it needs the lead's
  word, since it is a new row. The auditor's mutant script needs `fn tried(`
  with `  server = try tls.server` inside it and `\nend` after, so `tried` must
  keep that shape.

## Decisions so far (for the final list)

1. The alerts: OpenSSL's for pathLen, keyCertSign, and EKU; 43 for an unknown
   critical extension where OpenSSL sends 46 (the brief's two choices); 43 for
   name constraints.
2. The root's extensions are checked like any issuer's (OpenSSL does; RFC 5280
   leaves trust anchor constraints optional).
3. `anyExtendedKeyUsage` alone does not satisfy server authentication, on the
   leaf or a CA (OpenSSL's behaviour; limbo's webpki cases say the same for the
   leaf).
4. The leaf's keyUsage must hold digitalSignature (RFC 8446), stricter than
   OpenSSL.
5. A duplicate extension is `bad_certificate`.
6. The brick's own tests make chains in Zig instead of carrying more PEM copies;
   the corpus and the differential read the `c-*` files `gen-constrained.sh`
   writes, a second script so gen.sh's files and the brick's copies of them stay
   as they are.
7. The x509-limbo run calls `checkChain` directly (limbo has no private key for
   most leaves); the chain is ordered as a server would send it, by names, since
   the brick does no path building.
