import json, sys
from run import MO, invoke
failed = False
for name in sys.argv[1:]:
    command = [MO, "test", "--write", "examples/programs/agent/"+name+".mo"]
    if name in ["tools", "run", "book", "server", "runs"]:
        command += ["--sim", "100"]
    if name == "tests/coding-fixture-v1/boundaries":
        command += ["--sim", "100"]
    evidence = invoke(command, 120)
    print(json.dumps(evidence), flush=True)
    failed |= evidence["exit_code"] != 0
sys.exit(int(failed))
