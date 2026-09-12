---
source_url: https://docs.adacore.com/spark2014-docs/html/ug/en/gnatprove.html
ingested: 2026-09-12
sha256: e9425eefe1f77f4573b1c4d6f94852d3d7d251a628630b202ff25b5534a75f59
---
# 7. Formal Verification with GNATprove — SPARK User's Guide 27.0w

7. Formal Verification with GNATprove — SPARK User's Guide 27.0w

# 7. Formal Verification with GNATprove

The GNATprove tool is packaged as an executable called`gnatprove`. Like other tools in GNAT toolsuite, GNATprove is based on the structure of GNAT projects, defined in`.gpr` files.

A crucial feature of GNATprove is that it interprets annotations exactly like they are interpreted at run time during tests. In particular, their executable semantics includes the verification of run-time checks, which can be verified statically with GNATprove. GNATprove also performs additional verifications on the specification of the expected behavior itself, and its correspondence to the code.

7.1. How to Run GNATprove

- 7.1.1. Setting Up a Project File
- 7.1.2. Running GNATprove from the Command Line
- 7.1.3. Using the GNAT Target Runtime Directory
- 7.1.4. Specifying the Target Architecture and Implementation-Defined Behavior
- 7.1.5. Running GNATprove on Complex Projects
- 7.1.6. Running GNATprove from GNAT Studio
- 7.1.7. Running GNATprove from Visual Studio Code
- 7.1.8. Running GNATprove from GNATbench
- 7.1.9. Running GNATprove Without a Project File
- 7.1.10. GNATprove and Manual Proof
- 7.1.11. How to Speed Up a Run of GNATprove
- 7.1.12. GNATprove and Network File Systems or Shared Folders

7.2. How to View GNATprove Output

- 7.2.1. The Analysis Report Panel
- 7.2.2. The Analysis Results Summary File
- 7.2.3. Results in SARIF format
- 7.2.4. Categories of Messages
- 7.2.5. Errors and Completeness of Analysis
- 7.2.6. Effect of Mode on Output
- 7.2.7. Description of Messages
- 7.2.8. Understanding Counterexamples

7.3. How to Use GNATprove in a Team

- 7.3.1. Possible Workflows
- 7.3.2. Suppressing Warnings
- 7.3.3. Suppressing Information Messages
- 7.3.4. Justifying Check Messages
- 7.3.5. Sharing Proof Results with Others
- 7.3.6. Sharing Proof Results Via a Cache
- 7.3.7. Managing Assumptions

7.4. How to Write Subprogram Contracts

- 7.4.1. Generation of Dependency Contracts
- 7.4.2. Infeasible Subprogram Contracts
- 7.4.3. Writing Contracts for Program Integrity
- 7.4.4. Writing Contracts for Functional Correctness
- 7.4.5. Verifying Contract Consistency
- 7.4.6. Writing Contracts on Main Subprograms
- 7.4.7. Writing Contracts on Imported Subprograms
- 7.4.8. Contextual Analysis of Subprograms Without Contracts
- 7.4.9. Subprogram Termination

7.5. How to Write Object Oriented Contracts

- 7.5.1. Object Oriented Code Without Dispatching
- 7.5.2. Writing Contracts on Dispatching Subprograms
- 7.5.3. Writing Contracts on Subprograms with Class-wide Parameters

7.7. How to Write Loop Invariants

- 7.7.1. Automatic Unrolling of Simple For-Loops
- 7.7.2. Automatically Generated Loop Invariants
- 7.7.3. The Four Properties of a Good Loop Invariant
- 7.7.4. Proving a Loop Invariant in the First Iteration
- 7.7.5. Completing a Loop Invariant to Prove Checks Inside the Loop
- 7.7.6. Completing a Loop Invariant to Prove Checks After the Loop
- 7.7.7. Proving a Loop Invariant After the First Iteration

7.8. How to Investigate Unproved Checks

- 7.8.1. Investigating Incorrect Code or Assertion
- 7.8.2. Investigating Unprovable Properties
- 7.8.3. Investigating Prover Shortcomings
- 7.8.4. Looking at Machine-Parsable GNATprove Output
- 7.8.5. Understanding Proof Strategies

7.9. GNATprove by Example

- 7.9.1. Basic Examples
- 7.9.2. Loop Examples
- 7.9.3. Manual Proof Examples
