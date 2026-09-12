---
source_url: https://lwn.net/Articles/978955/
ingested: 2026-09-12
sha256: c9fbedf0079b18f34df0217a3631a2790f5e17e08f5d1629e4cf8ebf5d149583
---
# Programming in Unison [LWN.net]

Programming in Unison [LWN.net]

User: Password: | |

# Programming in Unison

By Daroc AldenJune 25, 2024

Unison is a MIT-licensed programming language, in development since 2013, that explores the ramifications of making code immutable and stored in a database, instead of a set of text files. Unison supports a greatly simplified model for distributed programming — one that describes the configuration of and communication between programs in the same language as the programs themselves. Along the way, it introduces a new approach to interfacing with programming languages, which is tailored to its design.

Every programming language, especially one that is just starting out, needs a niche. Unison's chosen niche is cloud computing — making it easier to build modern distributed systems, by radically simplifying some of the rough edges of existing technologies. While it is certainly possible to throw together simple, local scripts using the language, the core developers' focus is on making the development of distributed systems and web-based applications as seamless as possible. In support of this mission, the language employs a number of unusual features.

#### Naming

The feature that fundamentally sets the language apart is the way code is stored. Unlike most other programming languages, which store programs as text, Unison stores programs in a machine-readable format. There are other languages that have done this, including languages like Smalltalk with image-based persistence, or visual languages like LabVIEW. Unlike those languages, Unison programs are stored in an append-only, content-addressed database. The code is still displayed to the user for editing as text, using the editor of their choice, but it is only parsed once, and then stored internally in the database. Consider the following implementation of the factorial function:

```

    factorial : Nat -> Nat
    factorial n = match n with
      0 -> 1
      _ -> n * factorial (n - 1)

```

This function has the hash #in3bl5u64l (rendered in Unison's default base-32 hash format), using Unison's custom structural hash function. The hash is based on the structure of the code, not the variable names or formatting used to express it. Internally, the abstract syntax tree(AST) of the code is stored in Unison's database under that hash. If another person wrote the same function but decided to call it fac, it would have the same hash. When editing some other function that referenced it, Unison would display whatever name the user had defined for it; so one person might see factorial and the other might see fac. In this way, Unison names are a lot like Git tags: a human-readable name for an object that is primarily identified by a hash.

In general, the programmer interacts with Unison using an editor side-by-side with a terminal running the CLI interface, or a browser window running the graphical interface. When writing new code, the user types it in their editor, like any other language. On save, Unison is alerted by a filesystem watch, reads the code, and then presents any problems with it, or offers to update the database with it. When editing an existing function, Unison pretty-prints the stored definition into the user's editor, and watches for changes. This has the interesting effect of doing away with code formatting as a separate step — code is always formatted when the programmer goes to read or edit it. Overall, the approach ends up feeling much more like a collaboration with the compiler than conventional languages do: it asks for definitions, suggests changes, points out problems and failing tests, etc. Here's what it looked like when I added the above definition to my code:

```

    I found and typechecked these definitions in /tmp/scratch.u. If you do
    an `add` or `update`, here's how your codebase would change:

      ⍟ These new definitions are ok to `add`:

        factorial : Nat -> Nat

```

Unison's approach to naming may seem like an interesting curiosity, but it has a few practical ramifications. For one thing, renaming a function, variable, or type can never break anything. Even causing a name collision won't cause problems — Unison tracks the underlying code by hash, so two items that are both named foo might be displayed to the user as foo#hash1 and foo#hash2, but the program would still compile and run without any problems. Another consequence is the ability to use different versions of the same library without issue — different versions of the same function have different hashes, so they can be treated just like different functions with the same name. This also means that the hash of a function encodes not only its code, but also its exact dependencies, which makes sharing code between computers much simpler.

Claiming that Unison code is immutable raises the question of how a function could actually be updated, once it has been written. Since Unison code is stored in a database, the language always knows exactly which code references a particular function. If an edit to a function does not change the type signature, the language can automatically produce a new version of each function that depends on the changed function. The old versions are not removed, but the names of any functions are updated to point to the new ones. This makes it possible to write behavior tests that compare one implementation to another, by referring to the old version of a function, for example.

If the changes to a function do not preserve its type, Unison uses the same knowledge to produce a "to do" list for the programmer, which it will track and automatically remove items from as conflicts are solved. Since the old code is still present in the database, there is never a moment where the code is "broken" by a change. The old version still exists, and can be run, built, inspected, and so on, while the programmer works on the new version. Once the new version has been completed, the programmer can switch over to it all at once.

