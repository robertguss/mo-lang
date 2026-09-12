---
source_url: https://aube.sh/security.html
ingested: 2026-09-12
sha256: 8dc964f67339e41a6272add0d4fcd6d26dab671d5989b0d302f9fd3b659dd410
---
# aube documentation: security pages (text extract)

Source site: https://aube.sh (jdx, MIT). Pages concatenated; each section is headed by its URL. Extracted 12 Sep 2026 at Robert's request.


# https://aube.sh/security.html

Security ​
aube applies checks while selecting, downloading, and building dependencies. The protections have different boundaries: some fail the install, some warn, and some require explicit configuration.
Defaults at a glance ​
ProtectionDefaultBoundary
Dependency buildsProject allowlist plus built-in trusted packagesExplicit denies win; root scripts run normally
Publishing trustno-downgradeChecks evidence during resolution; locked versions and exceptions are trusted
New versions24-hour minimum ageCan fall back when no eligible version satisfies the range unless strict mode is enabled
Known malicious packagesLive OSV checks on fresh resolutionNetwork failure warns by default; unchanged installs skip live checks
Package reputationChallenges new, unpopular, or similar names on addPublic npm packages; reviewed exceptions are supported
Exotic transitive sourcesBlockedDirect dependencies explicitly declared by the project are allowed
Build jailOffOptional native write/network restrictions on macOS and Linux; reads remain unrestricted
Vulnerability auditExplicit aube auditSeparate from the malicious-package check
YAML examples on this page belong in aube-workspace.yaml or an existing pnpm-workspace.yaml. Review exceptions alongside your dependency changes.
To report a vulnerability, see the security policy.
The paranoid switch ​
The fastest way to enable the strict bundle is one line:
yamlparanoid: true

This forces every setting in the strict bundle on, regardless of how each is configured individually:
jailBuilds = true
trustPolicy = no-downgrade (overrides explicit off)
minimumReleaseAgeStrict = true — turns the age gate into a hard fail instead of "fall back to the lowest satisfying version"
strictStoreIntegrity = true — fail when a tarball ships without dist.integrity instead of warning
strictDepBuilds = true — fail the install when a dep has unreviewed build scripts instead of silently skipping them
advisoryCheck = required — fail any live-API OSV check when OSV can't be reached, instead of warning and continuing
Use this bundle when you want these stricter failure rules together. It does not enable a third-party scanner or live advisory checks on every unchanged install, and it does not expand the jail's platform capabilities.
Default-deny lifecycle scripts ​
Lifecycle scripts (preinstall, install, postinstall) run arbitrary code when a package is installed, which makes them a common attack vector. aube runs dependency lifecycle scripts only when project policy or its built-in trusted-dependencies list allows them. An explicit deny overrides built-in trust. Declare project approvals by package name:
yaml# aube-workspace.yaml
allowBuilds:
 esbuild: true
 sharp: true

Or interactively:
shaube approve-builds

