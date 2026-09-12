---
source_url: https://songlh.github.io/paper/survey.pdf
ingested: 2026-09-12
sha256: e99960b73c08e31a01821a305119ba1397208800b0eb21968a880e4cd87eccb9
---
# Learning and Programming Challenges of Rust: A Mixed-Methods Study

## Learning and Programming Challenges of Rust: A Mixed-Methods Study∗

Shuofei Zhu Pennsylvania State University USA

Ziyi Zhang† University of Wisconsin-Madison USA

Boqin Qin China Telecom Cloud Computing China

Aiping Xiong Pennsylvania State University USA

Linhai Song Pennsylvania State University USA

ABSTRACT Rust is a young systems programming language designed to provide both the safety guarantees of high-level languages and the execu tion performance of low-level languages. To achieve this design goal, Rust provides a suite of safety rules and checks against those rules at the compile time to eliminate many memory-safety and thread-safety issues. Due to its safety and performance, Rust’s pop ularity has increased significantly in recent years, and it has already been adopted to build many safety-critical software systems. It is critical to understand the learning and programming chal lenges imposed by Rust’s safety rules. For this purpose, we first conducted an empirical study through close, manual inspection of 100 Rust-related Stack Overflow questions. We sought to under stand (1) what safety rules are challenging to learn and program with, (2) under which contexts a safety rule becomes more difficult to apply, and (3) whether the Rust compiler is sufficiently helpful in debugging safety-rule violations. We then performed an online survey with 101 Rust programmers to validate the findings of the empirical study. We invited participants to evaluate program vari ants that differ from each other, either in terms of violated safety rules or the code constructs involved in the violation, and compared the participants’ performance on the variants. Our mixed-methods investigation revealed a range of consistent findings that can benefit Rust learners, practitioners, and language designers.

### CCS CONCEPTS

• Software and its engineering → General programming lan guages; Development frameworks and environments. 

KEYWORDS Rust; Programming Challenges; Empirical Study; Online Survey ∗This work was supported in part by NSF grants CNS-1955965 and CCF-2145394 and an IST seed grant from Pennsylvania State University. †Ziyi Zhang contributed equally with Shuofei Zhu in this work. Permission to make digital or hard copies of all or part of this work for personal or classroom use is granted without fee provided that copies are not made or distributed for profit or commercial advantage and that copies bear this notice and the full citation on the first page. Copyrights for components of this work owned by others than the author(s) must be honored. Abstracting with credit is permitted. To copy otherwise, or republish, to post on servers or to redistribute to lists, requires prior specific permission and/or a fee. Request permissions from permissions@acm.org. ICSE ’22, May 21–29, 2022, Pittsburgh, PA, USA © 2022 Copyright held by the owner/author(s). Publication rights licensed to ACM. ACM ISBN 978-1-4503-9221-1/22/05. . . $15.00 https://doi.org/10.1145/3510003.3510164

ACM Reference Format: 
Shuofei Zhu, Ziyi Zhang, Boqin Qin, Aiping Xiong, and Linhai Song. 2022. 
Learning and Programming Challenges of Rust: A Mixed-Methods Study. 
In 44th International Conference on Software Engineering (ICSE ’22), May 
21–29, 2022, Pittsburgh, PA, USA. ACM, New York, NY, USA, 13 pages. https: 
//doi.org/10.1145/3510003.3510164 

1 INTRODUCTION Rust is a new programming language designed to build safe and efficient systems software [31, 36]. The key innovation of Rust is its suite of safety rules that are checked against during compila tion to catch memory-safety and thread-safety issues. Alongside the language’s safety mechanism, Rust maintains its compiled exe cutable programs to be as efficient as C programs. Due to its safety and efficiency, Rust has become increasingly popular; it has been rated the most beloved programming language every year since 2016 [55–59, 61] and was the fifth fastest growing language on GitHub in 2018 [37]. Rust has already been adopted by many open source programmers and big tech companies to build safety-critical software [28, 34, 41, 42, 45, 54]. Rust’s safety mechanism centers around two important concepts: ownership and lifetime. The basic safety rule requires each value to have exactly one owner variable, and the value is freed when its owner variable ends its lifetime. To improve programming flexibil ity, Rust extends this basic rule to a suite of extended rules, such as allowing ownership to be moved to another owner or to be bor rowed using a reference, and still guarantees memory safety and thread safety. Rust’s safety mechanism is elegant and effective. It essentially prohibits programs from having mutability and alias ing at the same time, and inherently avoids many severe memory bugs (e.g., use after free) and concurrency bugs (e.g., data race). A recent empirical study reports that if a program is written solely in safe Rust code, then it will have no memory bugs, confirming the effectiveness of Rust’s safety mechanism in practice [43]. Unfortunately, Rust is known to have a steep learning curve and is difficult to program in practice [1, 73]. The ease with which programmers can write code that violates Rust’s safety rules and is rejected by the Rust compiler comes down to two reasons. First, Rust’s safety mechanism is unique, and the related grammar and semantics are very different from traditional systems programming languages (e.g., C/C++) [30]. Thus, it is difficult for programmers to migrate the programming experience they have gained from other languages to coding in Rust [51]. Second, the design philosophy of Rust is to reject all suspicious code and force programmers to

