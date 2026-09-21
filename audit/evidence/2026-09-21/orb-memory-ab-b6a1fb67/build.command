cwd=/home/user/workspace/verify-memory-b6a1fb67-bounded/toolchain
revision=1109b581f3e836cf202765ce4a7bf3fd000950ba
env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-b6a1fb67-bounded/.mo-cache-build-fresh ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-b6a1fb67-bounded/toolchain/.zig-cache-build-fresh ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-b6a1fb67-bounded/.zig-global-cache-build-fresh python3 bench/step36/guard.py 900 -- zig build -j4 --summary all
