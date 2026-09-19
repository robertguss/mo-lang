module Lead.PHex
intent "Lead probe for step 43."
fn main(platform: Platform)
  platform.stdout.write("#{0x100}\n")
end
