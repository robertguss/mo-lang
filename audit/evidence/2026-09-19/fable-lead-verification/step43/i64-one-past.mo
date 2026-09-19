module Lead.PI64Onepast
intent "Lead probe for step 43."
fn main(platform: Platform)
  platform.stdout.write("#{9223372036854775808}\n")
end
