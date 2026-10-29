# AI Component Vetting Report

**Component:** VectorCraft 0.17.0 (desktop app `vectorcraft.exe`, CLI `vectorcraft-cli.exe`, built-in MCP server)
**Source:** release `v0.17.0` (2026-10-25), `vectorcraft-0.17.0-windows-x64.msi`, SHA-256 `861f4e9f…5d11c1`
**Repository:** github.com/storytold/vectorcraft (source reviewed at `752a67e`, Oct 8, and `9997ff0`, Oct 28)
**Date:** 2026-10-29 (replaces the static-only report of 2026-10-28)

## Risk Tier: MEDIUM

VectorCraft 0.17.0 behaved like a well-behaved desktop editor in all 15 sandbox probes. It touched no
canary credentials, set nothing to start on its own, made no network contact at all, kept its control port on
loopback, and started only the helper programs it documents. It stays at Medium for two reasons:
- it is large, fast-moving code that was spot-checked, not read, and the exact 0.17.0 commit was not reviewed;
- it can start PowerShell and write wherever it is pointed, and its MCP interface hands that reach to an agent
  unless it is scoped. Scoping is off by default. When it is on, it confined every file path tried, by any route.

## Scorecard

| Category | Score | Reasoning |
|---|---|---|
| Provenance & Maintainer Trust | Pass | Official org repo. Both source zips are byte-identical to repo commits. The MSI was built by the repo's CI, its hash matches the release's `SHA256SUMS.txt`, and it is Authenticode-signed by a Microsoft-verified identity (Learning Machines Inc), re-verified after the probes. Minor LLC/Inc naming mismatch. |
| Permission Scope vs. Need | Pass | Observed use fits an editor: the files the user opens and saves, its own settings and logs, printer helpers, and a locale lookup. 0.17.0 has **no network client**: no connection in three online launches, and no updater or HTTP/TLS code in the shipped binaries. The control port is opt-in and bound to `127.0.0.1`. *(Up from Partial: the network use scored statically belongs to newer code.)* |
| Auditability | Partial | Open source, readable, no obfuscation. But it is large (606k lines changed in 20 days), was reviewed by pattern and not read, 32 dependencies come from the publisher's own unreviewed forks, and the `v0.17.0` commit itself sits between the two reviewed commits. The probes and a byte search of the shipped binaries cover part of that gap. |
| Blast Radius | Partial | It writes wherever the user (or an agent) saves, and starts fixed PowerShell scripts (printer list, printing), `rundll32 printui.dll` and `explorer`, all observed and all documented. It doesn't run arbitrary code, reach the network, persist or touch credentials. But its MCP file tools take **any path** by default (shown: an unscoped `export` wrote to the Desktop), and the control port lets any local process drive the app while it is on. With `--automation-read-root` / `--automation-write-root` it refused every out-of-root path tried: the four file tools, file commands run by id through `run_command` / `command_run` / `command_batch` / `invoke_menu`, `..` traversal, and symlinks or junctions inside a root. It read or wrote nothing outside. That mitigation works, but the score is for the defaults: unscoped, an open control port while `--control` runs, and `run_command` reaching print and Explorer (not tested under scoping). So it stays Partial. |
| Change Control | Pass | 0.17.0 doesn't update itself: no update check in three online launches, and no updater code in the binary. A new version arrives only when the user installs a new MSI, which comes with release notes, checksums and a signature. **Newer versions add a startup update check** (prompted, hash- and signature-checked, per the source); re-assess on upgrade. *(Up from Partial.)* |

## Capability Probes

One fresh Windows Sandbox per probe, canary credentials planted in every one, observed with Process Monitor plus
a once-a-second connection and process poll. Details in `03_probe/output/vectorcraft/probe-results.md`.

