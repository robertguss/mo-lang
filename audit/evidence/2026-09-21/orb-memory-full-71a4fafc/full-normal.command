cwd=/home/user/workspace/verify-memory-71a4fafc-full-normal/toolchain
revision=194f19697a2dfa542e95ac97529390995db16698
env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-71a4fafc-full-normal/.mo-cache-full-normal-fresh ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-71a4fafc-full-normal/toolchain/.zig-cache-full-normal-fresh ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-71a4fafc-full-normal/.zig-global-cache-full-normal-fresh python3 bench/step36/guard.py 7200 -- zig build test-corpus -j4 --summary all
