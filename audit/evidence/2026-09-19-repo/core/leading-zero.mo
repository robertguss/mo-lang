module Audit.LeadingZero
intent "Probe range checking beyond the checker digit buffer."
fn too_large() : UInt8
  00000000000000000000000000000000256
end
fn main(platform: Platform)
  platform.stdout.write("#{too_large()}\n")
end
