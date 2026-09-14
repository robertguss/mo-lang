import sys

from logstat.cli import main

raise SystemExit(main(sys.argv[1:], sys.stdout.buffer, sys.stderr))
