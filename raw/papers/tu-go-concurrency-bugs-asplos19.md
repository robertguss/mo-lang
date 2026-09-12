---
source_url: https://songlh.github.io/paper/go-study.pdf
ingested: 2026-09-12
sha256: 7de45a2d362609f1429cef8e405ead301c8fc5a1c62c99f844d8578234e190ae
---
# Understanding Real-World Concurrency Bugs in Go

## Understanding Real-World Concurrency Bugs in Go Tengfei Tu∗

BUPT, Pennsylvania State University tutengfei.kevin@bupt.edu.cn

Xiaoyu Liu Purdue University liu1962@purdue.edu

Linhai Song Pennsylvania State University songlh@ist.psu.edu

Yiying Zhang Purdue University yiying@purdue.edu

Abstract Go is a statically-typed programming language that aims to provide a simple, efficient, and safe way to build multi threaded software. Since its creation in 2009, Go has ma tured and gained significant adoption in production and open-source software. Go advocates for the usage of mes sage passing as the means of inter-thread communication and provides several new concurrency mechanisms and li braries to ease multi-threading programming. It is important to understand the implication of these new proposals and the comparison of message passing and shared memory synchro nization in terms of program errors, or bugs. Unfortunately, as far as we know, there has been no study on Go’s concur rency bugs. In this paper, we perform the first systematic study on concurrency bugs in real Go programs. We studied six pop ular Go software including Docker, Kubernetes, and gRPC. We analyzed 171 concurrency bugs in total, with more than half of them caused by non-traditional, Go-specific problems. Apart from root causes of these bugs, we also studied their fixes, performed experiments to reproduce them, and eval uated them with two publicly-available Go bug detectors. Overall, our study provides a better understanding on Go’s concurrency models and can guide future researchers and practitioners in writing better, more reliable Go software and in developing debugging and diagnosis tools for Go. CCS Concepts • Computing methodologies → Con current programming languages; • Software and its en gineering → Software testing and debugging.

∗The work was done when Tengfei Tu was a visiting student at Pennsylvania State University. Permission to make digital or hard copies of all or part of this work for personal or classroom use is granted without fee provided that copies are not made or distributed for profit or commercial advantage and that copies bear this notice and the full citation on the first page. Copyrights for components of this work owned by others than ACM must be honored. Abstracting with credit is permitted. To copy otherwise, or republish, to post on servers or to redistribute to lists, requires prior specific permission and/or a fee. Request permissions from permissions@acm.org. ASPLOS’19, April 13–17, 2019, Providence, RI, USA © 2019 Association for Computing Machinery. ACM ISBN ISBN 978-1-4503-6240-5/19/04. . . $15.00 https://doi.org/10.1145/3297858.3304069

Keywords Go; Concurrency Bug; Bug Study 
ACM Reference Format: 
Tengfei Tu, Xiaoyu Liu, Linhai Song, and Yiying Zhang. 2019. Un 
derstanding Real-World Concurrency Bugs in Go . In Proceedings 
of 2019 Architectural Support for Programming Languages and Op 
erating Systems (ASPLOS’19). ACM, New York, NY, USA, 14 pages. 
https://doi.org/10.1145/3297858.3304069 

