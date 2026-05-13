# Pacino Documentation

Overview of the Pacino microarchitecture documentation.

Pacino is an open source 8-issue out-of-order RISC-V processor targeting the
RVA23S64 profile, created in a co-design flow.

Use the tabs and hamburger menu to navigate the documentation.

## More Information

|Description|Link|
|:-----|:----|
|Pacino Overview|This document.<br> <https://uarchlabs.github.io/pacino/overview/>|
|Pacino Landing Page|<https://uarchlabs.github.io/pacino/> |
|Pacino Repo        |<https://github.com/uarchlabs/pacino> |
|uarchlabs Site     |<https://uarchlabs.com/> |
|uarchlabs Blog |Includes Pacino.<br><https://uarchlabs.github.io/blog> |
|uarchlabs Projects |<https://github.com/orgs/uarchlabs/repositories> |

## Project Status

Pacino is under active development. RTL and documentation are updated continuously.

Current project status and open issues are tracked in the [GitHub repository](https://github.com/uarchlabs/pacino).

## Pacino Documentation Summary

The documentation loosely follows the RTL organization. This is for reference.

Navigation uses the mkdocs convention: top of page tabs, hamburger menu, and
side menus.

|Unit|Description|
|:---|:---|
| Frontend | instruction fetch, branch prediction, decode pipeline|
| Backend  | rename, dispatch, out-of-order execution engine|
| Memory Subsystem | load/store queues, scalar and vector memory access|
| Cache Subsystem | L1D, L2 with TileLink/CHI interfaces|
| MMU | TLB hierarchy, page table walker, hypervisor support, PMP/PMA|
| System | CSR, exceptions, performance monitoring, debug|