ICSE ’22, May 21–29, 2022, Pittsburgh, PA, USA Shuofei Zhu, Ziyi Zhang, Boqin Qin, Aiping Xiong, and Linhai Song 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18

19 let r1 = &mut out1.a[0]; 
20 let r3 = &mut out2.a.0; 
21 let r2 = &out1.a[1]; 
22 let r4 = &out2.a.1; 
23 *r1 += 1; 
24 *r3 += 1; 
25 println!("{:?}", r2); 
26 println!("{:?}", r4); 

PC-1 changes to PC-3

#![allow(unused_variables)] 
struct Inner { inner: u8 } 
struct Outer1 { a: [Inner; 2] } 
struct Outer2 { a: (Inner, Inner) } 
fn test(in1: &mut Inner, in2: &Inner){} 
fn main() { 
let mut out1 = Outer1 { a: 
[Inner {inner: 1}, Inner {inner: 3}]}; 
let mut out2 = Outer2 { a: 
(Inner {inner: 1}, Inner {inner: 3})}; 
- test(&mut out1.a[0], &out1.a[1]); 
+ let (first, rest) = out1.a.split_first_mut().unwrap(); 
+ test(first, &rest[0]); 
test(&mut out2.a.0, &out2.a.1); 

}

(a) Rust program

error[E0502]: cannot borrow `out1.a[_]` as immutable because it is also 
borrowed as mutable 
--> demo-snippet3.rs:14:24 
| 
14 | test(&mut out1.a[0], &out1.a[1]); 
| ---- -------------- ^^^^^^^^^^ immutable borrow occurs here 
| | | 
| | mutable borrow occurs here 
| mutable borrow later used by call 
| 
note: `a` is an array and can only be borrowed as a whole 
| 
4 | struct Outer1 { a: [Inner; 2] } 
| ^ 
error: aborting due to previous error 
For more information about this error, try `rustc --explain E0502`. 

(b) Compiler error messages Figure 1: A Rust program and its compile error. In Figure 1a, the program is PC-1 in the survey; the red-colored tokens violate a safety rule; and “+” and “-” denote code added and deleted to fix the violation. We replaced lines 14 and 17 with the code in the cyan-colored rectangle to create PC-3 in the survey. In Figure 1b, the part in the green-colored rectangle does not belong to the original error messages, and we added it in the survey.

prove their code follows all safety rules. Rust’s safety checks are strict, sometimes overly so, making Rust code hard to be compiled. A piece of Rust code is shown in Figure 1a. Structs Outer1 and Outer2 are declared at lines 4 and 5, respectively. The two structs are similar to each other in the sense that both of them only contain one field with the same name and the same contents (two Inner objects). However, the field of Outer1 is an array, while the field of Outer2 is a tuple. Function test() takes two Inner objects as inputs. It uses a mutable reference to borrow the first Inner object and an immutable reference to borrow the second one. Function test() is called at line 14 using the two Inner objects in an Outer1 object as inputs. However, the Rust compiler reports an error on this line (Figure 1b). The reason for the error is that the elements of an array must be borrowed altogether in Rust (or after an element is borrowed, all other elements in the same array are also consid ered as being borrowed), since the Rust compiler conservatively assumes an index can access any element in an array. Rust does not allow a mutable reference to coexist with other references to the same object to prevent simultaneous mutability and aliasing. Array out1.a has already been mutably borrowed as the first parameter. Thus, it cannot be borrowed again as the second parameter. Coun terintuitively, line 17 is allowed by the compiler because different tuple fields can be borrowed separately. Figure 1b shows the error messages reported by the Rust com piler. The compiler points out which ownership rule is violated, where it is violated, and how it is violated, but it fails to provide the most important information for the programmer that array elements are borrowed together in Rust, causing the programmer to go to Stack Overflow to ask for more explanations about the code and the error messages [62]. The above case demonstrates the complexity of applying Rust’s safety mechanism under concrete coding scenarios and the diffi culty in writing programs accepted by the Rust compiler. Besides the safety rule that a mutable reference cannot coexist with an other reference to the same object, programmers must also know how array (and tuple) elements are borrowed to avoid similar mis takes. Moreover, the compiler may not always provide all necessary information for programmers to understand and fix the errors. Our ultimate goal is to facilitate the learning and programming of Rust. We take the identification of the challenges imposed by

