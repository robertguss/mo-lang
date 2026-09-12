---
source_url: https://docs.adacore.com/spark2014-docs/html/ug/en/source/subprogram_contracts.html
ingested: 2026-09-12
sha256: 2cadbcec7fbaa7e69a5a10cae87e8323a5b2d0c20682011f92ebe3f4beabfcda
---
# 5.2. Subprogram Contracts — SPARK User's Guide 27.0w

5.2. Subprogram Contracts — SPARK User's Guide 27.0w

# 5.2. Subprogram Contracts

The most important feature to specify the intended behavior of a SPARK program is the ability to attach a contract to subprograms. In this document, a subprogram can be a procedure, a function or a protected entry. This contract is made up of various optional parts:

The precondition introduced by aspect`Pre` specifies constraints on callers of the subprogram.

The postcondition introduced by aspect`Post` specifies (partly or completely) the functional behavior of the subprogram.

The contract cases introduced by aspect`Contract_Cases` is a way to partition the behavior of a subprogram. It can replace or complement a postcondition.

The data dependencies introduced by aspect`Global` specify the global data read and written by the subprogram.

The flow dependencies introduced by aspect`Depends` specify how subprogram outputs depend on subprogram inputs.

The exceptional contract introduced by aspect`Exceptional_Cases` specifies the exceptions that might be propagated by a procedure, along with exceptional postconditions.

The program exit contract introduced by aspect`Program_Exit` specifies in which cases a subprogram might terminate the program abruptly.

The exit cases introduced by aspect`Exit_Cases` is a way to specify how a subprogram is allowed to exit by partioning the input domain. It can replace or complement a postcondition or an exceptional contract.

The termination contract introduced by aspect`Always_Terminates` requires procedures and entries to terminate, possibly under a particular condition.

The subprogram variant introduced by aspect`Subprogram_Variant` is used to ensure termination of recursive subprograms.

Which contracts to write for a given verification objective, and how GNATprove generates default contracts, is detailed in How to Write Subprogram Contracts.

GNATprove formally verifies that each execution of each SPARK subprogram it analyzes will either:

return normally in a state that respects the subprogram’s postcondition,

raise an exception in a state that respects the subprogram’s exceptional contract,

terminate abnormally as a result of a primary stack, secondary stack, or heap memory allocation failure, or

not terminate at all when it is allowed by its termination contract.

GNATprove also checks that procedures that are marked with aspect or pragma`No_Return` do not return: they should either raise an exception, call a non-returning subprogram, or loop forever on any input.

## 5.2.1. Preconditions

Supported in Ada 2012

The precondition of a subprogram specifies constraints on callers of the subprogram. Typically, preconditions are written as conjunctions of constraints that fall in one of the following categories:

exclusion of forbidden values of parameter, for example`X /= 0` or`Y not
in Active_States`

specification of allowed parameter values, for example`X in 1 .. 10` or`Y in Idle_States`

relations that should hold between parameter values, for example`(if Y in
Active_State then Z /= Null_State)`

expected values of global variables denoting the state of the computation, for example`Current_State in Active_States`

invariants about the global state that should hold when calling this subprogram, for example`Is_Complete (State_Mapping)`

relations involving the global state and input parameters that should hold when calling this subprogram, for example`X in Next_States (Global_Map,
Y)`

When the program is compiled with assertions (for example with switch`-gnata` in GNAT), the precondition of a subprogram is checked at run time every time the subprogram is called. An exception is raised if the precondition fails. Not all assertions need to be enabled though. For example, a common idiom is to enable only preconditions (and not other assertions) in the production binary, by setting pragma`Assertion_Policy` as follows:

```
pragma Assertion_Policy (Pre => Check);

```

When a subprogram is analyzed with GNATprove, its precondition is used to restrict the contexts in which it may be executed, which is required in general to prove that the subprogram’s implementation:

is free from run-time errors (see Writing Contracts for Program Integrity); and

ensures that the postcondition of the subprogram always holds (see Writing Contracts for Functional Correctness).

