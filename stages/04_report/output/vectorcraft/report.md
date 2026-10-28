# AI Component Vetting Report

**Component:** VectorCraft 0.17.0 (desktop app, `vectorcraft-cli`, MCP server)
**Source:** release `v0.17.0`, `vectorcraft-0.17.0-windows-x64.msi`
**Repository:** github.com/storytold/vectorcraft (reviewed at `752a67e` and `9997ff0`)
**Date:** 2026-10-28

## Risk Tier: MEDIUM

## Scorecard

| Category | Score | Reasoning |
|---|---|---|
| Provenance & Maintainer Trust | Pass | Official org repo; both zips byte-identical to repo commits; MSI built by the repo's CI, hash matches `SHA256SUMS.txt`, Authenticode-signed by a Microsoft-verified identity (Learning Machines Inc). Minor LLC/Inc naming mismatch. |
| Permission Scope vs. Need | Partial | What it does fits an editor (files, printing, locale), but it also checks for updates over the network at every start, and can open a local control port; both are explained and the port is opt-in. |
| Auditability | Partial | Open source, readable, no obfuscation. But large (600k lines changed in 20 days), reviewed by pattern rather than read in full, and 32 dependencies come from the publisher's own forks that were not reviewed beyond the updater. |
| Blast Radius | Partial | Writes the user's files and spawns system helpers (PowerShell, rundll32, explorer) for documented jobs. Self-update can replace its own code, but only after consent with hash and signature checks. No secrets access or persistence found. |
| Change Control | Partial | Updates are prompted ("Later" available) and verified, not silent; release notes and checksums are published. But the startup check is on by default and the project changes extremely fast. |

## Capability Probes

| Capability | Grant | Probe task | Backend | Verdict |
|---|---|---|---|---|
| baseline | nothing | install, launch, idle | Windows Sandbox | Not run: no sandbox |
| install, net-out, self-update, net-listen, fs-read, fs-write, exec, secrets, persist, agent-text | one each (see `03_probe/.../probe-plan.md`) | one task each | Windows Sandbox | Not run: no sandbox |

## Coverage Limitations
- **No runtime probe was run** (no sandbox backend on this machine), so this tier is capped at Medium.
  All behaviour above is read from the code, not observed.
- The MSI's binaries were trusted through CI origin, checksum and signature; they were not rebuilt
  from source and compared.
- The 606k-line change between the reviewed versions was searched by pattern, not read.
- Forked dependencies (`craft-libs` except `update`, `egui`, `winit`, `winprint.rs`) were not reviewed.
- The MSI's own install actions (file associations, shortcuts, registry) were not inspected.
- The MCP server's tool descriptions were not reviewed as agent-facing text.

## Recommendation: Install with mitigations

(The user had already installed it when this report was written.)

1. **Updates:** keep answering the startup prompt deliberately. Before updating, check the release's
   `SHA256SUMS.txt` and signature as done here, or update manually from the releases page.
2. **Control port:** only start the app with `--control` when an agent needs to drive it, and close it
   afterwards. Any local program can use the port while it is open.
3. **MCP:** register the server headless and scoped: `vectorcraft-cli mcp --automation-read-root <dir>
   --automation-write-root <dir>`, so an agent can only touch one project folder.
4. **To reach Low:** enable Windows Sandbox and run `probe-plan.md`, starting with `baseline`, `net-out`
   and `self-update`, then `exec`.

---
*Generated using the ai-vetting-skill-sx skill. Static analysis plus the capability probes listed — see
Coverage Limitations above.*
