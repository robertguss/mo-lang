---
title: "The state of the project"
created: 2026-09-16
updated: 2026-09-16
type: synthesis
tags: [roadmap, research, thesis]
sources:
  [
    spec/design-v0/01-premise.md,
    spec/design-v0/08-milestone.md,
    plans/roadmap.md,
    decisions/decision-log.md,
    CHANGELOG.md,
  ]
status: living
---

# The state of the project

The forest, not the trees. This page is the lead's standing account of the whole
Mo project: where it came from, what it claims, what has been tested, what
turned out right and wrong, and what is left. It is rewritten at every pause;
the date at the top is the last one. The trees are one link away: the maps under
[[the-thesis-and-its-evidence|maps]] gather the pages behind each sentence
here, and the [[roadmap]] table is the authority on order.

**Last rewritten:** 16 Sep 2026, the morning after the first night on Robert's
Mac. Four and a half days since the first commit.

## In one paragraph

Mo is a programming language for a world where agents write nearly all the code
and people read only the parts that state intent. It was started on 12 Sep 2026
by Robert Guss and Claude, designed in a day, given a working toolchain in the
next, and then put under a measuring regime that has not let up: ten control
rounds against Go, Python, and Elixir, two of five planned measurements, two
generations of a maintenance experiment, and two outside reviews. The thesis
survived being restated once, on the review of 14 Sep, and the restated form is
what is being tested now: **software written by agents can be reliable and need
no third-party code, and a runtime and process model built for that, with
capabilities and recipes on top and the language as their surface, delivers
it.** The claim under test is a conjunction, reliability at zero dependencies.
So far Mo holds the reliability column and the feedback loop against every
baseline, holds the dependency column by construction, has lost the speed column
to Elixir and the runtime's own restart row to the BEAM, and has not yet shown
that its laws catch a bug an agent's own tests would miss. That last sentence is
the one the project turns on.

## Where it came from

**Sessions 1 to 4, 12 Sep.** A wiki of 35 directions, 17 questions, 15 syntax
picks, and 13 language comparisons, then an eight-chapter design in prose
(`spec/design-v0/`) and a grammar. The premise at the time: agents write the
code, humans read the spec altitude, the compiler is the teacher, and every
third-party package is code nobody read. Syntax: Elixir-shaped under Ruby's
taste, `end`-closed blocks, one formatter answer, no classes, immutable values,
capabilities as parameters, contracts and `never` clauses in the source.

**Session 5, 12 to 13 Sep, about twenty hours.** The design met a compiler. In
four worker steps an Opus session built a lexer, a parser, a type and law
checker, a bytecode VM with contracts and tests, and a simulator with seeds and
faults; the interpreter milestone (chapter 8) was met the same day. Then a
formatter, `mo run` with a platform, a standard library of 118 rows, `Net` and
`Http`, a C backend giving static binaries, and processes in both runtimes. The
first real programs, a log analyzer and a key-value store, found the toolchain's
bugs and the stdlib's gaps, and the first control runs began: the same spec
written in Go and Python by the same model, timed. Mo took two to three times
longer to write and cost more loops, almost all of them the language's own
grammar and laws.

**Session 6, 13 to 15 Sep.** Programs 1, 4, 5, and 6 (a durable job queue, a
notes service, an agent harness, a double-entry ledger), each finding two to
four toolchain bugs and several gaps, each followed by a step that closed them:
the derived deadline, the runtime surface as a capability, processes as green
threads, delayed sends, handles in state, writes in place, a `never` that reads
values at rest. Rounds 3 to 6 kept measuring agent time and loops, and round 6
failed on all four of its predictions. Two outside reviews (13 and 14 Sep) and
the research agenda's seventeen "contradicts Mo" ideas were each answered on a
page. On 14 Sep Robert restated the thesis: agent time was never the point,
since no model has seen Mo; the runtime and the process model come first,
capabilities and recipes second, the language third; and the measure from round
7 on is reliability under a hidden defect suite, native speed and memory, the
feedback loop, and the dependency count. The counted shape laws became project
settings in principle. Round 7 was the first round on that measure, and it held
on all four.

**Session 7, the night of 15 to 16 Sep, on the VM.** Steps 29 to 30 made the
runtime honest (a `:never` child stays down, replay memory bounded on a real
million-entry log, a scheduler per core). Round 8, the maintenance round, handed
the finished queues to fresh agents with a changed spec: held on all five
predictions, and its fourth oracle found an outage in the Mo program. Round 10
put the BEAM in a pane at last. Measurements 1 and 2 of direction 43 ran on five
of six programs.