1 Introduction Go [20] is a statically typed language originally developed by Google in 2009. Over the past few years, it has quickly gained attraction and is now adopted by many types of soft ware in real production. These Go applications range from libraries [19] and high-level software [26] to cloud infrastruc ture software like container systems [13, 36] and key-value databases [10, 15]. A major design goal of Go is to improve traditional multi threaded programming languages and make concurrent pro gramming easier and less error-prone. For this purpose, Go centers its multi-threading design around two principles: 1) making threads (called goroutines) lightweight and easy to create and 2) using explicit messaging (called channel) to communicate across threads. With these design princi ples, Go proposes not only a set of new primitives and new libraries but also new implementation of existing semantics. It is crucial to understand how Go’s new concurrency prim itives and mechanisms impact concurrency bugs, the type of bugs that is the most difficult to debug and the most widely studied [40, 43, 45, 57, 61] in traditional multi-threaded pro gramming languages. Unfortunately, there has been no prior work in studying Go concurrency bugs. As a result, to date, it is still unclear if these concurrency mechanisms actually make Go easier to program and less error-prone to concur rency bugs than traditional languages. In this paper, we conduct the first empirical study on Go concurrency bugs using six open-source, production grade Go applications: Docker [13] and Kubernetes [36], two datacenter container systems, etcd [15], a distributed key-value store system, gRPC [19], an RPC library, and Cock roachDB [10] and BoltDB [6], two database systems. In total, we have studied 171 concurrency bugs in these ap plications. We analyzed the root causes of them, performed experiments to reproduce them, and examined their fixing patches. Finally, we tested them with two existing Go con currency bug detectors (the only publicly available ones). Our study focuses on a long-standing and fundamental question in concurrent programming: between message pass ing [27, 37] and shared memory, which of these inter-thread communication mechanisms is less error-prone [2, 11, 48]. Go is a perfect language to study this question, since it pro vides frameworks for both shared memory and message passing. However, it encourages the use of channels over shared memory with the belief that explicit message passing is less error-prone [1, 2, 21]. To understand Go concurrency bugs and the comparison between message passing and shared memory, we propose to categorize concurrency bugs along two orthogonal dimen sions: the cause of bugs and their behavior. Along the cause dimension, we categorize bugs into those that are caused by misuse of shared memory and those caused by misuse of message passing. Along the second dimension, we separate bugs into those that involve (any number of) goroutines that cannot proceed (we call them blocking bugs) and those that do not involve any blocking (non-blocking bugs). Surprisingly, our study shows that it is as easy to make con currency bugs with message passing as with shared memory, sometimes even more. For example, around 58% of blocking bugs are caused by message passing. In addition to the viola tion of Go’s channel usage rules (e.g., waiting on a channel that no one sends data to or close), many concurrency bugs are caused by the mixed usage of message passing and other new semantics and new libraries in Go, which can easily be overlooked but hard to detect. To demonstrate errors in message passing, we use a block ing bug from Kubernetes in Figure 1. The finishReq func tion creates a child goroutine using an anonymous func tion at line 4 to handle a request—a common practice in Go server programs. The child goroutine executes fn() and sends result back to the parent goroutine through channel ch at line 6. The child will block at line 6 until the parent pulls result from ch at line 9. Meanwhile, the parent will block at select until either when the child sends result to ch (line 9) or when a timeout happens (line 11). If timeout hap pens earlier or if Go runtime (non-deterministically) chooses the case at line 11 when both cases are valid, the parent will return from requestReq() at line 12, and no one else can pull result from ch any more, resulting in the child being blocked forever. The fix is to change ch from an unbuffered channel to a buffered one, so that the child goroutine can always send the result even when the parent has exit. This bug demonstrates the complexity of using new fea tures in Go and the difficulty in writing correct Go programs like this. Programmers have to have a clear understanding of goroutine creation with anonymous function, a feature Go proposes to ease the creation of goroutines, the usage of buffered vs. unbuffered channels, the non-determinism of waiting for multiple channel operations using select,

1 func finishReq(timeout time.Duration) r ob { 
2 - ch := make(chan ob) 
3 + ch := make(chan ob, 1) 
4 go func() { 
5 result := fn() 
6 ch <- result // block 
7 } () 
8 select { 
9 case result = <- ch: 
10 return result 
11 case <- time.After(timeout): 
12 return nil 
13 } 
14 } 

Figure 1. A blocking bug caused by channel. and the special library time. Although each of these fea tures were designed to ease multi-threaded programming, in reality, it is difficult to write correct Go programs with them. Overall, our study reveals new practices and new issues of Go concurrent programming, and it sheds light on an answer to the debate of message passing vs. shared memory accesses. Our findings improve the understanding of Go concurrency and can provide valuable guidance for future tool design. This paper makes the following key contributions.

• We performed the first empirical study of Go concur rency bugs with six real-world, production-grade Go applications. 
• We made nine high-level key observations of Go con currency bug causes, fixes, and detection. They can be useful for Go programmers’ references. We further make eight insights into the implications of our study results to guide future research in the development, testing, and bug detection of Go. 
• We proposed new methods to categorize concurrency bugs along two dimensions of bug causes and behav iors. This taxonomy methodology helped us to better compare different concurrency mechanisms and corre lations of bug causes and fixes. We believe other bug studies can utilize similar taxonomy methods as well. All our study results and studied commit logs can be found at https://github.com/system-pclub/go-concurrency-bugs. 
2 Background and Applications 
Go is a statically-typed programming language that is de 
signed for concurrent programming from day one [60]. Al 
most all major Go revisions include improvements in its con 
currency packages [23]. This section gives a brief background 
on Go’s concurrency mechanisms, including its thread model, 
inter-thread communication methods, and thread synchro 
nization mechanisms. We also introduce the six Go applica 
tions we chose for this study. 
2.1 Goroutine 
Go uses a concept called goroutine as its concurrency unit. 
Goroutines are lightweight user-level threads that the Go 

