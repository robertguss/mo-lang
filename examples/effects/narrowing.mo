module Effects.Narrowing
expose load, inner

intent "fs.scoped(...).read_only is narrowed, then passed down."

fn inner(fs: Fs) : Fs
  fs
end

fn load(fs: Fs) : Fs
  inner(fs.scoped("/var/app").read_only)
end

test "narrowing returns a capability"
  fs = load(Fs.fixture, within: 50.ms)
  assert fs == fs
end
