# Step 34's measurements

The tools behind step 34's numbers (`mo-wiki/plans/interpreter-step-34.md`). Every `mo` process runs
under `guard.py SECONDS -- cmd` (a timeout and a 4 GB resident watchdog).

- `asks.mo [N] [same|apart]`: N asks (100,000) from one process to another; `same` has the pinger
  start the ponger, so both run on one scheduler, `apart` has main start both, so they land on two.
  Prints the milliseconds the asks took.
- `deferred.mo ASKERS TOTAL reply|send`: step 31's deferred reply under load, TOTAL asks from ASKERS
  askers to one batcher that answers once ASKERS are held (`reply`), against a send and a `Done` back
  (`send`); the batcher times itself from the first put to the last answer.
- `crunchers.mo [N] [ROUNDS]`: N processes (8), each started by main, so each on a scheduler of its own,
  sum ROUNDS squares (2,000,000) at once; prints the milliseconds from the first start to the last
  answer. The rows use 2,000,000 rounds under `mo run` and 100,000,000 in a binary.
- `mo-bench ../examples 5 --network` runs only `echo-1k`, `kv-10k-get`, `http-1k` and their `-c` rows.
- `MO_STATS=1` prints a line per scheduler after the counts: processes placed there, those placed with
  their starter, live at the end, and asks its processes made across schedulers.