In particular, the default precondition of`True` used by GNATprove when no explicit one is given may not be precise enough, unless it can be analyzed in the context of its callers by GNATprove (see Contextual Analysis of Subprograms Without Contracts). When a caller is analyzed with GNATprove, it checks that the precondition of the called subprogram holds at the point of call. And even when the implementation of the subprogram is not analyzed with GNATprove, it may be necessary to add a precondition to the subprogram for analyzing its callers (see Writing Contracts on Imported Subprograms).

For example, consider the procedure`Add_To_Total` which increments global counter`Total` by the value given in parameter`Incr`. To ensure that there are no integer overflows in the implementation,`Incr` should not be too large, which a user can express with the following precondition:

```
procedure Add_To_Total (Incr : in Integer) with
  Pre => Incr >= 0 and then Total <= Integer'Last - Incr;

```

To ensure that the value of`Total` remains non-negative, one should also add the condition`Total >= 0` to the precondition:

```
procedure Add_To_Total (Incr : in Integer) with
  Pre => Incr >= 0 and then Total in 0 .. Integer'Last - Incr;

```

Finally, GNATprove also analyzes preconditions to ensure that they are free from run-time errors in all contexts. This may require writing the precondition in a special way. For example, the precondition of`Add_To_Total` above uses the shortcut boolean operator`and then` instead of`and`, so that calling the procedure in a context where`Incr` is negative does not result in an overflow when evaluating`Integer'Last - Incr`. Instead, the use of`and
then` ensures that a precondition failure will occur before the expression`Integer'Last - Incr` is evaluated.

Note

It is good practice to use the shortcut boolean operator`and then` instead of`and` in preconditions. This is required in some cases by GNATprove to prove absence of run-time errors inside preconditions.

Raise expressions occuring in preconditions are handled in a special way. Indeed, it is a common pattern to use a raise expression to change the exception raised by a failed precondition. To support this use case, raising an expression in a precondition is considered in SPARK to be a failure of the precondition, as opposed to a runtime failure, which would not be allowed in SPARK. As an example, we may want to introduce specific exceptions for the the failure of each part of the precondition of`Add_To_Total`, so as to debug them more easily. This can be done by using two raise expressions as in the following snippet:

```
Negative_Increment  : exception;
Total_Out_Of_Bounds : exception;

procedure Add_To_Total (Incr : in Integer) with
  Pre => (Incr >= 0 or else raise Negative_Increment)
  and then (Total in 0 .. Integer'Last - Incr
            or else raise Total_Out_Of_Bounds);

```

The raise expressions are associated to each conjunct using an`or else` short circuit operator, so that they will be evaluated when the conjunct evaluates to`False` and the exception will be raised.

On this code, GNATprove will not attempt to verify that the exceptions can never be raised when evaluating the precondition in any context, like it does for other runtime exceptions. Instead, it will consider them being raised as a failure of the precondition. So, for GNATprove, the precondition with the raise expressions above is effectively equivalent to the precondition of the previous example.

## 5.2.2. Postconditions

Supported in Ada 2012

The postcondition of a subprogram specifies partly or completely the functional behavior of the subprogram. Typically, postconditions are written as conjunctions of properties that fall in one of the following categories:

possible values returned by a function, using the special attribute`Result`(see Attribute Result), for example`Get'Result in
Active_States`

possible values of output parameters, for example`Y in Active_States`

expected relations between output parameter values, for example`if Success
then Y /= Null_State`

expected relations between input and output parameter values, possibly using the special attribute`Old`(see Attribute Old), for example`if
Success then Y /= Y'Old`

expected values of global variables denoting updates to the state of the computation, for example`Current_State in Active_States`

invariants about the global state that should hold when returning from this subprogram, for example`Is_Complete (State_Mapping)`

relations involving the global state and output parameters that should hold when returning from this subprogram, for example`X in Next_States
(Global_Map, Y)`

When the program is compiled with assertions (for example with switch`-gnata` in GNAT), the postcondition of a subprogram is checked at run time every time the subprogram returns. An exception is raised if the postcondition fails. Usually, postconditions are enabled during tests, as they provide dynamically checkable oracles of the intended behavior of the program, and disabled in the production binary for efficiency.

When a subprogram is analyzed with GNATprove, it checks that the postcondition of a subprogram cannot fail. This verification is modular: GNATprove considers all calling contexts in which the precondition of the subprogram holds for the analysis of a subprogram. GNATprove also analyzes postconditions to ensure that they are free from run-time errors, like any other assertion.

