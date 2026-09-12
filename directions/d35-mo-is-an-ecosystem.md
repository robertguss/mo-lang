---
title: "Direction 35: Mo is an ecosystem; first-party batteries you own"
created: 2026-09-12
updated: 2026-09-12
type: direction
tags: [stdlib, security, philosophy]
sources: [research/concepts/supply-chain-defenses.md]
number: 35
status: liked
origin: "Robert (session 3)"
confidence: medium
---

# Direction 35: Mo is an ecosystem; first-party batteries you own

Robert (session 3): the inspiration is the Laravel ecosystem, where "Taylor and his team create all the packages and things developers need." So "Mo is more than just a programming language, it is an ecosystem, and the majority of the tools and things you are going to need are going to be created and built by us and the community and should be the defaults and your first choice, because everything is vetted and built by us," which "should hopefully prevent the whole supply chain attacks and also save you on tokens."

The second model is Phoenix's `mix phx.gen.auth` and shadcn: a feature ships as source files you then own and customize, "rather than just a package you install." AI "makes ownership and maintenance burden trivial." The goal: "have software engineers rely less and less upon the outside world."

## The three shelves (Claude's rendering)

1. **Bricks:** the stdlib and platform. Shared code, first-party, audited once. The only code that is not yours.
2. **Kits:** first-party features that install as source you own, Phoenix-auth style (auth, sessions, background jobs, an admin surface). A kit is a [[d34-packages-are-recipes|recipe]] that carries full reference bodies from a trusted publisher; the agent copies them rather than regenerating, which saves tokens, and they are compiled and capability-checked as your code.
3. **Recipes:** community booklets, spec only or with example bodies; the agent implements them.

Source-code packages from outside remain the last resort, under [[q17-package-management-and-supply-chain|Q17]].

One mechanism serves shelves 2 and 3: a recipe with bodies. Trust in the publisher decides whether the agent copies the bodies or treats them as examples. **Robert: in** (session 3) on this unification: one format, one registry, one set of rules, and the trust tier is the only dial.

## Related
- [[d34-packages-are-recipes]]
- [[q11-platform-and-stdlib]]
- [[d30-supply-chain-security]]
- [[q17-package-management-and-supply-chain]]
