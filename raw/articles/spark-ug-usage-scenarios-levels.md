---
source_url: https://docs.adacore.com/spark2014-docs/html/ug/en/usage_scenarios.html
ingested: 2026-09-12
sha256: 59e0d29aef8c637e81bbb8772a977c05fc984b6572ffe7d28d3919905a462b7a
---
# 8. Applying SPARK in Practice — SPARK User's Guide 27.0w

8. Applying SPARK in Practice — SPARK User's Guide 27.0w

# 8. Applying SPARK in Practice

SPARK tools offer different levels of analysis, which are relevant in different contexts. This section starts with a description of the five Levels of Software Assurance that can be achieved with SPARK. It continues with a description of the main Objectives of Using SPARK. This list gathers the most commonly found reasons for adopting SPARK in industrial projects, but it is not intended to be an exhaustive list.

Whatever the objective(s) of using SPARK, any project fits in one of four possible Project Scenarios:

the brown field scenario: Maintenance and Evolution of Existing Ada Software

the green field scenario: New Developments in SPARK

the migration scenario: Conversion of Existing SPARK Software to SPARK 2014

the frozen scenario: Analysis of Frozen Ada Software

The section Project Scenarios examines each of these scenarios in turn and describes how SPARK can be applied in each case.

The section Best Practices lists common cases that can be difficult to handle in SPARK, and explains the different possibilities.

## 8.1. Levels of Software Assurance

SPARK analysis can give strong guarantees that a program:

does not read uninitialized data,

accesses global data only as intended,

does not contain concurrency errors (deadlocks and data races),

does not contain run-time errors (e.g., division by zero or buffer overflow), except for`Storage_Error`, which is not covered by SPARK analysis (see also section Dealing with Storage_Error below)

respects key integrity properties (e.g., interaction between components or global invariants),

is a correct implementation of software requirements expressed as contracts.

SPARK can analyze either a complete program or those parts that are marked as being subject to analysis, but it can only be applied to code that follows some restrictions designed to facilitate formal verification. In particular, tasking is restricted to the Ravenscar or Jorvik profiles and use of pointers should follow a strict ownership policy aiming at preventing aliasing of allocated data. Pointers and tasking are both features that, if supported completely, make formal verification, as done by SPARK, infeasible, either because of limitations of state-of-the-art technology or because of the disproportionate effort required from users to apply formal verification in such situations. The large subset of Ada that is analyzed by SPARK is also called the SPARK language subset.

SPARK builds on the strengths of Ada to provide even more guarantees statically rather than dynamically. As summarized in the following table, Ada provides strict syntax and strong typing at compile time plus dynamic checking of run-time errors and program contracts. SPARK allows such checking to be performed statically. In addition, it enforces the use of a safer language subset and detects data flow errors statically.

Ada

SPARK

Contract programming

dynamic

dynamic / static

Run-time errors

dynamic

dynamic / static

Data flow errors

–

static

Strong typing

static

static

Safer language subset

–

static

Strict clear syntax

static

static

The main benefit of formal program verification as performed by SPARK is that it allows verifying properties that are difficult or very costly to verify by other methods, such as testing or reviews. That difficulty may stem from the complexity of the software, the complexity of the requirements, and/or the unknown capabilities of attackers. Formal verification allows giving guarantees that some properties are always verified, however complex the context. The latest versions of international certification standards for avionics (DO-178C / ED-12C) and railway systems (CENELEC EN 50128:2011) have recognized these benefits by increasing the role that formal methods can play in the development and verification of critical software.

### 8.1.1. Levels of SPARK Use

The scope and level of SPARK analysis depend on the objectives being pursued by the adoption of SPARK. The scope of analysis may be the totality of a project, only some units, or only parts of units. The level of analysis may range from simple guarantees provided by flow analysis to complex properties being proved. These can be divided into five easily remembered levels:

Stone level - valid SPARK

Bronze level - initialization and correct data flow

Silver level - absence of run-time errors (AoRTE)

