---
source_url: https://github.com/koka-lang/koka/releases/tag/v3.2.3
ingested: 2026-09-12
sha256: 37cad66eef83e07ea5a5a56893511c1b8481872cf8e6d97232752343b774bddc
---
# v3.2.3

# v3.2.3

- Tag: v3.2.3
- Repository: koka-lang/koka
- Published: 2026-03-18T02:36:34Z
- Author: github-actions[bot]

---

## VS Code installation 
 
It is recommended to install the binary compiler via the VS Code Koka extension. See the [getting started guide](https://koka-lang.github.io/koka/doc/book.html) for more information. 
 
## Command-line installation 
 
### Linux (x64, arm64) and macOS (x64, arm64) 
 
Tested on macOS, Ubuntu, Debian, and should run on most Linux distributions. From a command prompt, run: 
```
curl -sSL https://github.com/koka-lang/koka/releases/download/v3.2.3/install.sh | sh
```
After install, run `koka` to verify that Koka installed correctly. 
 
* For most installations this will ask for root access in order to install to `/usr/local/bin`. For more control, you can pass a different prefix. For example, installing to `~/.local` instead: 
 `curl -sSL https://github.com/koka-lang/koka/releases/download/v3.2.3/install.sh | sh -s -- --prefix=~/.local` 
 
* To uninstall a version, use the `--uninstall` option: 
 `curl -sSL https://github.com/koka-lang/koka/releases/download/v3.2.3/install.sh | sh -s -- --uninstall` 
 
### Windows (x64, arm64) 
 
Open a `cmd` prompt and download and run the installer: 
```
curl -sSL -o %tmp%\install-koka.bat https://github.com/koka-lang/koka/releases/download/v3.2.3/install.bat && %tmp%\install-koka.bat
```
This will also prompt to install the [Clang][llvm] compiler, the [Windows SDK][winSDK] if needed, and syntax highlighting for the [VS Code][vscode] editor. After install, run `koka` to verify that Koka installed correctly. 
 
* On Windows arm64, we use the x64 Koka compiler (which runs emulated), but the generated code is native arm64. 
 
* On Windows, the default install is to the user profile at `%APPDATA%\local`. You can change the installation directory using `--prefix`. For example: 
 `curl -sSL -o %tmp%\install-koka.bat https://github.com/koka-lang/koka/releases/download/v3.2.3/install.bat && %tmp%\install-koka.bat --prefix=c:\programs\local` 
 
* To uninstall a version, use the `--uninstall` option: 
 `curl -sSL -o %tmp%\install-koka.bat https://github.com/koka-lang/koka/releases/download/v3.2.3/install.bat && %tmp%\install-koka.bat --uninstall` 
 
### Other platforms 
 
You need to build [from source](https://github.com/koka-lang/koka#build-from-source), however Koka has few dependencies and should build from source without problems on most common platforms. 
 
[winSDK]: https://visualstudio.microsoft.com/downloads/ 
[llvm]: https://github.com/llvm/llvm-project/releases/latest 
[vscode]: https://code.visualstudio.com/ 

## Assets

| Name | Size | Downloads |
| --- | --- | --- |
| install.bat | 18.5 KB | 1139 |
| install.sh | 20.2 KB | 4040 |
| koka-v3.2.3-linux-arm64.tar.gz | 46.9 MB | 662 |
| koka-v3.2.3-linux-x64.tar.gz | 45.5 MB | 2224 |
| koka-v3.2.3-macos-arm64.tar.gz | 45.5 MB | 1479 |
| koka-v3.2.3-macos-x64.tar.gz | 30.5 MB | 34 |
| koka-v3.2.3-windows-x64.tar.gz | 66.5 MB | 1148 |
| language-koka-3.2.2.vsix | 368.7 KB | 25 |
