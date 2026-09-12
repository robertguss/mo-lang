#!/bin/sh
# Times the toolchain's own incremental build: touch one source file, rebuild, report ms.
# This is Q13's "first tested by" (Zig's incremental build claim), tracked from the first commit.
#   bench/rebuild.sh            touches src/lexer.zig
#   bench/rebuild.sh --record   also appends to bench/rebuild.tsv
set -e
cd "$(dirname "$0")/.."
zig build >/dev/null 2>&1            # warm: the number we care about is the second build
touch src/lexer.zig
start=$(python3 -c 'import time; print(int(time.time()*1000))')
zig build
end=$(python3 -c 'import time; print(int(time.time()*1000))')
ms=$((end - start))
echo "incremental zig build after touching src/lexer.zig: ${ms} ms"
if [ "$1" = "--record" ]; then
  printf '%s\tsrc/lexer.zig\t%s\n' "$(date +%s)" "$ms" >> bench/rebuild.tsv
fi