Gold level - proof of key integrity properties

Platinum level - full functional proof of requirements

Platinum level is defined here for completeness, but it is seldom applicable due to the high cost of achieving it. Each level builds on the previous one, so that the code subject to the Gold level should be a subset of the code subject to Silver level, which itself is a subset of the code subject to Bronze level, which is in general the same as the code subject to Stone level. We advise using:

Stone level only as an intermediate level during adoption,

Bronze level for as large a part of the code as possible,

Silver level as the default target for critical software (subject to costs and limitations),

Gold level only for a subset of the code subject to specific key integrity (safety/security) properties,

Platinum level only for those parts of the code with the highest integrity (safety/security) constraints.

Our starting point is a program in Ada, which could be thought of as the Brick level: thanks to the use of Ada programming language, this level already provides some confidence: it is the highest level in The Three Little Pigs fable! And indeed languages with weaker semantics could be thought of as Straw and Sticks levels. However, the adoption of SPARK allows us to get stronger guarantees, should the wolf in the fable adopt more aggressive means of attack than simply blowing.

A pitfall when using tools for automating human tasks is to end up “pleasing the tools” rather than working around the tool limitations. Both flow analysis and proof, the two technologies used in SPARK, have known limitations. Users should refrain from changing the program for the benefit of only getting fewer messages from the tools. When relevant, users should justify tool messages through appropriate pragmas. See the sections on Suppressing Warnings and Justifying Check Messages for more details.

GNATprove can be run at the different levels mentioned in this document, either through the Integrated Development Environments (IDE) GNAT Studio, Visual Studio Code or Eclipse, or on the command line. Use of the command-line interface at a given level is facilitated by convenient synonyms:

use switch`--mode=stone` for Stone level (synonym of`--mode=check_all`)

use switch`--mode=bronze` for Bronze level (synonym of`--mode=flow`)

use switch`--mode=silver` for Silver level (synonym of`--mode=all`)

use switch`--mode=gold` for Gold level (synonym of`--mode=all`)

Note that levels Silver and Gold are activated with the same switches. Indeed, the difference between these levels is not on how GNATprove is run, but on the objectives of verification. This is explained in the section on Gold Level. Platinum level is not given a separate switch value, as it would be the same.

Sections Stone Level to Platinum Level present the details of the five levels of software assurance. Each section consists in a short description of three key aspects of adopting SPARK at that level:

Benefits - What is gained from adopting SPARK?

Impact on Process - How should the process (i.e., the software life cycle development and verification activities) be adapted to use SPARK?

Costs and Limitations - What are the main costs and limitations for adopting SPARK?

Additionally, the index of this document contains entries for all levels (from Stone level to Platinum level) which point to parts of the User’s Guide relevant for reaching a specific level.

### 8.1.2. Stone Level - Valid SPARK

