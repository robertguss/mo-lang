# Moscope independent phrase smoke passes

Candidate f961c686cacf513daec22e771e73832a227298e5, based on accepted dad7b374.
Robert authorized continuing app-only compatibility fixes until the synthetic
smoke works. No toolchain edits or Step42 overlays. Oracle reviewed the final
four-file identifier/continuation/reduce diff; lead independently repeated it.

Lead command.json and exit.json record the exact60-second guarded command,
minimal environment and real exit0. smoke.stdout731 bytes and smoke.stderr107
bytes each pass cmp against unchanged expected/smoke-phrase files. jq -r
.child_exit piped to cmp also matches expected status0. Four matching messages.
Owned PGID668696 absent in guard and independent empty ps snapshot; no timeout,
cleanup or supervision error. Checkout /tmp/mo-moscope-f961c686 tracked-clean.
Split streams are direct files; wrapper output_bytes0 measures only its empty
combined stream, not the split files. No output-budget enforcement claim.

Accepted compiler SHA256:
3ef07d08ed6d0c802a2597bd956579873851855961cf2e5f01cf87018d273b78.
worker-attempts.tar.gz retains all five worker attempts, including failures;
SHA256528691881a2a8ef12bc3fe7176db3bb61be9f75070be60716fea1c02a71c687b. Lead
also cmp-checked final worker stdout/stderr against expected files.
source.bundle contains the complete candidate, prerequisite dad7b374;
SHA256b3d51af0f77a1d8a6efefbdcec9b7ca215f543edf0a4df8733fe8805932380a8.

This verifies only the phrase smoke. No native/full-corpus/private-data run,
broader semantic coverage, app acceptance or application merge is claimed.
