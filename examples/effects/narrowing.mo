module Effects.Narrowing
expose narrow, root
intent "Pass a scoped read-only filesystem capability down a function boundary."

fn root() : String
  "/var/app"
end

fn pass_down(fs: Fs) : Fs
  fs
end

fn narrow(fs: Fs) : Fs
  pass_down(fs.scoped(root()).read_only, within: 200.ms)
end

test "the scope is the application directory"
  assert root() == "/var/app"
end
