# run:
module Probe.Crash
expose main

fn main(platform: Platform)
  out = platform.stdout
  sealed = AesGcm.seal([1, 2, 3], [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], [9], [])
  out.write_line("unreachable #{sealed.size}")
end
