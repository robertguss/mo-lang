module Lead.PSumu8
intent "Lead probe for step 43."
fn add(a: UInt8, b: UInt8) : UInt8
  a + b
end
fn main(platform: Platform)
  platform.stdout.write("#{add(200, 100)}\n")
end
