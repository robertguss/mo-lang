module Lead.L
intent "Lead probe: a literal inside a typed list."
fn xs() : List(UInt8)
  [255, 256]
end
fn main(platform: Platform)
  platform.stdout.write("#{xs()}\n")
end
