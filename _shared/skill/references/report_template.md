# Report Template — AI Component Vetting

This defines the structure a saved report should follow when the skill
writes a `.md` file, so output is consistent every time. This is a
structure spec, not a script — apply it manually when writing the file.

## Structure

1. **Title**: "AI Component Vetting Report"
2. **Metadata block** (component name, source/registry, repo URL, date of
   assessment, assessor)
3. **Risk tier** — large, prominent, at the top (Critical/High/Medium/Low)
4. **Scorecard table** — the five categories, each with score
   (Pass/Partial/Fail) and 1-2 sentence reasoning
5. **Capability Probes** — table: capability, grant, probe task, backend, verdict (one row per inventoried capability plus baseline)
6. **Coverage Limitations** — mandatory section, never omit; list every probe not run
7. **Recommendation** — concrete action + specific mitigations if not
   "Install as-is"
8. **Footer note**: "Generated using the ai-vetting-skill-sx skill.
   Static analysis plus the capability probes listed — see Coverage Limitations above."

## Markdown structure

```markdown
# AI Component Vetting Report

**Component:** [name]
**Source:** [registry/marketplace URL]
**Repository:** [repo URL]
**Date:** [date]

## Risk Tier: [TIER]

## Scorecard

| Category | Score | Reasoning |
|---|---|---|
| Provenance & Maintainer Trust | ... | ... |
| Permission Scope vs. Need | ... | ... |
| Auditability | ... | ... |
| Blast Radius | ... | ... |
| Change Control | ... | ... |

## Coverage Limitations
[...]

## Recommendation
[...]

---
*Generated using the ai-vetting-skill-sx skill. Static analysis plus capability probes —
see Coverage Limitations above.*
```

Note: this .md file opens fine in Word, Google Docs, or any text/markdown
editor — no separate document-generation tooling is needed to produce or
open it.
