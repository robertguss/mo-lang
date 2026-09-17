module Bench

intent "Step 35's numbers: one crypto row run a given number of times on inputs built before the clock starts, printing the milliseconds the runs took, under mo run and as a binary alike."

fn times(count: UInt64) : List(UInt8)
  "x".repeat(count).bytes
end

fn run(op: String, count: UInt64, data: List(UInt8), key: List(UInt8), nonce: List(UInt8)) : UInt64
  case op
    "sha256": times(count).reduce(0, fn(n, _) n + Hash.sha256(data).size end)
    "hmac": times(count).reduce(0, fn(n, _) n + Hash.hmac_sha256(key, data).size end)
    "gcm": times(count).reduce(0, fn(n, _) n + AesGcm.seal(key, nonce, data, []).size end)
    "sign": times(count).reduce(0, fn(n, _) n + Ed25519.sign(key, data).size end)
    "verify":
      public = Ed25519.public(key)
      signature = Ed25519.sign(key, data)
      times(count).reduce(0,
        fn(n, _) n + (if Ed25519.verify?(public, data, signature): 1 else: 0) end)
    "password":
      times(count).reduce(0, fn(n, _)
        n + Password.hash("correct horse", nonce.take(12).concat(nonce.take(4))).byte_size
      end)
    _: 0
  end
end

fn main(platform: Platform)
  op = platform.args.first or ""
  count = (platform.args.get(1) or "1").to_u64 or 1
  size = (platform.args.get(2) or "0").to_u64 or 0
  data = "a".repeat(size).bytes
  key = "k".repeat(32).bytes
  nonce = "n".repeat(12).bytes
  clock = platform.clock
  start = clock.now
  got = run(op, count, data, key, nonce)
  took = clock.now - start
  platform.stdout.write_line("#{op} #{count} #{size} #{took.ms} #{got}")
end