Rust’s safety rules as the first step. Those rules are unique and complex. As shown by the empirical study in Section 3, they indeed cause challenges to Rust programmers in the real world. Rust is still evolving [10, 67]. Learning Rust is a continuous process, and programming Rust in practice often involves studying how to apply a safety rule under a particular coding context. Thus, we do not differentiate learning from programming in this paper. Overall, we aim to answer the following research questions (RQs):

• RQ-1: Which Rust safety rules are difficult to understand? 
• RQ-2: Under which programming contexts is a safety rule more challenging to apply? 
• RQ-3: How helpful is the Rust compiler in resolving program ming errors due to safety-rule violations? We adopted two approaches to answer these questions. We first conducted an empirical study on Rust-related Stack Overflow ques tions, since programmers usually seek technical advice on Stack Overflow for issues they cannot resolve on their own [2, 14, 69, 74]. 

We then performed an online survey to validate the findings of the empirical study by closely examining how Rust programmers answer carefully designed survey questions. We built two datasets for the empirical study. The larger one contains 15,509 Rust-related Stack Overflow questions, and the smaller one contains 100 questions caused by violations of Rust’s safety rules. To answer RQ-1, we built a taxonomy for safety-rule violations in the small dataset. The taxonomy contains two major categories: complex lifetime computation and violating ownership rules. Each of these contains several sub-categories. To answer RQ 2, we applied the LDA model [9] to the large dataset, and computed the correlation between violated safety rules and involved code constructs for the small dataset. We manually interpreted the results to identify scenarios where a safety rule is more challenging to apply. To answer RQ-3, we examined whether the Rust compiler provides all necessary information for debugging safety-rule violations in the small dataset. The empirical study yielded several important findings. First, Rust’s safety rules are difficult for programmers to apply in practice, and computing a lifetime is more challenging than applying an own ership rule. Moreover, some safety-rule violations are highly corre lated with particular code constructs, indicating the corresponding rules are more challenging to apply to those code constructs. In

Table 1: Our findings in the empirical study and how the findings are validated in the online survey. Findings in Empirical Study (Section 3) Validation in Online Survey (Section 4) (1) Rust’s complex safety rules indeed bring unique challenges to its programmers.

(1) A large portion of participants at least “sometimes” felt confused about Rust’s lifetime (or ownership) rules. RQ-1: Which Rust safety rules are difficult to understand? (2) A Rust safety rule may be difficult to apply in concrete scenarios. (2) The average scores in marking program tokens that violated Rust’s safety rules ranged from 0.39 to 0.75.

(3) Programmers ask more lifetime-related questions on Stack Overflow than ownership-related questions, suggesting that lifetime computation is more difficult than applying ownership rules.

(3) Participants who “always” understood compiler errors for lifetime rule violations (10.0%) were significantly fewer than those who “always” understood compiler errors for ownership-rule violations (39.6%). (4) Programs PD-1 and PD-2 shared the same code constructs, but PD-1 due to errors in lifetime computation was reported with a significantly higher difficulty level than PD-2 caused by violating an ownership rule.

(4) The majority (91.8%) of safety-rule violations can be fixed using safe code or well-encapsulated interior unsafe libraries. N.A. RQ-2: Under which programming contexts is a safety rule more challenging to apply? (5) The same Rust safety rule has different difficulty levels when applied to different code constructs, and different safety rules have different difficulty levels when applied to the same code construct.

