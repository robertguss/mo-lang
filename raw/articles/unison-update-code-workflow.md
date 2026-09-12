---
source_url: https://www.unison-lang.org/docs/usage-topics/workflow-how-tos/update-code/
ingested: 2026-09-12
sha256: 165ec4edb3b8d160dd7f13205fb73f8a0c59e4b2a0707a4b2ffaa6744589d4c3
---
# Common workflows for updating Unison code · Unison programming language

Common workflows for updating Unison code · Unison programming language

Usage topics

- Updating code and dependencies
- Resetting codebase state
- Running a program
- Documentation
- Testing
- Transcripts
- Profiling programs
- Docker
- Structural find and replace
- FAQ's
- Bibliography

Unison codebase management

- - Codebase organization
- - Projects quickstart
- Unison project workflows
- Project FAQ's
- Codebase organization
- - Workspace setup
- - Editor setup
- MCP setup
- Merge tool setup
- Code hosting with Unison Share
- UCM-desktop app
- Environment variables
- Add your author and license
- UCM command reference

Language reference

- Top-level declarations
- - Term declarations
- - Type signatures
- Term definition
- Operator definitions
- Ability declaration
- - User-defined data types
- - Structural types
- Unique types
- Record types
- - Expressions
- - Basic lexical forms
- Identifiers
- Name resolution and the environment
- Blocks and statements
- - Literals
- - Documentation literals
- Escape sequences
- Comments
- Type annotations
- Parenthesized expressions
- - Function application
- - Syntactic precedence of operators and prefix function application
- Boolean expressions
- - Delayed computations
- - Syntactic precedence
- Destructuring binds
- - Match expressions and pattern matching
- - Blank patterns
- Literal patterns
- Variable patterns
- As-patterns
- Constructor patterns
- List patterns
- Tuple patterns
- Ability patterns (or `Request` patterns)
- Guard patterns
- Hashes
- - Types
- - Type variables
- Polymorphic types
- Scoped type variables
- Type constructors
- Kinds of Types
- Type application
- Function types
- Tuple types
- Built-in types
- Built-in type constructors
- User-defined types
- Unit
- - Abilities and ability handlers
- - Abilities in function types
- The typechecking rule for abilities
- User-defined abilities
- Ability handlers
- Pattern matching on ability constructors
- Use clauses

Learning labs

- - Wordle clone
- - Codebase setup
- Lab breakdown
- Core logic
- Colorize results
- Validation
- Game loop
- Challenge task
- Other challenges
- - Unison Cloud modules
- - Deploy a simple HTTP service
- Write, deploy, and call typed functions
- Write a blog with Storage
- Add Auth to a web-service

# Common workflows for updating Unison code

The process of applying a potentially breaking change to your code need not be stressful! Here's how Unison handles that process in a few common cases:

Update workflows

- - Updating your own code
- - Updates with deletions
- Updating a library dependency
- Merging changes from a branch

## Updating your own code

Use the `edit` command to bring code into your scratch file and `update` to apply those changes.

If your code change cannot automatically be propagated to its dependents, for example, if you alter a data constructor for a type or change the arguments to a function, Unison will programmatically guide you through the edits.

Workflow summary:

1. Enter `update` in the UCM to save your changes
2. - The UCM opens up non-typechecking code in your editor
- - It creates a temporary branch to resolve your conflicts
3. Fix the impacted terms and save the file
4. - Run `update` to commit your changes.
- - The temporary branch is automatically deleted

### Example walk-through

Let's say we have a simple type and a few functions that use it in our codebase:

```
type Box = Box Nat

Box.toText : Box -> Text
Box.toText box = match box with
  Box.Box nat -> Nat.toText nat

Box.print : Box -> {IO,Exception} ()
Box.print box =
  Box.toText box |> printLine
```

```
scratch/main> update
```

We add it to the codebase, but later, we realize its data constructor should be changed.

```
scratch/main> edit Box
```

```
type Box = Box Int
```

We've changed the type from taking a value of type `Nat` to `Int`. Upon saving the file and running `update` again, the UCM will open the impacted terms in your editor and create a `-update` branch for resolving the conflicts.

```
scratch/main> update

  Some definitions don't typecheck with your changes. I've updated the file
  scratch.u with the definitions that need fixing. Once the file is
  compiling, try `update` again.

  I've also switched you to a new branch update-main for this work. On `update`, it will be merged
  back into main.

scratch/update-main>
```

All impacted terms, including indirect dependents, will be opened in your scratch file. In our example, the function `Box.print` is opened in the editor even though the change we need to make is in `Box.toText`. This is because resolving larger, more complicated updates can involve propagating changes to many terms, all the way up the function call chain.

```
type Box = Box Int

-- The definitions below no longer typecheck with the changes above.
-- Please fix the errors and try `update` again.

Box.print : Box ->{IO, Exception} ()
Box.print box = Box.toText box |> printLine

Box.toText : Box -> Text
Box.toText = cases Box nat -> Nat.toText nat
```

