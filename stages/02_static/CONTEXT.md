# 02_static — read it, list what it can do

One job: review the code without running it, and turn what it *can* do into a capability inventory
for 03.

## Inputs
- Working (this run): `../01_intake/output/<run>/intake.md` and the verified copy it points to
- Reference (every run): `../../_shared/skill/SKILL.md` (the five categories),
  `../../_shared/skill/references/capability-sandboxes.md` §1 (capability IDs and static signals)
- Tool: `../../_shared/skill/scripts/audit_npm_package.sh` when the component is an npm package

Do NOT load: §2-6 of `capability-sandboxes.md` (03's), other runs' outputs.

## Process
1. Inventory the files: types, binaries, install/build-time scripts (`postinstall`, `build.rs`,
   `setup.py`), dependencies and where each comes from (registry, git, vendored).
2. Search for each capability's static signals: network clients and URLs, listening sockets, process
   spawning, file writes, credential and env reads, persistence locations, self-update logic, and text
   an agent will read as instructions. Read the code around every hit.
3. Write `static-findings.md`: evidence per category, quoted file paths and lines, what was not read.
4. Write `capability-inventory.md`: one row per capability (ID, evidence, expected use, maps to which
   category). A capability you found but can't probe still goes in the inventory.

## Outputs
- `static-findings.md`, `capability-inventory.md` → `output/<run>/`

## Human check
Read the inventory. Does it miss anything the user knows the component does? Missing rows mean
missing probes.
