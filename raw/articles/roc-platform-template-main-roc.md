---
source_url: https://raw.githubusercontent.com/lukewilliamboswell/roc-platform-template-rust/main/platform/main.roc
ingested: 2026-09-12
sha256: 5b5e5a625eef1e5ad8c0054090a041a2ccd043595e14f453f7d4acee1cf07608
---
# roc-platform-template-rust: platform/main.roc

```roc
platform ""
	requires {
		main! : List(Str) => Try({}, [Exit(I32), ..])
	}
	exposes [Stdout, Stderr, Stdin]
	packages { roc: "nightly-2026-09-07-14d9829" }
	provides { "roc_main": main_for_host! }
	hosted {
		"roc_stderr_line": Host.stderr_line!,
		"roc_stdin_line": Host.stdin_line!,
		"roc_stdout_line": Host.stdout_line!,
	}
	targets: {
		inputs_dir: "targets/",
		x64mac: { inputs: ["libhost.a", app] },
		arm64mac: { inputs: ["libhost.a", app] },
		x64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
		arm64musl: { inputs: ["crt1.o", "libhost.a", "libunwind.a", app, "libc.a", "libzigc.a", "libcompiler_rt.a"] },
	}

import Stdout
import Stderr
import Stdin
import Host

main_for_host! : List(Str) => I32
main_for_host! = |args| {
	result = main!(args)
	match result {
		Ok({}) => 0
		Err(Exit(code)) => code
		Err(other) => {
			_ = Stderr.line!("ERROR: ${Str.inspect(other)}")
			-1
		}
	}
}

```
