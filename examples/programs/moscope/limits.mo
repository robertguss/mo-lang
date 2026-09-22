module Limits
expose query_bytes, terms, depth, entries, files, file_bytes, total_bytes, line_bytes, file_records, records, messages, blocks, results, diagnostics, excerpt, output_bytes, call_time, process_time

intent "Fixed finite limits keep a local serial search useful without presenting admission limits as hostile-input memory guarantees."

fn query_bytes() : UInt64
  4_096
end

fn terms() : UInt64
  64
end

fn depth() : UInt64
  24
end

fn entries() : UInt64
  50_000
end

fn files() : UInt64
  5_000
end

fn file_bytes() : UInt64
  67_108_864
end

fn total_bytes() : UInt64
  1_073_741_824
end

fn line_bytes() : UInt64
  1_048_576
end

fn file_records() : UInt64
  200_000
end

fn records() : UInt64
  1_000_000
end

fn messages() : UInt64
  100_000
end

fn blocks() : UInt64
  500_000
end

fn results() : UInt64
  10_000
end

fn diagnostics() : UInt64
  10_000
end

fn excerpt() : UInt64
  240
end

fn output_bytes() : UInt64
  8_388_608
end

fn call_time() : Duration
  10.seconds
end

fn process_time() : Duration
  60.seconds
end

test "the documented limits are the production constants"
  assert query_bytes() == 4_096 and terms() == 64 and depth() == 24
  assert entries() == 50_000 and files() == 5_000
  assert file_bytes() == 67_108_864 and total_bytes() == 1_073_741_824
  assert line_bytes() == 1_048_576 and file_records() == 200_000 and records() == 1_000_000
  assert messages() == 100_000 and blocks() == 500_000 and results() == 10_000
  assert diagnostics() == 10_000 and excerpt() == 240 and output_bytes() == 8_388_608
  assert call_time() == 10.seconds and process_time() == 60.seconds
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
