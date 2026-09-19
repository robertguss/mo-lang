module Audit.NegDuration
intent "Probe negating the minimum representable Duration."
fn main(platform: Platform)
  n = -9223372036854775807 - 1
  d = n.ms
  platform.stdout.write("#{(-d).ms}\n")
end
