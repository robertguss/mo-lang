cwd=/home/user/workspace/verify-memory-85edd344-helpers/toolchain
revision=f54cf71211c5b9614761e136203195c4680dc34e
filter=step 42 large restart stdout oracle rejects lifecycle and RSS failures
env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-85edd344-helpers/.mo-cache-filter-3-fresh ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-85edd344-helpers/toolchain/.zig-cache-filter-3-fresh ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-85edd344-helpers/.zig-global-cache-filter-3-fresh python3 bench/step36/guard.py 1800 -- zig build test-corpus -j4 -Dtest-filter='step 42 large restart stdout oracle rejects lifecycle and RSS failures' --summary all
