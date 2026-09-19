module Lead.LzInt8
intent "Leading zeros on a signed small type."
fn too_large() : Int8
  0000000000000000000000000000000000000200
end
fn main(platform: Platform)
  platform.stdout.write("#{too_large()}\n")
end
