# 03_probe — one sandbox per capability

One job: run each capability, alone, in its own disposable sandbox with canary credentials, and record
anything that reaches past its grant.

## Inputs
- Working (this run): `../02_static/output/<run>/capability-inventory.md`
- Reference (every run): `../../_shared/skill/references/capability-sandboxes.md` (all of it)
- Tool: `../../_shared/skill/scripts/probe.sh` (Linux/WSL2: bubblewrap + strace)

Do NOT load: 02's `static-findings.md` (the inventory carries what this stage needs), other runs.

## Process
1. Write `probe-plan.md`: for every inventory row plus `baseline`, the probe task, the grant, the
   expected footprint (written *before* running), the backend, and whether it touches the real internet.
2. **Stop. A person approves `probe-plan.md` before anything runs.** This stage executes third-party code.
3. Run each probe in a fresh sandbox; never reuse one between probes. Keep each probe's log in `logs/`.
4. Write `probe-results.md`: per probe, observed vs. expected, and the verdict (Within scope /
   OUT OF SCOPE with the exact path, host or process / Not run and why).
5. No sandbox backend available → every probe is "Not run: no sandbox". Never fall back to the host.

## Outputs
- `probe-plan.md` (gate), `probe-results.md`, `logs/` → `output/<run>/`

## Human check
Approve the plan first. Afterwards, read every OUT OF SCOPE line and every "Not run".