(5) Participants performed significantly better in labeling error tokens for program PC-1 than for program PC-2, where PC-1 and PC-2 shared the same code constructs but violated different safety rules. (6) A non-negligible portion of participants were confused by how to apply the same rule to two different code constructs (array and tuple). RQ-3: How helpful is the Rust compiler in resolving safety-rule violations? (6) The Rust compiler may not provide all information necessary to understand and fix violations of Rust’s safety rules.

(7) Participants shown with enhanced compiler error messages per formed significantly better than those with the original messages in explaining how safety rules are violated for program PC-1.

addition, the Rust compiler may not provide all the necessary infor mation for comprehending safety-rule violations. We summarize our findings in Table 1. In the online survey, we first asked for participants’ demographic information, technical background, and previous experience in interacting with Rust’s safety mechanism and the Rust compiler. We then showed them four small Rust programs, named PA, PB, PC, and PD. We only asked participants whether PA and PB could be compiled to test their Rust knowledge. We sampled PC and PD from two sets of similar program variants. All variants contained a safety rule violation; however, they were different from each other either in the safety rules they violated or in the code constructs those violations involved. For both PC and PD, we asked participants to (1) pinpoint error root causes by highlighting program tokens, (2) evaluate how difficult it was to comprehend the errors before and after seeing the error messages, (3) select the violated rules, (4) rate the helpfulness of the Rust compiler, and (5) describe the error root causes in their own words. We received 101 valid responses and conducted extensive data analysis on the responses. As shown in Table 1, we confirmed many findings of the empirical study with significant confidence. Overall, our mixed-methods investigation reveals what to learn about Rust, how to learn it, and how to interpret compiler error messages, all of which can benefit Rust learners and programmers. Moreover, our investigation pinpoints information missed by the Rust compiler when reporting safety-rule violations and thus pro vides valuable guidance for the evolution of the Rust compiler. In sum, this paper makes the following key contributions.

• We performed the first empirical study on Stack Overflow ques tions related to violations of Rust’s safety mechanism. 
• We gained six findings regarding the programming challenges caused by Rust’s safety rules and the helpfulness of the Rust 

compiler in debugging safety-rule violations. Those findings can be useful references for Rust learners and programmers.

• We conducted an online survey and confirmed our findings with statistical significance. 

All our study and survey results can be found at bit.ly/3uNAe88.

2 BACKGROUND 
This section gives some background for this project, including 
Rust’s safety mechanism and the information provided by the Rust 
compiler for safety-rule violations. 

2.1 Rust’s Safety Mechanism Rust’s safety mechanism centers around two critical concepts, own ership and lifetime. The basic rule requires that a value is associated with one and only one owner variable, and that the value is dropped (freed) when its owner variable’s lifetime ends. Sometimes, the place where a variable’s lifetime ends is easy to determine, such as at the end of a function or at a matched curly bracket. However, there are cases where lifetime computation is much more complex than inspecting a variable’s lexical scope. To improve its program ming flexibility, Rust extends its basic safety rule into a suite of rules, while still guaranteeing memory safety and thread safety. Ownership Move. Rust allows a value’s ownership to be moved to a different owner variable or to a different scope (e.g., a function, a closure), but it prohibits any access to the previous owner variable after the move. For example, array foo is moved to function max() at line 6 in Figure 2, since the parameter type of function max() is “Vec ”, not “& Vec ” like the function at line 2. Thus, the Rust compiler reports an error at line 7, since foo has already been moved and it cannot be accessed anymore. Ownership Borrow. Rust allows to temporarily borrow a variable’s ownership using a reference, which can be immutable for read-only

ICSE ’22, May 21–29, 2022, Pittsburgh, PA, USA Shuofei Zhu, Ziyi Zhang, Boqin Qin, Aiping Xiong, and Linhai Song 1 fn max ( array : Vec < i8 >) -> i8 { 71 } 2 // fn max ( array : & Vec < i8 >) -> i8 { 71 } 3 fn min ( array : Vec < i8 >) -> i8 { 8 } 4 fn main () { 5 let foo = vec ![71 , 23 , 8]; 6 let max_val = max ( foo ); 7 let min_val = min ( foo ); 8 println !("{} {}" , max_val , min_val ); 9 }

Figure 2: An example of ownership move. The program cannot be compiled, since foo is moved at line 6 and it cannot be used at line 7.

