<!-- SPDX-License-Identifier: CC-BY-4.0                        -->
<!-- Copyright (c) 2026 Jeff Nye, uarchlabs.com                -->
<!-- SPDX-FileCopyrightText: 2026 Jeff Nye <jeff@uarchlabs.com -->

# AI Assistant Pairings: Strategy vs. Implementation (v3)

This document evaluates the "Two-Actor" model for complex technical projects, specifically separating high-level planning (Web) from terminal-based execution (Linux CLI) across three distinct tiers of AI capability.

## Table of Contents
1. [Evaluation Framework](#evaluation-framework)
2. [Tier 1: Cloud Frontier (Proprietary)](#tier-1-cloud-frontier-proprietary)
3. [Tier 2: Open-Weight Frontier (Sovereign)](#tier-2-open-weight-frontier-sovereign)
4. [Tier 3: Consumer-Local (Private/On-Device)](#tier-3-consumer-local-privateon-device)
5. [Local Hardware Requirements (2026)](#local-hardware-requirements-2026)
6. [Strategic Workflow Recommendation](#strategic-workflow-recommendation)

---

## Evaluation Framework
* **Strategic Actor (Web):** High-context, reasoning-heavy, search-enabled. Focuses on 'the what and the why.'
* **Implementation Actor (CLI):** Filesystem access, terminal execution, autonomous or pair-programming. Focuses on 'the how.'

---

## Tier 1: Cloud Frontier (Proprietary)
*Best for: Absolute strategy, high-level architectural planning, and verifying complex technical standards (e.g., RVA23).*

| Provider | Strategic Actor (Web) | Implementation Actor (CLI) | Core Philosophy |
| :--- | :--- | :--- | :--- |
| **Anthropic** | Claude.ai (Projects) | Claude Code | High-reasoning 'Artifacts'; highly autonomous agentic CLI. |
| **Google** | NotebookLM / Deep Research | Gemini CLI / Code Assist | 2M+ token context; source-grounded research with citations. |
| **OpenAI / MS** | ChatGPT (o1/o3 Reasoning) | Codex CLI / Copilot CLI | Deep 'Chain of Thought' reasoning for architectural logic. |
| **Agnostic** | Perplexity (Pages) | Aider | Real-time technical search paired with flexible pair-programming. |

### Tier 1 Opinions
* **Anthropic:** Best for maintaining persistent project context in 'Projects' while allowing a stateful CLI agent to iterate on build errors.
* **Google:** The gold standard for documentation-heavy projects. Ingests entire ISA manuals and codebases simultaneously via the 2M+ token window.
* **OpenAI/MS:** Optimized for complex logic hazards. The 'o-series' models simulate structural hazards before committing to code.

---

## Tier 2: Open-Weight Frontier (Sovereign)
*Best for: Developers requiring IP sovereignty and high performance on private infrastructure or server-grade hardware.*

| Provider | Strategic Actor (Web/UI) | Implementation Actor (CLI) | Core Philosophy |
| :--- | :--- | :--- | :--- |
| **DeepSeek** | DeepSeek v4 (Full) | Aider (via API/Local) | **The SOTA Open Choice:** Leads benchmarks for RTL and hardware logic. |
| **Meta** | Llama 4 Scout | OpenCode CLI | **Massive Scale:** 10M+ token window for repo-wide synthesis. |
| **Mistral** | Mistral Le Chat (Open) | Mistral CLI (Codestral) | **Dense Logic:** Minimal 'chatter' with high-accuracy code output. |

### Tier 2 Opinions
* **DeepSeek:** Uses "Engram" memory systems to prevent logical drift in large-scale pipelines (e.g., 8-issue OoO designs).
* **Meta:** The 10M token window allows for 'zero-forgetting' across the entire ISA, Data Taxonomy, and RTL implementation.

---

## Tier 3: Consumer-Local (Private/On-Device)
*Best for: Instant latency, offline work, and rapid iteration on individual modules (ALU, FPU, etc.) using consumer GPUs.*

| Provider | Strategic Actor (Web/UI) | Implementation Actor (CLI) | Core Philosophy |
| :--- | :--- | :--- | :--- |
| **Alibaba** | Qwen 3.5 (27B) | Aider + Qwen Coder | **The Gold Standard:** Local model that rivals cloud SWE-bench scores. |
| **Google** | Gemma 4 (14B) | Mistral CLI + Codestral | **NPU Optimized:** Highly efficient for broad repo synthesis on light VRAM. |
| **Microsoft** | Phi-4 (14B) | OpenCode + Phi-4-mini | **Logic Specialist:** Outperforms larger models on math and ISA reasoning. |

### Tier 3 Opinions
* **Qwen 3.5 Series:** Provides near-instant autocomplete and stable terminal execution for specialized hardware logic.
* **Phi-4:** A 'Small Language Model' powerhouse designed specifically for scientific and logical accuracy over conversational breadth.

---

## Local Hardware Requirements (2026)
*Targeting Linux-based implementation and local model hosting (Ollama/vLLM).*

| Tier | Recommended Models | Minimum VRAM | Use Case |
| :--- | :--- | :--- | :--- |
| **Lightweight** | Mistral 7B, Llama 4 (8B) | 8GB - 12GB | Quick terminal edits, documentation linting. |
| **Professional** | Qwen 3.5 (32B), Llama 4 (30B) | 24GB (Single GPU) | Complex module implementation (ALU, Dispatch). |
| **Architect** | DeepSeek v4, Llama 4 (70B+) | 128GB+ (Multi-GPU) | Full-system architectural reasoning and planning. |


