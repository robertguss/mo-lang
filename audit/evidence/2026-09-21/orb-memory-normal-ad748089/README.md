# Independent full-normal RED

Validator: Amp medium thread T-01a0c217-68f4-70c6-84b5-8283e6125331. Candidate:
ad748089558018894021a2c2bb623df0e6a6ad35. Accepted base:
b2c6daabffc909f45d1b0ed70748e17e0f635507. Integrated revision:
38af0247df5ef2efea8571d208eba2524a03d940.

Raw command, split output, real exit, composition proof and cleanup are
adjacent. The source archive was downloaded and its SHA-256 verified by the
lead: 58fe05e6f444e3f23b0ad452ad57d921d6da9d1e65b89b20e32e41ed1d51ca41. Worker
archive: .amp/transfer/ad748089/verification-ad748089-normal.tar.gz.

Printed result: 300/301 passed, one failure, exit 1; no skipped/crashed tests.
The payload process group was absent after completion. No retry followed.

Lead reading (open after your own): the full-state assertion predates the shared
Relay fixture's held field. Source inspection and Oracle support replacing only
the expected literal with Relay(sent: 0, held: []), retaining exact equality and
all rollback assertions. Source-only correction authorized; execution and Step42
acceptance remain blocked pending subsequent review. No ASan, mutant, stress,
benchmark or timing result is established here.
