module Lead.U64Plus
intent "Does an oversized literal take part in arithmetic."
fn main(platform: Platform)
  a = 18446744073709551616
  b = a + 1
  platform.stdout.write("#{b}\n")
end
