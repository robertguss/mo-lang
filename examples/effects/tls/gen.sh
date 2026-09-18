#!/bin/sh
# gen.sh: writes every certificate and key in this folder with OpenSSL 3.0 (step 37,
# mo-wiki/plans/interpreter-step-37.md, part C). Run it from anywhere; it writes beside itself.
# Every run makes new keys, so the brick's own tests (toolchain/src/bricks/tls.zig), which carry
# copies of some of these as text, must be updated from the new files after a run.
#
# For each key type, Ed25519 and P-256 (the suffix -p256), a root, an intermediate it signs, and a
# leaf for localhost (SAN DNS:localhost, IP:127.0.0.1) the intermediate signs, every one valid from
# 2025-01-01 for ten years:
#
#   root.pem                the trust file a client reads: the root alone
#   cert.pem, key.pem       the server's chain, leaf first (leaf, intermediate), and the leaf's key
#
# and the refusal set, each a chain a client must refuse, with the key its server signs with:
#
#   refuse-host.pem         a leaf for example.org (SAN DNS:example.org), and its intermediate: bad_certificate
#   refuse-expired.pem      a localhost leaf valid 2020-01-01 to 2021-01-01: certificate_expired
#   refuse-link.pem         the localhost leaf with its intermediate left out (key.pem): unknown_ca
#   refuse-depth.pem        a localhost leaf under five intermediates, six certificates: unknown_ca
#   refuse-rsa.pem          a localhost leaf with an RSA key: unsupported_certificate
#   refuse-notca.pem        a localhost leaf signed by the example.org leaf, which is no CA: unknown_ca
#   root-other.pem          a second root that signed nothing here: a client trusting it is unknown_ca
#   depth5.pem              a localhost leaf under four intermediates, five certificates: accepted
#
# The dates: OpenSSL 3.0's `x509` and `req` start a certificate now and take only `-days`; its `ca`
# command takes `-startdate` and `-enddate` (YYYYMMDDHHMMSSZ), so every certificate here is signed
# with `openssl ca` from a throwaway database, and the expired leaf is simply dated in the past.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/new"
: > "$T/index.txt"
echo 1000 > "$T/serial"

START=20250101000000Z
END=20350101000000Z

cat > "$T/ca.cnf" <<EOF
[ca]
default_ca = mo
[mo]
dir = $T
database = $T/index.txt
new_certs_dir = $T/new
serial = $T/serial
default_md = default
policy = anything
unique_subject = no
[anything]
commonName = supplied
[ca_ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
subjectKeyIdentifier = hash
[leaf_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
[host_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:example.org
EOF

# key TYPE OUT: a PKCS#8 private key (BEGIN PRIVATE KEY), the only form the brick reads.
key() {
  case "$1" in
    ed25519) openssl genpkey -algorithm ed25519 -out "$2" ;;
    p256) openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$2" ;;
    rsa) openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$2" 2>/dev/null ;;
  esac
}

# sign CN KEY OUT EXT ISSUER_CERT ISSUER_KEY [START END]: a certificate for KEY, signed by the
# issuer; ISSUER_CERT "self" signs it with KEY itself.
sign() {
  cn=$1 k=$2 out=$3 ext=$4 icert=$5 ikey=$6 s=${7:-$START} e=${8:-$END}
  openssl req -new -key "$k" -subj "/CN=$cn" -out "$T/req.csr"
  if [ "$icert" = self ]; then
    openssl ca -batch -config "$T/ca.cnf" -selfsign -keyfile "$k" -in "$T/req.csr" -out "$T/out.crt" \
      -extensions "$ext" -startdate "$s" -enddate "$e" -notext 2>/dev/null
  else
    openssl ca -batch -config "$T/ca.cnf" -cert "$icert" -keyfile "$ikey" -in "$T/req.csr" -out "$T/out.crt" \
      -extensions "$ext" -startdate "$s" -enddate "$e" -notext 2>/dev/null
  fi
  # `openssl ca` writes the PEM alone with -notext; normalise through x509 all the same.
  openssl x509 -in "$T/out.crt" -out "$out"
}

