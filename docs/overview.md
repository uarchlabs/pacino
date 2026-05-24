---
hide:
  - toc
title: "Overview"
---

# Pacino — microarchitecture overview

Pacino is an open source 8-issue out-of-order RISC-V processor targeting the
RVA23S64 profile, designed using a structured AI co-design methodology.
Click any block to explore the pipeline.

<iframe
  src="../microarchitecture.html"
  title="Pacino microarchitecture block diagram"
  style="width:100%; height:500px; border:none; display:block; margin: 24px 0;"
></iframe>

## Documentation

The documentation follows the RTL cluster organization.

| Unit | Description |
|:---|:---|
| Frontend | instruction fetch, branch prediction, decode pipeline |
| Backend | rename, dispatch, out-of-order execution engine |
| Memory subsystem | load/store queues, scalar and vector memory access |
| Cache subsystem | L1D, L2 with TileLink/CHI interfaces |
| MMU | TLB hierarchy, page table walker, hypervisor support, PMP/PMA |
| System | CSR, exceptions, performance monitoring, debug |

## Project status

Active development. RTL and documentation updated continuously.
Open issues tracked in the [GitHub repository](https://github.com/uarchlabs/pacino).


## More information

| Description | Link |
|:-----|:----|
| Pacino overview | This document. <https://uarchlabs.github.io/pacino/overview/> |
| Pacino landing page | <https://uarchlabs.github.io/pacino/> |
| Pacino repo | <https://github.com/uarchlabs/pacino> |
| uarchlabs site | <https://uarchlabs.com/> |
| uarchlabs blog | Includes Pacino. <https://uarchlabs.github.io/blog> |
| uarchlabs projects | <https://github.com/orgs/uarchlabs/repositories> |
