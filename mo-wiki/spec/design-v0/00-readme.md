# Mo design, v0

**Status:** draft, 12 Sep 2026, session 3; reviewed chapter by chapter by Robert in sessions 4 and 5. Amended since with dated notes at each chapter's foot as the steps and rounds landed; what is locked is a row in `decisions/decision-log.md`, and the whole picture is `state-of-the-project.md`. Every claim was a hypothesis until measured: the interpreter milestone in `08-milestone.md` was met on 13 Sep, and the control rounds and the erosion round are the measure since (17 Sep 2026).

Mo is a programming language for a world where agents write nearly all the code and humans read only the parts that state intent. This folder is the design in ten short chapters. The wiki around this folder (`directions/`, `questions/`, `syntax/`, `research/`) holds the reasoning and the history; these chapters hold only the result.

| Chapter | What it settles |
|---|---|
| `01-premise.md` | why a new language, and the case against one |
| `02-laws.md` | the rules the compiler enforces with no override |
| `03-semantics.md` | values, functions, effects, processes, failure |
| `04-syntax.md` | the whole surface, with the refund module as the thread |
| `05-verification.md` | the three tiers and the `verified:` line |
| `06-packages.md` | bricks, kits, recipes; the registry |
| `07-toolchain.md` | the interpreter, the compiler, the agent interface |
| `08-milestone.md` | what the first interpreter must prove, and every open bet |
| `09-stdlib.md` | the standard library table (session 5, written from the first program's gaps) |
| `10-language-after-the-rounds.md` | the candidate changes the rounds' evidence supports, with code options for Robert (session 8, after rounds 8 and 10) |

Read top to bottom, in about half an hour; chapters 3 and 9 have grown.
