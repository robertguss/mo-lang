module Audit.Oversized
intent "Probe the boundary of a UInt64 literal."
fn too_large() : UInt64
  18446744073709551616
end
fn main(platform: Platform)
  platform.stdout.write("#{too_large()}\n")
end
