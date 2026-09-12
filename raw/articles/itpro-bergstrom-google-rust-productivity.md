---
source_url: https://www.itpro.com/software/development/google-devs-ditched-c-for-rust-heres-what-happened
ingested: 2026-09-12
sha256: 83771bd7f8f06e9f0f47652a69ec24d1e66e1617b417266a305598a675e2cab0
---
# Google devs ditched C++ for Rust — here's what happened | IT Pro

Google devs ditched C++ for Rust — here's what happened | IT Pro

# Google devs ditched C++ for Rust — here's what happened

Rust developers are twice as productive as their counterparts using other programming languages such as C++

 By Steve Ranger 

 Published 4 April 2024 In News 

 (Image credit: Getty Images) 

Developers writing in Rust can be twice as productive as teams using C++ when it comes to rewriting code, according to one of Google’s software executives.

Speaking at the Rust Nation UK conference last week, Lars Bergstrom, a director of engineering at Google’s Android team, said Rust has firmly staked its place as a leading programming language both in terms of performance and security.

The latter of these aspects, he noted, has been a recurring topic in recent months amidst growing concerns over the use of non-memory safe languages, including warnings from US lawmakers.

“Everyone is sort of recognizing that software plays such a crucial role in not only our critical infrastructure for our governments, but also for the end users and the software that they're getting delivered,” he said.

But comparing developer productivity across programming languages has often been hard to measure. That is, Bergstrom pointed out, unless you are a company like Google, which has had hundreds of developers rewriting a myriad of systems over the last couple of years.

“We have at this point, at Google, rewritten a large number of systems, whether we've ported them incrementally or rewritten them from C++ and so we actually have some very concrete things that we can say,” he said.

Back in 2021, Google said that the Android Open Source Project would support Rust for developing the operating system itself as a key way to prevent memory safety bugs, which were the biggest source of Android’s high-severity security vulnerabilities.

He said that when Google has rewritten systems from Go into Rust it takes about the same size team and about the same amount of time to build it.

That means there's no loss in productivity when moving from Go to Rust, and Bergstrom said there were some benefits from it too, like reduced memory usage in the services that have moved from Go and a “decreased defect rate” over time in those that have been rewritten in Rust.

## Rewrites to Rust deliver tangible benefits

Rewrites from C++ to Rust also delivered significant benefits, Bergstrom said, especially in terms of the effort applied by developers. 

“Comparing our rewrites of C++ code into Rust...in every case we've seen a decrease by more than 2x in the amount of effort required to both build the services in Rust as well as maintain and update those services written in Rust,” he revealed.

“So that's a really huge thing for us because C++ code is very expensive, these are large teams, it's a lot of work, there's a lot of risk, and so I'm really happy to be able to share some of that data.”

Bergstrom referenced a 2022 survey of Google developers who have used Rust, which found that more than two-thirds were confident in contributing to the language’s codebase within two months of learning it.

Still, Rust didn’t win over everyone. Around 15% said it took them between three and four months, 8% said it took more than four months, and another 8%said they were still not productive.

Google is doing a similar migration in the Java ecosystem by moving developers from Java to Kotlin, he noted. For developers traditionally working on Java, getting them comfortable and ready to contribute to Kotlin takes roughly eight weeks.

“So it takes about as long for us to retrain a C++ developer to use Rust as it does for us to train a Java developer to Kotlin,” said Bergstrom.

Bergstrom also pointed to data from the survey that found one-in-three said they became as productive using Rust as they were in other languages within two months of learning it. That’s not the case for everyone, though. 

One-third also said it took three to four months or longer, while almost a third said they were still not as good in Rust as they had been in their previous languages.

More than half of respondents said Rust code is easier to review than other languages. Similarly, 85% percent said they are more confident that their Rust code is correct compared to other languages.

“I'm fortunate in my 25-year career to have been part of the beginning of many programming languages and gone through the ecosystem and I think that Rust has uniquely invested in tooling, in documentation, and in culture compared to all the other languages I've been with,” he said.

## No widespread rewrites expected any time soon

That doesn’t mean there’s any desire to go back and rewrite the millions of lines of C++ code inside Android, however. 

The vast majority of security defects are in new code, he said, so going back to old code that may have been through rounds of fuzzers, sanitizers, and external security audits is not worth the cost, but also not worth the risk of introducing new problems.

Rust has grown in popularity in recent years, but it’s by no means the most popular programming language. Stack Overflow’s 2023 developer survey ranked it as 12th in the list of most popular languages.

Similarly, Rust only comes in at 19th on RedMonk’s Programming Language Rankings metrics.

However, Rust is considered to be a memory-safe language, unlike C++, which is why it has been used by many organizations, including Google, to rewrite older code.