#### Abilities

Unison's unique approach to naming may handle dependencies, but as the pervasive use of containers shows, there is more to getting program to run on many computers than just ensuring that dependencies are bundled with a program. Code does not just depend on library functions or types, but also on the state of the computer outside of the program. Unison can't solve that problem entirely, but it does have a solution to help manage the complexity of code that relies on interfacing with the outside world: abilities.

Abilities are a kind of effect system— a way to track in the type system what a given piece of code needs in order to run. The most general ability is called IO, and represents the ability to do arbitrary I/O, including reading and writing files, opening network connections, or reading information about the state of the computer. Programmers could write their programs with every function requiring the IO ability, but the more usual approach would be to consider which concrete things each part of the program will need to be able to do, and then declare smaller, more restricted abilities. Programs with custom abilities can be run by providing a "handler" function that describes how to implement the ability, usually in terms of another ability. For example, a programmer might provide a ReadEnvironment ability that lets a program fetch the value of environment variables. In normal use, a handler would translate that into the IO ability, but there can be multiple handlers for an ability, so a test suite might use a handler that supplies pre-defined test values instead.

Since abilities are tracked by the type system, it is impossible for a function to use an ability it has not declared. This means that the programmer can get a list of every interface with the outside world that a piece of code expects to use by looking at the type signature, and mock them for testing by specifying a different handler. Overall, abilities can make writing testable distributed programs much simpler, since everything is described in one flexible language. The guarantees of the type system also mean that it is theoretically possible to run untrusted code, and be sure that it only accesses abilities that the programmer gives it. In practice, Unison is still in development, and there may be some lurking holes in the security guarantee.

#### Funding

The founders of Unison Computing— Paul Chiusano, Rúnar Bjarnason, and Arya Irani — have enough faith in Unison's security properties to make them the basis for a cloud computing offering. Unison Cloud is a platform that allows running Unison programs that use a custom Cloud ability on managed hardware for a monthly fee. That money goes to Unison Computing, a public benefit corporation that employs the core Unison developers, to keep working on the language. The project does accept outside contributions, however, and the language itself will remain open source.

The Cloud ability has facilities for storing arbitrary Unison values to a typed database, handling HTTP(S) requests, deploying new services, and other operations necessary for a program running in the cloud. Since it is an ability like any other, the Unison Cloud library provides mock handlers that can test the entire process of deploying multiple services, running health checks and integration tests, and tearing down the resulting deployment locally.

#### Drawbacks

Unfortunately, Unison's unique design comes with its share of problems. For one thing, modern programs are often not written in just one language, but Unison's greatest benefits only come when an entire program is written in it. Unison doesn't even have a stable foreign-function interface (FFI) that could be used to wrap libraries written in other languages. Because of this, existing Unison programs need to reimplement a lot of functionality that is already present in other languages.

Unison Share is a cross between a package registry, a code forge, and a code browser. Since Unison code is not stored as text files, but rather as a database, the community can't really reuse existing tooling. Tools like Unison Share must be written from scratch. There is support for pushing code to a Git repository, but since it isn't human-readable, it can't really be viewed without either using the local Unison tools, or hosting an instance of Unison Share. The community is actively encouraging people to develop and post new libraries there, but there's a long way to go to catch up with other languages. Still, Unison's ideas around dependency management make using libraries that do exist quite easy — just pull them into your local database and start calling functions, with no worries about dependency conflicts or where to obtain the code.

That approach does prompt the question of how upgrades to libraries are handled. The process described above for updating dependent code when a function changes relies on all of the affected code being locally available for development. There are three partial answers to this question: small libraries, abilities, and patches. Since Unison makes it easy to seamlessly depend on a library, many of the existing libraries are quite small; it is easier to break out some small functionality into a separate library than it would be in another language. Smaller libraries require less frequent updates, and may even become completely finished. Larger libraries can present their interface as an ability. This makes upgrading to a newer version of the library as simple as changing to a newer version of the handler. Finally, for cases where neither of those approaches apply, Unison produces a special kind of value called a patch — really, a record of what changes the developer of a library made while developing the new version, including a mapping of which new functions were produced by editing old ones. Unison uses that information to do the same kind of upgrade as during local development.

Unison is in active development, not yet having reached a 1.0 release. So quite aside from throwing out the familiar text-based workflow, it also has the normal challenges that any language must face: performance problems, occasional bugs in the runtime, unstable interfaces, etc. Despite that, the documentation is already quite comprehensive, and the project has a policy of not breaking existing programs on upgrade. In fact, the standard library is managed using the same process as other libraries, so it is quite possible for a program to use different versions of the standard library internally without conflict.