For example, consider the procedure`Add_To_Total` which increments global counter`Total` with the value given in parameter`Incr`. This intended behavior can be expressed in its postcondition:

```
procedure Add_To_Total (Incr : in Integer) with
  Post => Total = Total'Old + Incr;

```

The postcondition of a subprogram is used to analyze calls to the subprograms. In particular, the default postcondition of`True` used by GNATprove when no explicit one is given may not be precise enough to prove properties of its callers, unless it analyzes the subprogam’s implementation in the context of its callers (see Contextual Analysis of Subprograms Without Contracts).

Recursive subprograms and mutually recursive subprograms are treated in this respect exactly like non-recursive ones. Provided the execution of these subprograms always terminates (a property that is not verified by GNATprove), then GNATprove correctly checks that their postcondition is respected by using this postcondition for recursive calls.

Special care should be exercized for functions that return a boolean, as a common mistake is to write the expected boolean result as the postcondition:

```
function Total_Above_Threshold (Threshold : in Integer) return Boolean with
  Post => Total > Threshold;

```

while the correct postcondition uses Attribute Result:

```
function Total_Above_Threshold (Threshold : in Integer) return Boolean with
  Post => Total_Above_Threshold'Result = Total > Threshold;

```

Both GNAT compiler and GNATprove issue a warning on the semantically correct but likely functionally wrong postcondition.

## 5.2.3. Contract Cases

Specific to SPARK

When a subprogram has a fixed set of different functional behaviors, it may be more convenient to specify these behaviors as contract cases rather than a postcondition. For example, consider a variant of procedure`Add_To_Total` which either increments global counter`Total` by the given parameter value when possible, or saturates at a given threshold. Each of these behaviors can be defined in a contract case as follows:

```
procedure Add_To_Total (Incr : in Integer) with
  Contract_Cases => (Total + Incr < Threshold  => Total = Total'Old + Incr,
                     Total + Incr >= Threshold => Total = Threshold);

```

Each contract case consists in a guard and a consequence separated by the symbol`=>`. When the guard evaluates to`True` on subprogram entry, the corresponding consequence should also evaluate to`True` on subprogram exit. We say that this contract case was enabled for the call. Exactly one contract case should be enabled for each call, or said equivalently, the contract cases should be disjoint and complete.

For example, the contract cases of`Add_To_Total` express that the subprogram should be called in two distinct cases only:

on inputs that can be added to`Total` to obtain a value strictly less than a given threshold, in which case`Add_To_Total` adds the input to`Total`.

on inputs whose addition to`Total` exceeds the given threshold, in which case`Add_To_Total` sets`Total` to the threshold value.

When the program is compiled with assertions (for example with switch`-gnata` in GNAT), all guards are evaluated on entry to the subprogram, and there is a run-time check that exactly one of them is`True`. For this enabled contract case, there is another run-time check when returning from the subprogram that the corresponding consequence evaluates to`True`.

When a subprogram is analyzed with GNATprove, it checks that there is always exactly one contract case enabled, and that the consequence of the contract case enabled cannot fail. If the subprogram also has a precondition, GNATprove performs these checks only for inputs that satisfy the precondition, otherwise for all inputs.

In the simple example presented above, there are various ways to express an equivalent postcondition, in particular using Conditional Expressions:

```
procedure Add_To_Total (Incr : in Integer) with
  Post => (if Total'Old + Incr < Threshold  then
             Total = Total'Old + Incr
           else
             Total = Threshold);

procedure Add_To_Total (Incr : in Integer) with
  Post => Total = (if Total'Old + Incr < Threshold then Total'Old + Incr else Threshold);

procedure Add_To_Total (Incr : in Integer) with
  Post => Total = Integer'Min (Total'Old + Incr, Threshold);

```

In general, an equivalent postcondition may be cumbersome to write and less readable. Contract cases also provide a way to automatically verify that the input space is partitioned in the specified cases, which may not be obvious with a single expression in a postcondition when there are many cases.

The guard of the last case may be`others`, to denote all cases not captured by previous contract cases. For example, the contract of`Add_To_Total` may be written:

