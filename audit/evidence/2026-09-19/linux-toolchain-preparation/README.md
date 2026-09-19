# Linux Zig archive preparation — 19 Sep 2026

The lead downloaded the official aarch64 Linux Zig 0.16.0 archive to a private
temporary directory using `download.py` under a 180-second guard in owned Herdr
pane w4:p12. `download.exit` is 0. The pane closed after the shell returned.

`archive.json` records the temporary path, exact URL, 51,211,944 bytes and SHA-256
verified against the fetched official index and the independently read value:
`ea4b09bfb22ec6f6c6ceac57ab63efb6b46e17ab08d21f69f3a48b38e1534f17`.
`download-commands.json` retains both curl commands and actual results.
Source: <https://ziglang.org/download/index.json>.

This is preparation only. The archive has not been installed or executed, and
no machine resources/configuration were changed while executor tests were
running. Linux compiler/application execution still needs separate verification.
