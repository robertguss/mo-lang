module Audit.LiteralControls
intent "Probe valid integer boundaries and ordinary runtime arithmetic."
fn largest() : UInt64
  18446744073709551615
end
fn main(platform: Platform)
  platform.stdout.write("#{largest()}\n")
end