| Capability | Grant | Probe task | Backend | Verdict |
|---|---|---|---|---|
| baseline | nothing | install, launch, idle 2 min, quit | Windows Sandbox | Within scope: its own settings/logs and the GPU shader cache only |
| install | Program Files, Start menu | silent MSI install, no launch | Windows Sandbox | Within scope: install dir, Start-menu shortcut, uninstall entry, App Paths. No custom actions, no association, nothing auto-starting. Also an **all-users desktop shortcut** (not expected, harmless) |
| persist | nothing extra | install, launch, quit; diff before and after | Windows Sandbox | Within scope: no Run key, task or service added |
| net-out | network | launch online, 2 min | Windows Sandbox (online) | Within scope: **no connection at all** (no socket opened) |
| self-update | network, install dir | two online launches as "0.1.0", Later / Update | Windows Sandbox (online) | Within scope: no check, no prompt, no download; still 0.17.0 and validly signed. The update step couldn't be exercised because **0.17.0 contains no updater** (binary search, below) |
| net-listen | loopback | `--control 7979` | Windows Sandbox | Within scope: `127.0.0.1:7979` only, no outbound |
| fs-read | read `test.svg` | open it from the command line | Windows Sandbox | Within scope: `test.svg` plus its own files. No other user file, no canary |
| fs-write | write `C:\probe\out` | CLI export to SVG, PDF, PNG | Windows Sandbox | Within scope: temp file then rename inside the out folder only |
| exec | nothing extra | print, printer setup, reveal in folder | Windows Sandbox | Within scope: only `powershell` (printer list, print script), `rundll32 printui.dll`, `explorer /select`, `reg.exe query` (and Windows' fax console after a mis-click on the Fax printer) |
| secrets | canaries present | 2½ min of normal use incl. Open/Save dialogs | Windows Sandbox | Within scope: no canary file opened, `CANARY_TOKEN` never written or sent |
| agent-text | none | `vectorcraft-cli mcp --headless`: list tools, prompts, resources | Windows Sandbox | Within scope: 32 tools, 5 prompts, 3 resources. Text accurate, nothing addressed to the agent's own rules, no URLs or hidden characters |
| mcp-call-unscoped | write `C:\probe\out` | MCP calls: new document, draw, paint, inspect, preview, export, open; plus an export to the Desktop | Windows Sandbox | Within scope: every result as its tool describes; writes only the requested files. The Desktop export succeeded: **unscoped, any path** |
| mcp-call-scoped | write `C:\probe\out`, read the tools folder | same calls with `--automation-read-root` / `--automation-write-root`, then 9 out-of-root writes and reads (Desktop, two canaries, `win.ini`, two `..` traversals) | Windows Sandbox | Within scope: in-root calls work; **all 9 out-of-root calls refused**, same message whether the file exists or not; no out-of-root content read or written (attribute-only handles for path resolution) |
| mcp-call-commands | as mcp-call-scoped | 5 file commands by id (`document.save`/`export`/`open`, `file.open`/`saveAs`, `document.exportForOffice`), each via `run_command`, `command_run`, `command_batch`, `invoke_menu`, in and out of root | Windows Sandbox | Within scope: in-root calls work; **all 40 out-of-root calls refused**, nothing read or written outside. 2 further commands picked by the selection rule take no path (not exercised) |
| mcp-call-links | roots on the sandbox's own disk | a file symlink and two junctions inside the roots pointing at a canary, `C:\Windows` and the Desktop; open, export and save through them | Windows Sandbox | Within scope: **all 4 refused**. The server follows each link to its real target before checking it |

**Binary check (host, read-only, after the probes).** The MSI was unpacked as data with 7-Zip. `vectorcraft.exe`
and `vectorcraft-cli.exe` match the hashes the sandbox recorded. Neither contains:
- the updater: `api.github.com`, `craft-update`, `SHA256SUMS`, `PRETEND_VERSION`, `CRAFT_UPDATE_DEV`, `verifysign`;
- an HTTP/TLS stack: `ureq`, `rustls`.

Their only web addresses are documentation, repository, XML-namespace, website and Discord links. The updater
in the static review is newer than this release.

## Coverage Limitations

- **The exact source of 0.17.0 was not reviewed.** The release tag lies between the two reviewed commits. Its
  behaviour rests on the probes and the binary search, and the binaries were not rebuilt from source and compared.
- **Updating is unobserved.** 0.17.0 has no updater, so the download, replacement and signature check in newer
  code have never been seen running. Any newer version needs `net-out` and `self-update` probed again.
- **Code coverage is partial:**
  - The 606k-line change between the reviewed commits was searched by pattern, not read.
  - `craft-libs` (beyond `update`) and the `egui`, `winit` and `winprint.rs` forks were not reviewed.
- **GUI probes cover only the paths that were clicked.** Not exercised:
  - import/place;
  - WebAssembly plug-ins;
  - image trace, fonts and text features;
  - hardware GPU paths (the sandbox has no GPU and used the software renderer).
- **The print script was seen only in part.** Procmon kept its first 4,070 characters. Its behaviour was
  observed for the Fax and Print-to-PDF paths only.
- **MCP coverage is partial:**
  - called: drawing, inspection, preview and the four file tools, unscoped and scoped. Not called: print,
    reveal, keyboard, `ui_*` and most other tools;
  - the root options were tested on the four file tools, on 5 file commands by id via all four command routes,
    and on symlinks and junctions. **Not tested:** file commands past the probe's cap of 8 (e.g. `file.place`,
    `file.saveCopy`, `file.export`). The check sits in the shared command path, so these are likely covered,
    but that is inferred. Print and reveal were not tested under scoping. Hard links inside a root can't be
    told apart from ordinary files by any path check;
  - `--connect` mode was not probed, with or without the root options.
