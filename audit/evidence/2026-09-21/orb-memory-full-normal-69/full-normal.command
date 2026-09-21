cwd=/home/user/workspace/verify-memory-69dc6df1-large-restart/toolchain
revision=0a0de7f7de45d7c5b597ab01c43a5e85d8834053
capture_dir=/home/user/workspace/repo/.amp/transfer/69dc6df1-full-normal/capture-0a0de7f7-full-normal
env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-69dc6df1-large-restart/.mo-cache-full-normal-fresh ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-69dc6df1-large-restart/toolchain/.zig-cache-full-normal-fresh ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-69dc6df1-large-restart/.zig-global-cache-full-normal-fresh MO_STEP42_CAPTURE_DIR=/home/user/workspace/repo/.amp/transfer/69dc6df1-full-normal/capture-0a0de7f7-full-normal python3 bench/step36/guard.py 7200 -- zig build test-corpus -j4 --summary all