Unison is not yet widely packaged, but downloads are available from the project's releases page. Running ucm, the Unison codebase manager, will set up a database for the user's code in ~/.unison and provide some quick-start guidance on starting a project in Unison.

It remains to be seen whether Unison will overcome the hurdles necessary to become a widely-used, productive language. Even if it does not, however, it at least illustrates that a different approach to software development is possible — one that builds collaboration with the computer directly into the language itself, and provides an alternative to the many text-based programming languages.

---

to post comments

### -EEXIST

Posted Jun 25, 2024 19:16 UTC (Tue) by grawity (subscriber, #80596) [Link] (11 responses)

Running ucm, the Unison codebase manager, will set up a database for the user's code in`~/.unison`

Ah, so not only does it add to the`~` clutter with more hidden directories, it also uses the exact same`~/.unison` where the Unison file synchronization software stores the user's sync configuration and state…

### -EEXIST

Posted Jun 25, 2024 19:18 UTC (Tue) by grawity (subscriber, #80596) [Link]

(I seem to faintly remember that both the programming language and the file sync tool might share the same roots? Or something? That doesn't stop me from expecting`ucm` to accidentally nuke the other program's configuration one day.)

### -EEXIST

Posted Jun 25, 2024 19:22 UTC (Tue) by daroc (editor, #160859) [Link] (2 responses)

Unfortunately, yes. I actually use the Unison file synchronization software as well, so I did notice that it was putting the database alongside my existing configuration files. Stuff like this is why I keep everything I actually care about on a separate Btrfs subvolume, wipe out my home folder every week, and then symlink the set of config files I've approved back into place. There is a lot of software that will put things in your home directory without permission.

### -EEXIST

Posted Jun 28, 2024 22:25 UTC (Fri) by karkhaz (subscriber, #99844) [Link] (1 responses)

```

chmod u-w ~

```

solves this problem permanently, both for dotfiles that ought to be written under`~/.config`, and other directories like "Downloads" and "Documents" that certain programs insist on trying to create.

### -EEXIST

Posted Jul 1, 2024 12:08 UTC (Mon) by daroc (editor, #160859) [Link]

Yes, I did try running with an immutable home directory for a while. It worked alright, but some software that I wanted to use just completely refused to cope with being unable to create files there. Eventually I decided it was easier to let it create files and then clean up afterwards.

### -EEXIST

Posted Jun 26, 2024 7:18 UTC (Wed) by epa (subscriber, #39769) [Link] (2 responses)

Maybe it's time to abolish the idea of hidden files and display filenames that begin with a . by default, apart from the special directories . and ..

### Get rid of hidden files? No thanks.

Posted Jun 27, 2024 23:20 UTC (Thu) by edgewood (subscriber, #1123) [Link] (1 responses)

So the solution to too much clutter is to ... show things that were previously hidden?

### Get rid of hidden files? No thanks.

Posted Jun 28, 2024 4:47 UTC (Fri) by intelfx (subscriber, #130118) [Link]

> So the solution to too much clutter is to ... show things that were previously hidden?

I'm assuming the GP's idea was to do this as a way to put pressure on the clutter-generating programs (i.e., via making their users annoyed).

Not sure if I agree with using human emotions as leverage, though.

### -EEXIST

Posted Jun 27, 2024 3:49 UTC (Thu) by ranger207 (guest, #134731) [Link]

Maybe Unison the programming language should store its config files in a directory named after the hash of its contents

### -EEXIST

Posted Jun 27, 2024 6:52 UTC (Thu) by zdzichu (subscriber, #17118) [Link] (2 responses)

Having read only the title, I somehow expected this article to be about file-syncing software growing scripting capability. Now I see this is completely different.

### -EEXIST

Posted Jun 27, 2024 22:43 UTC (Thu) by koh (subscriber, #101482) [Link] (1 responses)

I agree that titles, in general, contain too little information. This seems to be by design. Maybe it's time to get rid of them all together?

### -EEXIST

Posted Jun 28, 2024 5:16 UTC (Fri) by cpitrat (subscriber, #116459) [Link]

Or just put the content of the article in the title and the title in the content?

Copyright © 2024, Eklektix, Inc. This article may be redistributed under the terms of the Creative Commons CC BY-SA 4.0 license Comments and public postings are copyrighted by their creators. Linux is a registered trademark of Linus Torvalds