**Session 8, the night of 15 to 16 Sep, on the Mac.** The scaling run, P6 on
Elixir, chapter 10 (the language after the rounds) and its first change built as
step 31, the sixth program's regeneration, round 9 with four smaller models, and
generation two of the erosion round. The wiki became a site, and the same
morning round 9's last row, Haiku 4.5, ran, and P6 was probed on Mo's change 2
program: the crash under load answers `503` within milliseconds and loses
nothing, and the restart is the program's to write, not the language's.

## What Mo is, today

- **A toolchain of about 39,000 lines of Zig and 10,500 of C**: `mo check`,
  `mo test` (contracts, properties, a seeded simulator with fault injection),
  `mo run`, `mo build` to a static binary, `mo fmt`, `mo fix`, a runtime surface
  over HTTP, 60-odd diagnostics that say what to write. A cold full test of the
  toolchain is ten minutes on the VM and two warm on the Mac.
- **A corpus of 175 Mo files**: 50-odd single-construct files, the standard
  library's tests, and six programs of 769 to 4,551 lines (a log analyzer, a job
  queue, a key-value store, a notes service, an agent harness, a ledger), every
  one with a spec page, transcripts checked byte for byte, and a hidden test
  suite or a session of the lead's own probes.
- **A wiki of 460 pages**, of which this is one: 43 directions, 18 questions, 22
  spec pages, 73 plans, 30 deep dives, 54 research pages, 190 raw sources, a
  decision log of 418 rows, and a changelog.
- **Forty-eight worktrees beside the repo**, one per control-run session, kept
  as evidence and never merged.

## The thesis, and the hypotheses under it

Chapter 1 states three layers and what each is expected to carry.

1. **The runtime and the process model carry reliability.** Isolated processes
   as state machines, supervised; a failure model that says what a crash
   discards, what a timeout leaves, what a restart loses; a deadline on every
   wait, a bound on every mailbox; structured runtime events and a queryable
   surface.
2. **Capabilities and recipes carry zero dependencies.** Authority is a
   parameter; nothing enters a program that `main` did not hand it; a package is
   a recipe (a spec with tests whose bodies an agent generates and checks) or an
   audited brick.
3. **The language is the surface** that makes the first two visible in the
   source: contracts, `never` clauses, invariants, the `verified:` line. A law
   belongs in the language only when it removes a class of bug.

The **null hypothesis**, named in chapter 1 and now run: the BEAM with Elixir
already gives most of layer 1, and Mo's delta (static types at every boundary,
unforgeable capabilities, a deadline on every wait, one static binary, no
ecosystem to trust) does not justify a new language. The **language layer's own
null hypothesis**: agents do as well in a familiar language with Mo's checks
bolted on.

The **measure** (chapter 8, restated 14 Sep): predicted in this order,
reliability under a hidden adversarial suite, native speed and memory against Go
and Python, the loop from an edit to a verdict, the dependency count; recorded
and never predicted, agent time and loops; since round 8, tokens read per
correct change and first-fix rate per diagnostic.

Direction 43 added **five measurements** of the parts the rounds do not reach:
bodies as cache (are function bodies regenerable from the spec altitude?),
sampling as verification, the erosion round (ten changes by fresh maintainers,
does quality hold?), the incident round, and the two diagnostic columns.

## What has been tested, and how it came out