Resolve the compilation errors with the help of the UCM.

```
The 1st argument to `Nat.toText`

        has type:  Int
  but I expected:  Nat

  5 | Box.toText = cases Box nat -> Nat.toText nat
  6 |
  7 | type Box = Box Int
```

```
Box.toText : Box -> Text
Box.toText = cases Box int -> Int.toText int
```

When the scratch file compiles, you'll see a message describing the change set.

```
scratch/update-main>

Loading changes detected in scratch.u.

~ type Box

~ Box.print  : Box ->{IO, Exception} ()
~ Box.toText : Box -> Text

+ (added), ~ (modified), - (deleted)

Run `update` to apply these changes to your codebase.
```

Run `update` again to apply the change and the UCM will finish the update by deleting the temporary branch.

## Deleting terms in change sets

When you're resolving an update, you might realize that some definitions are no longer needed. To handle this, UCM has a specific workflow for removing terms as part of a change set.

Here's how it works:

- During the update process, UCM creates a temporary update branch and opens the affected terms in a scratch file.
- If you remove a term from that file, UCM interprets it as a deletion and removes it from the codebase in the resulting change set.

From our preceding update example, say we wanted to remove `Box.print` while resolving the type error.

```
 type Box = Box Int

 -- The definitions below no longer typecheck with the changes above.
 -- Please fix the errors and try `update` again.

 Box.toText : Box -> Text
 Box.toText = cases Box int -> Int.toText int

 Box.print : Box -> {IO,Exception} ()
 Box.print box =
   Box.toText box |> printLine
```

Removing it from the file causes `Box.print` to be listed as a deletion. It won't be present in the codebase after resolving the update.

```
   Loading changes detected in ~/Unison/website3/website/testTour.u.

   ~ type Box

   ~ Box.toText : Box -> Text
   - Box.print : Box ->{IO, Exception} ()

   + (added), ~ (modified), - (deleted)

   Run `update` to apply these changes to your codebase.
```

### How to update a library dependency

Upgrading a library is very similar to the regular process of updating Unison code. It involves one additional simple command. The following workflow uses Unison's standard library, `base`, as an example.

#### Upgrade workflow:

1. - `lib.install` the latest version of the dependency into your codebase so that it is a sibling of your current library version.
- - `myProject/main> lib.install @unison/base`
2. - Run the `upgrade` command, indicating which library you'd like to upgrade
- - `myProject/main> upgrade unison_base_1_0_0 unison_base_2_0_0`
3. The UCM will create a new branch for the upgrade to take place in, so if something goes wrong and you want to back out of your changes, you can easily switch back to the branch you were on before the upgrade.
4. If there are conflicts to resolve, the UCM will open up the affected terms in your editor. Resolve the conflicts and enter `update` again once the file typechecks.
5. Run `upgrade.commit` to merge the temporary branch created by the `upgrade` command back into its parent branch. It will delete the temporary branch.

You do not need to remember the exact versions of the libraries you are upgrading from and to. Enter `upgrade` with no arguments to pick from the list of libraries in your project.

## Updates from merging

Merging two branches together can also prompt an update workflow. The merge commands below are all valid ways to merge changes from one branch to another.

```
scratch/main> merge /featureBranch
scratch/main> merge /featureBranch /featureBranch2
scratch/main> merge /@contributor/featureBranch
```

If a term has been updated on the parent branch and the child branch being merged into it the UCM will do two things:

1. It will create a branch with the name `merge-child-into-parent` for the merge to take place in.
2. It will open up the impacted terms in a scratch file. Conflicting terms are prefixed by their branch name in a comment for resolution.

```
-- tmp/main
term1 : Nat
term1 =
  1 + 2 + 4000

-- tmp/updateTerm1
term1 : Nat
term1 =
  1 + 2 + 5000
```

Delete the term that is no longer up-to-date or combine the changes into one term, then run `update` to apply the change to the merge resolution branch.

```
tmp/merge-updateTerm1-into-main> update
```

Once the codebase changes are resolved, run `merge.commit` to commit the changes into the parent branch. `merge.commit` will also delete the merge resolution branch.

```
tmp/merge-updateTerm1-into-main> merge.commit
```

### edit

```
scratch/main> edit myTerm
```

```
scratch/main> ls base.List
scratch/main> edit 4
scratch/main> edit 1-5
```

edit prepends the definition of the given argument(s) to the top of the most recently saved file.

Often used in conjunction with `ucmCommands.update`.

### update

```
myProject/main> update
```

```
myProject/main> update aTerm
```

Adds everything in the most recently typechecked file to the namespace, replacing existing definitions having the same name, and attempts to update all the existing dependents accordingly. If the process can't be completed automatically, the dependents will be added back to the scratch file for your review.
