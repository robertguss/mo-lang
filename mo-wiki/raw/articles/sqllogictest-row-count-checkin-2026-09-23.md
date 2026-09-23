---
source_url: https://sqlite.org/sqllogictest/info/c5ec0e8e41a8106c
ingested: 2026-09-23
version: "Check-in overview dated 2024-11-15; patch diff and implementation not inspected"
read_status: complete-extracted-text-read
extraction: web_extract markdown
sha256: 86ae14981a73ccc2e74909e03d3f7f86a5b8f1e7350471ba41726d858a30c407
---
sqllogictest: Check-in [c5ec0e8e41]

Overview

| Comment: | Enhanced to verify that the correct number of rows is returned from each query. See SQLite Forum post 115a6fedd9. |
| --- | --- |
| Timelines: | family | ancestors | descendants | both | trunk |
| Files: | files | file ages | folders |
| SHA1: | c5ec0e8e41a8106c9f564c498b58d8c2 5cdb9179 |
| User & Date: | drh on 2024-11-15 00:01:36.192 |
| Other Links: | manifest | tags |

Context

| 2024-12-12 | |
| --- | --- |
| 17:57 | Update the license statement on the main source code file. check-in: 11f343c926 user: drh tags: trunk |
| 2024-11-15 | |
| 00:01 | Enhanced to verify that the correct number of rows is returned from each query. See SQLite Forum post 115a6fedd9. check-in: c5ec0e8e41 user: drh tags: trunk |
| 2024-10-18 | |
| 16:23 | Update the built-in SQLite to the latest 3.47.0 beta. check-in: 7dda571435 user: drh tags: trunk |

Changes

 Modified src/sqllogictest.c from [2c354f3d44] to [c1564006ee]. [diff] 

 Modified test/evidence/slt_lang_aggfunc.test from [2397e60fdd] to [b780ff50e7]. [diff] 

 Modified test/index/commute/10/slt_good_10.test from [e70de58b44] to [77642ecfcd]. [diff]