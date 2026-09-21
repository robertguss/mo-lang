cwd=/home/user/workspace/verify-memory-69dc6df1-large-restart/toolchain
revision=0a0de7f7de45d7c5b597ab01c43a5e85d8834053
PATH=/usr/local/bin:/usr/bin:/bin
HOME=/home/user
ASAN_SYMBOLIZER_PATH=/usr/lib/llvm-14/bin/llvm-symbolizer
ASAN_OPTIONS=detect_stack_use_after_return=1:detect_leaks=1:halt_on_error=1:abort_on_error=1:symbolize=1:log_path=stderr:leak_check_at_exit=1
MO_CACHE=/home/user/workspace/verify-memory-69dc6df1-large-restart/.mo-cache-asan-native-fresh
ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-69dc6df1-large-restart/toolchain/.zig-cache-asan-native-fresh
ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-69dc6df1-large-restart/.zig-global-cache-asan-native-fresh
MO_STRESS=1
MO_NATIVE_ASAN=1
CLANG_NO_DEFAULT_CONFIG=unset
python3 bench/step36/guard.py 1800 -- zig build test-corpus-asan -j4 --prefix /home/user/workspace/verify-memory-69dc6df1-large-restart/toolchain/zig-out-asan-native-fresh -Dtest-filter='corpus: step 42 native fibers cover first entry park resume caller reuse and excess retirement' --summary all
