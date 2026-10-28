---
name: ai-vetting-skill-sx
description: "Sandboxed (SX) vetting of third-party AI tooling (MCP servers, hooks, agents, plugins, skills, or any installable Claude Code / Claude.ai add-on or app) for supply-chain risk before installation, the way a vendor risk team vets a vendor: a static review, then each capability (network, files, processes, credentials, persistence, self-update, agent-facing text) probed alone in its own disposable sandbox with canary credentials, scored into a risk tier. Use it whenever a user wants to vet, sandbox, probe, test-run or check the runtime behavior of a component, asks 'is this safe to install' and wants more than a code read, or names ai-vetting-skill-sx. Prefer the static-only ai-component-vetting skill for a quick check that runs nothing. Do NOT use it for the user's own internal code or for general code review."
---

# AI Vetting Skill SX — Static + Sandboxed Capability Probes

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

CAPABILITY PROBES — one sandbox per capability (omit only if the user declined runtime probing; say so under Coverage Limitations)
| Capability | Grant | Probe task | Backend | Verdict |
|---|---|---|---|---|
| baseline | nothing | launch, idle | ... | Within scope / OUT OF SCOPE: <exact path, host or process> / Not run: <why> |
| <one row per capability in the inventory> | ... | ... | ... | ... |

COVERAGE LIMITATIONS — mandatory, never omit even when everything scored Pass
[What this assessment could NOT verify. E.g.: "Static analysis only — the
package was never executed, so runtime-only behavior (logic gated on an
API response or config value) would not surface here." "This package's
own dependencies were not recursively audited." "Component is distributed
only as a hosted endpoint — no downloadable package existed to inspect,
so Auditability is scored on trust in the vendor's claims alone."]

RECOMMENDATION: [Install as-is / Install with mitigations / Sandbox first / Do not install]
[If not "Install as-is": list the specific mitigations or missing info needed to move down a tier]
```

A scorecard with an empty or boilerplate Coverage Limitations section is incomplete — every audit has a boundary, and naming it is what separates real due diligence from a rubber stamp. If a limitation listed above is significant enough that it could hide a Critical finding (e.g. the component is closed-source with no inspectable code at all, or is hosted-only with no version pinning possible), cap the tier at **Medium at best**, regardless of how clean the visible checks looked — an unverifiable component cannot earn a Low.

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

Capability probes override static scores for the categories they map to
(see `references/capability-sandboxes.md` §6): a canary read, persistence,
or a connection to an undeclared host makes that category **Fail** and the
tier at least **High**; a baseline probe that touches the network or
secrets is **Critical**. A **Low** tier requires every inventoried
capability to have been probed and found within scope — if any probe was
not run, cap the tier at **Medium**.

## Process

1. If the component has a repo/manifest URL, fetch it (via web_fetch or the appropriate tool) to check actual permissions requested, maintainer info, and last-updated date rather than relying on marketing copy from a marketplace listing.
2. **If the component is distributed via npm, run `scripts/audit_npm_package.sh <package-name>`** before scoring Auditability or Blast Radius. This automates: checking publish history/version count, downloading the real tarball, scanning `package.json` for pre/post-install scripts (the most common supply-chain injection point), scanning source for `eval`/`exec`/`child_process` patterns, and extracting every outbound URL the code references. Feed the script's output into the scorecard rather than relying on the README's claims.
3. **Capability probes (runtime, sandboxed).** Follow `references/capability-sandboxes.md`:
   1. Build the **capability inventory** from the static pass — every capability the component has or plausibly could have (`install`, `net-out`, `net-listen`, `fs-read`, `fs-write`, `exec`, `secrets`, `persist`, `self-update`, `agent-text`), plus a `baseline` probe.
   2. For each one, write a **probe task** (the smallest real use that needs it) and its **expected footprint** *before* running anything.
   3. Ask the user before executing the component. Name the backend and what each probe grants, and flag the probes that reach the real internet.
   4. Run each probe in **its own fresh sandbox** that grants only that capability, with canary credentials seeded. On Linux/WSL2 use `scripts/probe.sh -c <capability> -t <component-dir> [-a expected,hosts] -- <command>`; for native Windows apps use one Windows Sandbox `.wsb` per probe; see the backends table for Docker and macOS.
   5. Record each result in the CAPABILITY PROBES table. Anything observed beyond the grant is **OUT OF SCOPE**: name the exact path, host or process. A probe you could not run is "Not run" plus the reason, and it also goes under Coverage Limitations.
   6. Never fall back to running on the host, with real credentials, or in a shared sandbox because a backend is missing.
4. If information for a category is genuinely unavailable (e.g., closed-source with no published permission list, or the component isn't npm-distributed so the script doesn't apply), score that category **Fail** by default — absence of evidence is not evidence of safety in a vendor-risk context.
5. Always end with a concrete recommendation, not just the scorecard. "Sandbox first" and "install with mitigations" should say specifically what that means (e.g., "run in an isolated project with no credentials for one week before wider rollout").
6. If the user is comparing multiple components, produce one scorecard per component, then a one-line summary ranking them.
7. See `references/example-brightdata-audit.md` for a full worked example of this process end-to-end, including real script output and how it fed into the final tier and recommendation. See `references/draft-v1-manual-checklist.md` for the original manual-only version of this skill, kept for history — useful if auditing a non-npm component where the script doesn't apply and the process reverts to manual research.

## Generating a saved report (optional)

The scorecard above is always produced inline in chat. Only go further and
write an actual `.md` file if the user asks to **save, export, download,
or deliver** a report — not for a normal vetting conversation.

This skill writes plain markdown reports only. No other skill or
document-formatting tool is required — markdown opens fine in Word,
Google Docs, or any text editor, and stays fully portable across any
environment this skill runs in.

1. Follow the structure in `references/report_template.md` (metadata
   block, risk tier, scorecard table, Coverage Limitations, recommendation,
   footer).
2. Write it as a `.md` file and save/present it to the user.
3. If multiple components were assessed in one session, one report may
   contain all scorecards back-to-back, following the same per-component
   structure, with an optional one-line ranking summary at the end.

## Notes

- This mirrors standard Third-Party Risk Management (TPRM) logic used in regulated industries (banking, healthcare) — same shape as vendor due diligence, adapted for AI tooling's specific risks (code execution, tool permissions, auto-update behavior).
- Be direct about Critical/High findings even if the user seems eager to install something — the point of this skill is to be the honest second opinion, not to rubber-stamp.