1 fn bar ( x : & mut i32 ) { 
2 println !("{}" , x ); 
3 } 
4 fn main () { 
5 let mut a = 100; 
6 let y = & a ; 
7 println !("{}" , y ); 
8 bar (& mut a ); 
9 } 

Figure 3: An example of ownership borrowing. The program can be compiled.

accesses or mutable for read-write accesses. A borrow ends at the last usage site of the reference. Rust requires that a reference can only be used within its borrowed variable’s lifetime. Rust permits multiple immutable references to a variable to exist at the same time, but it only allows at most one mutable reference to a variable at any time. These rules essentially guarantee all accesses to a variable are within its lifetime and forbid simultaneous mutability and aliasing, avoiding many severe memory and concurrency bugs. For example, in Figure 3, variable a is immutably borrowed by y at line 6 and mutably borrowed when calling bar() at line 8. Although the lexical scope of y does not end until the end of function main() at line 9, because y is not used after line 7, the Rust compiler decides that the borrow ends at line 7 and that it does not overlap with the mutable borrow at line 8. Thus, the compiler compiles the program. Lifetime Annotation. Rust allows programmers to explicitly anno tate a variable’s lifetime with an apostrophe followed by an annota tion name. Lifetime annotations can be used at function declaration sites to specify the lifetime relationship among parameters and the return value, and at struct declaration sites to describe the lifetime requirement between a struct object and its reference fields. When checking a function or a struct, the compiler reports errors when safety-rule violations are inferred based on the lifetime annotations of the function or the struct. When calling a function, the compiler inspects whether the real parameters satisfy the corresponding annotations. Rust allows lifetime elision to reduce the annotation burden, and the compiler automatically infers elided annotations during safety checks. Safe vs. Unsafe. All code discussed so far has been safe Rust code. Rust permits programmers to use the “unsafe” keyword to bypass some safety checks and conduct unsafe operations (e.g., pointer operations, calling an unsafe function). Unsafe code is similar to the traditional C programming language. A piece of code or a function can be unsafe. A function can also be interior unsafe by containing unsafe code internally but exposing a safe API externally, and it can be used as a safe function. In this paper, we focus on understanding programming challenges when coding safe code, since safe code must strictly follow Rust’s safety mechanism, and it is used much more often than unsafe code in Rust programs [43].

2.2 Rust’s Compiler Error Messages The Rust compiler serves as the primary communication channel be tween programmers and Rust’s safety mechanism. It checks against the aforementioned safety rules and reports an error when detect ing a rule violation. Typically, a piece of error messages contains three components: (1) the violated safety rule and its corresponding error code, (2) the lines of code or program tokens that violate the rule, and (3) some explanations about the violation. For example, Figure 1b shows the error messages for the program in Figure 1a, which present the error code (“E0502”) and the violated rule (“can not borrow ... as mutable”) at the beginning, underline program tokens violating the rule in red, and underline several other tokens in blue to provide more information. Sometimes error messages contain suggestions about how to fix an error or even directly give a concrete patch. Moreover, the Rust compiler provides a generic explanation for each error code, which can be obtained by executing rustc (e.g., “rustc --explain E0502” in Figure 1b). Unfortunately, Rust’s safety rules are complex [13, 52] and some are counterintuitive [43]. Moreover, compiler error messages may be imprecise [21] or even contain misleading information [19, 20]. Thus, compiler error messages may not be good enough for Rust programmers to debug and fix safety-rule violations. In Section 3.4, we combine cognitive task analysis [32] and manual inspection of safety-rule violations in real Rust programs to systematically evaluate error messages reported by the Rust compiler.

3 STUDYING STACK OVERFLOW QUESTIONS This section presents our empirical study on Stack Overflow ques tions. Our study aims to answer the research questions previously presented. Its results can guide the learning process of Rust and im prove the interaction between programmers and the Rust compiler.

