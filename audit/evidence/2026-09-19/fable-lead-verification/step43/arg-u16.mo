module Lead.PArgu16
intent "Lead probe for step 43."
fn take(p: UInt16) : UInt16
  p
end
fn main(platform: Platform)
  platform.stdout.write("#{take(65536)}\n")
end
