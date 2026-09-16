"""Take the run out of a transcript: ISO-8601 instants and the uptime."""

import re
import sys

TIMESTAMP = re.compile(r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?Z")
UPTIME = re.compile(r'"uptime_ms":\d+')

text = sys.stdin.read()
text = TIMESTAMP.sub("<ts>", text)
text = UPTIME.sub('"uptime_ms":<ms>', text)
sys.stdout.write(text)
