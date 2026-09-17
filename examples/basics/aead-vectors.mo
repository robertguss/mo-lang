# run:
module Basics.AeadVectors
expose unhex, main

intent "The AEAD vectors run as Mo: AES-256-GCM against NIST's test cases 13, 14, and 16 and ChaCha20-Poly1305 against RFC 8439, each sealed text the ciphertext and then its 16-byte tag; a changed byte, a changed aad, or a text shorter than a tag opens to None."

fn unhex(text: String) : List(UInt8)
  Hash.from_hex(text) or []
end

fn sunscreen() : List(UInt8)
  "Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.".bytes
end

fn main(platform: Platform)
  out = platform.stdout
  zeros = unhex("00".repeat(32))
  nonce = unhex("00".repeat(12))
  gcm = Hash.hex(AesGcm.seal(zeros, nonce, unhex("00".repeat(16)), []))
  key = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
  sealed = ChaCha.seal(key, unhex("070000004041424344454647"), sunscreen(),
    unhex("50515253c0c1c2c3c4c5c6c7"))
  tag = Hash.hex(sealed.drop(sealed.size - 16))
  out.write_line("aes256gcm nist-14 #{gcm}")
  out.write_line("chacha20poly1305 rfc8439 tag #{tag}")
end

test "NIST GCM test cases 13 and 14: AES-256, a zero key and a zero IV"
  zeros = unhex("00".repeat(32))
  nonce = unhex("00".repeat(12))
  assert Hash.hex(AesGcm.seal(zeros, nonce, [], [])) == "530f8afbc74536b9a963b4f1c4cb738b"
  sealed = AesGcm.seal(zeros, nonce, unhex("00".repeat(16)), [])
  assert Hash.hex(sealed) == "cea7403d4d606b6e074ec5d3baf39d18d0d1c8a799996bf0265b98b5d48ab919"
end

test "NIST GCM test case 16: AES-256 with aad, sealed and opened"
  key = unhex("feffe9928665731c6d6a8f9467308308feffe9928665731c6d6a8f9467308308")
  iv = unhex("cafebabefacedbaddecaf888")
  plain = unhex("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
  aad = unhex("feedfacedeadbeeffeedfacedeadbeefabaddad2")
  sealed = AesGcm.seal(key, iv, plain, aad)
  assert Hash.hex(sealed) == "522dc1f099567d07f47f37a32a84427d643a8cdcbfe5c0c97598a2bd2555d1aa8cb08e48590dbb3da7b08b1056828838c5f61e6393ba7a0abcc9f66276fc6ece0f4e1768cddf8853bb2d551b"
  assert AesGcm.open(key, iv, sealed, aad) == Some(plain)
  assert AesGcm.open(key, iv, sealed, []) == None
  assert AesGcm.open(key, iv, sealed.drop(1), aad) == None
  assert AesGcm.open(key, iv, sealed.take(15), aad) == None
end

test "RFC 8439 2.8.2: ChaCha20-Poly1305, sealed and opened"
  key = unhex("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
  nonce = unhex("070000004041424344454647")
  aad = unhex("50515253c0c1c2c3c4c5c6c7")
  sealed = ChaCha.seal(key, nonce, sunscreen(), aad)
  assert Hash.hex(sealed) == "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691"
  assert ChaCha.open(key, nonce, sealed, aad) == Some(sunscreen())
  assert ChaCha.open(key, unhex("00".repeat(12)), sealed, aad) == None
  assert ChaCha.open(key, nonce, [], aad) == None
end

test "an empty text seals to its tag alone and opens to an empty list"
  key = unhex("01".repeat(32))
  nonce = unhex("02".repeat(12))
  assert ChaCha.seal(key, nonce, [], []).size == 16
  assert ChaCha.open(key, nonce, ChaCha.seal(key, nonce, [], []), []) == Some([])
  assert AesGcm.open(key, nonce, AesGcm.seal(key, nonce, [], []), []) == Some([])
end

verified: types, contracts, tests (4), property (0 seeds), sim (not run)
          proven: not run
