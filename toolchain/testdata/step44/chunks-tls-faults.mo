module ChunksTlsFaults

use ChunksTls{Sink, tried, successful?, faulted?}

intent "Keep seeded TLS fault evidence separate from strict fault-free handshake and plaintext controls."

test "seeded TLS faults have a distinct bounded outcome oracle"
  got = tried(Tls.fixture(), Net.fixture(), Sink.start(), ["step44/1"], ["step44/1"])
  assert successful?(got) or faulted?(got)
  assert !faulted?(Ok(false)) and !faulted?(Error(BadPem))
end

verified: types, contracts, tests (1), property (0 seeds), sim (100 runs)
          proven: not run
