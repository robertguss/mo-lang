# Independent correction review

Own read-only Astra low worker in Herdr w4:p25; exact session 01a0b898-9845-7593-b1df-e11ecfd537e2. No tests executed.

Reviewed exact `08525c614b32b71b4f6101ecc93eb6e8f6d68797 → 00a0665790a1692c1b529b7b676cdcfa1a94990f`. **No remaining functional defect found within my assigned scope.** Both prior validation findings are closed by source inspection.

All references below are under `toolchain/harness/executor/recovery/` at the corrected commit.

- **Malformed proof flags — prior P2 closed.** `machine.py:36–39,149–159` now requires a dictionary with all three cleanup flags exactly `True` before accepting retained terminal or completed-execution proof when storage is absent. Missing, false, integer, string, and null flag values cannot confirm cleanup. `test_validation.py:13–36` covers all three flags across both proof sources: **30 negative subcases**.

- **Host response validation — prior acceptance gap closed.** `__init__.py:150–174,209–212` validates the byte bound, required/allowed fields, exact run/workspace identities, statuses, and phase sequence before merging. Confirmation requires the complete ordered execution-ID sequence, workspace deletion, no unresolved IDs, and no error. Unresolved responses require `cleanup_unknown`, a valid completed prefix, and its exact remaining suffix. Invalid responses retain the conservative local result.

- **Negative controls strengthened.** `test_validation.py:40–54` supplies nine malformed matching-ID responses plus an oversized response. `local_suite.py:21–22` includes these tests. `live.py:240–245,253–258` now immediately checks unchanged state hashes and absent terminals after foreign/omitted-identity refusals, before restoring receipts. This closes the earlier live-control assertion gap.

**Coverage limitation, not a demonstrated defect:** the new response controls use an empty execution list and mutate confirmed responses. They do not directly exercise multi-execution ordering, duplicate/foreign completed IDs, identity mismatches, or malformed unresolved-prefix/suffix responses (`test_validation.py:42–47`). The implementation rejects these by inspection; dedicated controls would strengthen regression evidence.

This is **source review only**. I executed no tests, builds, servers, remote/Docker operations, or nested agents, and changed no files. Pre-root ownership and lifecycle acceptance remain with the parent reviewer.
