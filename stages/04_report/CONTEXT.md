# 04_report — score, tier, recommend

One job: turn the evidence into the skill's scorecard, risk tier and a concrete recommendation.

## Inputs
- Working (this run): `../01_intake/output/<run>/intake.md`, `../02_static/output/<run>/static-findings.md`,
  `capability-inventory.md`, `../03_probe/output/<run>/probe-results.md`
- Reference (every run): `../../_shared/skill/SKILL.md` (output format, tiering logic),
  `../../_shared/skill/references/report_template.md`

Do NOT load: 03's `logs/` (results already summarise them), other runs.

## Process
1. Score the five categories from the evidence. Probe findings override static scores for the
   categories they map to.
2. Apply the tiering logic, including the caps: any probe not run caps the tier at Medium; an
   unverifiable component cannot earn Low.
3. Write Coverage Limitations: everything this run could not verify. It is never empty.
4. Recommend concretely: what to do, which mitigations, what would move it down a tier.

## Outputs
- `report.md` → `output/<run>/`

## Human check
Every Pass backed by evidence in 01-03; every limitation named; the recommendation is something the
user can act on today.
