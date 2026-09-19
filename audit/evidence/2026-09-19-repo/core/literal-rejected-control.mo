module Audit.LiteralRejectedControl
intent "Probe an out-of-range UInt32 literal as a negative control."
fn too_large() : UInt32
  4294967296
end
fn main(platform: Platform)
  platform.stdout.write("#{too_large()}\n")
end
