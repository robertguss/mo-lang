cwd=/home/user/workspace/verify-memory-71a4fafc-filters/toolchain
revision=194f19697a2dfa542e95ac97529390995db16698
filter=update is a transaction: a crash drops its state writes, sends, and emits, and the process restarts
command=env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-71a4fafc-filters/.mo-cache-filter-1 ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-71a4fafc-filters/toolchain/.zig-cache-filter-1 ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-71a4fafc-filters/.zig-global-cache-filter-1 python3 bench/step36/guard.py 1800 -- zig build test-corpus -Dtest-filter=update\ is\ a\ transaction:\ a\ crash\ drops\ its\ state\ writes\,\ sends\,\ and\ emits\,\ and\ the\ process\ restarts --summary all -j4 