The goal of reaching this level is to identify as much code as possible as belonging to the SPARK subset. The user is responsible for identifying candidate SPARK code by applying the marker`SPARK_Mode` to flag SPARK code to GNATprove, which is responsible for checking that the code marked with`SPARK_Mode` is indeed valid SPARK code. Note that valid SPARK code may still be incorrect in many ways, such as raising run-time exceptions. Being valid merely means that the code respects the legality rules that define the SPARK subset in the SPARK Reference Manual (see http://docs.adacore.com/spark2014-docs/html/lrm/). The number of lines of SPARK code in a program can be computed (along with other metrics such as the total number of lines of code) by the metrics computation tool GNATmetric.

Benefits

The stricter SPARK rules are enforced on a (hopefully) large part of the program, which leads to higher quality and maintainability, as error-prone features such as side effects in regular functions are avoided, and others, such as pointers, are restricted to avoid common mistakes. Individual and peer review processes can be reduced on the SPARK parts of the program, since analysis automatically eliminates some categories of defects. The parts of the program that don’t respect the SPARK rules are carefully isolated so they can be more thoroughly reviewed and tested.

Impact on Process

After the initial pass of applying the SPARK rules to the program, ongoing maintenance of SPARK code is similar to ongoing maintenance of Ada code, with a few additional rules, such as the need to avoid side effects in functions. These additional rules are checked automatically by running GNATprove on the modified program, which can be done either by the developer before committing changes or by an automatic system (continuous builder, regression testsuite, etc.)

Costs and Limitations

Pointer-heavy code needs to be rewritten to follow the ownership policy or to hide pointers from SPARK analysis, which may be difficult. The initial pass may require large, but shallow, rewrites in order to transform the code, for example to annotate functions with side effects with aspect`Side_Effects` and move calls to such functions to the right-hand side of assignments.

### 8.1.3. Bronze Level - Initialization and Correct Data Flow

The goal of reaching this level is to make sure that no uninitialized data can ever be read and, optionally, to prevent unintended access to global variables. This also ensures no possible interference between parameters and global variables; i.e., the same variable isn’t passed multiple times to a subprogram, either as a parameter or global variable. Finally, it ensures that functions must return in the absence of run-time error.

Benefits

The SPARK code is guaranteed to be free from a number of defects: no reads of uninitialized variables, no possible interference between parameters and global variables, no unintended access to global variables, no infinite loop or recursion in functions.

When`Global` contracts are used to specify which global variables are read and/or written by subprograms, maintenance is facilitated by a clear documentation of intent. This is checked automatically by GNATprove, so that any mismatch between the implementation and the specification is reported.

Impact on Process

An initial pass is required where flow analysis is enabled and the resulting messages are resolved either by rewriting code or justifying any false alarms. Once this is complete, ongoing maintenance can preserve the same guarantees at a low cost. A few simple idioms can be used to avoid most false alarms, and the remaining false alarms can be easily justified.

Costs and Limitations

The guarantees offered at Bronze level do not extend to subprograms with the annotation`Skip_Flow_And_Proof`, which are only analyzed at Stone level. These guarantees also do not extend to code in the following constructs:

branches ending in an error-signaling statement such as`pragma Assert
(False)`, which flow analysis treats as dead code.

exception handlers and any code that can be executed after catching an exception, which flow analysis could treat as dead code if no callee has a corresponding exceptional contract.

Analysis by proof at Silver Level and above is required in these two cases.

The property that no uninitialized data can be read can only be guaranteed when the following SPARK feature is not used, as its purpose is precisely to allow more complex initialization patterns that can only be analyzed by proof at Silver Level and above:

relaxed initialization of types and variables using aspect`Relaxed_Initialization`.

The property that functions must return in the absence of run-time errors can only be guaranteed when the following SPARK features are not used, as their purpose is precisely to allow more complex termination conditions that can only be analyzed by proof at Silver Level and above:

specification of termination with aspect`Always_Terminate` with a non-static expression;

specification of subprogram variants with aspect`Subprogram_Variant`;

specification of loop variants with pragma`Loop_Variant`;

specification of exceptional contracts with aspect`Exceptional_Cases`.

The initial pass may require a substantial effort to deal with the false alarms, depending on the coding style adopted up to that point. The analysis may take a long time, up to an hour on large programs, but it is guaranteed to terminate. Flow analysis is, by construction, limited to local understanding of the code, with no knowledge of values (only code paths) and handling of composite variables is only through calls, rather than component by component, which may lead to false alarms.

### 8.1.4. Silver Level - Absence of Run-time Errors (AoRTE)

The goal of this level is to ensure that the program does not raise an unexpected exception at run time. Among other things, this guarantees that the control flow of the program cannot be circumvented by exploiting a buffer overflow, or integer overflow. This also ensures that the program cannot crash or behave erratically when compiled without support for run-time checking (compiler switch`-gnatp`) because of operations that would have triggered a run-time exception.

GNATprove can be used to prove the complete absence of possible run-time errors corresponding to the explicit raising of unexpected exceptions in the program, raising the exception`Constraint_Error` at run time, and failures of assertions (corresponding to raising exception`Assertion_Error` at run time).

A special kind of run-time error that can be proved at this level is the absence of exceptions from defensive code. This requires users to add subprogram preconditions (see section Preconditions for details) that correspond to the conditions checked in defensive code. For example, defensive code that checks the range of inputs is modeled by a precondition of the form`Input_X in Low_Bound .. High_Bound`. These conditions are then checked by GNATprove at each call.

Benefits

The SPARK code is guaranteed to be free from run-time errors (Absence of Run Time Errors - AoRTE) plus all the defects already detected at Bronze level: no reads of uninitialized variables, no possible interference between parameters and/or global variables, no unintended access to global variables, and no infinite loop or recursion in functions. These guarantees extend to code using features that require proof for ensuring correct initialization and termination, as described in the limitations for Bronze Level. Thus, the quality of the program can be guaranteed to achieve higher levels of integrity than would be possible in other programming languages.

All the messages about possible run-time errors can be carefully reviewed and justified (for example by relying on external system constraints such as the maximum time between resets) and these justifications can be later reviewed as part of quality inspections.

The proof of AoRTE can be used to compile the final executable without run-time exceptions (compiler switch`-gnatp`), which results in very efficient code comparable to what can be achieved in C or assembly.

The proof of AoRTE can be used to comply with the objectives of certification standards in various domains (DO-178B/C in avionics, EN 50128 in railway, IEC 61508 in many safety-related industries, ECSS-Q-ST-80C in space, IEC 60880 in nuclear, IEC 62304 in medical, ISO 26262 in automotive). To date, the use of SPARK has been qualified in an EN 50128 context. Qualification plans for DO-178 have been developed by AdaCore. Qualification material in any context can be developed by AdaCore as part of a contract.

Impact on Process

An initial pass is required where proof of AoRTE is applied to the program, and the resulting messages are resolved by either rewriting code or justifying any false alarms. Once this is complete, as for the Bronze level, ongoing maintenance can retain the same guarantees at reasonable cost. Using precise types and simple subprogram contracts (preconditions and postconditions) is sufficient to avoid most false alarms, and any remaining false alarms can be easily justified.

Special treatment is required for loops, which may need the addition of loop invariants to prove AoRTE inside and after the loop. See the relevant sections of the SPARK User’s Guide for a description of the detailed process for adding loop contracts, as well as examples of common patterns of loops and their corresponding loop invariants.

Costs and Limitations

The guarantees offered at Silver level and above do not extend to subprograms with the annotations`Skip_Flow_And_Proof` or`Skip_Proof`, which are only analyzed at Stone or Bronze level respectively.

The initial pass may require a substantial effort to resolve all false alarms, depending on the coding style adopted previously. The analysis may take a long time, up to a few hours, on large programs but is guaranteed to terminate. Proof is, by construction, limited to local understanding of the code, which requires using sufficiently precise types of variables, and some preconditions and postconditions on subprograms to communicate relevant properties to their callers.

Even if a property is provable, automatic provers may nevertheless not be able to prove it, due to limitations of the heuristic techniques used in automatic provers. In practice, these limitations mostly show up on non-linear integer arithmetic (such as division and modulo) and floating-point arithmetic.

### 8.1.5. Gold Level - Proof of Key Integrity Properties

The goal of the Gold level is to ensure key integrity properties such as maintaining critical data invariants throughout execution and guaranteeing that transitions between states follow a specified safety automaton. Typically these properties derive from software requirements. Together with the Silver level, these goals ensure program integrity, that is, the program executes within safe boundaries: the control flow of the program is correctly programmed and cannot be circumvented through run-time errors and data cannot be corrupted.

SPARK has a number of useful features for specifying both data invariants and control flow constraints:

Type predicates reflect properties that should always be true of any object of the type.

Preconditions reflect properties that should always hold on subprogram entry.

Postconditions reflect properties that should always hold on subprogram exit.

These features can be verified statically by running GNATprove in proof mode, similarly to what was done at the Silver level. At every point where a violation of the property may occur, GNATprove issues either an ‘info’ message, verifying that the property always holds, or a ‘check’ message about a possible violation. Of course, a benefit of proving properties is that they don’t need to be tested, which can be used to reduce or completely eliminate unit testing.

These features can also be used to augment integration testing with dynamic verification of key integrity properties. To enable this additional verification during execution, you can use either the compilation switch`-gnata`(which enables verification of all invariants and contracts at run time) or`pragma Assertion_Policy`(which enables a subset of the verification) either inside the code (so that it applies to the code that follows in the current unit) or in a pragma configuration file (so that it applies to the entire program).

Benefits

The SPARK code is guaranteed to respect key integrity properties as well as being free from all the defects already detected at the Bronze and Silver levels: no reads of uninitialized variables, no possible interference between parameters and global variables, no unintended access to global variables, no infinite loop or recursion in functions, and no run-time errors. This is a unique feature of SPARK that is not found in other programming languages. In particular, such guarantees may be used in a safety case to make reliability claims.

The effort in achieving this level of confidence based on proof is relatively low compared to the effort required to achieve the same level based on testing. Indeed, confidence based on testing has to rely on an extensive testing strategy. Certification standards define criteria for approaching comprehensive testing, such as Modified Condition / Decision Coverage (MC/DC), which are expensive to achieve. Some certification standards allow the use of proof as a replacement for certain forms of testing, in particular DO-178C in avionics, EN 50128 in railway and IEC 61508 for functional safety. Obtaining proofs, as done in SPARK, can thus be used as a cost-effective alternative to unit testing.

Impact on Process

In a high-DAL certification context where proof replaces testing and independence is required between certain development/verification activities, one person can define the architecture and low-level requirements (package specs) and another person can develop the corresponding bodies and use GNATprove for verification. Using a common syntax/semantics – Ada 2012 contracts – for both the specs/requirements and the code facilitates communication between the two activities and makes it easier for the same person(s) to play different roles at different times.

Depending on the complexity of the property being proven, it may be more or less costly to add the necessary contracts on types and subprograms and to achieve complete automatic proof by interacting with the tool. This typically requires some experience with the tool, which can be gained by training and practice. Thus not all developers should be tasked with developing such contracts and proofs, but instead a few developers should be designated for this task.

As with the proof of AoRTE at Silver level, special treatment is required for loops, such as the addition of loop invariants to prove properties inside and after the loop. Details are presented in the SPARK User’s Guide, together with examples of loops and their corresponding loop invariants.

Costs and Limitations

The analysis may take a long time, up to a few hours, on large programs, but it is guaranteed to terminate. It may also take more or less time depending on the proof strategy adopted (as indicated by the switches passed to GNATprove). Proof is, by construction, limited to local understanding of the code, which requires using sufficiently precise types of variables and some preconditions and postconditions on subprograms to communicate relevant properties to their callers.

Even if a property is provable, automatic provers may fail to prove it due to limitations of the heuristic techniques they employ. In practice, these limitations are mostly visible on non-linear integer arithmetic (such as division and modulo) and on floating-point arithmetic.

Some properties might not be easily expressible in the form of data invariants and subprogram contracts, for example properties of execution traces or temporal properties. Other properties may require the use of non-intrusive instrumentation in the form of ghost code.

### 8.1.6. Platinum Level - Full Functional Correctness

Platinum level is achieved when contracts fully cover the functional requirements. Achieving the Platinum level is rare in itself, and usually done for small parts of an application.

Benefits

The SPARK code is guaranteed to correctly implement its specification, including being free from all the defects already detected at the Bronze, Silver and Gold levels. These strong guarantees can be used as arguments in a safety/security case for the overall software system, providing steps are taken for Managing Assumptions.

Impact on Process

The impact on process is mostly the same as for Gold level. When manual proof is used, which is very likely at this level, there is an associated activity to maintain these proofs as the code evolves. Typically a dedicated verification engineer with enough experience of formal program verification in SPARK should be tasked with this activity.

Costs and Limitations

These are the same as for Gold level, plus the cost of applying manual proof more systematically. Depending on the manual proof technique used and the complexity of the proof, this might be more or less costly initially and during maintenance:

Manual Proof Using SPARK Lemma Library is the least costly of all, only requiring to use the right lemma from the library.

Manual Proof Using Ghost Code is more costly, as it requires expertise and interactions with the tool to guide automatic provers.

Manual Proof Using Coq is the most costly, as it require expertise in interactive proof as well as knowledge of the syntax of the Coq interactive prover.

While the use of manual proof allows to prove any provable property in principle, a balance needs to be found between the higher cost of manual proof techniques and the benefits they bring compared to testing or manual justification.

## 8.2. Objectives of Using SPARK

### 8.2.1. Safe Coding Standard for Critical Software

SPARK is a subset of Ada meant for formal verification, by excluding features that are difficult or impossible to analyze automatically. This means that SPARK can also be used as a coding standard to restrict the set of features used in critical software. As a safe coding standard checker, SPARK allows both to prevent the introduction of errors by excluding unsafe Ada features, and it facilitates their early detection with GNATprove’s flow analysis.

#### 8.2.1.1. Exclusion of Unsafe Ada Features

Once the simple task of Identifying SPARK Code has been completed, one can use GNATprove in`check` mode to verify that SPARK restrictions are respected in SPARK code. Here we list some of the most error-prone Ada features that are excluded from SPARK (see Excluded Ada Features for the complete list).

All expressions, including function calls, are free of side-effects. Expressions with side-effects are problematic because they hide interactions that occur in the code, in the sense that a computation will not only produce a value but also modify some hidden state in the program. In the worst case, they may even introduce interferences between subexpressions of a common expression, which results in different executions depending on the order of evaluation of subexpressions chosen by the compiler.

The use of access types and allocators is restricted to pool specific access types and subject to an ownership policy ensuring that a mutable memory cell has a single owner. In general, pointers can introduce aliasing, that is, they can allow the same object to be visible through different names at the same program point. This makes it difficult to reason about a program as modifying the object under one of the names will also modify the other names. What is more, access types come with their own load of common mistakes, like double frees and dangling pointers.

SPARK also prevents dependencies on the elaboration order by ensuring that no package can write into variables declared in other packages during its elaboration. The use of controlled types is also forbidden as they lead to insertions of implicit calls by the compiler. Finally, backward goto statements are not permitted as they obfuscate the control flow.

#### 8.2.1.2. Early Detection of Errors

GNATprove’s flow analysis will find all the occurrences of the following errors:

uses of uninitialized variables (see Data Initialization Policy)

aliasing of parameters that can cause interferences, which are often not accounted for by programmers (see Absence of Interferences)

It will also warn systematically about the following suspicious behaviors:

wrong parameter modes (can hurt readability and maintainability or even be the sign of a bug, for example if the programmer forgot to update a parameter, to read the value of an out parameter, or to use the initial value of a parameter)

unused variables or statements (again, can hurt readability and maintainability or even be the sign of a bug)

### 8.2.2. Prove Absence of Run-Time Errors (AoRTE)

#### 8.2.2.1. With Proof Only

GNATprove can be used to prove the complete absence of possible run-time errors corresponding to:

all possible explicit raising of unexpected exceptions in the program,

raising exception`Constraint_Error` at run time, and

all possible failures of assertions corresponding to raising exception`Assert_Error` at run time.

AoRTE is important for ensuring safety in all possible operational conditions for safety-critical software (including boundary conditions, or abnormal conditions) or for ensuring availability of a service (absence of DOS attack that can crash the software).

When run-time checks are enabled during execution, Ada programs are not vulnerable to the kind of attacks like buffer overflows that plague programs in C and C++, which allow attackers to gain control over the system. But in the case where run
