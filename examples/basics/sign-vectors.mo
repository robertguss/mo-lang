# run:
module Basics.SignVectors
expose unhex, main

intent "The key agreement and signature vectors run as Mo: X25519 against RFC 7748 and Ed25519 against RFC 8032, a low-order point agreeing to None and a changed byte verifying to false."

fn unhex(text: String) : List(UInt8)
  Hash.from_hex(text) or []
end

fn main(platform: Platform)
  out = platform.stdout
  alice = unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
  bob = unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
  shared = Hash.hex(X25519.shared(alice, X25519.public(bob)) or [])
  seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  signature = Ed25519.sign(seed, [])
  valid = Ed25519.verify?(Ed25519.public(seed), [], signature)
  out.write_line("x25519 rfc7748 shared #{shared}")
  out.write_line("ed25519 rfc8032-1 valid #{valid}")
end

test "RFC 7748 6.1: X25519 public keys and the shared secret, both ways"
  alice = unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
  bob = unhex("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
  assert Hash.hex(X25519.public(alice)) == "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a"
  assert Hash.hex(X25519.public(bob)) == "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f"
  shared = unhex("4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742")
  assert X25519.shared(alice, X25519.public(bob)) == Some(shared)
  assert X25519.shared(bob, X25519.public(alice)) == Some(shared)
end

test "X25519 agrees to None with a low-order point"
  alice = unhex("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
  assert X25519.shared(alice, unhex("00".repeat(32))) == None
  assert X25519.shared(alice, unhex("01#{"00".repeat(31)}")) == None
end

test "RFC 8032 7.1 test 1: Ed25519 over the empty message"
  seed = unhex("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60")
  public = Ed25519.public(seed)
  assert Hash.hex(public) == "d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a"
  signature = Ed25519.sign(seed, [])
  assert Hash.hex(signature) == "e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b"
  assert Ed25519.verify?(public, [], signature)
end

test "RFC 8032 7.1 test 2: Ed25519 over one byte, and what does not verify"
  seed = unhex("4ccd089b28ff96da9db6c346ec114e0f5b8a319f35aba624da8cf6ed4fb8a6fb")
  public = Ed25519.public(seed)
  assert Hash.hex(public) == "3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c"
  signature = Ed25519.sign(seed, [114])
  assert Hash.hex(signature) == "92a009a9f0d4cab8720e820b5f642540a2b27b5416503f8fb3762223ebdb69da085ac1e43e15996e458f3613d0f11d8c387b2eaeb4302aeeb00d291612bb0c00"
  assert Ed25519.verify?(public, [114], signature)
  assert !Ed25519.verify?(public, [115], signature)
  assert !Ed25519.verify?(public, [114], signature.drop(1).push(0))
  assert !Ed25519.verify?(unhex("ff".repeat(32)), [114], signature)
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
