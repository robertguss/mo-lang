---
source_url: https://arxiv.org/abs/2106.12678
ingested: 2026-09-12
sha256: 70fd57f8ac90acb876e6b5337b8671c209dc1167df7a92d511855f7b6d1c7477
---
# [2106.12678] Native Implementation of Mutable Value Semantics

[2106.12678] Native Implementation of Mutable Value Semantics

 -->

# Computer Science > Programming Languages

arXiv:2106.12678 (cs)

[Submitted on 23 Jun 2021]

# Title:Native Implementation of Mutable Value Semantics

Authors: Dimitri Racordon, Denys Shabalin, Daniel Zheng, Dave Abrahams, Brennan Saeta

View PDF

> Abstract:Unrestricted mutation of shared state is a source of many well-known problems. The predominant safe solutions are pure functional programming, which bans mutation outright, and flow sensitive type systems, which depend on sophisticated typing rules. Mutable value semantics is a third approach that bans sharing instead of mutation, thereby supporting part-wise in-place mutation and local reasoning, while maintaining a simple type system. In the purest form of mutable value semantics, references are second-class: they are only created implicitly, at function boundaries, and cannot be stored in variables or object fields. Hence, variables can never share mutable state. Because references are often regarded as an indispensable tool to write efficient programs, it is legitimate to wonder whether such a discipline can compete other approaches. As a basis for answering that question, we demonstrate how a language featuring mutable value semantics can be compiled to efficient native code. This approach relies on stack allocation for static garbage collection and leverages runtime knowledge to sidestep unnecessary copies.

 

https://doi.org/10.48550/arXiv.2106.12678

 

arXiv-issued DOI via DataCite

| Comments: |
| --- |
| Subjects: | Programming Languages (cs.PL) |
| ACM classes: | D.3.0 |
| Cite as: | arXiv:2106.12678 [cs.PL] |
| (or arXiv:2106.12678v1 [cs.PL] for this version) |

## Submission history

From: Dimitri Racordon [view email] [v1] Wed, 23 Jun 2021 22:40:06 UTC (54 KB)

 

Full-text links:

## Access Paper:

- View PDF
- TeX Source

view license

 

Current browse context:

cs.PL

< prev| next >

new| recent| 2021-06

Change to browse by:

cs

### References & Citations

- Google Scholar
- Semantic Scholar

### DBLP - CS Bibliography

listing| bibtex

Dimitri Racordon

export BibTeX citation

### Bookmark

 

Bibliographic Tools

# Bibliographic and Citation Tools

Bibliographic Explorer Toggle

Bibliographic Explorer (What is the Explorer?)

Connected Papers Toggle

Connected Papers (What is Connected Papers?)

Litmaps Toggle

Litmaps (What is Litmaps?)

scite.ai Toggle

scite Smart Citations (What are Smart Citations?)

Code, Data, Media

# Code, Data and Media Associated with this Article

alphaXiv Toggle

alphaXiv (What is alphaXiv?)

Links to Code Toggle

CatalyzeX Code Finder for Papers (What is CatalyzeX?)

DagsHub Toggle

DagsHub (What is DagsHub?)

GotitPub Toggle

Gotit.pub (What is GotitPub?)

Huggingface Toggle

Hugging Face (What is Huggingface?)

Links to Code Toggle

Papers with Code (What is Papers with Code?)

ScienceCast Toggle

ScienceCast (What is ScienceCast?)

Demos

# Demos

Replicate Toggle

Replicate (What is Replicate?)

Spaces Toggle

Hugging Face Spaces (What is Spaces?)

Spaces Toggle

TXYZ.AI (What is TXYZ.AI?)

Related Papers

# Recommenders and Search Tools

Link to Influence Flower

Influence Flower (What are Influence Flowers?)

Core recommender toggle

CORE Recommender (What is CORE?)

- Author
- Venue
- Institution
- Topic

About arXivLabs

# arXivLabs: experimental projects with community collaborators

arXivLabs is a framework that allows collaborators to develop and share new arXiv features directly on our website.

Both individuals and organizations that work with arXivLabs have embraced and accepted our values of openness, community, excellence, and user data privacy. arXiv is committed to these values and only works with partners that adhere to them.

Have an idea for a project that will add value for arXiv's community? Learn more about arXivLabs.

 

Which authors of this paper are endorsers?| Disable MathJax(What is MathJax?)