runtime library manages and maps to kernel-level threads in an M-to-N way. A goroutine can be created by simply adding the keyword go before a function call. To make goroutines easy to create, Go also supports creat ing a new goroutine using an anonymous function, a function definition that has no identifier, or “name”. All local variables declared before an anonymous function are accessible to the anonymous function, and are potentially shared between a parent goroutine and a child goroutine created using the anonymous function, causing data race (Section 6).

2.2 Synchronization with Shared Memory Go supports traditional shared memory accesses across goroutines. It supports various traditional synchroniza tion primitives like lock/unlock (Mutex), read/write lock (RWMutex), condition variable (Cond), and atomic read/write (atomic). Go’s implementation of RWMutex is different from pthread_rwlock_t in C. Write lock requests in Go have a higher privilege than read lock requests. As a new primitive introduced by Go, Once is designed to guarantee a function is only executed once. It has a Do method, with a function f as argument. When Once.Do(f) is invoked many times, only for the first time, f is executed. Once is widely used to ensure a shared variable only be initialized once by multiple goroutines. Similar to pthread_join in C, Go uses WaitGroup to al low multiple goroutines to finish their shared variable ac cesses before a waiting goroutine. Goroutines are added to a WaitGroup by calling Add. Goroutines in a WaitGroup use Done to notify their completion, and a goroutine calls Wait to wait for the completion notification of all goroutines in a WaitGroup. Misusing WaitGroup can cause both blocking bugs (Section 5) and non-blocking bugs (Section 6).

2.3 Synchronization with Message Passing Channel (chan) is a new concurrency primitive introduced by Go to send data and states across goroutines and to build more complex functionalities [3, 50]. Go supports two types of channels: buffered and unbuffered. Sending data to (or receiving data from) an unbuffered channel will block a gor outine, until another goroutine receives data from (or sends data to) the channel. Sending to a buffered channel will only block, when the buffer is full. There are several underlying rules in using channels and the violation of them can create concurrency bugs. For example, channel can only be used after initialization, and sending data to (or receiving data from) a nil channel will block a goroutine forever. Sending data to a closed channel or close an already closed channel can trigger a runtime panic. The select statement allows a goroutine to wait on mul tiple channel operations. A select will block until one of its cases can make progress or when it can execute a default branch. When more than one cases in a select are valid, Go will randomly choose one to execute. This randomness can cause concurrency bugs as will be discussed in Section 6. Go introduces several new semantics to ease the interac tion across multiple goroutines. For example, to assist the programming model of serving a user request by spawn ing a set of goroutines that work together, Go introduces context to carry request-specific data or metadata across goroutines. As another example, Pipe is designed to stream data between a Reader and a Writer. Both context and Pipe are new forms of passing messages and misusing them can create new types of concurrency bugs (Section 5).

Application Stars Commits Contributors LOC Dev History Docker 48975 35149 1767 786K 4.2 Years Kubernetes 36581 65684 1679 2297K 3.9 Years etcd 18417 14101 436 441K 4.9 Years CockroachDB 13461 29485 197 520k 4.2 Years gRPC* 5594 2528 148 53K 3.3 Years BoltDB 8530 816 98 9K 4.4 Years

Table 1. Information of selected applications. The num ber of stars, commits, contributors on GitHub, total source lines of code, and development history on GitHub. *: the gRPC version that is written in Go.

2.4 Go Applications Recent years have seen a quick increase in popularity and adoption of the Go language. Go was the 9th most popular language on GitHub in 2017 [18]. As of the time of writing, there are 187K GitHub repositories written in Go. In this study, we selected six representative, real-world software written in Go, including two container systems (Docker and Kubernetes), one key-value store system (etcd), two databases (CockroachDB and BoltDB), and one RPC library (gRPC-go1) (Table 1). These applications are open source projects that have gained wide usages in datacenter environments. For example, Docker and Kubernetes are the top 2 most popular applications written in Go on GitHub, with 48.9K and 36.5K stars (etcd is the 10th, and the rest are ranked in top 100). Our selected applications all have at least three years of development history and are actively main tained by developers currently. All our selected applications are of middle to large sizes, with lines of code ranging from 9 thousand to more than 2 million. Among the six applications, Kubernetes and gRPC are projects originally developed by Google.