for type in ed25519 p256; do
  if [ $type = ed25519 ]; then sfx= name=Ed25519; else sfx=-p256 name=P-256; fi
  W="$T/$type"
  mkdir "$W"

  key $type "$W/root.key"
  sign "Mo Test Root ($name)" "$W/root.key" "$W/root.crt" ca_ext self self
  key $type "$W/int.key"
  sign "Mo Test Intermediate ($name)" "$W/int.key" "$W/int.crt" ca_ext "$W/root.crt" "$W/root.key"
  key $type "$W/leaf.key"
  sign localhost "$W/leaf.key" "$W/leaf.crt" leaf_ext "$W/int.crt" "$W/int.key"

  cp "$W/root.crt" "$HERE/root$sfx.pem"
  cat "$W/leaf.crt" "$W/int.crt" > "$HERE/cert$sfx.pem"
  cp "$W/leaf.key" "$HERE/key$sfx.pem"

  # The refusals.
  key $type "$W/host.key"
  sign example.org "$W/host.key" "$W/host.crt" host_ext "$W/int.crt" "$W/int.key"
  cat "$W/host.crt" "$W/int.crt" > "$HERE/refuse-host$sfx.pem"
  cp "$W/host.key" "$HERE/refuse-host-key$sfx.pem"

  key $type "$W/old.key"
  sign localhost "$W/old.key" "$W/old.crt" leaf_ext "$W/int.crt" "$W/int.key" 20200101000000Z 20210101000000Z
  cat "$W/old.crt" "$W/int.crt" > "$HERE/refuse-expired$sfx.pem"
  cp "$W/old.key" "$HERE/refuse-expired-key$sfx.pem"

  cp "$W/leaf.crt" "$HERE/refuse-link$sfx.pem"

  # Five intermediates under the root, d1 signed by the root and each next by the one before.
  prev_crt="$W/root.crt" prev_key="$W/root.key"
  for d in 1 2 3 4 5; do
    key $type "$W/d$d.key"
    sign "Mo Test Depth $d ($name)" "$W/d$d.key" "$W/d$d.crt" ca_ext "$prev_crt" "$prev_key"
    prev_crt="$W/d$d.crt" prev_key="$W/d$d.key"
  done
  key $type "$W/deep.key"
  sign localhost "$W/deep.key" "$W/deep.crt" leaf_ext "$W/d5.crt" "$W/d5.key"
  cat "$W/deep.crt" "$W/d5.crt" "$W/d4.crt" "$W/d3.crt" "$W/d2.crt" "$W/d1.crt" > "$HERE/refuse-depth$sfx.pem"
  cp "$W/deep.key" "$HERE/refuse-depth-key$sfx.pem"
  key $type "$W/deep4.key"
  sign localhost "$W/deep4.key" "$W/deep4.crt" leaf_ext "$W/d4.crt" "$W/d4.key"
  cat "$W/deep4.crt" "$W/d4.crt" "$W/d3.crt" "$W/d2.crt" "$W/d1.crt" > "$HERE/depth5$sfx.pem"
  cp "$W/deep4.key" "$HERE/depth5-key$sfx.pem"

  key rsa "$W/rsa.key"
  sign localhost "$W/rsa.key" "$W/rsa.crt" leaf_ext "$W/int.crt" "$W/int.key"
  cat "$W/rsa.crt" "$W/int.crt" > "$HERE/refuse-rsa$sfx.pem"
  cp "$W/rsa.key" "$HERE/refuse-rsa-key$sfx.pem"

  key $type "$W/notca.key"
  sign localhost "$W/notca.key" "$W/notca.crt" leaf_ext "$W/host.crt" "$W/host.key"
  cat "$W/notca.crt" "$W/host.crt" "$W/int.crt" > "$HERE/refuse-notca$sfx.pem"
  cp "$W/notca.key" "$HERE/refuse-notca-key$sfx.pem"

  key $type "$W/other.key"
  sign "Mo Other Root ($name)" "$W/other.key" "$W/other.crt" ca_ext self self
  cp "$W/other.crt" "$HERE/root-other$sfx.pem"
done

echo "gen.sh: wrote $(ls "$HERE"/*.pem | wc -l) PEM files in $HERE"
