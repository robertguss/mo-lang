#!/bin/sh
# gen-constrained.sh: the chains of step 39 (mo-wiki/plans/interpreter-step-39.md, part A), each
# correctly signed under its own root and each one restriction of RFC 5280's away from the good
# chain, written with OpenSSL (`openssl ca`, as gen.sh writes the rest). Run it from anywhere; it
# writes beside itself and leaves gen.sh's files alone. Every run makes new keys; the files the
# corpus and the differential run read are these, and the brick's own tests make their chains in
# Zig instead (tls.zig, "the chain made here").
#
# For each key type, Ed25519 and P-256 (the suffix -p256), a root that signs keyCertSign and
# nothing about paths, and under it:
#
#   c-root.pem                  the trust file a client reads for every chain below
#   c-limit.pem, -key           an intermediate with pathLenConstraint 1, one intermediate under
#                               it, the localhost leaf: accepted (the limit met exactly)
#   c-refuse-pathlen.pem        pathLenConstraint 0 with an intermediate under it: unknown_ca
#   c-refuse-pathlen1.pem       pathLenConstraint 1 with two intermediates under it: unknown_ca
#   c-refuse-keyusage.pem       an intermediate whose key usage is digitalSignature, no
#                               keyCertSign: unknown_ca
#   c-refuse-eku.pem            the leaf's extended key usage client authentication alone:
#                               unsupported_certificate
#   c-refuse-critical.pem       the leaf with a critical extension nobody reads (1.2.3.4.5.6, the
#                               auditor's): unsupported_certificate
#   c-refuse-names.pem          an intermediate with name constraints the leaf meets (permitted
#                               DNS:localhost): unsupported_certificate, since the brick does not
#                               check names against them (OpenSSL accepts this one)
#
# each with its leaf's key beside it (c-limit-key.pem, c-refuse-pathlen-key.pem, ...). Every
# certificate is valid from 2025-01-01 for ten years; every leaf is for localhost (SAN
# DNS:localhost, IP:127.0.0.1) with key usage digitalSignature.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
T=$(mktemp -d)
trap 'rm -rf "$T"' EXIT
mkdir "$T/new"
: > "$T/index.txt"
echo 2000 > "$T/serial"

START=20250101000000Z
END=20350101000000Z

cat > "$T/ca.cnf" <<CNF
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
[len0_ext]
basicConstraints = critical, CA:TRUE, pathlen:0
keyUsage = critical, keyCertSign, cRLSign
[len1_ext]
basicConstraints = critical, CA:TRUE, pathlen:1
keyUsage = critical, keyCertSign, cRLSign
[sign_ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, digitalSignature
[names_ext]
basicConstraints = critical, CA:TRUE
keyUsage = critical, keyCertSign, cRLSign
nameConstraints = critical, permitted;DNS:localhost, permitted;IP:127.0.0.1/255.255.255.255
[leaf_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
[client_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = clientAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
[critical_ext]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = serverAuth
subjectAltName = DNS:localhost, IP:127.0.0.1
1.2.3.4.5.6 = critical, DER:05:00
CNF

key() {
  case "$1" in
    ed25519) openssl genpkey -algorithm ed25519 -out "$2" ;;
    p256) openssl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$2" ;;
  esac
}

# sign CN KEY OUT EXT ISSUER_CERT ISSUER_KEY: as gen.sh's.
sign() {
  cn=$1 k=$2 out=$3 ext=$4 icert=$5 ikey=$6
  openssl req -new -key "$k" -subj "/CN=$cn" -out "$T/req.csr"
  if [ "$icert" = self ]; then
    openssl ca -batch -config "$T/ca.cnf" -selfsign -keyfile "$k" -in "$T/req.csr" -out "$T/out.crt" \
      -extensions "$ext" -startdate "$START" -enddate "$END" -notext 2>/dev/null
  else
    openssl ca -batch -config "$T/ca.cnf" -cert "$icert" -keyfile "$ikey" -in "$T/req.csr" -out "$T/out.crt" \
      -extensions "$ext" -startdate "$START" -enddate "$END" -notext 2>/dev/null
  fi
  openssl x509 -in "$T/out.crt" -out "$out"
}

# chain NAME LEAF_EXT EXT...: intermediates with the extensions named, top down under the root,
# then a leaf with LEAF_EXT; writes c-NAME.pem (leaf first) and c-NAME-key.pem.
chain() {
  name=$1 leaf_ext=$2
  shift 2
  icert="$W/root.crt" ikey="$W/root.key" n=0 rest=""
  for ext in "$@"; do
    n=$((n + 1))
    key $type "$W/$name-$n.key"
    sign "Mo Constrained $name $n ($label)" "$W/$name-$n.key" "$W/$name-$n.crt" "$ext" "$icert" "$ikey"
    icert="$W/$name-$n.crt" ikey="$W/$name-$n.key" rest="$W/$name-$n.crt $rest"
  done
  key $type "$W/$name-leaf.key"
  sign localhost "$W/$name-leaf.key" "$W/$name-leaf.crt" "$leaf_ext" "$icert" "$ikey"
  # shellcheck disable=SC2086
  cat "$W/$name-leaf.crt" $rest > "$HERE/c-$name$sfx.pem"
  cp "$W/$name-leaf.key" "$HERE/c-$name-key$sfx.pem"
}

for type in ed25519 p256; do
  if [ $type = ed25519 ]; then sfx= label=Ed25519; else sfx=-p256 label=P-256; fi
  W="$T/$type"
  mkdir "$W"
  key $type "$W/root.key"
  sign "Mo Constrained Root ($label)" "$W/root.key" "$W/root.crt" ca_ext self self
  cp "$W/root.crt" "$HERE/c-root$sfx.pem"

  chain limit leaf_ext len1_ext ca_ext
  chain refuse-pathlen leaf_ext len0_ext ca_ext
  chain refuse-pathlen1 leaf_ext len1_ext ca_ext ca_ext
  chain refuse-keyusage leaf_ext sign_ext
  chain refuse-eku client_ext ca_ext
  chain refuse-critical critical_ext ca_ext
  chain refuse-names leaf_ext names_ext
done

echo "gen-constrained.sh: wrote the constrained chains in $HERE"