- **The control port was only checked for where it listens,** not for what it accepts from a local process.
- **No real reboot.** The Windows 10 sandbox can't restart, so `persist` shows nothing is *set up* to start
  again, not what happens across a restart.
- **Observer limits:**
  - Process Monitor sees hosts and files, not the content of encrypted traffic.
  - Defender, Windows Search and telemetry processes were filtered out in every probe.
  - Events Procmon attributes to `System` were dropped until `self-update`. Earlier network verdicts also rest on
    the connection poll and on loaded libraries.
- **The host install is not covered.** The user installed and ran the same MSI (same hash) on their own machine
  on 2026-10-28, before this assessment. That was not monitored. The probes describe what this binary does,
  not what happened there.

## Recommendation: Install with mitigations

The user already has 0.17.0 installed, from the same MSI that was probed. Nothing found calls for removing it.

1. **Stay on 0.17.0 deliberately.** It doesn't check for or install updates and makes no network contact. Before
   moving to a newer version:
   - check its `SHA256SUMS.txt` and Authenticode signature as in intake;
   - expect a startup update check (prompted, with "Later");
   - ideally re-run the `net-out` and `self-update` probes against it (`make-wsb.ps1 -Redo net-out`, with the
     new MSI and hash in `probe.ps1`).
2. **Scope the MCP server before giving it to an agent:** `vectorcraft-cli mcp --automation-read-root <project>
   --automation-write-root <project>`. Unscoped (the default), its file tools read and write any path your
   account can, and `run_command` can trigger printing and Explorer. With the roots set, every path outside them
   was refused in the probes, whether through the file tools, file commands run by id, `..` tricks or links.
   The server confirms on stderr: `files confined: read …; write …`. What remains:
   - the roots confine files, not actions. Keep the agent client's approval prompt on for `run_command`,
     `command_batch` and `invoke_menu`, which can still print or open Explorer;
   - keep hard links to outside files out of the root folders.
3. **Use the control port only when needed.** Start `--control` only while an agent drives the app, and close
   the app afterwards. Any local program can use the port while it's open.
4. *(Optional)* Delete the all-users desktop shortcut (`C:\Users\Public\Desktop\VectorCraft.lnk`) if you don't
   want it.

**What would move it to Low:**
- Auditability: review the `v0.17.0` tag commit and the forked dependencies, or rebuild the MSI from that tag
  and match the binaries.
- Blast Radius: the root options are now shown to confine file access by every route tried. The score is held
  back by the defaults, not by the mitigation: unscoped by default, the control port, and print/Explorer via
  `run_command`. A future release that scopes by default, or limits `run_command` under the roots, would
  change that.

---
*Generated using the ai-vetting-skill-sx skill. Static analysis plus the capability probes listed — see
Coverage Limitations above.*
