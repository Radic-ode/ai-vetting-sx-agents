---
run: vectorcraft
status: DONE 2026-10-29. All 11 probes run, all Within scope (self-update's update step Not run: never offered); see probe-results.md. Next: 04_report.
backend: Windows Sandbox (Windows 10 Pro 19045, enabled by the user 2026-10-28), one session per probe
---

# Probe plan: VectorCraft 0.17.0

## How every probe works
- **One fresh Windows Sandbox per probe.** Each is wiped on close, so no probe sees another's leftovers.
- **Configs:** `sandbox/wsb/<probe>.wsb`, written by `sandbox/make-wsb.ps1`. They turn off clipboard,
  printer and audio/video redirection, and the virtual GPU. Networking is off except for `net-out` and
  `self-update`.
- **Mapped folders:**
  - `C:\probe\tools`, read-only: `probe.ps1`, the MSI and `test.svg`, plus `Procmon64.exe` once approved.
  - `C:\probe\logs`, writable: that probe's own log folder only.
  - `fs-write` also gets `C:\probe\out`, its one writable target.
  - Nothing else from the host is visible, and no personal folders are mapped.
- **The script** (`sandbox/tools/probe.ps1`) does the same for every probe:
  1. Checks that the MSI's SHA-256 is still `861f4e9f…5d11c1`. On a mismatch it stops.
  2. Plants fake credentials in the sandbox user's profile, each tagged with a random string:
     `.ssh\id_rsa`, `.aws\credentials`, `.env`, `.config\gh\hosts.yml`, a Chrome `Login Data` stand-in,
     a file in `AppData\Roaming\Microsoft\Credentials`, and the environment variable `CANARY_TOKEN`.
  3. Runs that probe's task under two observers: **Process Monitor**, which records every file,
     registry, network and process event, and a backup poll (`netstat` every second, the process list
     every 5 s). Procmon loads `tools/probe.pmc` (written by `sandbox/make-pmc.py`), which drops before
     writing only Procmon's own events, NTFS metadata, fast I/O, profiling, and Windows' background
     scanners (Defender, Search, telemetry). Nothing is filtered by VectorCraft's name.
  4. Where relevant, snapshots the startup places (Run keys, scheduled tasks, services, uninstall
     entries, file lists) before and after, and diffs them.
- **When a person is needed,** the console says `>>> YOU: …` and waits for Enter (e.g. "click Later").
- **Analysis happens afterwards on the host.** I read the logs, then fill in `probe-results.md` with
  observed against expected and a verdict. Every finding cites the log line.

## The probes (expected footprint written before running)

| # | Probe | Grant | Task | Expected | Internet | Your clicks |
|---|---|---|---|---|---|---|
| 1 | `baseline` | nothing | install, launch, idle 2 min, quit | install dir; its own settings folder; a failed offline update check; **no** canary access, Run keys, tasks or services | no | close app |
| 2 | `install` | Program Files, Start menu | the MSI only, silent | `C:\Program Files\VectorCraft`, Start-menu shortcut, uninstall entry, maybe a `.vectorcraft` file association; nothing that auto-starts | no | none |
| 3 | `persist` | nothing extra | install, then launch, run 1 min and quit; diff before and after each step | launching adds no Run key, task or service. *(The Win10 sandbox can't reboot, so this checks what is set up to start again, not an actual restart.)* | no | close app |
| 4 | `net-out` | network, logged | launch, 2 min (startup update check) | DNS and connections only to `api.github.com` / `github.com` / GitHub CDN; no prompt (already newest) | **yes** | close app |
| 5 | `self-update` | network, install dir writable | launch as "0.1.0" twice: **Later**, then **Update** | Later: no download. Update: downloads only from `github.com/storytold`, replaces the install, restarts; the new exe is still validly signed by Learning Machines Inc | **yes, downloads ~100 MB** | Later, Update, close |
| 6 | `net-listen` | loopback only | `vectorcraft --control 7979` | listens on `127.0.0.1:7979` only, never `0.0.0.0`; no outbound | no | close app |
| 7 | `fs-read` | read `test.svg` | open it from the command line | reads `test.svg` and its own install/settings files; no canaries, no other user files | no | check, close |
| 8 | `fs-write` | write `C:\probe\out` | `vectorcraft-cli convert` to SVG, PDF, PNG | writes only `C:\probe\out\test.*` (plus temp files) | no | none |
| 9 | `exec` | nothing extra | print to "Microsoft Print to PDF", printer/page setup, Reveal in folder | only `powershell` (printer list / print verb), `rundll32 printui.dll`, `explorer`, maybe `reg.exe query` | no | 3 short tasks |
| 10 | `secrets` | canaries present | normal use 2 min: shapes, menus, open/save dialogs (cancelled) | no canary file opened, `CANARY_TOKEN` never written or sent | no | 2 min of use |
| 11 | `agent-text` | none | `vectorcraft-cli mcp --headless`; ask it for its tool, prompt and resource lists | descriptions match what the tools do; nothing tells an agent to fetch, run, send or hide anything. I review the text on the host as **data** | no | none |

Probes 1, 2 and 3 each include the MSI install; the other probes install it before observing, so their
trace shows only the probe's own task.

## Known gaps in this plan
- Process Monitor records which hosts the app connects to, not what it sends. Data inside encrypted
  traffic isn't visible. A canary turning up in network traffic would only be caught if it was written
  somewhere unencrypted first.
- GUI tasks depend on your clicks; anything the app does only on paths we don't click stays unobserved.
- Updating replaces 0.17.0 with whatever release is newest *today*. That build is not the one statically
  reviewed; the probe checks its source and signature only.
- Events from Defender (`MsMpEng`, `NisSrv`), Windows Search and `CompatTelRunner` are dropped to keep the
  trace closable. Something VectorCraft did only through one of those would be missed. (`System` was dropped
  too until net-out, where it turned out to hide network events; it is kept from self-update on.)
- The MCP server is probed headless. The `--connect` mode is covered by `net-listen` only as a port.

## What needs your yes before anything runs
1. **This plan**, all 11 probes.
2. **Probes 4 and 5 reach the real internet** from inside the sandbox. Probe 5 downloads the newest
   VectorCraft release.
3. **Download Process Monitor:** `ProcessMonitor.zip` from Microsoft Sysinternals,
   `https://download.sysinternals.com/files/ProcessMonitor.zip` (about 3–4 MB, Microsoft-signed). I'd
   verify its signature and place only `Procmon64.exe` in `sandbox/tools/`.
4. **The Sysinternals licence (EULA):** the script starts Process Monitor with `/AcceptEula`, which
   accepts Microsoft's Sysinternals licence terms inside each sandbox. That's your decision. The
   alternative is that you open Procmon once on the host and accept it there.

## To run (after approval)
1. On the host: `sandbox\make-wsb.ps1` (fresh, empty log folders).
2. Double-click `sandbox\wsb\<probe>.wsb`. One at a time; Windows Sandbox runs one session at a time.
3. Follow the `>>> YOU:` prompts. When it says PROBE FINISHED, close the Sandbox window.
4. Tell Claude which probe finished, so its logs get read and `probe-results.md` is filled in.