Root-package lifecycle scripts (your own project's) still run normally; only dependency scripts need approval.
For a Git dependency that tracks a branch, approve the package and repository URL rather than a resolved commit. The rule remains limited to that repository; a package-name-only rule never approves Git-sourced code:
yamlallowBuilds:
 native-addon@git+https://github.com/acme/native-addon.git: true

Settings: allowBuilds. Install adds unreviewed build packages to aube-workspace.yaml (or pnpm-workspace.yaml if one already exists) as false; approving them flips the entry to true.
Suspicious-script content sniff ​
Before suggesting aube approve-builds, aube checks each unreviewed dependency's preinstall / install / postinstall script bodies and surfaces a WARN_AUBE_SUSPICIOUS_LIFECYCLE_SCRIPT for any that match a known-dangerous shape:
curl … | sh / wget … | bash — fetch-and-pipe-to-shell.
eval(atob(…)) / Function(atob(…)) / eval(Buffer.from(…)) — base64-decode-then-evaluate, a common dropper shape.
Reads of ~/.ssh, ~/.aws, ~/.npmrc, ~/.config/gh — credential files a lifecycle script has no business touching.
process.env.*TOKEN, *SECRET, *API_KEY, etc. — secret-shaped env vars exfiltrated from CI.
Discord webhooks, Telegram bot API, OAST collaborator hosts — known exfil channels.
http://1.2.3.4/… bare-IP HTTP targets.
The sniff is advisory — it never blocks an install or write. The allowBuilds allowlist remains the only gate on whether scripts actually execute; the sniff just gives you more than name@version to judge by when deciding whether to approve a build. aube approve-builds repeats the same warnings inline next to each picker entry, and aube ignored-builds lists them under each name@version line.
These patterns can produce false positives and do not detect every harmful script. After reviewing a flagged package, use aube approve-builds to record a package-specific approval. Keep allowBuilds as a map of names to booleans.
Jailed lifecycle scripts ​
For an approved dependency, jailing restricts filesystem writes, network access, and inherited environment variables. Filesystem reads remain unrestricted. On macOS aube wraps the script with a Seatbelt profile; on Linux it applies Landlock and seccomp before exec. Both deny network access and limit writes to package and jail-owned temporary directories. On Windows the env is scrubbed and HOME is redirected to a temporary directory.
yamljailBuilds: true

Grant narrow exceptions per-package instead of disabling the jail wholesale:
yamljailBuilds: true
jailBuildPermissions:
 sharp:
 env: [SHARP_DIST_BASE_URL]
 write: ["~/.cache/sharp"]
 network: true

Default: false today, planned to flip to true in the next major.
Full reference: Jailed builds.
Trust policy ​
trustPolicy = no-downgrade blocks installs of a version that carries weaker trust evidence than any earlier-published version of the same package. aube recognizes three tiers of evidence, strongest first, and only counts the structured metadata shapes npm emits after registry-side checks:
npm staged publish approval — package metadata carries an approver field from the registry-side approval flow.
npm trusted-publisher — package was published via OIDC from a trusted CI provider (_npmUser.trustedPublisher.id).
Sigstore provenance — package was published with npm publish --provenance (dist.attestations.provenance.predicateType with an SLSA provenance URI).
This install-time policy validates the registry metadata shape; it does not cryptographically verify the attached attestation bundle.
The policy runs when aube resolves a package version. Versions already present in the active lockfile are trusted, so frozen and repeat installs do not re-fetch publishing evidence for packages the project has already accepted.
A trust downgrade may indicate a supply-chain incident: publisher account takeover, repository tampering, or a malicious co-maintainer publishing without the original CI flow.
yamltrustPolicy: no-downgrade

Exempt specific packages or versions when needed:
yamltrustPolicyExclude:
 - "@vendor/legacy-pkg" # every version of one package
 - "old-thing@1.0.0" # one exact version
 - "things@^1.0.0 || >=2 <3" # union of semver ranges
 - "is-*" # name glob (globs take no version)

Version selectors are npm-style semver ranges.
Default: no-downgrade. Set trustPolicy: off to disable, or use trustPolicyExclude for per-package opt-outs.
aube also ships a small built-in exclude list for well-known packages whose maintainers legitimately publish provenance-inconsistent releases (e.g. maintaining multiple major-version lines and backporting to older ones without attestation), so common installs don't fail on a known-benign downgrade. Your own trustPolicyExclude entries are added on top of these defaults.
See Trust policy downgrades for an investigation checklist, guidance for reporting packaging failures upstream, and the dynamically generated list of built-in exceptions.
Settings: trustPolicy, trustPolicyExclude, trustPolicyIgnoreAfter.
Minimum release age ​
Wait a configurable period before installing newly published versions. This 24-hour release quarantine is intentionally separate from the longer package-name quarantine used for slopsquatting protection.
yamlminimumReleaseAge: 4320 # 3 days

minimumReleaseAgeStrict: true fails the install when no version satisfies the range; otherwise the resolver falls back to the lowest satisfying version ignoring the cutoff for that pick only.
Default: 1440 (24 hours). Set minimumReleaseAge: 0 to disable.
Settings: minimumReleaseAge, minimumReleaseAgeExclude, minimumReleaseAgeStrict.
Typosquat and impersonation protection ​
aube add checks every package you name on the command line — and, after resolution, the full transitive closure — against OSV for MAL-* malicious-package advisories. The same check runs on aube update and on any install where the resolver picks a version the lockfile didn't already pin. Plain reinstalls (where the lockfile was authoritative) skip the live API for latency; two opt-in local backends cover that path — see Install-time OSV check below.
Four signals, with different response levels:
Known-malicious advisories. aube batch-queries OSV for MAL-* advisories on every name about to be added. A hit fails the install with ERR_AUBE_MALICIOUS_PACKAGE and a link to the advisory. If the OSV API can't be reached, the default (advisoryCheck: on) warns and continues; advisoryCheck: required upgrades that to a fail-closed ERR_AUBE_ADVISORY_CHECK_FAILED so CI can tell a network outage from a confirmed-malicious advisory.
Similar package name. aube compares requested names with a monthly snapshot of the 100,000 most-downloaded npm packages before contacting the registry. The comparison is namespace-aware: unscoped packages are compared only with unscoped packages, names within the same scope are compared by basename, and names in different scopes are compared in full. This catches lookalikes such as lodahs → lodash, @babel/parserr → @babel/parser, and @type/node → @types/node without treating an intentional scoped fork as an unscoped-package impersonation.
Interactive sessions show a “did you mean?” prompt. Non-interactive sessions fail with ERR_AUBE_SIMILAR_PACKAGE_NAME. The popularity corpus contains names only, is compressed into release binaries, and is generated from the continuously updated ecosyste.ms npm registry index rather than an infrequently published npm data package.
Low download count. A typosquat or impersonation has approximately zero installs on day one regardless of how cleverly it's named, so a download-count floor catches the long tail of squats that haven't been reported yet. Below the threshold, aube prompts for confirmation:
aube add supabase-javascript

 ⚠ supabase-javascript looks suspicious:
 • 3 downloads last week (threshold: 1000)
 Continue adding supabase-javascript? [y/N]

In non-interactive contexts the prompt becomes a hard refusal with ERR_AUBE_LOW_DOWNLOAD_PACKAGE unless --allow-low-downloads is passed. Packages already present in the active lockfile are trusted for this download-count check, regardless of which supported lockfile format the project uses. Lockfile membership does not bypass the OSV check.
New package name. Before adding a direct dependency, aube reads npm's time.created timestamp and challenges names registered within minimumPackageAge (30 days by default). Interactive sessions require confirmation; non-interactive sessions fail with ERR_AUBE_NEW_PACKAGE_NAME. Packages already present in the active lockfile and names matched by allowedUnpopularPackages are trusted. Missing or unavailable creation-time metadata fails closed with ERR_AUBE_PACKAGE_AGE_CHECK_FAILED. --allow-low-downloads bypasses all three reputation challenges after the package has been verified out of band.
yamlminimumPackageAge: 43200 # 30 days

Private packages skip all four gates automatically. Any package routed through a non-registry.npmjs.org registry — whether by a scoped override (@myorg:registry=https://npm.internal.example/) or by replacing the default registry= URL outright — is exempted from the OSV check and the reputation gates, because npmjs has no signal on it. Workspace deps and git/local specs are also skipped.
For names that do route through public npmjs but are known-internal (e.g. you publish a low-traffic helper under your own brand), list them in allowedUnpopularPackages to skip all three reputation gates:
yamladvisoryCheck: on # default; fail open on network error
lowDownloadThreshold: 1000 # weekly downloads, 0 disables
allowedUnpopularPackages: # glob patterns; OSV check still runs
 - "@mycompany/*"
 - "internal-*"

Set advisoryCheck: required to fail closed when OSV can't be reached — appropriate for hardened CI, included in paranoid: true. Set advisoryCheck: off or lowDownloadThreshold: 0 to disable either check independently.
Settings: advisoryCheck, lowDownloadThreshold, allowedUnpopularPackages.
Install-time OSV check ​
After resolution, every install picks exactly one OSV MAL-* backend, so the freshest signal lands when it matters most without paying a per-install network round-trip when it doesn't:
Install pathBackendSetting
aube add, aube updateLive APIadvisoryCheck (default on)
Missing lockfile / resolver picked new versionLive APIadvisoryCheck (default on)
advisoryCheckEveryInstall = trueLive APIadvisoryCheck (default on)
Plain reinstall (lockfile authoritative)Bloom prefilteradvisoryBloomCheck (default off)
Plain reinstall, bloom disabledLocal mirroradvisoryCheckOnInstall (default off)
Plain reinstall, both disabledNo check—
The two local backends cover plain reinstalls without a live round-trip:
Bloom prefilter (advisoryBloomCheck) downloads a ~380 KB bloom filter built from OSV's malicious-package archive (regenerated upstream every 10 minutes), probes the resolved graph against it, and escalates only the hits (~0.1% false-positive rate) to the live API for exact (name, version) confirmation. A typical lockfile costs zero or one extra live-API round trip per install. When both local backends are enabled, the bloom wins — it's far cheaper on the wire and its confirmed hits go through the same live-API oracle.
Local mirror (advisoryCheckOnInstall) keeps the bulk zip from osv-vulnerabilities.storage.googleapis.com/npm/all.zip (roughly tens of MB) at $XDG_CACHE_HOME/aube/osv/npm/, lazily refreshed with an ETag-conditional GET every 24 hours. Lookups are sub-millisecond, but the index lags reality by up to ~24h — an advisory published in the last day won't be in it unless a refresh happens to fall after it. Fresh-resolution installs always go through the live API, so that lag never affects new picks.
Confirmed hits from any backend fail the install with the same ERR_AUBE_MALICIOUS_PACKAGE exit.
yaml# Default: live API on aube add / update / fresh-resolution.
# Plain reinstalls skip OSV entirely.
advisoryCheck: on
advisoryBloomCheck: off
advisoryCheckOnInstall: off
advisoryCheckEveryInstall: false

yaml# Hardened CI: live API on every install, fail-closed on fetch errors.
advisoryCheck: required
advisoryCheckEveryInstall: true

yaml# Cheap always-on coverage: bloom prefilter covers plain reinstalls
# with a ~380 KB download; hits escalate to the live API.
advisoryCheck: on
advisoryBloomCheck: on

Both local backends share the same refresh-failure semantics:
on: warn (WARN_AUBE_OSV_BLOOM_REFRESH_FAILED / WARN_AUBE_OSV_MIRROR_REFRESH_FAILED) and continue against the prior on-disk copy (or empty on first sync).
required: refresh failures map to ERR_AUBE_ADVISORY_CHECK_FAILED. Use in hardened CI where a stale or unreachable index should block.
Settings: advisoryCheck, advisoryBloomCheck, advisoryCheckOnInstall, advisoryCheckEveryInstall.
Block exotic transitive dependencies ​
Reject transitive dependencies that resolve to git+, file:, or direct tarball URLs — those skip the registry and its integrity verification. Direct deps you pin yourself in package.json are still allowed.
yamlblockExoticSubdeps: true # default

Settings: blockExoticSubdeps.
Tarball integrity ​
With integrity verification enabled, aube checks fetched registry tarballs against their recorded integrity before importing them into the store. A mismatch fails the install. Missing integrity metadata warns by default; strictStoreIntegrity: true makes it an error. The lockfile preserves the integrity value for later fetches.
The content-addressable store uses BLAKE3 to identify files. This is separate from registry tarball integrity. Reflinks, hardlinks, and copies have different write semantics, so content addressing is not a sandbox for arbitrary edits to installed files. Use aube patch to make reproducible changes and aube store status to check cached file integrity.
Auth tokens ​
Registry tokens are read from .npmrc (the npm convention) or environment variables (NPM_TOKEN, AUBE_AUTH_TOKEN, etc.) and never written to the lockfile, tarball cache, or logs. aube login and aube logout manage tokens via the standard npm config file.
Inside jailed lifecycle scripts, common token env vars (NPM_TOKEN, NODE_AUTH_TOKEN, GITHUB_TOKEN, SSH_AUTH_SOCK, AWS_*, etc.) are scrubbed from the script environment unless explicitly granted via jailBuildPermissions.
Pluggable security scanner ​
securityScanner runs a Bun-compatible security scanner against the resolved install graph. Point the setting at the same npm package you'd put in Bun's bunfig.toml#install.security.scanner and aube loads it through a node bridge — the oven-sh template and @socketsecurity/bun-security-scanner both run unchanged.
yaml# aube-workspace.yaml
securityScanner: "@acme/bun-security-scanner"

The scanner fires post-resolve, sees the full transitive graph with resolved versions, and fails closed on any scanner failure (missing node, unresolvable module, timeout, etc.). Requires Node 22.6+. Set securityScanner: "" to disable when bootstrapping.
Full reference: Security scanner.
Auditing installed dependencies ​
shaube audit # report advisories at the configured severity (default: low)
aube audit --audit-level high
aube audit --fix # write package.json overrides to patched versions
aube audit --json | jq # machine-readable for CI

Same advisory data source as npm audit and pnpm audit; same response schema.
Example strict policy ​
For a project that has reviewed its dependency builds and can use the jail:
yaml# aube-workspace.yaml
paranoid: true # bundles jailBuilds, no-downgrade, strict gates
allowBuilds:
 esbuild: true
 sharp: true
 # ...whatever your project actually needs to build

trustPolicy: no-downgrade and minimumReleaseAge: 1440 (24h) are already default-on; paranoid: true adds the rest of the bundle on top. Pair this with aube audit in CI so a newly disclosed CVE fails the build instead of silently shipping.

# https://aube.sh/package-manager/lifecycle-scripts.html

Lifecycle scripts ​
Packages can define lifecycle scripts such as preinstall, install, postinstall, and prepare. aube treats root scripts and dependency scripts differently.
Root scripts ​
Root package scripts run during install unless scripts are ignored:
shaube install --ignore-scripts

Dependency scripts ​
Dependency lifecycle scripts follow the pnpm v11 build approval model. Packages must be allowlisted before their install-time scripts run. aube includes a built-in snapshot of pnpm's maintained trusted-dependencies list; an explicit deny rule always overrides the built-in trust.
shaube ignored-builds
aube approve-builds
aube rebuild

Supported policy fields — aube reads all of these at install time:
In aube-workspace.yaml or pnpm-workspace.yaml (pnpm v11's build-review map, and what aube writes to — aube creates aube-workspace.yaml from scratch, but mutates an existing pnpm-workspace.yaml in place):
yamlallowBuilds:
 esbuild: true
 sharp: true
 untrusted-package: false

The old onlyBuiltDependencies and neverBuiltDependencies list keys are still honored as read-only compatibility inputs, but new approvals go into allowBuilds. When install sees an unreviewed dependency build, it adds that package to allowBuilds with false; aube approve-builds flips reviewed entries to true.
In package.json (legacy — still honored as a read source). Every key under pnpm.* is also accepted under aube.*; when both are present for the same key, aube.* wins. Disjoint entries from either namespace merge.
json{
 "aube": {
 "allowBuilds": {
 "esbuild": true,
 "untrusted-package": false
 }
 }
}

Deny rules win over allow rules. Workspace-yaml entries and package.json entries merge; you don't have to migrate a legacy pnpm.allowBuilds to start using aube approve-builds.
Entry keys support a bare package name (matches every version), an exact version pin (esbuild@0.19.0), an exact version union (esbuild@0.19.0 || 0.20.0), or a * wildcard name (@babel/*, *-loader, or bare * for everything). Exact non-registry source keys from pnpm are also honored, such as dep@https://codeload.github.com/example/dep/tar.gz/<sha>. Wildcards can't be combined with a version pin — the point of a version pin is to assert a specific build was audited, and a wildcard defeats that. Semver ranges aren't supported for the same reason.
Jailed dependency builds ​
Build approval controls whether a dependency script may run at all. Jailed builds add a second boundary for approved packages:
yamljailBuilds: true

With jailBuilds enabled, approved dependency preinstall, install, and postinstall scripts run with a scrubbed environment and a temporary HOME. On macOS and Linux, aube also applies a native jail that denies network access and restricts filesystem writes to the package directory and temporary directories.
jailBuilds defaults to false today and is planned to default to true in the next major version.
For packages that need a narrow exception, grant only that privilege:
yamljailBuildPermissions:
 "@vendor/*":
 env:
 - SHARP_DIST_BASE_URL
 write:
 - ~/.cache/sharp

For packages that cannot run in the jail yet, disable the jail for a package glob while keeping the build approval requirement:
yamljailBuildExclusions:
 - "@legacy-native/*"

See Jailed builds for the full profile, supported permissions, and platform behavior.
Git dependencies ​
Git dependencies with prepare scripts get a nested install in the clone before aube snapshots the package. The final linked package uses the packed result, not the raw checkout.
Side effects cache ​
Allowlisted dependency builds can cache their post-build package tree and reuse it on future installs with the same input hash.
Bun comparison ​
Bun also treats dependency scripts as a security boundary and uses an allowlist model through trustedDependencies. aube reads the top-level trustedDependencies array as an additional allow-source alongside pnpm.onlyBuiltDependencies, so bun projects work without rewriting the manifest. pnpm.neverBuiltDependencies still wins when both sides list the same package.

# https://aube.sh/package-manager/jailed-builds.html

Jailed dependency builds ​
Build approval decides whether a dependency script can run. A build jail restricts an approved script's environment, filesystem writes, and network access. The jail is optional and does not replace build review.
Enable it in aube-workspace.yaml or an existing pnpm-workspace.yaml:
yamljailBuilds: true

jailBuilds defaults to false. Root lifecycle scripts are not jailed. See lifecycle scripts for approvals.
Default profile ​
CapabilitymacOS and supported Linux systemsWindows
Filesystem readsUnrestrictedUnrestricted
Filesystem writesPackage directory and jail-owned temporary directoriesNo native restriction
NetworkDeniedNo native restriction
EnvironmentScrubbed allowlistScrubbed allowlist
HOMETemporary jail directoryTemporary jail directory
Current boundary
Filesystem reads are unrestricted. A temporary HOME and scrubbed environment do not prevent a script from reading a known absolute path to a credential file. Windows currently provides environment scrubbing and a temporary home only; aube warns that native filesystem and network enforcement are unavailable.

Grant a specific permission ​
If a reviewed package needs an environment variable, writable cache, or network access, grant that permission while keeping the rest of the jail:
yamljailBuilds: true
jailBuildPermissions:
 sharp:
 env:
 - SHARP_DIST_BASE_URL
 write:
 - ~/.cache/sharp
 network: true

KeyEffect
envInherit the named variables from the parent process
writeAdd paths to the native write allowlist on macOS and Linux
networkPermit network access when true
readReserved for a future read-restricted profile; reads are currently unrestricted
Environment grants can expose secrets, and network: true enables network access rather than a host-specific allowlist. Grant only what the build needs.
Package keys accept bare names, exact name@version pins, exact version unions, and name wildcards such as @scope/*. A bare name applies to every version; use an exact pin when the exception belongs to one reviewed release.
Exclude a package ​
If a reviewed package cannot run with individual permission grants, exclude it:
yamljailBuilds: true
jailBuildExclusions:
 - "legacy-native-addon@1.2.3"

An exclusion disables the jail for that package. It does not approve the build: the package must still pass the active build policy. See jailBuildExclusions.
Native enforcement ​
macOS: a Seatbelt profile, applied through sandbox-exec, restricts writes and network access.
Linux: Landlock write restrictions and a seccomp network filter are applied in the child process. The baseline requires kernel 5.19 or newer with Landlock ABI v2. If the requested jail cannot be enforced, the build fails rather than running without it. Landlock v2 does not restrict truncate() on otherwise read-only paths; that protection requires kernel 6.2 or newer.
Windows: environment scrubbing and a temporary home are applied, with a warning about unavailable native enforcement.
The jail runs below the dependency script runner, so approved builds from install and aube rebuild use the same policy.
Environment policy ​
The scrubbed environment includes values needed for build tools, such as PATH, INIT_CWD, and npm lifecycle metadata. HOME points to a temporary directory. Common credential variables such as NPM_TOKEN, NODE_AUTH_TOKEN, GITHUB_TOKEN, and SSH_AUTH_SOCK are removed unless explicitly granted.
Diagnose a failed build ​
Confirm the package is approved with aube ignored-builds.
Read the failing script and its first error. Identify the missing variable, denied write, or required network access.
Add a package-specific permission and retry aube rebuild.
Commit the policy once the build works on the platforms your project supports.
Read security defaults for the other install protections and configuration for managed organization policy.

# https://aube.sh/trust-policy-exceptions.html

Trust policy downgrades ​
trustPolicy = no-downgrade stops an install when the selected package version has weaker publishing evidence than an earlier release. This is a signal to investigate, not just another version-resolution error.
What the failure means ​
An earlier-published version had npm staged-publish approval, trusted-publisher identity, or provenance metadata that the selected version no longer has. That can indicate a compromised publisher, stolen token, malicious co-maintainer, or a release built outside the repository's expected CI workflow.
A downgrade can also come from a release-process or registry change:
a maintainer manually published a release or backport;
a release shortcut skipped the trusted-publisher or provenance-enabled job;
parallel major-version lines use inconsistent release automation;
a registry proxy or mirror omitted trust metadata.
Compare the package on its source registry with any proxy or mirror before choosing an exception. This distinguishes missing upstream evidence from metadata removed in transit.
What to do before adding an exception ​
Confirm the package name and selected version are the ones you expected.
Compare the npm publish time, publisher identity, source tag, commit, and release notes with the last trusted release.
Inspect the tarball contents and integrity metadata. Look for unexpected files, generated code, install scripts, dependency changes, or other signs that the release was tampered with.
Check the upstream repository and advisories for a compromised account, workflow outage, or intentional manual publish.
Report inconsistent evidence to the relevant upstream owner. Ask the package maintainer to restore a drifted publishing workflow, or ask the registry operator to restore metadata that exists on npmjs.org but is missing from its proxy or mirror.
Do not treat an allowlist entry as proof that a package is safe. It only records that someone chose to bypass this particular signal.
Inspect an exact version without installing it:
shaube trust check package-name@1.2.3

The report shows its publish time and trust evidence, the strongest evidence on an earlier release, and whether a built-in exception applies. Add --ignore-default-excludes to enforce the underlying policy even when aube normally exempts that version, or --json for machine-readable output.
Choosing the narrowest workaround ​
Prefer these options in order:
Pin a release that still carries trust evidence.

After reviewing the release, exempt only the affected version:
yamltrustPolicyExclude:
 - "package-name@1.2.3"

Exempt every version only when the package's release model is inherently inconsistent and you are willing to review future releases without this protection:
yamltrustPolicyExclude:
 - "package-name"

Setting trustPolicy = off disables the check for the entire install and should be a last resort.
Built-in exceptions ​
The following 12 packages are built into aube's default exception list because their published metadata has triggered legitimate no-downgrade failures:
@hono/node-server@1.19.15
@octokit/endpoint
chokidar
eslint-config-prettier
eslint-import-resolver-typescript
react-redux
reselect
semver
ua-parser-js
undici
undici-types
vite
This list is generated directly from DEFAULT_TRUST_POLICY_EXCLUDES at documentation build time, so it cannot drift from the resolver. Inclusion records an accepted exception to the evidence check, not a verdict that a package is malicious or safe.
If a package restores consistent trusted publishing, remove its built-in exception so future regressions are blocked again.

# https://aube.sh/package-manager/security-scanner.html

Security scanner ​
aube ships a drop-in implementation of Bun's Security Scanner API. Point securityScanner at the same npm package you'd put in Bun's bunfig.toml#install.security.scanner and aube loads the module through a node bridge that adapts Bun's in-process plugin contract to a subprocess. The reference scanner template at oven-sh/security-scanner-template and the production scanner at @socketsecurity/bun-security-scanner both run unchanged.
yaml# aube-workspace.yaml
securityScanner: "@acme/bun-security-scanner"
# or a path to a local scanner:
# securityScanner: ./scripts/scanner.mjs

Install a package-based scanner before enabling the setting. The gate runs before fetching project dependencies, so it cannot bootstrap its own scanner package:
shaube add -D @acme/bun-security-scanner

The empty string (the default) disables the integration. Requires Node 22.6+ on PATH.
When the scanner runs ​
Post-resolve, once per command invocation. After the resolver returns a finalized graph and before the fetch / link phase starts, aube extracts every resolved (name, version) pair — root direct deps plus every transitive — and hands the full set to the scanner in one node subprocess call. A fatal advisory aborts before any tarball downloads happen.
The same gate covers aube install and aube add (since aube add runs the install pipeline internally). One node spawn per command invocation, regardless of how many packages are in the graph.
Scoped private packages, file: / link: / workspace siblings, git deps, and remote tarballs are excluded from the payload — public-data scanners have no advisories for those. Aliased entries ({ "my-alias": "npm:real-pkg@^4" }) are reported under the real registry name real-pkg, not the alias.
Authoring a scanner ​
A scanner is a JavaScript (or TypeScript) module that exports a scanner object with a scan({ packages }) function:
tsimport type { Security } from "bun";

export const scanner: Security.Scanner = {
 version: "1",
 async scan({ packages }) {
 const advisories: Security.Advisory[] = [];
 for (const p of packages) {
 // packages[i].name — registry name (alias-resolved)
 // packages[i].version — resolved version, e.g. "4.17.21"
 if (await isMalicious(p.name, p.version)) {
 advisories.push({
 level: "fatal",
 package: p.name,
 description: "Reported as malicious",
 url: `https://example.org/${p.name}`,
 });
 }
 }
 return advisories;
 },
};

The example assumes an isMalicious(name, version) function backed by your scanner's advisory source.
Levels:
fatal — aborts the install with ERR_AUBE_SECURITY_SCANNER_FATAL (exit 48).
warn — emits WARN_AUBE_SECURITY_SCANNER_FINDING and lets the install proceed.
Anything else — logged at debug level and otherwise ignored (future-proof for additional levels).
Return shape: Bun's docs specify the return value is Advisory[]. aube also accepts { advisories: [...] } as a friendly fallback for scanners that wrap their result.
The published @types/bun package ships the canonical Bun.Security.Scanner / Bun.Security.Package / Bun.Security.Advisory types — install it as a dev dep when authoring a TypeScript scanner.
Bun runtime APIs aube shims ​
Real published scanners use a small but specific slice of the Bun runtime. The bridge ships shims so they work unchanged:
Bun APIaube shim
import Bun from 'bun'Resolves to an aube virtual module via a Node module.register() loader hook. globalThis.Bun is also populated.
Bun.envAlias for process.env.
Bun.file(path)Returns an object with .exists(), .text(), .json(), .arrayBuffer(), .bytes().
Bun.write(path, data)Writes a file (supports strings, ArrayBuffer, TypedArray, BunFile-like objects, or anything JSON-serializable).
Bun.semver.satisfies(version, range)Delegates to the project's semver npm package (near-universal transitive dep). Falls back to exact-equality comparison with a one-time stderr warning if semver isn't resolvable.
That surface covers everything the oven-sh template (Bun.semver.satisfies) and the Socket scanner (Bun.env, Bun.file) actually call.
Differences from Bun ​
Requires Node 22.6+ so the bridge can pass --experimental-strip-types to load .ts scanner entrypoints directly (Socket's package, for example, ships raw TypeScript via "exports": "./src/index.ts" with no build step).
Bun-runtime APIs outside the shim — Bun.spawn, Bun.password, Bun.serve, the web framework, the test runner — throw at runtime. The bridge surfaces this as ERR_AUBE_SECURITY_SCANNER_FAILED and the install fails closed (see below).
A fatal advisory on aube add exits non-zero after the manifest may have changed. Inspect git diff -- package.json and remove only the rejected dependency edit if you do not want to keep it.
Failure semantics ​
Fail closed on any scanner failure: node missing on PATH, scanner module unresolvable in node_modules, non-zero exit, 30 second timeout, unparseable JSON output, scanner throws. A configured scanner that can't run is treated as a refusal — silently bypassing on failure would defeat the entire point of opting in.
Escape hatch: set securityScanner = "" to disable the integration. Operators bootstrapping a project (the scanner package isn't in node_modules on first install) or recovering from a broken scanner can unset, complete the install, then re-enable.
Performance ​
The bridge starts one Node process and sends the resolved graph in a single batch. Cost depends on scanner startup and any requests the scanner makes. Warm installs that return before resolution do not run this scanner; do not use it as evidence that an unchanged install was rescanned.
Scanner process boundary ​
The scanner is executable project code. It is not run inside the dependency build jail; only the named environment variables below are removed. Choose and review the scanner accordingly.
The subprocess environment is scrubbed of AUBE_AUTH_TOKEN, NPM_TOKEN, NODE_AUTH_TOKEN, GITHUB_TOKEN, and GH_TOKEN before exec. This removes those values from process.env; it does not restrict filesystem reads or the scanner's other access.
kill_on_drop(true) on the spawn ensures a hung scanner is SIGKILLed at the 30 s timeout instead of leaking as an orphan process.
The scanner module is loaded with the project root as cwd, not aube's working directory. Module resolution from the scanner uses the project's node_modules.
The bridge writes three short .mjs files (the shim, the loader hook, the runner) to a fresh tempfile::TempDir per invocation. The temp dir is cleaned up when the subprocess exits.
Configuring an existing Bun scanner ​
Most Bun-compatible scanners are published as npm packages with a single securityScanner = "<package-name>" line. Some accept extra configuration via environment variables (Socket, for example, reads SOCKET_SECURITY_API_KEY from Bun.env). Set those in the parent shell environment — aube's bridge passes process.env through (minus the token scrub list above).
shexport SOCKET_SECURITY_API_KEY="…"
aube install # scanner sees SOCKET_SECURITY_API_KEY via Bun.env

Related settings ​
securityScanner — the module spec.
paranoid — does not currently enable a default scanner. If you want a scanner running in CI, configure it explicitly.
Related codes ​
ERR_AUBE_SECURITY_SCANNER_FATAL (exit 48) — scanner returned a fatal advisory.
ERR_AUBE_SECURITY_SCANNER_FAILED — scanner couldn't run (fail-closed contract).
WARN_AUBE_SECURITY_SCANNER_FINDING — scanner returned a warn-level advisory.

# https://aube.sh/package-manager/lockfiles.html

Lockfiles ​
aube's default lockfile for new projects is aube-lock.yaml. For projects that already have a different supported lockfile, aube keeps reading and writing that file in place.
Supported lockfile formats ​
aube reads and writes all of the following formats:
FileSupported formatBefore switching
aube-lock.yamlaube's native YAML formatDefault for a new project
pnpm-lock.yamlv9Upgrade v5/v6 lockfiles with pnpm first
package-lock.jsonv2 and v3Keep the file in place
npm-shrinkwrap.jsonnpm shrinkwrapTakes precedence over package-lock.json
yarn.lockClassic v1 and Berry v2+PnP projects need a node_modules linker
bun.lockText format v1Convert binary bun.lockb with Bun first
Write behavior ​
On install (and on add, remove, update, dedupe), aube picks the lockfile to write from whichever supported file already exists in the project directory. Precedence is: aube-lock.yaml → pnpm-lock.yaml → bun.lock → yarn.lock → npm-shrinkwrap.json → package-lock.json. When none of those exist yet, aube writes aube-lock.yaml by default; default-lockfile-format can select pnpm-lock.yaml.
For example:
A pnpm project keeps getting pnpm-lock.yaml updates.
An npm project keeps getting package-lock.json updates.
aube import switches a project onto aube-lock.yaml; removing the existing lockfile makes the next install follow the configured default.
To create pnpm-lock.yaml when a project has no lockfile yet, set the creation default in .npmrc:
inidefault-lockfile-format=pnpm

This also preserves the pnpm filename after aube clean --lockfile followed by aube install. The setting does not convert an existing lockfile; the existing supported file still wins.
Keep one canonical lockfile while both tools are in use. Review lockfile diffs as you would with the original package manager; preserving the format does not prevent merge conflicts or guarantee identical version selection.
Convert intentionally ​
aube import reads an existing supported lockfile and writes aube-lock.yaml. Use it only when you want to change formats. The new file takes precedence; retire the previous lockfile once all workflows use the new one.
Frozen installs ​
shaube install --frozen-lockfile
aube ci

Frozen mode fails when the lockfile no longer matches the manifest.
Prefer frozen installs ​
shaube install --prefer-frozen-lockfile

This is the local default. aube uses the lockfile if it is fresh and re-resolves when the manifest changed.
Lockfile-only updates ​
shaube install --lockfile-only

Use this when CI or automation needs to update dependency metadata without touching node_modules.
Runtime pins ​
When package.json pins Node through devEngines.runtime, the resolved exact version (plus per-platform download URLs and SHA-256 checksums) is recorded in the lockfile using pnpm 10.14+'s node@runtime: entry shape — a synthetic dep on the root importer and a packages: entry with a variations resolution. aube and pnpm read each other's pins. Formats without a runtime shape (npm / yarn / bun) skip the pin and re-resolve the range at run time. See Node runtime switching.
Branch lockfiles ​
When gitBranchLockfile is enabled, aube writes branch-specific lockfile names such as aube-lock.<branch>.yaml. Use this for long-running branches that produce frequent lockfile conflicts.

# https://aube.sh/cli/find-hash.html

aube find-hash ​
Usage: aube find-hash [FLAGS] <HASH>
Effect: read-only
List packages whose cached index references a given file hash
Read the workflow guide for context. Global options apply to this command too.
Arguments ​
<HASH> — Hash to look up.
Accepts sha512-<base64> (pnpm integrity format) or a raw hex CAS digest.

Flags ​
--json — Emit machine-readable JSON instead of a plain text listing.
Output is an array of { "name", "version", "path" } objects.

-h --help — Print help

Network ​
--fetch-retries <N> — Number of retry attempts for failed registry fetches.
Overrides fetchRetries / fetch-retries from .npmrc / aube-workspace.yaml when set. Pair with --fetch-timeout to fail fast in scripted test runs.

--fetch-retry-factor <N> — Exponential backoff factor between retry attempts.
Overrides fetchRetryFactor / fetch-retry-factor from .npmrc / aube-workspace.yaml when set. Integer-only; fractional values like 1.5 are rejected.

--fetch-retry-maxtimeout <MS> — Upper bound (ms) on the computed retry backoff.
Overrides fetchRetryMaxtimeout / fetch-retry-maxtimeout from .npmrc / aube-workspace.yaml when set.

--fetch-retry-mintimeout <MS> — Lower bound (ms) on the computed retry backoff.
Overrides fetchRetryMintimeout / fetch-retry-mintimeout from .npmrc / aube-workspace.yaml when set.

--fetch-timeout <MS> — Per-request HTTP timeout in milliseconds.
Overrides fetchTimeout / fetch-timeout from .npmrc / aube-workspace.yaml when set. Covers the whole request (headers and body together).

--registry <URL> — Override the default registry URL for this invocation.
Use this npm registry URL for package metadata, tarballs, audit requests, dist-tags, and registry writes.
