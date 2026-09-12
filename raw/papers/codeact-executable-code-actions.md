---
source_url: https://arxiv.org/abs/2402.01030
ingested: 2026-09-12
sha256: f5dea9878b427bb3a370c6138e144fd7a8d418eeec0413a90fd46e3dbe1fb41d
---
# Executable Code Actions Elicit Better LLM Agents

Executable Code Actions Elicit Better LLM Agents

arXiv is now an independent nonprofit! Learn more×

# Executable Code Actions Elicit Better LLM Agents

Xingyao Wang Affiliation: Department of Computer Science, University of Illinois Urbana-Champaign Correspondence to: xingyao6@illinois.edu Yangyi Chen Affiliation: Department of Computer Science, University of Illinois Urbana-Champaign Lifan Yuan Affiliation: Department of Computer Science, University of Illinois Urbana-Champaign Yizhe Zhang Affiliation: Apple Yunzhu Li Affiliation: Department of Computer Science, University of Illinois Urbana-Champaign Hao Peng Affiliation: Department of Computer Science, University of Illinois Urbana-Champaign Heng Ji Affiliation: Department of Computer Science, University of Illinois Urbana-Champaign Correspondence to: hengji@illinois.edu

###### Abstract

Large Language Model (LLM) agents, capable of performing a broad range of actions, such as invoking tools and controlling robots, show great potential in tackling real-world challenges. LLM agents are typically prompted to produce actions by generating JSON or text in a pre-defined format, which is usually limited by constrained action space (e.g., the scope of pre-defined tools) and restricted flexibility (e.g., inability to compose multiple tools). This work proposes to use executable Python code to consolidate LLM agents’ actions into a unified action space (CodeAct). Integrated with a Python interpreter, CodeAct can execute code actions and dynamically revise prior actions or emit new actions upon new observations through multi-turn interactions. Our extensive analysis of 17 LLMs on API-Bank and a newly curated benchmark shows that CodeAct outperforms widely used alternatives (up to 20% higher success rate). The encouraging performance of CodeAct motivates us to build an open-source LLM agent that interacts with environments by executing interpretable code and collaborates with users using natural language. To this end, we collect an instruction-tuning dataset CodeActInstruct that consists of 7k multi-turn interactions using CodeAct. We show that it can be used with existing data to improve models in agent-oriented tasks without compromising their general capability. CodeActAgent, finetuned from Llama2 and Mistral, is integrated with Python interpreter and uniquely tailored to perform sophisticated tasks (e.g., model training) using existing libraries and autonomously self-debug11 1 The code, data, model, and demo are available at https://github.com/xingyaoww/code-act..

###### Keywords:

Machine Learning, ICML

## 1 Introduction

Figure 1: Comparison between CodeAct and Text / JSON as action. (top) Illustrative example comparing different actions. (bottom) Quantitative results on M3ToolEval (§2.3).

Large Language Models (LLMs) have emerged as a pivotal breakthrough in natural language processing (NLP). When augmented with action modules that allow access to APIs, their action space expands beyond conventional text processing, allowing LLMs to acquire capabilities such as tool invocation and memory management (Mialon et al., 2023; Schick et al., 2023) and venture into real-world tasks such as controlling robots (Ahn et al., 2022; Huang et al., 2023; Ma et al., 2023) and performing scientific experiments (Bran et al., 2023).

We inquire: how to effectively expand LLM agents’ action space for solving complex real-world problems? Much existing research has examined using text (Yao et al., 2022b; Park et al., 2023, inter alia) or JSON (Qin et al., 2023b; Chase, 2022, inter alia) to produce actions (e.g., tool uses in Fig. 1 top left). However, both methods typically suffer from constrained scope of action spaces (actions are usually tailored for specific tasks) and restricted flexibility (e.g., inability to compose multiple tools in a single action). As an alternative approach, several work (Liang et al., 2022; Singh et al., 2023; Wang et al., 2023a) demonstrate the potential of using LLMs to generate code to control robots or game characters. However, they typically rely on pre-specified control primitives and hand-engineered prompts and, more importantly, struggle to dynamically adjust or emit actions based on new environmental observation and feedback.

This work proposes CodeAct, a general-purpose framework that allows LLMs to generate executable Python code as actions (Fig. 1 top right). CodeAct is designed to handle a variety of applications and comes with unique advantages:

(1)

Integrated with a Python interpreter, CodeAct can execute code actions and dynamically adjust prior actions or emit new action based on observations (e.g., code execution results) it receives through multiple turns of interactions.

(2)

Code actions allow LLM to leverage existing software packages. CodeAct can use readily available Python packages for an expanded action space instead of hand-crafted task-specific tools (Yuan et al., 2023; Shen et al., 2023). It also allows LLM to use automated feedback (e.g., error messages) implemented in most software to improve task-solving by self-debugging its generated code (Chen et al., 2023b; Wang et al., 2023d).

(3)

Code data is widely used in pre-training today’s LLMs (Yang et al., 2024b). These models are already familiar with structured programming languages, allowing cost-effective adoption of CodeAct.

(4)

Compared to JSON and text with a pre-defined format, code inherently supports control and data flow, allowing for the storage of intermediate results as variables for reuse and the composition of multiple tools to perform complex logical operations (e.g., if-statements, for-loops) with one piece of code, thereby unlocking LLMs’ potential to tackle complex tasks by leveraging its pre-trained knowledge of programming. In Fig. 1, an LLM using with CodeAct (top right) can apply the same sequence of tools (e.g., passing one tool’s output as input to another tool using the data flow feature) to all inputs through for-loops (i.e., control flow feature) with one action; while text or JSON have to take action for every input (top left).

- H CodeActAgent Anomaly on M3ToolEval

Our extensive experiments with 17 LLMs (including both open-source and proprietary ones) confirm the above benefits (3 & 4) of CodeAct. To demonstrate benefit (3), our first experiment (§2.2) compares CodeAct to baselines on basic tasks involving atomic tool use (i.e., only one tool is used per action), ablating the control and data flow advantage offered by CodeAct. The results show that, for most LLMs, CodeAct achieves comparable or better performance than the baselines. CodeAct’s performance gains are more prominent on complex tasks, as demonstrated in our second experiment (benefit 4). We curate a new benchmark consisting of 82 human-curated tasks that typically require multiple calls to multiple tools in multi-turn interactions (M3ToolEval; §2.3). Problems in this benchmark often require intricate coordination and composition of multiple tools. With its strengths in control and data flow, CodeAct achieves up to a 20% absolute improvement over baselines on the success rate of solving the problems while requiring up to 30% fewer actions. These performance gains widen as the capabilities of the LLMs increase (Fig. 1 bottom).

The promising performance of CodeAct motivates an open-source LLM agent that can effectively act through CodeAct, and collaborate with humans through natural language. To this end, we collect an instruction-tuning dataset CodeActInstruct consisting of 7k high-quality multi-turn interaction trajectories with CodeAct (§3.1). CodeActInstruct is motivated by a general agent framework consisting of agent, user, and environments (Fig. 2) and focuses on agent-environment interactions with the computer (information seeking, software package use, external memory) and the physical world (robot planning). On CodeActInstruct, we perform careful data selection to promote the capability of improving
