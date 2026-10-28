---
run: vectorcraft
version: 0.17.0
---

# Capability inventory: VectorCraft

| ID | Has it? | Evidence (see static-findings.md) | Expected use | Maps to |
|---|---|---|---|---|
| `install` | yes | MSI installer (admin, Program Files); `build.rs` scripts when built from source | install files, shortcut; icon embedding at build | Blast Radius, Auditability |
| `net-out` | yes | `craft-update` (ureq/rustls) | update check at start to `api.github.com`, downloads from `github.com/storytold` | Permission Scope, Blast Radius |
| `net-listen` | opt-in | control server, `--control` / `VECTORCRAFT_CONTROL_PORT` | loopback JSON-lines for the MCP server | Blast Radius |
| `fs-read` | yes | open/place/import; MCP `--automation-read-root` | the files the user opens | Permission Scope |
| `fs-write` | yes | save/export/package; MCP `--automation-write-root` | the files the user saves | Blast Radius |
| `exec` | yes | explorer/open/xdg-open, PowerShell printing, `rundll32 printui.dll`, `reg.exe query`, self-restart | reveal, print, printer setup, locale, update restart | Blast Radius |
| `secrets` | none found | reads only its own env vars (`VECTORCRAFT_CONTROL_PORT`, `CRAFT_UPDATE_DEV`, `*_PRETEND_VERSION`) | — | Permission Scope, Blast Radius |
| `persist` | none found in code | no Run keys/tasks/services; MSI install actions not inspected | Start-menu shortcut from the MSI | Blast Radius, Change Control |
| `self-update` | yes | `craft-update` self_update + startup prompt | replace itself after consent, SHA-256 + signature checked | Change Control |
| `agent-text` | yes | repo `CLAUDE.md`/`AGENTS.md` (not in the MSI); MCP tool descriptions | guidance for contributors; tool docs for agents | Permission Scope, Blast Radius |

Plus `baseline` (launch, idle, nothing granted).
