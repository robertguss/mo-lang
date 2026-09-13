# run: missing-config bad-port
# exit: 3
module Programs.ExitCode
expose exit_code

intent "Report problems on stderr and exit with a code a shell can test; stdout stays empty."

fn exit_code(problems: UInt64) : UInt8
  return 0 if problems == 0
  3
end

fn main(platform: Platform)
  problems = platform.args
  platform.stderr.write("#{problems.size} problems: #{problems}\n")
  platform.exit(exit_code(problems.size))
end

test "no problems is success, and any problem is 3"
  assert exit_code(0) == 0
  assert exit_code(2) == 3
end

verified: types, contracts, tests (1), property (0 seeds), sim (not run)
          proven: not run
