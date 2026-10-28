---
run: vectorcraft
status: NOT APPROVED, NOT RUN (no sandbox backend on this machine, 2026-10-28)
backend: Windows Sandbox, one .wsb per probe (VectorCraft is a native Windows app; probe.sh's Linux
  backend does not apply). Observe with Sysinternals Process Monitor inside the sandbox.
---

# Probe plan: VectorCraft 0.17.0

Each probe: a fresh Windows Sandbox session, the MSI mapped read-only, canary files in the sandbox
user's profile (`.ssh\id_rsa`, `.aws\credentials`, `.env`, a browser-profile stand-in, env `CANARY_TOKEN`),
everything denied except the grant. Expected footprint written before running.

| Probe | Grant | Task | Expected footprint | Real internet? |
|---|---|---|---|---|
| `baseline` | nothing (`<Networking>Disable`) | install, launch, idle 2 min, quit | install dir + its own settings folder; an update check that fails offline; no canary reads | no |
| `install` | write: Program Files, Start menu | run the MSI | files in `C:\Program Files\VectorCraft`, Start-menu shortcut, uninstall registry entry; nothing in Run keys, tasks or services | no |
| `net-out` | network on (logged) | launch with the startup update check | connections only to `api.github.com`, `github.com`, their CDNs; nothing else | **yes** |
| `self-update` | network on, install dir writable | pretend an old version (`VECTORCRAFT_PRETEND_VERSION=0.1.0`), answer the prompt both ways | "Later": no download. "Update": download from `github.com/storytold`, SHA-256 + signature checked, install dir replaced, restart | **yes** |
| `net-listen` | loopback only | `vectorcraft --control 7979`; `vectorcraft-cli mcp --connect 127.0.0.1:7979` | binds `127.0.0.1:7979` only; no outbound | no |
| `fs-read` | read: one test SVG in a mapped folder | open it | reads that file and its own install/settings files only | no |
| `fs-write` | write: one mapped `out` folder | export SVG/PDF/PNG there | writes only to `out` and its own settings | no |
| `exec` | nothing extra | print to "Microsoft Print to PDF"; Reveal in folder; Printer setup | `powershell` (printer list, print verb), `explorer`, `rundll32 printui.dll` only | no |
| `secrets` | canaries present | normal use 2 min | no canary file opened | no |
| `persist` | nothing extra | install, launch, reboot the sandbox session | no new Run keys, scheduled tasks, services | no |
| `agent-text` | throwaway agent session, no tools | load `vectorcraft-cli mcp` tool descriptions, ask for a simple drawing | descriptions match their tools; nothing asks the agent to fetch, run or send | no |

## To run this plan
1. The user turns on **Windows Sandbox** (Settings → Optional features; Windows 10/11 Pro). Not done for them.
2. A person approves this plan (and the two probes that reach the internet).
3. Write `probe-results.md` with observed vs. expected per row; logs to `logs/`.