3.1 Methodology 
We construct a large dataset and a small dataset for statistical anal 
ysis and manual inspection, respectively. 
3.1.1 Large Dataset. The large dataset contains all Stack Overflow 
questions that are labeled with tag “Rust”, have a score greater than 
or equal to zero, and have at least one answer as of February 17, 
2021. In total, there are 15,509 questions in the large dataset. 
We randomly sampled 100 questions from the large dataset and 
manually inspected why programmers asked them on Stack Over 
flow. Common reasons include not knowing how to use a library 
function (26%), being unable to understand Rust’s safety rules (23%), 
being confused by type conversions and type checks in Rust (14%), 
not knowing how to implement or use a trait (similar to an interface 
in Java) (9%), and failing to use FFI properly (7%). 
Finding 1: Rust shares many programming challenges with tra 
ditional programming languages, but its complex safety rules pose 
unique difficulties. 
3.1.2 Small Dataset. We randomly sampled 100 questions related 
to Rust’s safety mechanism from the large dataset to build the 
small dataset. We studied these questions by reading their question 
texts, answers, and discussions. Moreover, each sampled question 

Table 2: Root causes and fixes of violations in the small dataset. Safe/Unsafe: directly writing safe/unsafe code; SL: safe li braries; IUL: interior unsafe libraries; UL: unsafe libraries; and No: eight violations do not have fixes. Root Causes Safe Unsafe SL IUL UL No Total Complex Lifetime Computation Intra-procedural 31 0 1 10 0 2 44 Inter-procedural 19 2 1 4 0 4 30 Simple Syntax Error 3 0 0 0 0 0 3 Violating Ownership Rules Move Rule 12 0 1 5 0 0 18 Borrowing Rule 9 1 3 8 0 2 23 Total 74 3 6 27 0 8 118 contains a code snippet for describing the problem. Based on the snippets, we successfully implemented standalone programs and reproduced all problems offline. For eight questions, the programs can be compiled, but the compilation contradicts the questioners’ understanding. We consider each of these questions to be a case where the programmer’s understanding violates a safety rule. For all other questions, the programs cannot be compiled. Among these, 76 programs contain one violation of a safety rule, 14 programs contain two violations, and the remaining two contain three violations. In total, there are 118 safety-rule violations in the small dataset.

3.2 Which Safety Rules Are Difficult? To determine which safety rules are difficult and are more likely to cause usage violations, we build a taxonomy for the root causes of the violations in the small dataset. As shown in Table 2, we first divide the root causes into complex lifetime computation and violating ownership rules, as they are the two core concepts of Rust’s safety mechanism. We then separate each of these categories into several sub-categories.

3.2.1 Complex Lifetime Computation. Lifetime computation may be much more complicated than referring to a variable’s lexical scope. Seventy-seven violations are due to complex lifetime compu tation. For most of them, programmers estimate a variable’s lifetime to be longer or shorter than it actually is, thus violating a safety rule. We further divide these violations into those due to intra-procedural lifetime computation, those due to inter-procedural lifetime compu tation, and those caused by syntax errors when declaring a struct. These sub-categories do not overlap with each other and cover all cases of lifetime computation. Intra-procedural Lifetime Computation. Lifetime computation may be difficult even for cases within a single function. Forty-four vio lations are in this category, 32 of which are cases where program mers miscompute variable lifetimes when using particular code constructs, including control flow constructs (e.g., if, loop), data structures (e.g., hashmap, vector), temporary variables, and program constants. For example, SO#65682678 (Stack Overflow question 65682678 [63]) is caused by miscomputing the lifetime of a refer ence held by a closure, while both SO#63428868 and SO#51044568 are caused by errors when computing a lifetime inside a match block. Eleven out of the 44 violations are due to unsatisfied life time requirements at a function declaration or a struct declaration. For example, when declaring an async function, Rust requires an explicit lifetime annotation for each input object. Violating this