| claim                                                     | how it was tested                                                                                         | what happened                                                                                                                                                                                                                                                                                                                               | standing                                                                                                                                                                 |
| --------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Reliability under a hidden defect suite                   | rounds 7 and 8 (Mo, Go, Python), round 10 (Elixir), round 9 (four smaller models), erosion generation two | Mo 0 defects in rounds 7 and 8 where Go had 1 and Elixir 2; in round 9 the two open-weights models' Mo changes carried 1 and 2 defect causes (Go 1 for every cloud model, Python 0) and Haiku 4.5's change was wrong in every language (Mo 28 checks over 4 causes, Go 22 over 6, Python 18 over 2); in generation two Mo 1, Go 0, Python 1, Elixir 3                                                                                                                   | **held for the frontier models, thinly**: Mo is never worse than Go by more than one, and the one defect it carries in the newest rows is shared with Python; below them, at Haiku's size, every language fails and Mo fails most by check count |
| Zero dependencies                                         | every round's dependency count                                                                            | Mo 0 packages and 0 tools by construction; Go 1 tool; Python 1 package and 2 tools; Elixir 0 at run time, 3 tools                                                                                                                                                                                                                           | **held, with a tie**: Elixir ties the run-time column, which chapter 1 says refutes the reliability claim only if Elixir is also as reliable; it was not (2 causes to 0) |
| The feedback loop                                         | check-and-test time over the finished program, every round                                                | Mo 0.4 to 0.8 s; Go 14 s (0.25 warm); Python 7 to 9 s; Elixir 7 s                                                                                                                                                                                                                                                                           | **held every time**, the clearest win                                                                                                                                    |
| Native speed and memory                                   | rounds 7 and 8, round 10, the Mac scaling run                                                             | Mo's binary 1,420 lease-and-ack pairs a second on the VM's disk against Go's 428 and Python's 325 at 32 workers, from the fsync pool; Elixir 2,870, twice Mo; one core on the Mac 2,908 and every added core slower; the ledger doubled from the fsync pool                                                                                 | **mixed**: ahead of Go and Python at concurrency, behind at one client, behind Elixir, and nothing scales across cores yet                                               |
| A crashed process with the service still answering (P6)   | round 8's outage, P6 on Elixir with kills and with a full disk, generation two                            | Mo's spec-as-written queue stopped answering when its queue process crashed (a wait hidden as a message pattern); Elixir's supervisor restored service in under 600 ms three times, and exits on the fourth kill inside two seconds or on a full disk; Mo's generation-two program answers through a full disk and now asks with a deadline | **the BEAM's row today**, with the counter-probe on Mo's change 2 program still to run                                                                                   |
| The laws catch what tests miss                            | every round's loop log read for a check that caught a change-induced bug                                  | none, in any language, in ten rounds and nine round-9 sessions; one `never` cost two loops as a false positive; round 3 had one real bug caught by a test and a `never` together                                                                                                                                                            | **not shown**; the biggest open risk                                                                                                                                     |
| Bodies are cache (measurement 1)                          | six programs regenerated twice from intent, types, signatures with contracts, and tests                   | twelve of twelve at completeness 1.0, in 11 to 47 minutes; with the tests deleted too, logstat at 1.0 under its transcripts and 0.74 under its original tests                                                                                                                                                                               | **held**, and it located where the spec's open choices live: in the tests                                                                                                |
| Sampling as verification (measurement 2)                  | five regenerations of the queue's board compared over 132,000 operations                                  | identical, except on one impossible record a random driver never sends                                                                                                                                                                                                                                                                      | **held for a spec'd module**; directed inputs from the maintainers' own decisions find what random ones do not                                                           |
| Quality holds across maintainers (erosion, measurement 3) | generation one (round 8) and generation two                                                               | nothing eroded in Mo, Go, or Python on the old suites; Elixir eroded (a torn line refused at open); the new behaviour within one defect across all four                                                                                                                                                                                     | **too early**: the ten-generation prediction (Go and Python at least three defects, Mo at most one) is alive but unsupported after two                                   |
| Reliability moves with the model (round 9)                | round 8's change by kimi-k3, deepseek-v4-flash, gpt-5.5, Haiku 4.5, and a local 27B                       | for the cloud models it moved on the Mo side only, and the diagnostics carried them to green (first fix right in 21 of 23 loops); gpt-5.5 matched Opus in 14 minutes; Haiku 4.5 was wrong in every language in under ten minutes, most in Mo by checks (28, 22, 18), least by cause in Python (4, 6, 2); the local 27B made no edit in any language | **held**; for the cloud models the language teaches without the laws catching; at Haiku's size the language does not change whether the change is right, only which checks are missing |
| Agent time                                                | rounds 1 to 6, recorded since                                                                             | Mo 1.3 to 2.5 times Go's time and two to five times its loops, nearly all loops the grammar's and the laws'                                                                                                                                                                                                                                 | **recorded, not a prediction**: the unfamiliarity tax is real and unmeasured against the value                                                                           |

## Where we were wrong

- **Agent time was the wrong measure for four rounds.** Rounds 1 to 6 timed
  agents writing a language none had seen and read the result as the language's
  cost. The restatement of 14 Sep fixed the measure; the tax is still real, and
  direction 43 names the experiment that would size it (the same agent writing
  the same program twice).
