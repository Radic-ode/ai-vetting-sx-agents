# ai-vetting-sx-agents — the pipeline

The flow in one line: pin down exactly what is being installed → read it and list what it can do →
run each capability in its own sandbox → score it and say what to do.

| Stage | Job | Input | Output (`output/<run>/`) | Human check |
|---|---|---|---|---|
| `01_intake` | identify the component, verify where the copy came from | the user's link, file or name | `intake.md` | is this exactly the thing that will be installed (version, hash, source)? |
| `02_static` | read the code; build the capability inventory | 01's `intake.md` + the copy | `static-findings.md`, `capability-inventory.md` | does the inventory miss anything you know it does? |
| `03_probe` | plan one sandbox per capability; **approve**; run; record | 02's `capability-inventory.md` | `probe-plan.md`, then `probe-results.md` (+ `logs/`) | **approve `probe-plan.md` before anything executes** |
| `04_report` | five-category scorecard, tier, recommendation | 01's `intake.md`, 02's findings, 03's results | `report.md` | is every Pass backed by evidence, and every limitation named? |

**Factory** (stable, every run): `_shared/skill/`, the ai-vetting-skill-sx skill: `SKILL.md` (five
categories, tiering, output format), `references/capability-sandboxes.md` (capability IDs, probe tasks,
grants, backends, safety rules), `references/report_template.md`, `scripts/probe.sh` (Linux/WSL
sandbox runner), `scripts/audit_npm_package.sh` (npm static checks).

**Product** (new each run): `stages/*/output/<run>/`, the same `<run>` name in every stage
(lowercase component name, plus the version if several are vetted, e.g. `vectorcraft`).

**Status** is whatever exists: a run has finished a stage when that stage's `output/<run>/` holds its
listed files. `03_probe` is waiting on a person when `probe-plan.md` exists without an `APPROVED:` line
covering its probes (see `START-HERE.md`, rule 2).

**Starting a run:** pick a `<run>` name and begin at `stages/01_intake/CONTEXT.md`. The `vectorcraft`
run is the worked example: a real vetting of the VectorCraft vector editor (zip, repo and MSI), done
2026-10-28.

**Safety, every run:** downloaded components go into their own new, empty folder, outside this
workspace; scripts that read them run from elsewhere with paths as arguments. Nothing from a component
is executed outside a sandbox, and never before the person has added the `APPROVED:` line to
`probe-plan.md`. The probe runners check for it.

**Source of truth for the method:** `_shared/skill/` here, in plain Markdown and shell, usable by any agent.
`SKILL.md` also follows the open Agent Skills format, so tools that load skills can load it directly. This
workspace is the model-neutral copy of `ai-vetting-skill-sx`. Its static-only parent is `ai-component-vetting`.

**Entry point:** `START-HERE.md`. `AGENTS.md`, `CLAUDE.md` and `GEMINI.md` only point there.