```
procedure Add_To_Total (Incr : in Integer) with
  Contract_Cases => (Total + Incr < Threshold => Total = Total'Old + Incr,
                     others                   => Total = Threshold);

```

When`others` is used as a guard, there is no need for verification (both at run-time and using GNATprove) that the set of contract cases covers all possible inputs. Only disjointness of contract cases is checked in that case.

## 5.2.4. Data Dependencies

Specific to SPARK

The data dependencies of a subprogram specify the global data that a subprogram is allowed to read and write. Together with the parameters, they completely specify the inputs and outputs of a subprogram. Like parameters, the global variables mentioned in data dependencies have a mode:`Input` for inputs,`Output` for outputs and`In_Out` for global variables that are both inputs and outputs. A last mode of`Proof_In` is defined for inputs that are only read in contracts and assertions. For example, data dependencies can be specified for procedure`Add_To_Total` which increments global counter`Total` as follows:

```
procedure Add_To_Total (Incr : in Integer) with
  Global => (In_Out => Total);

```

For protected subprograms, the protected object is considered as an implicit parameter of the subprogram:

it is an implicit parameter of mode`in` of a protected function; and

it is an implicit parameter of mode`in out` of a protected procedure or a protected entry.

Data dependencies have no impact on compilation and the run-time behavior of a program. When a subprogram is analyzed with GNATprove, it checks that the implementation of the subprogram:

only reads global inputs mentioned in its data dependencies,

only writes global outputs mentioned in its data dependencies, and

always completely initializes global outputs that are not also inputs.

See Data Initialization Policy for more details on this analysis of GNATprove. During its analysis, GNATprove uses the specified data dependencies of callees to analyze callers, if present, otherwise a default data dependency contract is generated (see Generation of Dependency Contracts) for callees.

There are various benefits when specifying data dependencies on a subprogram, which gives various reasons for users to add such contracts:

GNATprove verifies automatically that the subprogram implementation respects the specified accesses to global data.

GNATprove uses the specified contract during flow analysis, to analyze the data and flow dependencies of the subprogram’s callers, which may result in a more precise analysis (less false alarms) than with the generated data dependencies.

GNATprove uses the specified contract during proof, to check absence of run-time errors and the functional contract of the subprogram’s callers, which may also result in a more precise analysis (less false alarms) than with the generated data dependencies.

When data dependencies are specified on a subprogram, they should mention all global data read and written in the subprogram. When a subprogram has neither global inputs nor global outputs, it can be specified using the`null` data dependencies:

```
function Get (X : T) return Integer with
  Global => null;

```

When a subprogram has only global inputs but no global outputs, it can be specified either using the`Input` mode:

```
function Get_Sum return Integer with
  Global => (Input => (X, Y, Z));

```

or equivalently without any mode:

```
function Get_Sum return Integer with
  Global => (X, Y, Z);

```

Note the use of parentheses around a list of global inputs or outputs for a given mode.

Global data that is both read and written should be mentioned with the`In_Out` mode, and not as both input and output. For example, the following data dependencies on`Add_To_Total` are illegal and rejected by GNATprove:

```
procedure Add_To_Total (Incr : in Integer) with
  Global => (Input  => Total,
             Output => Total);  --  INCORRECT

```

Global data that is partially written in the subprogram should also be mentioned with the`In_Out` mode, and not as an output. See Data Initialization Policy.

## 5.2.5. Flow Dependencies

Specific to SPARK

The flow dependencies of a subprogram specify how its outputs (both output parameters and global outputs) depend on its inputs (both input parameters and global inputs). For example, flow dependencies can be specified for procedure`Add_To_Total` which increments global counter`Total` as follows:

```
procedure Add_To_Total (Incr : in Integer) with
  Depends => (Total => (Total, Incr));

```

The above flow dependencies can be read as “the output value of global variable`Total` depends on the input values of global variable`Total` and parameter`Incr`”.

Outputs (both parameters and global variables) may have an implicit input part depending on their type:

an unconstrained array`A` has implicit input bounds`A'First` and`A'Last`

a discriminated record`R` has implicit input discriminants, for example`R.Discr`

