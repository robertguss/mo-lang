# 6. Packages

Packages were built by humans for humans, to avoid rewriting what someone else already wrote. Agents change the economics: writing and maintaining code is cheap, and every incident in the 2024–26 supply-chain record was someone else's code executing on your machine. Mo's package system is designed from that premise.

## Three shelves

1. **Bricks.** The standard library and the platform. First-party, audited once, the only code in a Mo program that is not yours. The box is big on purpose: collections, strings, JSON, regex, time, HTTP client and server, crypto, TLS, compression, Unicode, and database drivers. The rule for what is a brick: if a bug in it is a security or data-loss event, it is first-party code.
2. **Kits.** First-party features that install as source you own, the way Phoenix generates auth or shadcn installs a component: auth, sessions, background jobs, an admin surface. Vetted by the Mo team, copied into your repo, then yours to change. Agents make ownership cheap.
3. **Recipes.** Community packages that share intent, not code. A recipe is the spec altitude of a module and nothing below it:

```ruby
recipe RateLimiter
  intent "Token bucket per client; refills from the clock; never blocks"
  needs Clock
  pub fn allow?(l: Limiter, id: ClientId, now: Time) : (Limiter, Bool)
    ensures result.0.tokens(id) <= l.capacity
  end
  test "refills at the declared rate" ... end
  rejects "a burst beyond capacity" ... end
end
```

Your agent implements the bodies in your repo from the bricks. The compiler checks the result against the recipe: shape, tests, and that its capabilities stay under `needs`. It is then your code, and no dependency exists.

Kits and recipes are one mechanism. A recipe may carry full reference bodies. When the publisher is first-party, the agent copies them, which keeps behavior identical across projects and saves tokens. When the publisher is the community, the bodies are examples and the agent regenerates. Either way the code is compiled and capability-checked as yours.

Source-code packages from outside remain allowed as the last resort. They show their computed capability manifest at install and live under the registry rules below.

## The registry

Six layers, no new syntax:

1. **Language.** No install scripts, macros, or build-time code. Capabilities are the permission system, and effects never hide in a value. Platforms are the entire trusted base: the lockfile records each platform's native-code hash, and `mo` refuses an unaudited platform without a human's `--trust`.
2. **Identity.** A package version is a set of declaration hashes, pinned in the lockfile. The registry serves bytes that must match, and every version goes into a transparency log. Source only, never binaries.
3. **Publishing.** One central registry. A WebAuthn key is required; no token type can publish alone; CI publishes only through short-lived identity, with a second signer for widely used packages. Trust evidence is monotone across versions: the registry refuses a publish with weaker evidence than the last.
4. **Age gates.** Versions younger than 3 days and names younger than 30 days are refused by default. `mo update` falls back to the newest old-enough version. Overrides need a human, never an agent.
5. **The install conversation.** `mo add` prints the computed manifest. A capability widening on update is a breaking change that pulls a human in, the same rule as `never`. Four reputation signals served by the registry: known-malicious, similar name (namespace-aware), low use, new name. Every "ask the human" is a hard fail for an agent.
6. **Offline and incident response.** A signed revocation bloom filter checks plain rebuilds cheaply. `mo find-hash` lists every package version containing a given declaration hash. No dependency bypasses the registry except an in-repo path.

Each check has a documented boundary (fail, warn, or opt-in) and a stable error code in the catalog.

## The norm

Copy a function rather than add a dependency. Build your own rather than import. The stdlib and kits are the first choice, recipes the second, outside code the last. The goal is for software to rely less and less on the outside world.
