---
name: ai-component-vetting
description: "Vets third-party AI tooling components — MCP servers, hooks, agents, plugins, skills, or any installable Claude Code / Claude.ai add-on — for supply-chain risk before installation, the same way a vendor risk team would vet a new vendor. Use this whenever a user is about to install, evaluate, compare, or ask 'is this safe to install' about any third-party MCP, hook, agent, command, plugin, or skill — including ones found on marketplaces like aitmpl.com, npm, GitHub, or a plugin directory. Also trigger when a user asks to 'assess the risk', 'do due diligence on', or 'check the supply chain' of any AI tool, template, or integration, even if they don't use the word 'vendor' or 'risk' explicitly. Do NOT use this for vetting the user's own internal code, or for general code review unrelated to third-party components."
---

# AI Component Vetting

Assesses third-party AI tooling components (MCP servers, hooks, agents, commands, plugins, skills) for supply-chain risk, using the same due-diligence logic a bank or hospital's vendor risk team would apply to any new vendor — just adapted for AI tooling.

## When this triggers

Any request to install, review, compare, or judge the safety of a third-party AI component. This includes casual phrasing like "is this MCP legit" or "should I install this" — not just formal "risk assessment" requests.

## Output format

Always produce a **risk tier** with reasoning. Never just say "looks fine" or "be careful" without the structured breakdown below.

```
RISK TIER: [Critical / High / Medium / Low]

1. Provenance & Maintainer Trust — [score: Pass/Partial/Fail]
   [1-2 sentence reasoning]

2. Permission Scope vs. Need — [score: Pass/Partial/Fail]
   [1-2 sentence reasoning]

3. Auditability — [score: Pass/Partial/Fail]
   [1-2 sentence reasoning]

4. Blast Radius — [score: Pass/Partial/Fail]
   [1-2 sentence reasoning]

5. Change Control — [score: Pass/Partial/Fail]
   [1-2 sentence reasoning]

RECOMMENDATION: [Install as-is / Install with mitigations / Sandbox first / Do not install]
[If not "Install as-is": list the specific mitigations or missing info needed to move down a tier]
```

## The five categories

### 1. Provenance & Maintainer Trust
Who actually publishes this, and can that be verified?
- Official vendor / verified org account → Pass
- Individual maintainer, active repo, real history, responsive to issues → Partial
- Anonymous, no verifiable identity, dead or brand-new repo → Fail

### 2. Permission Scope vs. Need
Does the component request only what its stated function requires?
- Requested permissions clearly map to function (e.g., a calendar-read MCP asks only for calendar read) → Pass
- Some extra scope requested but plausible/explained → Partial
- Requests broad scope (filesystem write, arbitrary network, credential access) unrelated to its stated job → Fail — this alone is a strong signal, regardless of other categories

### 3. Auditability
Can the actual behavior be inspected before trusting it?
- Open source, readable source, no obfuscation/minification hiding logic → Pass
- Open source but large/complex, spot-checked rather than fully read → Partial
- Closed-source binary, obfuscated, or "trust us" black box → Fail

### 4. Blast Radius
If this component is malicious or just buggy, what's the worst case?
- Read-only, sandboxed, reversible actions only → Pass
- Can write/modify but not execute arbitrary code or reach external networks unprompted → Partial
- Can execute arbitrary shell/code, auto-run on triggers (hooks), reach the network unprompted, or touch credentials/financial actions → Fail

### 5. Change Control
How does this component change after you trust it once?
- Pinned version, changes require explicit user action to pull → Pass
- Auto-updates but with changelogs/release notes to review → Partial
- Silent auto-update with no visibility into what changed → Fail

## Tiering logic

- **Critical**: Any single red-line — arbitrary code execution + no verifiable maintainer, or credential/financial access + closed source — regardless of other scores. Also Critical if 2+ categories are Fail.
- **High**: Exactly one Fail, no red-line combination.
- **Medium**: No Fails, but 2+ Partials — workable but needs mitigation (sandboxing, scoped permissions, monitoring).
- **Low**: Pass or Partial-with-good-reason across the board, verified publisher, minimal blast radius.

## Process

1. If the component has a repo/manifest URL, fetch it (via web_fetch or the appropriate tool) to check actual permissions requested, maintainer info, and last-updated date rather than relying on marketing copy from a marketplace listing.
2. If information for a category is genuinely unavailable (e.g., closed-source with no published permission list), score that category **Fail** by default — absence of evidence is not evidence of safety in a vendor-risk context.
3. Always end with a concrete recommendation, not just the scorecard. "Sandbox first" and "install with mitigations" should say specifically what that means (e.g., "run in an isolated project with no credentials for one week before wider rollout").
4. If the user is comparing multiple components, produce one scorecard per component, then a one-line summary ranking them.

## Notes

- This mirrors standard Third-Party Risk Management (TPRM) logic used in regulated industries (banking, healthcare) — same shape as vendor due diligence, adapted for AI tooling's specific risks (code execution, tool permissions, auto-update behavior).
- Be direct about Critical/High findings even if the user seems eager to install something — the point of this skill is to be the honest second opinion, not to rubber-stamp.
