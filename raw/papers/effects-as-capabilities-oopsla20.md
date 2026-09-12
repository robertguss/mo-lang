---
source_url: https://ps.cs.uni-tuebingen.de/publications/brachthaeuser20effects/
ingested: 2026-09-12
sha256: 859af992b0804f48beff9c54c8bbd7c3b3cfa26dcbc64178281b2c77733131a8
---
# Universität Tübingen - Effects as Capabilities: Effect Handlers and Lightweight Effect Polymorphism

Universität Tübingen - Effects as Capabilities: Effect Handlers and Lightweight Effect Polymorphism

# Effects as Capabilities: Effect Handlers and Lightweight Effect Polymorphism

by Jonathan Immanuel Brachthäuser, Philipp Schuster, and Klaus Ostermann

In Proc. Int’l Conf. Object-Oriented Programming, Systems, Languages and Applications (OOPSLA). ACM Press, 2020.

This publication is related to the Effects research project.

# Abstract

Effect handlers have recently gained popularity amongst programming language researchers. Existing type- and effect systems for effect handlers are often complicated and potentially hinder a wide-spread adoption. We present the language Effekt with the goal to close the gap between research languages with effect handlers and languages for working programmers. The design of Effekt revolves around a different view of effects and effect types. Traditionally, effect types express which _side effects_ a computation might have. In Effekt, effect types express which _capabilities_ a computation requires from its context. While this new point in the design space of effect systems impedes reasoning about purity, we demonstrate that it simplifies the treatment of effect polymorphism and the related issues of effect parametricity and effect encapsulation. To guarantee effect safety, we separate functions from values and treat _all_ functions as second-class. We define the semantics of Effekt as a translation to System Xi, a calculus in explicit capability-passing style.

###### Citation as BibTeX

@inproceedings{brachthaeuser20effects, author = {Brachthäuser, Jonathan Immanuel and Schuster, Philipp and Ostermann, Klaus}, title = {Effects as Capabilities: Effect Handlers and Lightweight Effect Polymorphism}, booktitle = {Proc. Int’l Conf. Object-Oriented Programming, Systems, Languages and Applications (OOPSLA)}, year = {2020}, publisher = {ACM Press}, url = {https://doi.org/10.1145/3428194}, doi = {10.1145/3428194} }

# News

#### Paper accepted for publication at OOPSLA 2020

Our paper “Effects as Capabilities: Effect Handlers and Lightweight Effect Polymorphism” (Jonathan BrachthäuserAlumniJonathan Immanuel Brachthäuser, Philipp SchusterAlumniPhilipp Schuster and Klaus OstermannHeadKlaus Ostermann) has been accepted for publication at the International Conference on Object Oriented Programming Systems Languages & Applications (OOPSLA, 2020).

Read more ...

# Related Publications

### Effekt: Lightweight Effect Polymorphism for Handlers (Technical Report)

by Jonathan Immanuel Brachthäuser, Philipp Schuster, and Klaus Ostermann

Technical report. University of Tübingen, Germany, 2020.