Thus, an output array`A` and an output discriminated record`R` may appear in input position inside a flow-dependency contract, to denote the input value of the bounds (for the array) or the discriminants (for the record).

For protected subprograms, the protected object is considered as an implicit parameter of the subprogram which may be mentioned in the flow dependencies, under the name of the protected unit (type or object) being declared:

as an implicit parameter of mode`in` of a protected function, it can be mentioned on the right-hand side of flow dependencies; and

as an implicit parameter of mode`in out` of a protected procedure or a protected entry, it can be mentioned on both sides of flow dependencies.

Flow dependencies have no impact on compilation and the run-time behavior of a program. When a subprogram is analyzed with GNATprove, it checks that, in the implementation of the subprogram, outputs depend on inputs as specified in the flow dependencies. During its analysis, GNATprove uses the specified flow dependencies of callees to analyze callers, if present, otherwise a default flow dependency contract is generated for callees (see Generation of Dependency Contracts).

When flow dependencies are specified on a subprogram, they should mention all flows from inputs to outputs. In particular, the output value of a parameter or global variable that is partially written by a subprogram depends on its input value (see Data Initialization Policy).

When the output value of a parameter or global variable depends on its input value, the corresponding flow dependency can use the shorthand symbol`+` to denote that a variable’s output value depends on the variable’s input value plus any other input listed. For example, the flow dependencies of`Add_To_Total` above can be specified equivalently:

```
procedure Add_To_Total (Incr : in Integer) with
  Depends => (Total =>+ Incr);

```

When an output value depends on no input value, meaning that it is completely (re)initialized with constants that do not depend on variables, the corresponding flow dependency should use the`null` input list:

```
procedure Init_Total with
  Depends => (Total => null);

```

## 5.2.6. Abstraction and Contracts

Just like for programming, abstraction is a key concept for the scalability of formal verification. In Ada, it is usually provided through packages and privacy. A package is composed of (at most) three parts, the public part of the specification, its private part, and the package body. Entities defined in the private part of the specification or the package body cannot be used in the public part of the specification nor in other units.

### 5.2.6.1. State Abstraction and Dependencies

Specific to SPARK

The subprogram contracts mentioned so far always used directly global variables. In many cases, this is not possible because the global variables are defined in another unit and not directly visible (because they are defined in the private part of a package specification, or in a package implementation). The notion of abstract state in SPARK can be used in that case (see State Abstraction) to name in contracts global data that is not visible.

Suppose the global variable`Total` incremented by procedure`Add_To_Total` is defined in the package implementation, and a procedure`Cash_Tickets` in a client package calls`Add_To_Total`. Package`Account` which defines`Total` can define an abstract state`State` that represents`Total`, as seen in State Abstraction, which allows using it in`Cash_Tickets`’s data and flow dependencies:

```
procedure Cash_Tickets (Tickets : Ticket_Array) with
  Global  => (Output => Account.State),
  Depends => (Account.State => Tickets);

```

As global variable`Total` is not visible from clients of unit`Account`, it is not visible either in the visible part of`Account`’s specification. Hence, externally visible subprograms in`Account` must also use abstract state`State` in their data and flow dependencies, for example:

```
procedure Init_Total with
  Global  => (Output => State),
  Depends => (State => null);

procedure Add_To_Total (Incr : in Integer) with
  Global  => (In_Out => State),
  Depends => (State =>+ Incr);

```

Then, the implementations of`Init_Total` and`Add_To_Total` can define refined data and flow dependencies introduced respectively by`Refined_Global` and`Refined_Depends`, which give the precise dependencies for these subprograms in terms of concrete variables:

```
procedure Init_Total with
  Refined_Global  => (Output => Total),
  Refined_Depends => (Total => null)
is
begin
   Total := 0;
end Init_Total;

procedure Add_To_Total (Incr : in Integer) with
  Refined_Global  => (In_Out => Total),
  Refined_Depends => (Total =>+ Incr)
is
begin
   Total := Total + Incr;
end Add_To_Total;

```

Here, the refined dependencies are the same as the abstract ones where`State` has been replaced by`Total`, but that’s not always the case, in particular when the abstract state is refined into multiple concrete variables (see State Abstraction). GNATprove checks that:

