---
source_url: https://blog.rust-lang.org/2026/03/02/2025-State-Of-Rust-Survey-results/
ingested: 2026-09-12
sha256: ea26819964bbadf54972752ab92a238488a673f6619e556df568fb2ab360a773
---
# 2025 State of Rust Survey Results | Rust Blog

2025 State of Rust Survey Results | Rust Blog

Mar. 2, 2026 · The Rust Survey Team

Hello, Rust community!

Once again, the survey team is happy to share the results of the State of Rust survey, this year celebrating a round number - the 10th edition!

The survey ran for 30 days (from November 17th to December, 17th 2025) and collected 7156 responses, a slight decrease in responses compared to last year. In this blog post we will shine a light on some specific key findings. As usual, the full report is available for download.

| Survey | Started | Completed | Completion rate | Views |
| --- | --- | --- | --- | --- |
| 2024 | 9 450 | 7 310 | 77.4% | 13 564 |
| 2025 | 9 389 | 7 156 | 76.2% | 20 397 |

Overall, the answers we received this year pretty closely match the results of last year, differences are often under a single percentage point. The number of respondents decreases slightly year over year. In 2025, we published multiple surveys (such as the Compiler Performance or Variadic Generics survey), which might have also contributed to less people answering this (longer) survey. We plan to discuss how (and whether) to combine the State of Rust survey with the ongoing work on the Rust Vision Doc.

Also to be noted that these numbers should be taken in context: we cannot extrapolate too much from a mere 7 000 answers and some optional questions have even less replies.

Let's point out some interesting pieces of data:

- Screenshotting Rust use
- Challenges and wishes about Rust
- Learning about Rust
- Industry and community

## Screenshotting Rust use

Confirmed that people develop using the stable compiler and keep up with releases, trusting our stability and compatibility guarantees. On the other hand, people use nightly out of "necessity" (for example, something not yet stabilized). Compared to last year (link) we seem to have way less nightly users. This may not be a significant data point because we are looking at a sliding window of releases and differences could depend on many factors (for example, at a specific point in time we might have more downloads of the nightly compiler because of a highly anticipated feature).

One example might be the very popular let chains and async closures features, which were stabilized last year.

[PNG] [SVG] [Wordcloud of open answers]

[PNG] [SVG]

We are also interested to hear from (and grateful to) people not using Rust (or not anymore) when they tell us why they dropped the language. In most cases it seems to be a "see you again in the future" rather than a "goodbye".

[PNG] [SVG]

[PNG] [SVG] [Wordcloud of open answers]

Some specific topic we were interested in: how often people download crates using a git repository pinned in the Cargo.toml (something like`foo = { git = "https://github.com/foo/bar" }`).

[PNG] [SVG] [Wordcloud of open answers]

and if people actually find the output of--explain useful. Internal discussions hinted that we were not too sure about that but this graph contradicts our prior assumption. Seems like many Rust users actually do find compiler error code explanations useful.

[PNG] [SVG] [Wordcloud of open answers]

## Challenges and wishes about Rust

We landed long-awaited features in 2025 (`let chains` and`async closures`) and the survey results show that they are indeed very popular and often used. That's something to celebrate! Now`generic const expressions` and`improved trait methods` are bubbling up in the charts as the most-wanted features. Most of the other desired features didn't change significantly.

[PNG] [SVG] [Wordcloud of open answers]

When asked about which non-trivial problems people encounter, little changes overall compared to 2024: resource usage (slow compile times and storage usage) is still up there. The debugging story slipped from 2nd to 4th place (~2pp). We just started a survey to learn more about it!

[PNG] [SVG] [Wordcloud of open answers]

## Learning about Rust

Noticeable (within a ~3pp) flection in attendance for online and offline communities to learn about Rust (like meetups, discussion forums and other learning material). This hints at some people moving their questions to LLM tooling (as the word cloud for open answers suggests). Still, our online documentation is the preferred canonical reference, followed by studying the code itself.

[PNG] [SVG] [Wordcloud of open answers]

[PNG] [SVG]

## Industry and community

Confirmed the hiring trend from organisations looking for more Rust developers. The steady growth may indicate a structural market presence of Rust in companies, codebases consolidate and the quantity of Rust code overall keeps increasing.

[PNG] [SVG]

As always we try to get a picture of the concerns about the future of Rust. Given the target group we are surveying, unsurprisingly the majority of respondents would like even more Rust! But at the same time concerns persist about the language becoming more and more complex.

Slight uptick for "developer and maintainers support". We know and we are working on it. There are ongoing efforts from RustNL (https://rustnl.org/fund) and on the Foundation side. Funding efforts should focus on retaining talents that otherwise would leave after some time of unpaid labor.

This graph is also a message to companies using Rust: please consider supporting Rust project contributors and authors of Rust crates that you use in your projects. Either by joining the Rust Foundation, by allowing some paid time of your employees to be spent on Rust projects you benefit from or by funding through other collect funds (like https://opencollective.com, https://www.thanks.dev and similar) or personal sponsorships (GitHub, Liberapay or similar personal donation boxes).

Trust in the Rust Foundation is improving, which is definitively good to hear.

[PNG] [SVG] [Wordcloud of open answers]

As a piece of trivia we ask people which tools they use when programming in Rust. The Zed editor did a remarkable jump upward in the preferences of our respondents (with Helix as a good second). Editors with agentic support are also on the rise (as the word cloud shows) and seems they are eroding the userbase of VSCode and IntelliJ, if we were to judge by the histogram.

We're happy to meet again those 11 developers still using Atom (hey 👋!) and we salute those attached to their classic editors choice like Emacs and Vim (or derivatives).

[PNG] [SVG] [Wordcloud of open answers]

And finally, here are some data about marginalized groups, out of all participants who completed our survey:

| Marginalized group | Count | Percentage |
| --- | --- | --- |
| Lesbian, gay, bisexual, queer, or otherwise non-heterosexual | 752 | 10.59% |
| Neurodivergent | 706 | 9.94% |
| Trans | 548 | 7.72% |
| Woman or perceived as a woman | 457 | 6.43% |
| Non-binary gender | 292 | 4.11% |
| Disabled (physically, mentally, or otherwise) | 218 | 3.07% |
| Racial or ethnic minority | 217 | 3.06% |
| Political beliefs | 211 | 2.97% |
| Educational background | 170 | 2.39% |
| Cultural beliefs | 139 | 1.96% |
| Language | 134 | 1.89% |
| Religious beliefs | 100 | 1.41% |
| Other | 61 | 0.86% |
| Older or younger than the average developers I know | 22 | 0.31% |

While some of these numbers have slightly improved, this still shows that only a very small percentage of the people who are part of marginalized groups make it to our project. While we still do better than many other tech communities, it is a reminder that we need to keep working hard on being a diverse and welcoming FOSS community for everyone, which has always been and always will be one of our core values.

## Conclusions

Overall, no big surprises and a few trends confirmed.

If you want to dig more into details, feel free to download the PDF report.

We want once again to thank all the volunteers that helped shaping and translating this survey and to all the participants, who took the time to provide us a picture of the Rust community.

## A look back

Since this year we publish a round number, if you fancy a trip down the memory lane here the blog posts with the past years' survey results:

- 2024 State of Rust Survey results
- 2023 Rust Annual Survey results
- 2022 Rust Annual Survey results
- 2021 Rust Survey results
- 2020 Rust Survey results
- 2019 Rust Survey results
- 2018 Rust Survey results
- 2017 Rust Survey results
- 2016 State of Rust survey
