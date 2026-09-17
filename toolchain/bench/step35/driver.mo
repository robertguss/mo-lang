module Driver

intent "Step 35's differential and fuzz driver: each line of the file it is given names a crypto row and its arguments in hex, and it prints the row's answer, one line each, so diff.py and fuzz.py hold both runtimes against Python's cryptography."

fn unhex(text: String) : List(UInt8)
  Hash.from_hex(text) or []
end

fn field(parts: List(String), i: UInt64) : List(UInt8)
  unhex(parts.get(i) or "")
end

fn text(parts: List(String), i: UInt64) : String
  String.from_bytes(field(parts, i)) or ""
end

fn opened(got: Option(List(UInt8))) : String
  case got
    Some(bytes): Hash.hex(bytes)
    None: "none"
  end
end

fn size(parts: List(String), i: UInt64) : UInt64
  (parts.get(i) or "0").to_u64 or 0
end

fn answer(op: String, parts: List(String)) : String
  case op
    "sha256": Hash.hex(Hash.sha256(field(parts, 1)))
    "sha512": Hash.hex(Hash.sha512(field(parts, 1)))
    "hmac": Hash.hex(Hash.hmac_sha256(field(parts, 1), field(parts, 2)))
    "hkdf":
      Hash.hex(Hash.hkdf_sha256(field(parts, 1), field(parts, 2), field(parts, 3), size(parts, 4)))
    "hex": Hash.hex(field(parts, 1))
    "from_hex": opened(Hash.from_hex(text(parts, 1)))
    "equal": "#{Hash.equal?(field(parts, 1), field(parts, 2))}"
    "gcm_seal":
      Hash.hex(AesGcm.seal(field(parts, 1), field(parts, 2), field(parts, 3), field(parts, 4)))
    "gcm_open":
      opened(AesGcm.open(field(parts, 1), field(parts, 2), field(parts, 3), field(parts, 4)))
    "chacha_seal":
      Hash.hex(ChaCha.seal(field(parts, 1), field(parts, 2), field(parts, 3), field(parts, 4)))
    "chacha_open":
      opened(ChaCha.open(field(parts, 1), field(parts, 2), field(parts, 3), field(parts, 4)))
    "x25519_public": Hash.hex(X25519.public(field(parts, 1)))
    "x25519_shared": opened(X25519.shared(field(parts, 1), field(parts, 2)))
    "ed25519_public": Hash.hex(Ed25519.public(field(parts, 1)))
    "ed25519_sign": Hash.hex(Ed25519.sign(field(parts, 1), field(parts, 2)))
    "ed25519_verify": "#{Ed25519.verify?(field(parts, 1), field(parts, 2), field(parts, 3))}"
    "password_hash": Password.hash(text(parts, 1), field(parts, 2))
    "password_verify": "#{Password.verify?(text(parts, 1), text(parts, 2))}"
    _: "unknown #{op}"
  end
end

fn main(platform: Platform)
  path = platform.args.first or ""
  case platform.fs.read_lines(path, within: 60.minute)
    Ok(lines):
      for line in lines
        parts = line.split(" ")
        platform.stdout.write_line(answer(parts.first or "", parts))
      end
    Error(_):
      platform.stderr.write_line("driver: cannot read #{path}")
      platform.exit(1)
  end
end
