# Independent benchmark watcher synthetic check

Lead reading; open after your own. Recorded 21 Sep 2026, 1:46 AM ET.

The exact canonical command, clean integrated revision4161f7b9, payload identity
and exit receipt are under attempt/. Candidate watcher source is72a49307,
composed with the accepted main guard and full server dependency tree. No
partial three-file overlay or worker-generated metadata was used in this run.

Actual exit0; exact ordered eleven cases and locally reaped sentinel in
result.json. Exit receipt: all three exit fields0, both reasons child_exit,
reason_source supervision, no timeout, cleanup_confirmed true, literal group
absent, group_absent true, no remaining members or errors. Elapsed4.91s is a
control duration, not benchmark timing. Payload output and guard stderr empty.
The payload command receipt hash matches command.json; its PGID matches the exit
receipt. Lead jq assertions of the exact result and exit fields passed.

The worker's independent equivalent run passed11/11 in5.429s, archive SHA-256
4129ae4d22f3c8812040b10a346736188c255e83cbb697a05ec867e29b4ef5e7. Its earlier
attempt failed at import before any cases because the lead's three-file
composition instruction omitted unchanged_client_green. That failure is not a
watcher result and remains retained in the worker's transfer directory.

Oracle reviewed the exact source and specified these acceptance predicates. They
are met for the synthetic checks only. This does not release real-Mo lifecycle
modes or measurements, accept part A, or prove an aggregate/hard memory cap. The
watcher requires a schedulable trusted driver and samples only its owned direct
child. Accepted outer supervision owns final group cleanup.