1 struct Foo {} 
2 struct Bar2 <'b > { x : &'b Foo ,} 
3 
4 impl <'b > Bar2 <'b > { 
5 - fn f (&'b mut self ) - > &'b Foo { 
6 + fn f (& mut self ) - > &'b Foo { 
7 self . x 
8 } 
9 } 
10 fn f4 () { 
11 let foo = Foo {}; 
12 let mut bar2 = Bar2 { 
13 x : & foo }; 
14 bar2 . f (); 
15 let z = bar2 . f (); 
16 } 

Figure 4: An example of complex inter-procedural lifetime computation. The red-colored tokens are the root-cause tokens. “+” and “-” denote code added and deleted to fix the violation.

requirement is the root cause of SO#62440972. The remaining vio lation is due to a lack of basic understanding of Rust. Inter-procedural Lifetime Computation. Thirty violations are due to lifetime computation across function boundaries. Among them, 22 are cases where a real parameter does not satisfy the lifetime requirement of its corresponding formal parameter. The remain ing eight are caused by unexpected lifetime extensions through a function call. Figure 4 shows one such example from SO#39827244. Function f() is implemented for struct Bar2 at line 5. It borrows a Bar2 object and returns its field x. Lifetime annotation 'b is speci fied for both input reference self and the return value, so that the questioner thought the borrowing of a Bar2 object ended when the corresponding return terminated its lifetime. The questioner also believed that since the return value at line 14 is not saved to any variable, both the lifetime of the return and the borrow of bar2 ended at line 14. He was confused about how the function still borrowed bar2 after line 14 and why the compiler complained that two mutable references to bar2 exist at line 15. The reason is that lifetime annotation 'b is also applied to struct Bar2 at line 4, so that the borrow conducted by function f() does not stop until the borrowed object ends its lifetime. Thus, the borrow of bar2 at line 14 ends at line 16, which is out of the questioner’s expectation. When declaring a function or a variable, programmers may ex plicitly specify all lifetime annotations or choose to elide some annotations. Among the 30 violations in this category, 16 only in volve explicit lifetime annotations (e.g., Figure 4), and the lifetime miscomputation or mismatch happens at an elided annotation for the remaining 14 cases (e.g., SO#40053550). Simple Syntax Errors. Three violations are caused by the misuse of lifetime annotations when declaring or implementing a struct. For example, the questioner of SO#62422857 only used an apostrophe to annotate a struct field without providing an annotation name.

3.2.2 Violating Ownership Rules. Ownership rules can be divided into move rules and borrowing rules [50]. Among the 41 ownership rule violations in the small dataset, 18 of them violate a move rule, and the remaining 23 do not comply with a borrowing rule. Move Rule Violations. A variable cannot be accessed after it is moved. Non-compliance with this requirement causes 18 violations. Of these, 16 violations involve (complex) program constructs. For example, SO#65873356 is caused by accessing an object that has already been moved to a called function. As another example, when an object is moved to a closure, it may be unclear to programmers whether the move happens at the closure’s creation site or at the location where the closure is firstly used, which is the root cause of SO#62125100. The remaining two cases are very simple, and

we speculate the questioners asked the corresponding questions because they did not know the move rule. Borrowing Rule Violations. Misuse of references leads to 23 vio lations. Two of them are due to mistakenly borrowing a collection of objects altogether, instead of a single element (e.g., Figure 1a). Another two are cases where programmers intended to copy an object using a reference but mistakenly copied the reference itself. Moreover, 11 cases are due to using a reference to move an object, which is not allowed in Rust. For example, “a = *x” moves the ob ject referenced by x if the object does not implement the Copy trait, which confused the questioner of SO#35649968. In addition, mu tability mismatches (e.g., changing a variable using an immutable reference) cause two violations. Rust prohibits a closure from re turning a mutable reference since it leads two mutable references existing simultaneously (one is returned and the other is held by the closure). Not complying with this rule causes three violations. The remaining three are due to not knowing how to use the reference counted library (Rc) or library APIs that take a reference as input. Finding 2: Rust’s safety mechanism may be difficult to apply in concrete usage scenarios. Finding 3: More lifetime-related questions are asked on Stack Over flow than ownership-related questions, indicating lifetime computa tion is more challenging in Rust programming. 3.2.3 How Violations Are Fixed? We examine whether unsafe code is used in the violation patches to understand whether programmers can achieve the desired functionalities while complying with all safety rules. Since eight violations are cases where programmers’ understanding (not implementation) conflicts with the safety rules and therefore have no fix, we focus on the remaining 110 cases. As shown in Table 2, only three violations are fixed by writing unsafe code directly (column “Unsafe”). For example, the questioner of SO#64274964 wants to use two editor objects to modify the same image at the same time. Since the two editors change two different parts of the image, there is no bug logically. However, the Rust compiler does not allow the two editors to have two mutable references to the image at the same time. The patch uses pointers in unsafe code to have two writers for the same image simultaneously. Another 27 violations are patched with interior unsafe library functions (column “IUL” in Table 2). Although the interfaces of those functions are safe and programmers can use them as safe functions, they actually contain unsafe code internally. For exam ple, SO#57766918 is patched by calling interior unsafe function into_iter() [48]. All other violations are fixed by writing safe code directly or using safe library functions (columns “Safe” and “SL” in Table 2). For example, SO#39827244 in Figure 4 is fixed by removing the lifetime annotation of self to break the lifetime binding between the borrow conducted by function f() and the borrowed Bar2 object, and SO#62491845 in Figure 1a is fixed by calling safe standard library function split_first_mut() [49], which returns the first element of the input array. These patches only involve safe code. Finding 4: The majority of safety-rule violations are fixed with safe code, and a small portion of violations are patched using well encapsulated interior unsafe libraries. Programmers usually do not have to write unsafe code by themselves to fix safety-rule violations.

3.3 When Is a Safety Rule More Confusing? To detect when a safety rule is more difficult, we first apply the LDA model [9] to the large dataset. We then follow existing empirical studies on software artifacts [26, 29, 68] and compute a statistical metric lift to measure the correlation between root-cause categories and involved code constructs for the small dataset. 3.3.1 LDA Model. The LDA model can pinpoint the hidden topics of analyzed documents, and the hidden topics of Rust-related Stack Overflow questions describe when programmers feel Rust is more challenging. We take two steps to apply LDA. We first identify questions related to safety rules. We then run LDA on the questions and manually interpret the identified topics. We use Stack Overflow tags to identify questions related to safety rules. Following the taxonomy in Section 3.2, we divide safety rules into three groups: lifetime-related rules, move rules, and borrowing rules. We find 790, 28, and 848 questions respectively for these rule groups in the large dataset. For each group of rules, we use the Gensim package [46] to run bigram LDA on all its identified questions. We remove Rust code in those questions and consider only question titles, descriptions, and answers in the analysis. We preprocess the texts using NLTK [7] to lemmatize words and to remove stop words and punctuations. We try each of the numbers from 5 to 30 as the topic number to configure the model. We manually inspect the results for the topic number with coherence value [33] closest to zero, since a coherence value closer to zero represents a better clustering result. The topic numbers with the best coherence value for lifetime, borrowing, and move are 5, 5, and 9, respectively. After reading the top words and representative questions re ported by LDA, we identify several challenging scenarios for each group of rules. For example, 204 questions contain the topic of how to use lifetime annotations in a trait, 32 questions contain the topic of how to borrow an element from a container, and three questions are about moving an object in a match block. Rust programmers can refer to our identified topics to enhance their understanding of Rust’s safety rules. 3.3.2 Lift Correlation. We use the lift metric to measure the corre lation between the root-cause categories in Section 3.2 and code constructs. The lift of category A and code construct B is computed as lift( ) = ( ) ( ) ( )

, where ( ) represents the probability of a violation that is due to A and also involves B, ( ) means the probability of a violation caused by A, and ( ) denotes the probability of a violation involving B. If lift( ) equals 1, A is in dependent of . If lift( ) is larger than 1, A and B are positively correlated, indicating when A is applied to B, it is more likely to cause problems and it is more challenging. The larger the lift value is, the more positively A and B are correlated. If lift( ) is smaller than 1, A and B are negatively correlated. Among all code constructs with at least ten violations, root cause “inter-procedural lifetime computation” is most correlated with the 'static code construct. The lift value is 2.36. Self-defined annotations and generics are ranked as the second and the third most correlated code constructs with “inter-procedural lifetime computation.” Their lift values are 2.32 and 2.14, respectively. “Intra procedural lifetime computation” is most correlated with standard

library Box, function declarations, and return statements, with lift values 2.19, 1.89, and 1.87, respectively. The top three code constructs correlated with “move rule violations” are loops (1.96), vectors (1.38), and function calls (1.19). The largest three lift values for “borrowing rule violations” are 1.57 for hashmaps, 1.35 for iterators, and 1.31 for closure declarations. Many of those widely used code constructs have different lift values with different root-cause categories. For example, function declarations are positively correlated with “intra-procedural life time computation”, but they are negatively correlated with the other three categories. As another example, generics are positively correlated with “inter-procedural lifetime computation”; however, they are roughly independent of “borrowing rule violations.” Finding 5: The same rule has different difficulty levels when applied to different code constructs, and different rules have different difficulty levels when applied to the same code construct.

3.4 Evaluating Compiler Error Messages As we discussed earlier, 110 rule violations in the small dataset can trigger compiler errors1. The Rust compiler associates 20 different error codes t