- **Round 6 failed on all four predictions**, and the laws it cost loops on (the
  500-line file law, keywords as names, a `never` on a `var` copy) were removed
  or loosened by step 27. The counted shape laws are settings now, not laws,
  though chapter 2 still lists them as laws and a step owes the edit.
- **Two of three derived deadlines in program 1 were wrong when written by
  hand**, which is how the derived deadline (`reply_by`, step 22) came to exist.
- **The runtime was not honest about `restart: :never`** until program 6 found
  it restarting anyway (step 29), and replay memory was unbounded on a real log
  until step 29b.
- **Round 8's outage was Mo's**: the queue answered its workers by a send and a
  message back, a wait no law bounds, and when the queue crashed every
  connection hung. Chapter 10 §1 and step 31 (a deferred reply that keeps the
  ask's deadline) are the answer, used by the next maintainer the first time it
  was offered.
- **Cores do not help on the Mac.** Step 30's placement is by fewest live
  processes and every cross-scheduler ask pays a hop; on the M3 Max every row is
  fastest at one core.
- **Two predictions of the erosion round were wrong in Mo's favour**: Go and
  Python already answer through a full disk as Mo does, and Go's change 2 was
  one defect cleaner than Mo's.
- **The lead swept a worker's staged files into two commits** on 16 Sep; the
  rule is now to commit by path.

## Where we were right

- **The spec altitude is real.** Twelve regenerations from intent, types,
  signatures with contracts, and tests, all at 1.0. A reader who reads what the
  language says a reader should read has enough to rebuild the program.
- **Reliability at zero dependencies has survived every round on the frontier
  models.** Mo has never had more defects than Go under a hidden suite, and has
  never needed a package or a tool.
- **The loop is under a second**, and every baseline's is seconds to tens of
  seconds.
- **The runtime's numbers held up under measurement**: 65,530 idle connections,
  200,000 short-lived processes, a million-entry replay at the book's own size,
  a kill under load losing nothing in five of five.
- **The diagnostics teach.** First-fix rates above 0.9 for every diagnostic with
  more than a handful of sightings, across Opus and three smaller models in a
  language none had seen.
- **Pre-registration and hidden suites kept us honest.** Every prediction is on
  its page before the sessions start, every suite is written after the
  branching, and the findings that mattered (the outage, the torn line, the
  shared scheduling miss, the full-disk death) came from inputs no suite sent
  until the lead wrote one.

## What is still to test, measure, and verify

1. **The laws' value for the second agent.** No check has caught a
   change-induced bug in any language. The erosion round's later generations,
   changes 3 to 10, are where a law either earns a row or is removed. The check
   that would have caught round 9's shared miss is a program `never`, which
   points at the spec, not the language.
2. **The reopening store, change 3**: P6 on Mo's change 2 closed round 8's
   outage (`503` within 2 ms, nothing lost) and showed the restart is writable
   today, since a restarted process re-runs its state initializers; change 3
   asks the four programs for it, and the BEAM's P6 row is answered or not.
3. **Placement**: a process placed with its asker or a reply answered on the
   asker's scheduler, so the Mac's fourteen cores stop costing.
4. **Round 9's Opus-in-Pi baseline**, so the harness is the same in every row,
   when Pi has an Anthropic key.
5. **Chapter 10's other sections**: the restart budget as a diagnostic, the
   counted laws into `mo.toml`, MO0317 naming the changed module.
6. **The unfamiliarity tax**, sized: the same agent writing the same program
   twice.
7. **Program 7**, a real open-source service reimplemented against its own
   tests, the first program built on capabilities, recipes, and the runtime
   surface together, and the one chapter 1 says answers the BEAM.
8. **The bricks page**, the compile benchmark at 5,000 modules, `mo prove`, the
   package registry, and the toolchain in Mo, in that order and all later.

## Rows waiting on Robert

In the decision log, marked "for Robert": the outage row (program or runtime);
the BEAM row after round 10 and P6; chapter 10 §1 as built; measurement 1's
completeness row; the erosion round's reading; round 9's reading; whether the
ledger pages its history; the 16 lint issues from his history bundle.

## Related

- [[roadmap]]
- [[the-thesis-and-its-evidence]]
- [[the-rounds]]
- [[the-language]]
- [[the-runtime]]
- [[the-programs]]
- [[for-robert]]
- [[how-we-work]]
- [[decision-log]]
