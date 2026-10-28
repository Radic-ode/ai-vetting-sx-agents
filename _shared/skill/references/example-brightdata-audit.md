# Worked Example: Bright Data MCP (@brightdata/mcp)

This is a real, complete run of the vetting process against a live component
(the featured Bright Data integration on aitmpl.com), kept here as a template
for how to structure future audits — both the manual research and the
automated script output.

Source: https://www.aitmpl.com/featured/brightdata
Repo: https://github.com/brightdata/brightdata-mcp
npm: @brightdata/mcp

---

## Step 1 — Don't trust the marketing page

The aitmpl.com listing and Bright Data's own docs are marketing copy. Before
scoring anything, went to the actual GitHub repo and npm registry:
- 2.5k+ GitHub stars, active issue tracker, official org account
- `npm view @brightdata/mcp --json` showed 51 published versions since
  April 2025, latest release about a month old at time of audit — genuinely
  active maintenance, not a one-shot publish-and-abandon package.

## Step 2 — Ran the automated script

```
./scripts/audit_npm_package.sh @brightdata/mcp
```

Findings:
- **No preinstall/postinstall scripts** in package.json — the single most
  common supply-chain injection point (code that runs the moment `npm
  install` finishes, before the user has reviewed anything). Clean here.
- **License: MIT**, confirmed present.
- **Dependencies**: `@modelcontextprotocol/sdk`, `axios`, `playwright`,
  `zod`, `fastmcp`, `remark` — all well-known, non-typosquatted libraries.
- **Pattern scan**: two hits for `eval(` — both turned out to be
  `page.$eval()`, a standard Playwright browser API (reads DOM content),
  not JavaScript's `eval()`. No `child_process` or `exec(` found.
- **Outbound URLs**: everything resolves to `api.brightdata.com`, plus
  expected scrape targets (Google, Bing, X, ChatGPT, etc. — sites it's
  *told* to scrape, not places it silently phones home to). No mystery
  third-party endpoint.

## Step 3 — Scored the five categories

| Category | Score | Reasoning |
|---|---|---|
| Provenance & Maintainer Trust | **Pass** | Official org, verified badge, active releases, public support channel |
| Permission Scope vs. Need | **Partial** | 60+ tools is broad, but matches its stated function (web-data platform). Defaulting to `PRO_MODE=true` grants everything at once rather than scoping to task |
| Auditability | **Partial → upgraded to Pass after script run** | Source is public and now *actually inspected*, not just assumed open. The hosted-URL install mode (vs. the npx/local install mode) remains un-auditable at runtime — flagged separately |
| Blast Radius | **Partial** | Real browser automation (click/type/navigate) means it can act on third-party sites, not just read them. No local filesystem/code execution found |
| Change Control | **Partial (npx, pinned) / Fail (hosted URL)** | npm releases are versioned and pinnable; the hosted URL install has no pinning — it changes silently whenever the vendor changes it |

## Step 4 — Tier and recommendation

**RISK TIER: Medium** (High if installed via the hosted-URL method)

**Recommendation: Install with mitigations**
- Use `npx @brightdata/mcp@<pinned-version>`, not `@latest` and not the
  hosted URL.
- Don't default to `PRO_MODE=true` — scope `GROUPS`/`TOOLS` env vars to
  the actual task.
- Store the API token as a secret, not inline in a committed config file.
- Re-run this audit script on version bumps — cheap given the public
  changelog.

## Lesson for future audits

The vendor's own "quick start" instructions are not necessarily the safest
option they offer. Bright Data documents three install modes; the fastest
one (hosted URL) is also the least auditable and least pinnable. Always
check whether a more auditable install path exists before defaulting to
whatever's first in the README.
