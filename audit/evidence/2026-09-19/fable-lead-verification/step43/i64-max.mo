module Lead.PI64Max
intent "Lead probe for step 43."
fn main(platform: Platform)
  platform.stdout.write("#{9223372036854775807} #{-9223372036854775807}\n")
end
