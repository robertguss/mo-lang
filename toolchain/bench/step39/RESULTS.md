# Step 39: results

The brief is `mo-wiki/plans/interpreter-step-39.md`. Raw outputs are under
`evidence/`; every process ran under `bench/step36/guard.py`. The machine is
Robert's Mac (14 cores, in use by its owner), so every table carries the date,
`uptime`, and the top of `ps` from its own run.

## A: the chain

**The auditor's `chain-checks.py`, both copies, unedited**
(`evidence/chain-checks-*-part-a.json`, brick built as the scripts ask,
`zig build-lib toolchain/src/bricks/tls.zig -dynamic -lc -O ReleaseSafe -femit-bin=/tmp/libmo-audit-tls.so`,
Homebrew OpenSSL 3.6.4 first on PATH): the control ready/ready; `pathlen` 48,
`ca-keyusage` 48, `eku-client-only` 43, `unknown-critical` 43, each not ready on
either side; `alpn-65` still 120 (part B).

**Both runtimes over a real socket**: `examples/effects/tls-client.mo`'s run 2
(`# run: chains`) serves each chain `gen-constrained.sh` wrote from its own
listener to a client trusting its root: `c-limit` echoes `hello`, the six
refusals print `Untrusted`, each key type; `mo run` and the binary print the
same (`tls-client-2.expected`).

**x509-limbo** (`limbo.py`, limbo at `118721335e67`, `evidence/limbo.txt`):
9,793 cases, 9,723 in the cut (70 outside: 43 a key or signature outside Ed25519
and P-256, 10 not a server's chain, 8 a CRL, 6 a max chain depth, 2 an asked-for
key usage or signature algorithm, 1 no DNS name or address). 8,893 agree.

- **Accepted but limbo says reject: 27, not 0.** None is an RFC 5280 path rule.
  6 are rules on what a conforming CA must include (an AKI on every certificate
  not self-signed, an SKI on every CA, an EKU on the leaf), and the auditor's
  valid control in `chain-checks.py` has none of them: enforcing them refuses
  the control the brief requires ready, so the two Done-when items conflict and
  the lead decides. 9 are CA/B Forum BR 7.1.4.3 (the common name must be one of
  the SAN's values), not enforced because the brick no longer reads the common
  name and a private CA's descriptive common name would be refused. 3 are
  wildcards over a public suffix, which need the public suffix list. 9 are other
  CA/B Forum profile rules (web PKI, not RFC 5280): an AKI on a root with issuer
  or serial fields or not matching its SKI, the leaf's EKU critical or holding
  anyExtendedKeyUsage, an EKU on a root, a critical SAN beside a subject, a leaf
  with cA true.
- **Rejected but limbo says accept: 803**: 795 name constraints (refused as
  unsupported by design), 6 bettertls path-building cases (the pool holds
  several paths and the brick checks the one a server sends; limbo.py sends the
  shortest whose names and signatures link), 2 a CA certificate as the leaf with
  no digitalSignature in its key usage (RFC 8446 4.4.2.2, decision 4).

Limbo found three things in the brick, all fixed in part A: **Zig's `parseTime`
reads a UTCTime year of 50 or more as 20YY** (RFC 5280: 19YY), so every limbo
chain, dated from 1970, was refused as not yet valid, and that hid 38 wrong
accepts behind a wrong reason; the brick now reads each certificate's validity
itself. **The common-name fallback** accepted a leaf with no SAN whose CN was
the host (bettertls `tc736`, and `tc7297`, a CN of `127.0.0.1` for that
address); the brick no longer reads the CN. And the RFC 5280 rules on a
conforming CA's certificates that the certificate alone shows (serial number,
keyCertSign only on a CA, the root a CA, every CA's basicConstraints critical
and its subject not empty, an empty subject's SAN critical, the DNS name syntax,
the AKI's keyIdentifier and neither AKI nor AIA critical, AIA's shape), and
policyConstraints refused as unsupported.

**The chain check's cost** (`cost.py`, `evidence/cost.txt`): 2026-09-18 19:57:51
UTC, `15:57 up 8:22, 1 user, load averages: 3.28 3.86 4.27`; top of `ps`:
WindowServer 35.5%, moshi-hook 6.3%, Telegram 2.8%, WezTerm 1.9%, claude 1.7%.
Best of five; `checkChain` on gen.sh's chain of three 20,000 times, and 2,000
whole handshakes in memory through the ABI, one thread.

| brick            | key     | µs a chain check | handshakes a second |
| ---------------- | ------- | ---------------: | ------------------: |
| before (d6534b3) | Ed25519 |            197.0 |               1,976 |
| after            | Ed25519 |            199.2 |               1,964 |
| before (d6534b3) | P-256   |            827.9 |                 694 |
| after            | P-256   |            829.6 |                 694 |

The extensions cost about 2 µs a chain, 1% of an Ed25519 check; the handshake
rate does not move beyond the run's noise.
