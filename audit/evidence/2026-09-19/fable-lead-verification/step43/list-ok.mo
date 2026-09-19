module Lead.L
intent "Lead probe: a literal inside a typed list."
fn xs() : List(UInt8)
  [0, 255, 0_0_7]
end
fn main(platform: Platform)
  platform.stdout.write("#{xs()}\n")
end
