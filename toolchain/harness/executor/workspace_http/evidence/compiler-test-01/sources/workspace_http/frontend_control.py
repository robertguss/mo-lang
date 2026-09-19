"""Actual killable frontend parent for the local lifetime test."""
import sys
from pathlib import Path
import time
from .local import Controls

control = Controls()
# Keep evidence outside unittest temporary teardown so the parent test reads it.
class Temp:
    name = str(Path(sys.argv[1]).parent)
control.temp = Temp()
control.bridges = []
# Controls.bridge normally chooses /0; rename is unsafe for receipt paths, so
# create the exact requested path through its indexed directory convention.
control.temp.name = str(Path(sys.argv[1]))
Path(control.temp.name).mkdir()
bridge = control.bridge()
# Parent watches this path; use a pointer instead of relocating owner state.
Path(sys.argv[1], 'location').write_text(str(bridge.directory))
conn = control.connect(bridge, control.req(bridge,'command',{'command':'slow','timeout_ms':1000}))
time.sleep(10)
