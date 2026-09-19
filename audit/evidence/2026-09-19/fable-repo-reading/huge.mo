module Lead.Huge
intent "A literal far past 128 bits."
fn too_large() : UInt64
  999999999999999999999999999999999999999999999999999999
end
fn main(platform: Platform)
  platform.stdout.write("#{too_large()}\n")
end
