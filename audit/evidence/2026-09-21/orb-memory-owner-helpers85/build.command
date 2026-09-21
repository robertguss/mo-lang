cwd=/home/user/workspace/verify-memory-85edd344-helpers/toolchain
revision=f54cf71211c5b9614761e136203195c4680dc34e
env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-85edd344-helpers/.mo-cache-build-fresh ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-85edd344-helpers/toolchain/.zig-cache-build-fresh ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-85edd344-helpers/.zig-global-cache-build-fresh python3 bench/step36/guard.py 900 -- zig build -j4 --summary all
