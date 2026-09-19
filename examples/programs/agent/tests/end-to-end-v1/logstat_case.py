"""The protected Logstat verifier, its expected stdout, and the candidate's own test command.

The verifier runs on the frozen read-only snapshot under the unchanged application policy. It
builds from /workspace/logstat/main.mo with cwd /build (never copying source), refuses a stale
/build, runs the four CLI cases from /workspace/logstat and the test binary, and prints one
transcript: each case's stdout, real exit and stderr; the tests' output and real exit; and the
SHA-256 of every file a repair must leave alone, including Main's tests. The whole transcript is
compared exactly with one computed on the trusted side from the goldens, so a candidate's own
stdout cannot make its verdict. The script always exits 0 once it has printed; a failed build
shows as its exit in the transcript."""
import hashlib

CASES = [('fixture', 'logstat.expected', 0),
         ('fixture --top 3 --since 2026-09-12T10:00:10Z --json', 'logstat-2.expected', 0),
         ('fixture --top 0', 'logstat-3.expected', 2),
         ('.', 'logstat-4.expected', 1)]
# stderr of each case, bound from the clean host build and checked again on the machine.
STDERR = {'fixture': '', 'fixture --top 3 --since 2026-09-12T10:00:10Z --json': '',
          'fixture --top 0': 'logstat: --top takes a whole number from 1 to 100, not 0; usage: logstat <dir> [--top N] [--since <ISO-8601>] [--json]\n',
          '.': 'logstat: no .log file in .\n'}
SCOPE = ['mo.root', '.mo.ids', 'logstat/parse.mo', 'logstat/report.mo', 'logstat/stats.mo',
         'logstat/fixture/a.log', 'logstat/fixture/b.log', 'logstat/fixture/c.log', 'logstat/fixture/notes.txt']
TESTS_FROM = 'test "the defaults are the top five'

BUILD = ('cd /build\n'
         'if mo build /workspace/logstat/main.mo -o logstat >/build/build.log 2>&1; then echo "build=0"; else echo "build=$?"; fi\n'
         'if mo build /workspace/logstat/main.mo --tests -o logstat-tests >/build/build-tests.log 2>&1; then echo "build-tests=0"; else echo "build-tests=$?"; fi\n'
         'tail -c 4000 /build/build.log >&2; tail -c 4000 /build/build-tests.log >&2\n')


def verifier_script():
    lines = ['set -u', 'if [ -n "$(ls -A /build)" ]; then echo "stale-build"; exit 0; fi', BUILD.rstrip('\n'),
             'B=/build/zig-out/mo-build/logstat/logstat', 'T=/build/zig-out/mo-build/logstat-tests/logstat-tests',
             'cd /workspace/logstat']
    for args, _, _ in CASES:
        lines += [f'echo "== {args}"', f'"$B" {args} 2>/build/stderr; echo "exit=$?"', 'echo "-- stderr"', 'cat /build/stderr']
    lines += ['echo "== tests"', '"$T" >/build/tests.out 2>&1; echo "exit=$?"', 'cat /build/tests.out',
              'echo "== scope"', 'cd /workspace']
    lines += [f'sha256sum {path}' for path in SCOPE]
    lines += [f"sed -n '/^{TESTS_FROM}/,$p' logstat/main.mo | sha256sum", 'exit 0']
    return '\n'.join(lines) + '\n'


def expected_stdout(goldens, tree, tests_output):
    """The transcript a correct candidate prints, from trusted goldens and the prepared tree."""
    out = ['build=0\n', 'build-tests=0\n']
    for args, golden, code in CASES:
        out += [f'== {args}\n', goldens[golden].decode(), f'exit={code}\n', '-- stderr\n', STDERR[args]]
    out += ['== tests\n', 'exit=0\n', tests_output, '== scope\n']
    out += [f'{hashlib.sha256(tree[p]).hexdigest()}  {p}\n' for p in SCOPE]
    main = tree['logstat/main.mo'].decode()
    tests = main[main.index('\n' + TESTS_FROM) + 1:]
    out.append(f'{hashlib.sha256(tests.encode()).hexdigest()}  -\n')
    return ''.join(out)


def verifier(goldens, tree, tests_output):
    return {'script': verifier_script(), 'seconds': 120,
            'checks': [{'id': 'logstat-transcript', 'stream': 'stdout', 'mode': 'exact',
                        'expected': expected_stdout(goldens, tree, tests_output)}]}


# The model's own check inside the run: build the tests and run them; exit 1 is a failing test.
CANDIDATE_COMMAND = ('cd /build && if ! mo build /workspace/logstat/main.mo --tests -o logstat-tests >/build/build.log 2>&1; '
                     'then tail -c 4000 /build/build.log; exit 2; fi; /build/zig-out/mo-build/logstat-tests/logstat-tests')
