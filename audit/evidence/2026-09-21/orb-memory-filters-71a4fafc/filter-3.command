cwd=/home/user/workspace/verify-memory-71a4fafc-filters/toolchain
revision=194f19697a2dfa542e95ac97529390995db16698
filter=step 42: packs=true committed event owns its nested payload until cleanup
command=env -u MO_NATIVE_ASAN -u MO_STRESS -u MO_CORPUS MO_CACHE=/home/user/workspace/verify-memory-71a4fafc-filters/.mo-cache-filter-3 ZIG_LOCAL_CACHE_DIR=/home/user/workspace/verify-memory-71a4fafc-filters/toolchain/.zig-cache-filter-3 ZIG_GLOBAL_CACHE_DIR=/home/user/workspace/verify-memory-71a4fafc-filters/.zig-global-cache-filter-3 python3 bench/step36/guard.py 1800 -- zig build test-corpus -Dtest-filter=step\ 42:\ packs=true\ committed\ event\ owns\ its\ nested\ payload\ until\ cleanup --summary all -j4 
