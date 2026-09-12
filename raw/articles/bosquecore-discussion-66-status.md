---
source_url: https://github.com/BosqueLanguage/BosqueCore/discussions/66
ingested: 2026-09-12
sha256: cbeae8c4d0a9d230720b826775e1fe2e20e44535b9dbaa59d42ba147fe82a45c
---
# Seeking information about the current state of the project · BosqueLanguage/BosqueCore · Discussion #66 · GitHub

Seeking information about the current state of the project · BosqueLanguage/BosqueCore · Discussion #66 · GitHub

# Seeking information about the current state of the project #66

Floriansylvain started this conversation in General

Seeking information about the current state of the project #66

Return to top

## Floriansylvain Aug 13, 2023

Hello!

I am writing to find out more about the current state of the Bosque programming language. As an enthusiast of programming languages, I have been intrigued by the features and design principles that Bosque aims to bring to the table.

However, I have encountered some difficulty in finding recent and reliable information regarding the ongoing development and trajectory of the Bosque project. It appears that there is limited discussion and updates available online, and notably, there seems to be a lack of communication from the (old?) project's sponsor, Microsoft.

I would greatly appreciate it if anyone within the old/new contributors, could provide insights into the following questions:

- What is the current general status of the Bosque programming language? Is it still actively being developed?
- Has there been any official communication or indication from Microsoft (or anyone else) regarding their involvement and support for the Bosque project? Is it safe to assume that the project has not been abandoned?
- Are there still individuals or groups actively contributing to the Bosque project or planning to do so?
- Could you share any insights or speculations on the potential future direction of the Bosque project? Any information regarding upcoming goals would be of great interest.

I apologize if my inquiries seem redundant or if this information is available elsewhere, but my attempts to gather information have proven to be somewhat challenging. Any insights would undoubtedly help shed light on the current state of the project.

Warm regards!

3

👍 2

## 2 comments 1 reply

### MicahZoltu Aug 13, 2023

I don't know the answer but I'm hoping you get one! I subscribed to the this repository so I could get alerted if it ever picks up steam.

To answer one of your questions, the commit history suggests that this is still under active development, though it appears by a single person. It could be a personal/hobby project, or it may be sponsored (difficult to tell from commit history alone).

🤞 someone answers the rest of your question!

2

👍 2

0 replies

### marron-at-work Aug 13, 2023 Collaborator

Hi@Floriansylvain and@MicahZoltu, thanks for the questions and interest in the project. I am Mark the lead researcher and developer of Bosque, formerly at Microsoft, and now as an independent project. Let me try to answer the questions you have:

1. Bosque is definitely being actively developed. I left MSR last year and started moving the into a fully open-source and community based project. I am currently doing some consulting work that is related to the project and will join the University of Kentucky CS department in January. Bosque will continue to be my (and my students) primary focus.
2. I will post more updates shortly but the current focus is to dogfood the Bosque toolchain in Bosque. Starting with porting the prototype SMT powered checker from TypeScript to Bosque. Once this is done (plenty bugs fixed and std lib code added) I believe the system will be ready to start encouraging actual use in (simple) production scenarios.
3. I got notification today on the acceptance of an overview paper of the Bosque project and some of the major near terms goals into SPLASH Onward!. I will be revising a bit based on the review comments but that paper will be available shortly with more information on some key future directions.

Some of these include (1) a`small-model validator` that is designed to always, in theory and usually in practice, find a small repro for any possible error in an application, (2) a novel data-format language that makes writing inline tests and examples simple + a Prorogued Programming engine to make`(non-trivial) LLM based code-generation reliable/simple`, and work on integrating all of this, along with`auto-mocking`,`test generation`, and versioning work with existing service based development paradigms.

I'll also be posting updates to the Bosque account on X (twitter)!

3

👍 1 ❤️ 1

1 reply

#### Floriansylvain Aug 13, 2023 Author

Thanks a ton for the super insightful update! It's genuinely awesome to hear that Bosque is still going strong and you're at the helm. The whole shift to being open-source and community-focused is really nice, and it's especially cool to see you're not just keeping it alive, but also getting students involved. Sending you all the luck for your overview paper at SPLASH Onward! and thanks for the heads-up about the Bosque Twitter updates. I'm definitely clicking that follow button 😄

Sign up for free to join this conversation on GitHub. Already have an account? Sign in to comment

Category

Labels

None yet

3 participants
