# run:
module Probe.Capture
expose main

fn main(platform: Platform)
  random = platform.random
  sizes = [4, 8].map(fn(n) random.bytes(n).size end)
  platform.stdout.write_line("#{sizes}")
end