each abstract global input has at least one of its constituents mentioned by the concrete global inputs

each abstract global in_out has at least one of its constituents mentioned with mode input and one with mode output (or at least one constituent with mode in_out)

each abstract global output has to have all its constituents mentioned by the concrete global outputs

the concrete flow dependencies are a subset of the abstract flow dependencies

GNATprove uses the abstract contract (data and flow dependencies) of`Init_Total` and`Add_To_Total` when analyzing calls outside package`Account` and the more precise refined contract (refined data and flow dependencies) of`Init_Total` and`Add_To_Total` when analyzing calls inside package`Account`.

Refined dependencies can be specified on both subprograms and tasks for which data and/or flow dependencies that are specified include abstract states which are refined in the current unit.

### 5.2.6.2. Abstraction and Functional Contracts

Abstraction affects how functional contracts are written. First, if global variables are not visible for data dependencies, they are not visible either for functional contracts. For example, in the case of procedure`Add_To_Total`, if global variable`Total` is not visible, we cannot express anymore the precondition and postcondition of`Add_To_Total` as in Preconditions and Postconditions. In this case, it is necessary to define accessor functions to retrieve properties of the state that are needed to express contracts. For example here:

```
function Get_Total return Integer;

procedure Add_To_Total (Incr : in Integer) with
  Pre  => Incr >= 0 and then Get_Total in 0 .. Integer'Last - Incr,
  Post => Get_Total = Get_Total'Old + Incr;

```

The body of the function`Get_Total` may be defined either in the private part of package`Account` or in its implementation. It may take the form of a regular function or an expression function (see Expression Functions):

```
Total : Integer;

function Get_Total return Integer is (Total);

```

Accessor functions can be annotated as Ghost Functions functions to prevent them from being available in the standard API of the package.

Abstraction also affects the visibility of contracts by the verification tool. By default, the notion of visibility used by GNATprove is rather liberal: subprogram contracts and bodies of expression functions are visible except if they occur in the body of another (possibly nested) unit. In particular, contracts of subprograms declared in the private part of other units are visible. On our example, the precise definition of`Get_Global` is visible for the verification of`Account` no matter whether it is declared in its private part or its implementation. However, it will only be available when verifying units using the`Account` package if it is declared in its private part. To demonstrate this, we can introduce two distinct functions to access the value of`Total` in the public part of the specification of`Account`:

```
function Get_Total_1 return Integer;

function Get_Total_2 return Integer;

```

They can be defined as expression functions as done previously, either in private part of`Account` or in its implementation:

```
function Get_Total_1 return Integer is (Total);

function Get_Total_2 return Integer is (Total);

```

In both cases, it will be possible to prove that`Get_Total_1` and`Get_Total_2` necessarily return the same value when verifying`Account` and all subprograms declared within. However, in a`Main` procedure using the`Account` package, this property would no longer be provable if the expression functions are supplied in the body of`Account`.

Note that abstraction is an important concept for verification as it ensures scalability of complex proofs by enforcing separation of concerns - i.e. only the information that is necessary for a given verification is available in the verification tool. The default visibility rules for verification can be tuned in some cases using the annotations`Hide_Info` and`Unhide_Info`, see Annotation for Managing the Proof Context, to achieve a fine-grained abstraction.

The examples presented so far take advantage of the specific handling of expression functions to provide different contracts for a subprogram. Since the body of expression functions acts as an implicit postcondition, it directly provides a refined version of the function’s contract possibly with a different visibility. Not all subprograms can be turned into an expression function. As an alternative, the SPARK language provides the`Refined_Post` aspect or pragma that can be used to provide an alternative postcondition on a subprogram body. For example, procedure`Add_To_Total` may also increment the value of a counter`Call_Count` at each call. If this information is not relevant for the verification of programs using the`Account` package, it can be expressed in a refined postcondition:

```
procedure Add_To_Total (Incr : in Integer) with
  Refined_Post => Total = Total'Old + Incr and Call_Count = Call_Count'Old + 1
is
   ...
end Add_To_Total;

```

GNATprove uses the abstract contract (precondition and postcondition) of`Add_To_Total` when analyzing calls outside package`Account` and the more preci