3 Go Concurrency Usage Patterns Before studying Go concurrency bugs, it is important to first understand how real-world Go concurrent programs are like. This section presents our static and dynamic analysis results of goroutine usages and Go concurrency primitive usages in our selected six applications.

1We will use gRPC to represent the gRPC version that is written Go in the following paper, unless otherwise specified.

Application Normal F. Anonymous F. Total Per KLOC Docker 33 112 145 0.18 Kubernetes 301 233 534 0.23 etcd 86 211 297 0.67 CockroachDB 27 125 152 0.29 gRPC-Go 14 30 44 0.83 BoltDB 2 0 2 0.22 gRPC-C 5 - 5 0.03

Table 2. Number of goroutine/thread creation sites. The number of goroutine/thread creation sites using normal functions and anonymous functions, total number of creation sites, and creation sites per thousand lines of code. Workload Goroutines/Threads Ave. Execution Time client server client-Go server-Go g_sync_ping_pong 7.33 2.67 63.65% 76.97% sync_ping_pong 7.33 4 63.23% 76.57% qps_unconstrained 201.46 6.36 91.05% 92.73%

Table 3. Dynamic information when executing RPC benchmarks. The ratio of goroutine number divided by thread number and the average goroutine execution time normalized by the whole application’s execution time.

3.1 Goroutine Usages To understand concurrency in Go, we should first under stand how goroutines are used in real-world Go programs. One of the design philoshopies in Go is to make goroutines lightweight and easy to use. Thus, we ask “do real Go pro grammers tend to write their code with many goroutines (static)?” and “do real Go applications create a lot of gorou tines during runtime (dynamic)?” To answer the first question, we collected the amount of goroutine creation sites (i.e., the source lines that create goroutines). Table 2 summarizes the results. Overall, the six applications use a large amount of goroutines. The av erage creation sites per thousand source lines range from 0.18 to 0.83. We further separate creation sites to those that use normal functions to create goroutines and those that use anonymous functions. All the applications except for Kubernetes and BoltDB use more anonymous functions. To understand the difference between Go and traditional languages, we also analyzed another implementation of gRPC, gRPC-C, which is implemented in C/C++. gRPC-C con tains 140K lines of code and is also maintained by Google’s gRPC team. Compared to gRPC-Go, gRPC-C has surprisingly very few threads creation (only five creation sites and 0.03 sites per KLOC). We further study the runtime creation of goroutines. We ran gRPC-Go and gRPC-C to process three performance benchmarks that were designed to compare the performance of multiple gRPC versions written in different program ming languages [22]. These benchmarks configure gRPC with different message formats, different numbers of con nections, and synchronous vs. asynchronous RPC requests. Since gRPC-C is faster than gRPC-Go [22], we ran gRPC-C and gRPC-Go to process the same amount of RPC requests, instead of the same amount of total time.

Application Shared Memory Message Total Mutex atomic Once WaitGroup Cond chan Misc. Docker 62.62% 1.06% 4.75% 1.70% 0.99% 27.87% 0.99% 1410 Kubernetes 70.34% 1.21% 6.13% 2.68% 0.96% 18.48% 0.20% 3951 etcd 45.01% 0.63% 7.18% 3.95% 0.24% 42.99% 0 2075 CockroachDB 55.90% 0.49% 3.76% 8.57% 1.48% 28.23% 1.57% 3245 gRPC-Go 61.20% 1.15% 4.20% 7.00% 1.65% 23.03% 1.78% 786 BoltDB 70.21% 2.13% 0 0 0 23.40% 4.26% 47

Table 4. Concurrency Primitive Usage. The Mutex column includes both Mutex and RWMutex.

