module Lead.PCaseu8
intent "Lead probe for step 43."
fn name(n: UInt8) : String
  case n
    300: "big"
    _: "other"
  end
end
fn main(platform: Platform)
  platform.stdout.write("#{name(7)}\n")
end
