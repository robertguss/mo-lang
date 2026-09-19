# Retained recovery evidence

All attempts are retained independently. Nonzero exits remain failures, including expected red controls. See ../WORKER-REPORT.md for interpretation and API/operator distinctions.

| Attempt | Exit | Elapsed seconds |
| --- | --- | --- |
| `application-observed-01` | 0 | 152.932531749997 |
| `executor-observed-01` | 0 | 33.15063233300316 |
| `final-inventory-01` | 0 | 0.466242250004143 |
| `final-inventory-02` | 0 | 0.5771929589973297 |
| `full-build-01` | 0 | 38.185454124999524 |
| `full-test-01` | 1 | 418.34516079100285 |
| `full-test-02` | 0 | 406.5163478339964 |
| `green-receipt-01` | 0 | 0.11156129199662246 |
| `lifecycle-observed-01` | 0 | 9.736121250003634 |
| `live-02` | 1 | 0.4521102080034325 |
| `live-03` | 0 | 1.0020835830000578 |
| `live-04` | 1 | 4.471436333995371 |
| `live-05` | 0 | 4.629471666994505 |
| `local-01` | 0 | 0.32476658299856354 |
| `local-02` | 0 | 0.8686495829970227 |
| `local-03` | 0 | 0.9046150419962942 |
| `local-04` | 0 | 0.9035921250033425 |
| `local-05` | 0 | 0.9261370419990271 |
| `local-06` | 0 | 1.523441332996299 |
| `local-edges-01` | 0 | 1.5293558330013184 |
| `local-final-01` | 0 | 1.532547249997151 |
| `local-final-02` | 0 | 1.5617011249996722 |
| `operator-cleanup-01` | 1 | 1.0864447499989183 |
| `operator-cleanup-02` | 0 | 1.2987750000029337 |
| `operator-cleanup-observed01` | 0 | 1.286669000000984 |
| `readiness-probes-01` | 1 | 0.23694095900282264 |
| `readiness-probes-02` | 0 | 1.3008185409998987 |
| `readiness-probes-03` | 0 | 1.4008144170002197 |
| `recovery-final-01` | 0 | 9.531704417000583 |
| `recovery-final-02` | 1 | 0.15429250000306638 |
| `recovery-final-03` | 0 | 11.62720383299893 |
| `recovery-final-04` | 0 | 11.890450958002475 |
| `red-01` | 1 | 0.10347979200014379 |
| `red-dispose-01` | 1 | 0.13520370900369016 |
| `red-edges-01` | 1 | 0.1429563329947996 |
| `red-edges-02` | 1 | 0.14219129199773306 |
| `red-validation-01` | 1 | 0.25843479199829744 |
| `regressions-01` | 0 | 233.11920804100373 |
| `regressions-final-01` | 1 | 94.51817966700037 |
| `runtime-diagnostic-01` | 0 | 0.24896054199780338 |
| `runtime-diagnostic-02` | 0 | 0.24009833300078753 |
| `workspace-observed-01` | 1 | 126.58668304199819 |
| `workspace-observed-02` | 0 | 37.55256591700163 |

`live-01` retains a pre-launch wrapper traceback without exit.json. `MANIFEST.json` hashes every retained file/link except itself. `FINAL-RECEIPT.json` and final-inventory-02 provide the final bounds and absence proof.