Table 3 shows the ratio of the number of goroutines cre ated in gRPC-Go over the number of threads created in gRPC C when running the three workloads. More goroutines are created across different workloads for both the client side and the server side. Table 3 also presents our study results of goroutine runtime durations and compare them to gRPC-C’s thread runtime durations. Since gRPC-Go and gRPC-C’s total execution time is different and it is meaningless to compare absolute goroutine/thread duration, we report and compare the goroutine/thread duration relative to the total runtime of gRPC-Go and gRPC-C. Specifically, we calculate average execution time of all goroutines/threads and normalize it using the total execution time of the programs. We found all threads in gRPC-C execute from the beginning to the end of the whole program (i.e., 100%) and thus only included the results of gRPC-Go in Table 3. For all workloads, the normal ized execution time of goroutines is shorter than threads. Observation 1: Goroutines are shorter but created more fre quently than C (both statically and at runtime). 3.2 Concurrency Primitive Usages After a basic understanding of goroutine usages in real-world Go programs, we next study how goroutines communicate and synchronize in these programs. Specifically, we calcu late the usages of different types of concurrency primitives in the six applications. Table 4 presents the total (absolute amount of primitive usages) and the proportion of each type of primitive over the total primitives. Shared memory syn chronization operations are used more often than message passing, and Mutex is the most widely-used primitive across all applications. For message-passing primitives, chan is the one used most frequently, ranging from 18.48% to 42.99%. We further compare the usages of concurrency primitives in gRPC-C and in gRPC-Go. gRPC-C only uses lock, and it is used in 746 places (5.3 primitive usages per KLOC). gRPC-Go uses eight different types of primitives in 786 places (14.8 primitive usages per KLOC). Clearly, gRPC-Go uses a larger amount of and a larger variety of concurrency primitives than gRPC-C. Next, we study how the usages of concurrency primitives change over time. Figures 2 and 3 present the shared-memory and message-passing primitive usages in the six applications from Feb 2015 to May 2018. Overall, the usages tend to be stable over time, which also implies that our study results will be valuable for future Go programmers.

.

1

5 −

0

2

1

5 −

0

5

1

5 −

0

8

1

5 −

1

1

1

6 −

0

2

1

6 −

0

5

1

6 −

0

8

1

6 −

1

1

1

7 −

0

2

1

7 −

0

5

1

7 −

0

8

1

7 −

1

1

1

8 −

0

2

1

8 −

0

5

0

0.2

0.4

0.6

0.8

docker kubernetes etcd cockroachdb grpc−go boltdb

Figure 2. Usages of Shared-Memory

Primitives over Time. For each appli cation, we calculate the proportion of shared memory primitives over all primitives.

.

1

5 −

0

2

1

5 −

0

5

1

5 −

0

8

1

5 −

1

1

1

6 −

0

2

1

6 −

0

5

1

6 −

0

8

1

6 −

1

1

1

7 −

0

2

1

7 −

0

5

1

7 −

0

8

1

7 −

1

1

1

8 −

0

2

1

8 −

0

5

0

0.2

0.4

0.6

0.8

docker kubernetes etcd cockroachdb grpc−go boltdb

Figure 3. Usages of Message

Passing Primitives over Time. For each application, we calculate the proportion of message-passing primitives over all

primitives.

Bug Life Time (Days)

B u g s

0 100 200 300 400 500 600 700

0

0.2

0.4

0.6

0.8

shared memory message passing

Figure 4. Bug Life Time. The CDF of the life time of all shared-memory bugs and all message-passing bugs.

Observation 2: Although traditional shared memory thread communication and synchronization remains to be heavily used, Go programmers also use significant amount of message

passing primitives.

Implication 1: With heavier usages of goroutines and new types of concurrency primitives, Go programs may potentially introduce more concurrency bugs.

4 Bug Study Methodology

This section discusses how we collected, categorized, and reproduced concurrency bugs in this study.

Collecting concurrency bugs. To collect concurrency bugs, we first filtered GitHub commit histories of the six applications by searching their commit logs for concurrency related keywords, including “race”, “deadlock”, “synchroniza tion”, “concurrency”, “lock”, “mutex”, “atomic”, “compete”, “context”, “once”, and “goroutine leak”. Some of these key words are used in previous works to collect concurrency bugs in other languages [40, 42, 45]. Some of them are re lated to new concurrency primitives or libraries introduced by Go, such as “once” and “context”. One of them, “goroutine leak”, is related to a special problem in Go. In total, we found

3211 distinct commits that match our search criteria.

Application Behavior Cause blocking non-blocking shared memory message passing

Docker 21 23 28 16

Kubernetes 17 17 20 14 etcd 21 16 18 19

CockroachDB 12 16 23 5 gRPC 11 12 12 11

BoltDB 3 2 4 1

Total 85 86 105 66

Table 5. Taxonomy. This table shows how our studied bugs dis tribute across different categories and applications.

We then randomly sampled the filtered commits, identified commits that fix concurrency bugs, and manually studied them. Many bug-related commit logs also mention the cor responding bug reports, and we also study these reports for our bug analysis. We studied 171 concurrency bugs in total.

Bug taxonomy. We propose a new method to categorize Go concurrency bugs according to two orthogonal dimensions.

