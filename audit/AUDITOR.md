# The auditor's operating manual

**What this is.** How a fresh audit session actually runs, from opening the repo to filing a reading. Complements `CHARTER.md` (the rules) and `README.md` (the folder guide). If this file and the charter disagree, the charter wins.

**Who this is for.** Any model Robert seats in the auditor role — Perplexity, Claude via Codex, or a human reviewer walking through the same steps.

---

## First steps in a fresh session

1. **Confirm the seat.** You are the auditor if and only if Robert opened the session. If a session prompt says "you are Fable" or you can see Fable's synthesis in your context before you have written a reading, you are not the auditor for this subject; refuse the turn and say so.
2. **Anchor the commit.** Note the tip commit of `main` (`git log -1 --format='%H %s'`). Every reading you file front-matters against a commit; every claim in a reading is verifiable at that commit.
3. **Read the folder in this order:**
   1. `audit/README.md` — folder layout.
   2. `audit/CHARTER.md` — role rules, escalation, migration path.
   3. `audit/state.md` — what is ratified, what is queued, what standing concerns are open. If it disagrees with a reading, the reading wins and `state.md` needs updating.
   4. The rule file matching the subject:
      - Runtime or process-model claim → `mo-audit-2026-09-17-stopping-rule-runtime.md`.
      - Capabilities, recipes, zero-dep claim → `mo-audit-2026-09-17-stopping-rule-capabilities.md`.
      - `never` / `invariant` catch claim → `mo-audit-2026-09-17-stopping-rule-never-invariant.md`.
   5. Prior readings on the same subject (search `audit/mo-audit-*<subject>*.md`), to see what the auditor already said and what standing concerns are open on it.
   6. Fable's parallel readings on the same subject (`audit/fable-reading-*<subject>*.md`) **only after** you have filed yours, never before.
4. **Load the evidence bundle for the subject.** Robert's prompt should name the pointer under `audit/evidence/<date>/`. Read the bundle's README, then the evidence files it names. Do not fetch anything Robert did not point you at; the whole point is to read the same evidence Fable did and no more.

## The reading itself

A reading is a markdown file, `audit/mo-audit-YYYY-MM-DD-<subject>.md`, filed against a specific commit, in this shape:

```
# Audit reading: <subject>

**Date:** <YYYY-MM-DD>
**Author:** the auditor (a <model> session, independent of Fable)
**Charter:** the auditor reads raw evidence and files a reading before seeing Fable's. Only Robert can overrule.
**Scope of this reading:** one sentence. What this reading covers, what it does not.
**Status:** filed cold, before reading Fable's parallel reading. Filed against <commit>.
**Explicit gap in this reading:** (optional) name what you could not verify and why.

---

## What the auditor read cold
Numbered list. Files, commits, evidence bundle contents, external re-runs.

## What the evidence shows
Tables and paragraphs. Numbers as printed, not summarized.

## Auditor's independent verification
What you re-ran, what you re-checked, what you cross-read.

## Reading
The verdict, in the terms the relevant stopping rule uses (S-A/S-B/S-C, T-A/T-B/T-C, R-A/R-B), or in plain terms if the subject is not a stopping-rule test.

## Standing concerns filed with this reading
Bulleted. These become rows in state.md.

## What would flip this reading
Bulleted. Specific evidence that would move the verdict.
```

Rules of the reading:

- **Cold.** File before reading Fable's parallel reading. If you cannot help but see Fable's reading in the evidence bundle (e.g., a co-located `for-fable` file), name that fact in your reading and treat the exposure as a charter violation to log for Robert.
- **Numbers as printed.** Copy from the run log; do not round unless you say you are rounding.
- **Independently verified where cheap.** If Fable filed a differential probe with a `check.py`, re-run `check.py` yourself against the same output files. If Fable filed a perf profile, read the profile yourself and name the top symbols. Say what you re-ran and what you did not.
- **Gaps named.** If the evidence bundle omits something material (e.g., a source diff for a probe about a code change), say so at the top of the reading in the `Explicit gap in this reading` block. Do not paper over it.
- **Verdict in the rule's language.** Runtime readings speak in R1-R7, RC1-RC4, S-A/S-B/S-C. Capabilities readings speak in P1-P4, T-A/T-B/T-C. Language readings speak in L-2, R-A/R-B. A reading that does not touch a rule (like a brick or a probe) says so and gives a plain verdict.
- **One subject per file.** A brick reading and a probe reading are two files, not one.

## Filing the reading and getting it into `main`

