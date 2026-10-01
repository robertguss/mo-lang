---
source_url: https://sqlite.org/forum/forumpost/115a6fedd9
ingested: 2026-09-23
version: "Forum thread 2024-11-14 through 2024-11-15; reported reproducer not executed"
read_status: complete-extracted-text-read
extraction: Exa cached text
sha256: 78f1df83086f301025ed9669986e0ec3974a94efc00ad9e5f0fd95564f5a2bb6
---
SQLite User Forum: sqllogictest row count mismatch

# sqllogictest row count mismatch

### (1) By Guillaume Huysmans (ghuysmans) on 2024-11-14 22:00:27 [source]

Hi,

I'd like to use sqllogictest to test an app I'm currently working on. In doing so, I found a bug: it doesn't compare row counts, it only reports values that don't match. This leads to situations where row count mismatches go undetected — in my case, I forgot to populate a table with test data. To illustrate, here's a minimal reproducible example:

```
query I
SELECT 0 a WHERE a
----
42

```

As you can see, sqllogictest doesn't report any issue:

```
$ sqllogictest --verify zero_one.test
0 errors out of 1 tests in zero_one.test - 0 skipped.

```

To resolve this, I added a check after the main comparison loop. Here's the patch I used, which makes my MRE pass:

```
--- a/sqllogictest.c
+++ b/sqllogictest.c
@@ -679,6 +679,11 @@ int main(int argc, char **argv){
               break;
             }
           }
+          if (i!=nResult || sScript.zLine[0]) {
+            fprintf(stdout, "%s:%d: wrong result size\n", zScriptFile,
+                    sScript.nLine);
+            nErr++;
+          }
         }else{
           if( strcmp(sScript.zLine, zHash)!=0 ){
             fprintf(stderr, "%s:%d: wrong result hash\n",

```

Could you review this change and let me know if any further adjustments are needed?

Thank you!

### (2) By Richard Hipp (drh) on 2024-11-15 00:03:12 in reply to 1 [link] [source]

SQLLogictest patched at https://sqlite.org/sqllogictest/info/c5ec0e8e41a8106c.

### (3) By Guillaume Huysmans (ghuysmans) on 2024-11-15 11:21:22 in reply to 2 [link] [source]

Thanks a lot!