The first dimension is based on the behavior of bugs. If one or more goroutines are unintentionally stuck in their execution and cannot move forward, we call such concurrency issues blocking bugs. If instead all goroutines can finish their tasks but their behaviors are not desired, we call them non-blocking ones. Most previous concurrency bug studies [24, 43, 45] categorize bugs into deadlock bugs and non-deadlock bugs, where deadlocks include situations where there is a circular wait across multiple threads. Our definition of blocking is broader than deadlocks and include situations where there is no circular wait but one (or more) goroutines wait for resources that no other goroutines supply. As we will show in Section 5, quite a few Go concurrency bugs are of this kind. We believe that with new programming habits and semantics with new languages like Go, we should pay more attention to these non-deadlock blocking bugs and extend the traditional concurrency bug categorization mechanism.

The second dimension is along the cause of concurrency bugs. Concurrency bugs happen when multiple threads try to communicate and errors happen during such communication.

Our idea is thus to categorize causes of concurrency bugs by how different goroutines communicate: by accessing shared memory or by passing messages. This categorization can help programmers and researchers choose better ways to perform inter-thread communication and to detect and avoid potential errors when performing such communication.

According to our categorization method, there are a total of 85 blocking bugs and 86 non-blocking bugs, and there are a total of 105 bugs caused by wrong shared memory protection and 66 bugs caused by wrong message passing.

Table 5 shows the detailed breakdown of bug categories

across each application.

We further analyzed the life time of our studied bugs, i.e., the time from when the buggy code was added (committed)

to the software to when it is being fixed in the software (a bug fixing patch is committed). As shown in Figure 4, most bugs we study (both shared memory and message passing) have long life time. We also found the time when these bugs were report to be close to when they were fixed. These results show that most of the bugs we study are not easy to be

Application Shared Memory Message Passing Mutex RWMutex Wait Chan Chan w/ Lib Docker 9 0 3 5 2 2 Kubernetes 6 2 0 3 6 0 etcd 5 0 0 10 5 1 CockroachDB 4 3 0 5 0 0 gRPC 2 0 0 6 2 1 BoltDB 2 0 0 0 1 0 Total 28 5 3 29 16 4

Table 6. Blocking Bug Causes. Wait includes both the Wait function in Cond and in WaitGroup. Chan indicates channel opera tions and Chan w/ means channel operations with other operations. Lib stands for Go libraries related to message passing.

triggered or detected, but once they are, they got fixed very soon. Thus, we believe these bugs are non-trivial and worth close examination. Reproducing concurrency bugs. In order to evaluate the built-in deadlock and data-race detection techniques, we reproduced 21 blocking bugs and 20 non-blocking bugs. To reproduce a bug, we rolled the application back to the buggy version, built the buggy version, and ran the built program using the bug-triggering input described in the bug report. We leveraged the symptom mentioned in the bug report to decide whether we have successfully reproduced a bug. Due to their non-deterministic nature, concurrency bugs are difficult to reproduce. Sometimes, we needed to run a buggy program a lot of times or manually add sleep to a buggy program. For a bug that is not reproduced, it is either because we do not find some dependent libraries, or because we fail to observe the described symptom. Threats to validity. Threats to the validity of our study could come from many aspects. We selected six represen tative Go applications. There are many other applications implemented in Go and they may not share the same con currency problems. We only studied concurrency bugs that have been fixed. There could be other concurrency bugs that are rarely reproduced and are never fixed by developers. For some fixed concurrency bugs, there is too little infor mation provided, making them hard to understand. We do not include these bugs in our study. Despite these limita tions, we have made our best efforts in collecting real-world Go concurrency bugs and in conducting a comprehensive and unbiased study. We believe that our findings are general enough to motivate and guide future research on fighting Go concurrency bugs.

5 Blocking Bugs 
This section presents our study results on blocking bugs, 
including their root causes, fixes, and the effectiveness of the 
built-in runtime Go deadlock detector on detecting blocking 
situations. 
5.1 Root Causes of Blocking Bugs 
Blocking bugs manifest when one or more goroutines con 
duct operations that wait for resources, and these resources 

are never available. To detect and avoid blocking bugs, it is important to understand their root causes. We study block ing bugs’ root causes by examining which operation blocks a goroutine and why the operation is not unblocked by other goroutines. Using our second dimension of bug categoriza tion, we separate blocking bugs into those that are caused by stuck operations that are intended to protect shared mem ory accesses and those that are caused by message passing operati
