module Limits
expose query_bytes, terms, depth, entries, files, line_bytes, candidates, blocks, results, diagnostics, warning_kinds, excerpt, context, output_bytes, call_time

intent "Fixed finite limits keep a local serial search bounded by what it retains, not by how much history it reads."

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
  500_000
end

fn files() : UInt64
  100_000
end

# Real tool results carry multi-megabyte lines; a longer line is skipped with a warning.
fn line_bytes() : UInt64
  33_554_432
end

# Logical messages holding at least one matching block, whether or not they match yet.
fn candidates() : UInt64
  100_000
end

# Matching blocks retained across all candidates; each keeps only a bounded excerpt.
fn blocks() : UInt64
  100_000
end

fn results() : UInt64
  10_000
end

fn diagnostics() : UInt64
  10_000
end

fn warning_kinds() : UInt64
  1_000
end

fn excerpt() : UInt64
  240
end

# Graphemes shown before the first match inside an excerpt.
fn context() : UInt64
  80
end

fn output_bytes() : UInt64
  8_388_608
end

fn call_time() : Duration
  10.seconds
end

verified: types, contracts, tests (0), property (0 seeds), sim (not run)
          proven: not run