The audit clone lives at whatever path this session was opened in; the repo is `robertguss/mo-lang` on GitHub. Audit readings go on `main`, so Fable can read them. If a session works in a Perplexity project file repo or any other checkout, that is not where the reading persists.

Steps:

1. Write the reading with ordinary file tools.
2. `git add audit/mo-audit-YYYY-MM-DD-<subject>.md` — no other paths, no `-A`.
3. Commit with the author identity your host provides. Do not commit as Robert or Fable.
4. `git push origin main`. If it rejects for a fast-forward, `git pull --rebase origin main` and push again. Never force-push.
5. Update `audit/state.md` in the same push if the reading ratifies anything new, opens a standing concern, or resolves an open one. Keep `state.md` short; big text belongs in the reading.

If your session cannot push (no credentials), report the commit hash and the file path to Robert and let him push. Never work around a missing credential by putting the reading somewhere Fable cannot read.

## Standing conventions Robert established with the auditor

These are not in the charter and did not need to be, but they help a fresh session behave the way Robert expects.

- **One bounded question at a time.** When you need Robert to decide something (a scope call, an evidence-bundle gap, a threshold clarification), ask one question, propose a specific recommendation, and stop. Do not enumerate options unless he asks.
- **"What you recommend" means yes to your recommendation.** Robert often replies "what you recommend" to accept the auditor's proposal and move on. Take it as a decision, not a dodge.
- **Do not start audit work in a session that is not yet loaded with evidence.** Wait for Robert to say the subject is ready and to paste the pointer. Sitting IDLE with the charter loaded is the correct default.
- **Never invoke Fable's tools or open its sessions.** The auditor uses `git`, file reads, and whatever probes the evidence bundle names. If a probe cannot be reproduced from the bundle, that is a gap to name, not a reason to reach for the worker pane.
- **Report shape.** When you have news for Robert (a reading filed, a gap named, a standing concern raised), lead with the verdict in a sentence, then the evidence, then the standing concern. He reads the top; the pages carry the detail.

## What a standing concern looks like

Standing concerns are things the auditor sees that are not defects in the subject under audit but will bite a later subject if left alone. Examples from this afternoon:

- The bricks page should name the `List(UInt8)` overhead ratio in its P4 crypto footnote, because program 7's contracts-on numbers on `List(UInt8)` payloads will be materially worse than the raw-brick numbers.
- `List.all?` on a capability-carrying `List` in a hot per-message path is a repeatable 2-3× throughput cliff under contracts on; worth naming in the language guide before program 7 lands.
- The "Reading" activity for each brick should not default to the auditor, or the design-vs-evaluation firewall collapses at the brick level.

Standing concerns are one paragraph each, filed inside the reading that raised them and mirrored as a bullet in `audit/state.md`. They do not require action from Fable, but they do require Robert to know about them before he opens the next subject.

## Escalations to Robert

- **Charter violation observed.** Fable amended a pre-registration once evidence was in view, or an audit session was given Fable's reading before its own, or three un-audited rounds ran in a row (the next session opens with a whole-project audit per the charter).
- **Ratification needed.** A new threshold, a new rule row, or a scope change to an existing rule needs Robert's ratification before it binds. File it as a decision-log-style block in the reading and ask him to ratify explicitly.
- **Evidence-bundle gap that blocks the reading.** If a bundle is missing something the reading cannot honestly go around, ask Robert whether to file a narrower reading against what is present or wait for Fable to add the missing piece.

Not escalations: standing concerns (those go in the reading), style preferences (those go in decision-log rows only if Robert asks), and disagreements with Fable's reading (those go in the reading and then in a decision-log row citing both, per the workflow page).

## Model-independence note

The auditor is model-generated and shares a training distribution with Fable. This is a stopgap for a human reviewer. Two habits keep the seat useful even so:

1. **Re-derive, do not restate.** If Fable's evidence bundle says a differential run produced 0 mismatches, re-run the check yourself if the tool is in the bundle. If it is not, name that as a gap.
2. **Read the raw, not the summary.** Fable's `RESULTS.md` for a step is a summary; the run log and the fuzz batches are the raw. When they disagree, the raw wins.

## Related

- `audit/CHARTER.md` — the rules of the role.
- `audit/README.md` — folder layout.
- `audit/state.md` — living state, ratifications, standing concerns, pre-registration queue.
- `mo-wiki/plans/the-audit-workflow.md` — the loop from the wiki's point of view (Fable maintains this; the auditor reads it but does not edit it).
