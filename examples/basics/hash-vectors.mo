# run:
module Basics.HashVectors
expose unhex, sha256_hex, main

intent "The standards' vectors for SHA-2, HMAC, HKDF, and hex, run as Mo: the crypto brick's rows give the bytes FIPS 180-4, RFC 4231, and RFC 5869 print, under mo run and in a binary alike."

fn unhex(text: String) : List(UInt8)
  Hash.from_hex(text) or []
end

fn sha256_hex(text: String) : String
  Hash.hex(Hash.sha256(text.bytes))
end

fn main(platform: Platform)
  out = platform.stdout
  empty = sha256_hex("")
  abc = sha256_hex("abc")
  sha512 = Hash.hex(Hash.sha512("abc".bytes))
  hmac = Hash.hex(Hash.hmac_sha256(unhex("0b".repeat(20)), "Hi There".bytes))
  hkdf = Hash.hex(Hash.hkdf_sha256(unhex("0b".repeat(22)), unhex("000102030405060708090a0b0c"),
    unhex("f0f1f2f3f4f5f6f7f8f9"), 42))
  out.write_line("sha256('') #{empty}")
  out.write_line("sha256(abc) #{abc}")
  out.write_line("sha512(abc) #{sha512}")
  out.write_line("hmac_sha256 rfc4231-1 #{hmac}")
  out.write_line("hkdf_sha256 rfc5869-1 #{hkdf}")
end

test "FIPS 180-4: SHA-256 of nothing, of abc, and of two blocks"
  assert sha256_hex("") == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
  assert sha256_hex("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
  assert sha256_hex("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1"
  assert Hash.sha256("abc".bytes).size == 32
end

test "FIPS 180-4: SHA-512 of abc and of two blocks"
  assert Hash.hex(Hash.sha512("abc".bytes)) == "ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f"
  two = "abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"
  assert Hash.hex(Hash.sha512(two.bytes)) == "8e959b75dae313da8cf4f72814fc143f8f7779c6eb9f7fa17299aeadb6889018501d289e4900f7e4331b99dec4b5433ac7d329eeb6dd26545e96e55b874be909"
end

test "RFC 4231: HMAC-SHA256, cases 1, 2, and 6"
  one = Hash.hmac_sha256(unhex("0b".repeat(20)), "Hi There".bytes)
  assert Hash.hex(one) == "b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7"
  two = Hash.hmac_sha256("Jefe".bytes, "what do ya want for nothing?".bytes)
  assert Hash.hex(two) == "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
  six = Hash.hmac_sha256(unhex("aa".repeat(131)),
    "Test Using Larger Than Block-Size Key - Hash Key First".bytes)
  assert Hash.hex(six) == "60e431591ee0b67f0d8a26aacbf5b77f8e0bc6213728c5140546040f0ee37f54"
end

test "RFC 5869: HKDF-SHA256, cases 1 and 3"
  ikm = unhex("0b".repeat(22))
  one = Hash.hkdf_sha256(ikm, unhex("000102030405060708090a0b0c"), unhex("f0f1f2f3f4f5f6f7f8f9"),
    42)
  assert Hash.hex(one) == "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865"
  three = Hash.hkdf_sha256(ikm, [], [], 42)
  assert Hash.hex(three) == "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8"
  assert Hash.hkdf_sha256(ikm, [], [], 0) == []
end

test "hex is lowercase, and from_hex reads either case and refuses the rest"
  assert Hash.hex([0, 171, 255]) == "00abff"
  assert Hash.hex([]) == ""
  assert Hash.from_hex("00ABff") == Some([0, 171, 255])
  assert Hash.from_hex("") == Some([])
  assert Hash.from_hex("abc") == None
  assert Hash.from_hex("zz") == None
end

test "equal? compares bytes, and lists of other sizes are unequal"
  assert Hash.equal?("abc".bytes, "abc".bytes)
  assert !Hash.equal?("abc".bytes, "abd".bytes)
  assert !Hash.equal?("abc".bytes, "ab".bytes)
  assert Hash.equal?([], [])
end

verified: types, contracts, tests (6), property (0 seeds), sim (not run)
          proven: not run
