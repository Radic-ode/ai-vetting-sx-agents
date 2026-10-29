---
run: vectorcraft
date: 2026-10-29
backend: Windows Sandbox, one fresh session per probe (see probe-plan.md)
---

# Probe results: VectorCraft 0.17.0

| Probe | Verdict |
|---|---|
| baseline | Within scope (run 2, 2026-10-29), with two notes and one gap below |
| install | Within scope (2026-10-29), with one note |
| persist | Within scope (2026-10-29) |
| net-out | Within scope (2026-10-29): **no connection at all**, where an update check was expected |
| self-update | Within scope (2026-10-29), but **the update path was never triggered**: no check, no prompt, no download |
| net-listen | Within scope (2026-10-29): `127.0.0.1:7979` only |
| fs-read | Within scope (2026-10-29) |
| fs-write | Within scope (2026-10-29) |
| exec | Within scope (2026-10-29): only the expected PowerShell, `rundll32 printui.dll`, `explorer` (+ `reg`) |
| secrets | Within scope (2026-10-29): no canary opened, token not written or sent |
| agent-text | Within scope (2026-10-29): text accurate, no instructions to the agent; file tools take any path |
| mcp-call-unscoped | Within scope (2026-10-29): 8 calls, each result as described; the Desktop control export was written (unscoped = any path) |
| mcp-call-scoped | Within scope (2026-10-29): in-root calls work; **all 9 out-of-root calls refused**, traversal included; no out-of-root file read or written (only metadata handles for path resolution) |
| mcp-call-commands | Within scope (2026-10-29): 5 file commands × 4 routes (`run_command`, `command_run`, `command_batch`, `invoke_menu`): every in-root call worked, **all 40 out-of-root calls refused**; 2 chosen commands take no `path` (not exercised) |
| mcp-call-links | Within scope (2026-10-29): a file symlink and two junctions inside the roots, pointing out: **all 4 attempts refused**, nothing read or written through them |

## baseline

**Runs.** Run 1 (2026-10-28, `logs/baseline-run1/`): snapshots fine, but both Procmon traces are corrupt
("not closed cleanly", procmon-parser), so it is not evidence. Run 2 (2026-10-29, `logs/baseline/`) is the
one this verdict rests on. The trace closed cleanly: 5,910,893 events. Procmon ran with `probe.pmc` (26 rules,
drop mode). That is confirmed by `procmon-settings.reg`, exported from inside the sandbox
(`DestructiveFilter=1`, `FilterRules` count `0x1a`).

**Tree.** `vectorcraft.exe` PID 5340, started by the probe script at 09:31:25. It had one child:
`reg.exe query "HKCU\Control Panel\International" /v LocaleName` (PID 5364, plus its conhost 5372). Windows
later reused PID 5372 for a `netstat` run of the backup poll; those events are not counted as the tree's.

| Expected (written before running) | Observed | |
|---|---|---|
| install dir | msiexec wrote `C:\Program Files\VectorCraft\…`, the Start-menu `VectorCraft.lnk`, uninstall entry `{1BAEC43A-…}`, `App Paths\vectorcraft.exe`, `HKLM\Software\VectorCraft` (`InstallDir`, `DesktopShortcut`). The MSI log shows no custom actions. | as expected |
| its own settings folder | The tree wrote only `%APPDATA%\VectorCraft\logs\vectorcraft.log`, `…\logs\graphics-start.json`, and the Direct3D shader cache `%LOCALAPPDATA%\D3DSCache\…`. Its only reads outside the install dir and `C:\Windows` were those same paths. | as expected |
| a failed offline update check | No TCP/UDP events from the tree. A name lookup goes through Windows' DNS service, not the app, so a failed check would not show under the app either. Its own log, which would say, was discarded with the sandbox. | **not confirmed** (gap 1) |
| no canary access | No process opened any of the six canary files (0 events on those paths). `CANARY_TOKEN` appears only where Windows itself handles the environment (`HKCU\Environment` reads, every process's inherited environment). | as expected |
| no Run keys, tasks or services | Snapshot diffs: no task added. Run keys: only Windows consuming its own `RunOnce` `ctfmon.exe /n`. Services: `BITS` Manual→Automatic, written by `services.exe` at 09:32:21, a minute after VectorCraft started and with no link to it (Windows' own trigger-start). Uninstall: `+ VectorCraft 0.17.0`. | as expected |

**Note 1: desktop shortcut.** msiexec also wrote `C:\Users\Public\Desktop\VectorCraft.lnk`, for all users,
controlled by `HKLM\Software\VectorCraft\DesktopShortcut`. It is not in the expected footprint, and not a
risk. The `install` probe should list it.

**Note 2: a root certificate appeared.** msiexec wrote `HKLM\…\SystemCertificates\AuthRoot\Certificates\
F40042E2E5F7E8EF8189FED15519AECE42C3BFA2`. That is *Microsoft Identity Verification Root Certificate
Authority 2020*. It is the root of the MSI's own Authenticode chain (Learning Machines Inc → Microsoft ID
Verified CS EOC CA 03 → … PCA 2021 → this root) and of its timestamp chain. The same certificate is in the
host's own `LocalMachine\Root` and `AuthRoot`. Windows installs a trusted root on first use when it verifies a
signature. The MSI didn't add it.

**Gap 1: the app's own log was not kept.** Fixed for the next probes: `probe.ps1` now copies
`%APPDATA%\VectorCraft` and `%LOCALAPPDATA%\VectorCraft` into the log folder.

**Trace size.** It is still 2.9 GB. 90% (4.83 M events) is svchost PID 1104 (`-k netsvcs`) doing registry,
AMSI and Defender lookups. *Corrected after `persist`:* I first put this down to the backup poll's WMI
queries. But `persist` ran with no WMI in the poll and the same svchost still logged 4.3 M events. Call
stacks sampled there (3,812 events) all go through the WMI service's own repository (`wbemcore.dll` →
`repdrvfs.dll` → `amsi.dll`). Windows' `WMIADAP.EXE /R /T` performance-counter refresh starts right after
the install, and VectorCraft loads no WMI or AMSI library. This is Windows' own background noise; it can't
be filtered without hiding the Task Scheduler, which runs in the same svchost. VectorCraft's whole tree was
18,026 events.

## install

**Run.** 2026-10-29 09:47, `logs/install/`. The trace closed cleanly with 1,002,508 events (490 MB, against
2.9 GB for baseline before the poll stopped using WMI). The MSI hash was checked and `msiexec` exited 0.
Silent install only, no launch.

| Expected (written before running) | Observed | |
|---|---|---|
| `C:\Program Files\VectorCraft` | 25 files: `vectorcraft.exe`, `vectorcraft-cli.exe`, README, NOTICE, licence and font-licence texts (`diff-pre-post-files.txt`) | as expected |
| Start-menu shortcut | `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\VectorCraft.lnk` | as expected |
| uninstall entry | `Uninstall\{1BAEC43A-AC44-4476-887E-D64AE1BBCC36}`, 25 standard values. The snapshot shows `+ VectorCraft 0.17.0` | as expected |
| maybe a `.vectorcraft` file association | none written. `GlobalAssocChangedCounter` was bumped, which Windows Installer does whenever it adds shortcuts | none |
| nothing that auto-starts | no Run key, task or service added. The only Run-key change is Windows consuming its own `RunOnce` `ctfmon.exe /n`. The services diff is empty | as expected |

Also written by msiexec, all ordinary installer work: `App Paths\vectorcraft.exe`, `HKLM\Software\VectorCraft`
(`InstallDir`, `DesktopShortcut`), `C:\Config.Msi` and an `MSI*.tmp` (rollback data, removed again), and
`ngen.log` under `Microsoft.NET\Framework64`. The MSI log lists no custom actions. msiexec started no other
program (`analysis-detail.txt`). No process touched a canary file.

**Note: shortcut on the all-users desktop.** `C:\Users\Public\Desktop\VectorCraft.lnk`, the same as in
baseline. It is not in the expected footprint, and not a risk. The Microsoft root certificate was added again,
as in baseline Note 2.

## persist

**Run.** 2026-10-29 09:52, `logs/persist/`. Install, then snapshot `installed`, then the trace starts. Launch
at 09:53:26, about 1 minute of running, closed by the user at 09:55:37, then 15 s of waiting before the trace
stopped. The trace closed cleanly: 4,528,955 events, 2.2 GB, 96% of it Windows' WMI churn (see the baseline
"Trace size" note). VectorCraft's own data folder was copied out (`appdata-Roaming/`).

**Tree.** `vectorcraft.exe` PID 2008 had one child, the same `reg.exe query "HKCU\Control Panel\International"
/v LocaleName` as in baseline. It exited normally (`Process Exit`).

| Expected (written before running) | Observed, `installed` → `post` | |
|---|---|---|
| launching adds no Run key | `diff-installed-post-run-keys.txt` empty | as expected |
| no scheduled task | `diff-installed-post-tasks.txt` empty | as expected |
| no service | only `BITS` Manual→Automatic, written by `services.exe`, as in baseline (Windows) | as expected |
| *(implied)* nothing else left to start again | new files are only VectorCraft's own `ui.json`, `logs\vectorcraft.log`, `logs\graphics-start.json`, the Direct3D cache, a Windows Security Health `.etl`, and two Credential Vault files (below). No HKCU class or association written by the tree | as expected |

**The Credential Vault files are Windows' own.** `AppData\Local\Microsoft\Vault\…\Policy.vpol` and
`…\UserProfileRoaming\Latest.dat` were created by `lsass.exe` (PID 888) at 09:54:12. It is the only process
that touched `Microsoft\Vault` in this trace, and baseline shows the same files at the same point in its
session (09:32:26). VectorCraft never opened a Vault path.

**Registry writes in VectorCraft's name** were only Windows' own bookkeeping, which Procmon records in the
process's context: `bam\State\UserSettings\…\vectorcraft.exe` (Background Activity Moderator, which records
each program that runs) and one `Notifications\Data` value.

**VectorCraft's own log** (`appdata-Roaming/logs/vectorcraft.log`) has 7 lines, all about graphics: no GPU in
the sandbox, so it falls back to the Microsoft Basic Render Driver. **There is no update-check line, not even
a failure.** The static review expected a startup check to `api.github.com`. Either it isn't made on startup,
or it isn't logged. That is for `net-out` to settle. `ui.json` holds UI and editor preferences only, ends with
`"status": "quit"`, and lists no recent files. The canary tag appears in none of the copied files.

**Limit (from the plan):** the Windows 10 sandbox can't reboot. This shows nothing is *set up* to start
again; it doesn't watch an actual restart.

## net-out

**Run.** 2026-10-29 10:22, `logs/net-out/`, **networking on**. Launch at 10:22:38, 2 minutes untouched,
closed by the user (`Process Exit`, status 0, at 10:26:30). No update prompt appeared. The trace closed
cleanly: 2.8 GB, almost all of it Windows' WMI churn again.

**Observed: VectorCraft opened no network connection.** Three independent signs:
- **Procmon:** no TCP or UDP event from `vectorcraft.exe` (PID 5836) or its one child (`reg.exe`, the locale
  query).
- **Backup poll** (`netstat -ano` every second, `poll-net.txt`): PID 5836 never owns a connection or listening
  port. The PIDs that do are Windows': SmartScreen, Explorer, msiexec's certificate check, and several service
  hosts.
- **Loaded libraries:** VectorCraft loaded `ws2_32.dll`, `crypt32.dll` and `bcrypt.dll` at startup (plain
  imports). It never loaded `mswsock.dll`, which Winsock loads the first time a socket is created, or
  `dnsapi.dll`.

Its own log (`appdata-Roaming/logs/vectorcraft.log`) again has only the 7 graphics lines. There was no
connection to Discord either; the Discord button in its title bar was not clicked.

| Expected (written before running) | Observed | |
|---|---|---|
| DNS and connections only to `api.github.com` / `github.com` / GitHub CDN | none at all | within scope, but **not as expected** |
| no prompt (already newest) | no prompt | as expected |

**Why this matters.** The static inventory lists an update check at startup (`craft-update`, ureq/rustls, to
`api.github.com`). This run didn't see one. What we can say is that VectorCraft 0.17.0 made **no** network
contact in 2 minutes of idle running. It does not show that the update code is absent. The check might be
delayed, conditional, or only run from a menu. `self-update` runs it as 0.1.0 and should show which.

**Gaps found and fixed for the next probes:**
- Procmon booked one Windows service's HTTPS traffic (svchost PID 6124, `-k NetworkService`, started by
  `services.exe` at 10:23:58) under `System`, which the filter dropped. Only the poll caught it. VectorCraft's
  result above doesn't rest on Procmon alone, but `System` is now kept (`make-pmc.py`).
- `dns-cache.txt` was never written: `Get-DnsClientCache` silently returned nothing. An `ipconfig /displaydns`
  taken by hand 6 minutes later had expired. The script now turns on the Windows DNS-client event log, which
  records each lookup with the PID that made it, and saves it as `dns-client-events.txt`.

## self-update

**Run.** 2026-10-29 10:44, `logs/self-update/`, **networking on**, `System` no longer dropped, DNS-client event
log on. Two launches with `VECTORCRAFT_PRETEND_VERSION=0.1.0`, confirmed in both processes' start-up
environment in the trace:
- PID 952, 10:44:47 to 10:51:59, about 7 minutes.
- PID 5036, 10:52:04 to 10:56:02, about 4 minutes.

Both exited normally (status 0). The user saw **no update prompt either time**. The trace closed cleanly
(3.0 GB).

**Observed: no update check, so nothing to approve, download or install.**
- **DNS-client log** (`dns-client-events.txt`, the whole session): no lookup of any GitHub, VectorCraft,
  ArtCraft (`getartcraft.com`) or Discord name, by any process. Every name looked up is Microsoft's: Windows
  Update, certificate revocation, SmartScreen, and the MSN news-and-weather taskbar panel, which the user
  opened by accident at about 10:53.
- **Procmon:** no TCP or UDP event from either VectorCraft process, and neither loaded `mswsock.dll`,
  `dnsapi.dll` or `winhttp.dll`.
- **Backup poll:** neither PID ever owns a connection. Other processes do throughout, so the sandbox was
  online.
- **Its own log:** both files (`vectorcraft.1.log`, `vectorcraft.log`) have only the 7 graphics lines.
- **After:** `vectorcraft --version` is `0.17.0`. Both exes are validly signed by Learning Machines Inc
  (`signature-after.txt`). The snapshot diff shows no change except the app's own settings and logs, and no
  Run key, task, service or uninstall change.

| Expected (written before running) | Observed | |
|---|---|---|
| Later: no download | no prompt, no download | as expected (trivially) |
| Update: downloads only from `github.com/storytold`, replaces the install, restarts, still validly signed | **not exercised**: no prompt appeared | **Not run: update never offered** |

**What this means for the report.** In three online launches (net-out, and self-update twice as 0.1.0),
VectorCraft 0.17.0 never contacted its update server. The update code the static review found (`craft-update`,
startup prompt, SHA-256 and signature checks) exists in the source but did not run at startup here. The
download, the replacement of the install, and the signature check on a downloaded build remain **unobserved**.
A check from a menu, if VectorCraft has one, was not tried; it isn't in the approved plan.

**Environment note, not VectorCraft's doing:** while the sandbox was online, the host's USB-tethered connection
(`Ethernet 4`, Remote NDIS) dropped and stayed down until the user reconnected it, twice. The host's System log
shows Hyper-V reinitialising its virtual switches (Default Switch, WSL) at 10:46:55. The sandbox stayed online
apart from those drops: the DNS log shows Windows' own lookups succeeding throughout both launches.

## net-listen

**Run.** 2026-10-29 11:06, `logs/net-listen/`, networking off (loopback works). `vectorcraft --control 7979`,
PID 860, started at 11:07:13. The listener snapshot was taken 15 s later. The user closed the app, and the
trace stopped at 11:08:29 (1.7 GB, closed cleanly).

| Expected (written before running) | Observed | |
|---|---|---|
| listens on `127.0.0.1:7979` only, never `0.0.0.0` | `listening.txt`: `127.0.0.1:7979 pid=860 vectorcraft`, and no other port owned by PID 860. The poll agrees (`TCP 127.0.0.1:7979 0.0.0.0:0 LISTENING 860`). Every other listener is Windows' (`svchost`, `lsass`, `wininit`, `services`, `spoolsv`) | as expected |
| no outbound | no TCP/UDP event from PID 860 in Procmon. The only DNS lookups in the session are Windows' `wpad` and `localhost` | as expected |

Child processes: only the usual `reg.exe query "HKCU\Control Panel\International" /v LocaleName`. Its own log
doesn't mention the control port. The trace has no `Process Exit` for PID 860, because Procmon stopped 7 s
after the user pressed Enter. That doesn't affect what was listening. Nothing connected to the port: the probe
only checks where it listens, not what it accepts (see the plan's known gaps).

## fs-read

**Run.** 2026-10-29 11:11, `logs/fs-read/`, networking off. `vectorcraft "C:\probe\tools\test.svg"`, PID 2204,
started at 11:12:13. The user closed it without saving at 11:18:06. The trace closed cleanly (2.6 GB).

| Expected (written before running) | Observed | |
|---|---|---|
| reads `test.svg` | opened, read to end-of-file and closed at 11:12:13.56 (path in the trace: the mapped tools folder, `\Device\vmsmb\…\test.svg`). `ui.json` now lists it in `recent_files` | as expected |
| its own install/settings files | the install dir, `%APPDATA%\VectorCraft` (`ui.json` via a temp file and rename, `logs\`), the Direct3D shader cache | as expected |
| no canaries | no process opened a canary file | as expected |
| no other user files | nothing else under the profile. In the mapped tools folder, the only other access was one failed open of a `Fonts` folder next to the document (a document-local fonts lookup; the folder doesn't exist). It never touched the MSI, `probe.ps1` or Procmon | as expected |

Child processes: the usual `reg.exe` locale query only. No network events. Registry writes only Windows'
bookkeeping (`bam`).

**Analysis fix.** `trace-tree.py` listed only reads under `C:\`, so it missed reads in mapped host folders
(`\Device\vmsmb\…`). It now includes them. The five earlier traces were re-checked with it (baseline,
persist, net-out, self-update, net-listen): VectorCraft read nothing in a mapped host folder in any of them,
so their results stand.

## fs-write

**Run.** 2026-10-29 11:29, `logs/fs-write/`, networking off. It ran with no clicks. The sandbox then shut itself
down after `DONE.txt`. Windows Sandbox reported that on the host as "connection to the sandbox was lost", and
its window then hung until the user ended it. The logs were already complete, but the self-shutdown has been
taken out again. Three runs of `vectorcraft-cli convert C:\probe\tools\test.svg C:\probe\out\test.<ext>`
(PIDs 2268, 2508, 3684), all exit 0. The trace closed cleanly (260 MB).

| Expected (written before running) | Observed | |
|---|---|---|
| writes only `C:\probe\out\test.*` (plus temp files) | each run wrote one temp file in the out folder (`.test.<ext>.<pid>-0.tmp`) and renamed it to `test.<ext>`. Nothing written anywhere else, apart from the console pipe back to the script. `out-files.txt` / `logs/fs-write-out/`: `test.svg` 683 B, `test.pdf` 10,376 B, `test.png` 2,870 B | as expected |

Reads outside the install dir: only `test.svg` in the read-only tools folder. No child processes, no network
events, no registry writes beyond Windows' handle bookkeeping (`RegSetInfoKey`), and no canary touched. The CLI's
own output (`cli-output.txt`) is one JSON line per export. The PDF and PNG warn that the drawing's font isn't
installed, so a fallback font (Source Sans 3) was used.

## agent-text

**Run.** 2026-10-29 11:49, `logs/agent-text/`, networking off, no clicks. `vectorcraft-cli mcp --headless` (PID
756) got five JSON-RPC messages on stdin (`mcp-requests.jsonl`): initialize, initialized, `tools/list`,
`prompts/list`, `resources/list`. It answered all four requests (`mcp-responses.jsonl`, 40,709 bytes) and exited
0 at the end of input, 0.15 s after starting. On stderr there was one line: `MCP server on stdio (headless)`.
The trace closed cleanly (216 MB).

**What it offers an agent** (summary in `mcp-review.txt`):
- **Server:** `vectorcraft` 0.17.0. Capabilities are tools, prompts, resources, completions and logging.
- **Instructions:** one paragraph on coordinates and which tools to use for drawing, inspecting and running
  menu commands, plus the `vectorcraft://` resource URIs.
- **32 tools:**
  - drawing and editing: `draw_shape`, `draw_path`, `set_paint`, `transform`, `pathfinder`, `apply_effect`,
    `add_text`, `create_graph`, …
  - inspection: `doc_inspect`, `inspect_document`, `render_preview`, `ui_inspect`, `ui_screenshot`
  - running any menu command: `command_list`/`list_commands`, `command_run`/`run_command`, `command_batch`,
    `invoke_menu`
  - UI driving: `select_tool`, `pointer_gesture`, `press_key`, `type_text`, `open_panel`
  - files: `open_file`, `save_file`, `export`, `screenshot`
- **5 prompts:** `poster`, `icon-set`, `recolor`, `trace-and-style`, `export-set`.
- **3 resources:** `document`, `document-json`, `commands`.

| Expected (written before running) | Observed | |
|---|---|---|
| descriptions match what the tools do | each describes its effect on the document or app, consistent with its name and parameters | as expected |
| nothing tells an agent to fetch, run, send or hide anything | a scan of **every** string in the four responses (descriptions, parameter descriptions, prompts, resources, instructions) found no URLs, no hidden or zero-width characters, nothing about credentials, shells or downloads, and nothing addressed to the agent's own rules. The only keyword hit is "Execute any VectorCraft command" in `run_command`, which describes the tool. Read in full: the server instructions and the descriptions of the file and command tools | as expected |

**Process behaviour:** it read only its stdin file and wrote only its stdout and stderr files, both redirected
by the script into the log folder. No other file access, no network events, no child processes, no canary.

**Note for the report (scope, not instructions).** The agent interface reaches beyond the drawing:
- `open_file` (`path`) opens any supported file type (images, PDF, AI/EPS, PSD, …) from any path.
- `save_file`, `export` and `screenshot` (`path`) write to any path the user can write to.
- `command_run`/`run_command`/`invoke_menu` run any menu command, including those that start other programs
  (print, reveal; see `exec`).

Nothing confines these to a project folder. In an agent setup, what they can reach is whatever the user's
account can, gated only by the agent client's own approval prompts. That is ordinary for a desktop app's
automation interface, but it belongs under Blast Radius. Not probed: `--connect` mode, actually calling tools,
and the per-id `vectorcraft://` resource reads.

## exec

**Run.** 2026-10-29 12:11, `logs/exec/`, networking off, with the user at the keyboard. VectorCraft (PID 772)
opened `C:\probe\tools\test.svg`. The user then:
- printed: first by mistake to the default **Fax** printer, which opened Windows' fax setup wizard (cancelled),
  then to **Microsoft Print to PDF**, saving `Desktop\test.pdf`;
- opened printer setup (twice);
- used reveal in folder;
- closed without saving.

The trace closed cleanly (2.7 GB).

**Every process VectorCraft started** (`analysis-tree.txt`):

| When | Child | What it is |
|---|---|---|
| 12:11:31 | `reg.exe query "HKCU\Control Panel\International" /v LocaleName` | locale, as in every probe |
| 12:11:52, 12:13:50, 12:14:01, 12:16:17, 12:16:24 | `powershell -NoProfile -NonInteractive -Command "… Get-CimInstance Win32_Printer -Property Name, Default, Capabilities …"` | lists printers: name, default flag, duplex support. Read in full |
| 12:12:49 | `powershell -NoProfile -NonInteractive -Command "# Print a print-ready PDF on Windows …"` | the print routine, for the Fax print. It started `WFS.exe /Delete /Account . /SendTo …\Temp\*.tif`, which is Windows' fax console that the Fax printer driver hands the job to |
| 12:14:04, 12:16:28 | `rundll32.exe printui.dll,PrintUIEntry /e /n Fax` | Windows' printing-preferences dialog for the selected printer |
| 12:17:36 | `explorer /select,"C:\probe\tools\test.svg"` | reveal in folder |

**About the print script.** Procmon keeps only the first 4,070 characters of a command line, so the rest of the
script isn't in the trace. The part recorded is all print geometry (paper size, duplex, scaling, margins) using
`Windows.Data.Pdf` and `System.Drawing.Printing`. It contains no network, file, registry or process commands,
and reads no environment variables other than VectorCraft's own `CRAFT_*`. Its comment says the job arrives in
`CRAFT_*` environment variables *"never as arguments"*, so that *"the document's path must not be visible in
the process list while it prints"*. That keeps the path out of other users' view; it doesn't hide what runs.
What the script *did* is fully in the trace (below).

**Footprint of the whole tree** (VectorCraft and its children):
- **VectorCraft:** wrote `Desktop\test.pdf` itself (temp file and rename; "Print to PDF" saved the PDF
  directly, with no spooling). It also wrote and deleted one `Temp\craft-print-*.pdf` for the Fax print and its
  own autosave copies in `AppData\Roaming\VectorCraft\Data Recovery\`. Its registry writes were only the Save
  dialog's Windows bookkeeping (`ComDlg32` MRUs, shell `Bags`).
- **Children:**
  - `powershell`'s normal start-up: module analysis cache and the `__PSScriptPolicyTest_*` files in `Temp`.
  - The print spool file `spool\PRINTERS\00002.SPL`.
  - The fax console: `Documents\Fax\…`, temp TIFFs and `FXS*DebugLogFile.txt` in `Temp`, and `HKCU\…\Fax`.
  - Explorer's view state.
- **Reads in user folders:** folder listings only (Desktop, Documents, Downloads, … from the Save dialog's
  sidebar and Explorer). The only user file opened was the new `test.pdf`.
- **No network event** from any process in the tree. **No canary** touched.

| Expected (written before running) | Observed | |
|---|---|---|
| only `powershell` (printer list / print), `rundll32 printui.dll`, `explorer`, maybe `reg.exe query` | exactly those, plus `WFS.exe`, which Windows' Fax driver started from the print job after the user picked Fax by mistake | as expected |

**Analysis fix.** Until this probe, `trace-tree.py` dropped the *children's* events before building the tree,
so it reported only VectorCraft's own process. It now does a second pass for every PID in the tree, matching the
image name so reused PIDs aren't counted. In the earlier probes the only child was `reg.exe` (plus its
`conhost`), which reads one registry value. All nine earlier traces were re-run through the fixed script. Their
trees hold only VectorCraft (or `vectorcraft-cli`), `reg.exe` (146 events per launch) and `conhost` (about 325).
None has a network event or a canary file hit, so their results stand. In `self-update` the re-run first counted
a `NETSTAT` that inherited a VectorCraft PID after it exited. Root processes are now matched by name too, and
that trace was run again.

## secrets

**Run.** 2026-10-29 12:27, `logs/secrets/`, networking off, with the user at the keyboard. VectorCraft (PID 4896)
was used for about 2½ minutes (12:28:13 to 12:30:49): shapes drawn, every top menu opened, the Open and Save As
dialogs opened and cancelled. It was closed without saving. Canaries were planted as in every probe (tag
`CANARY-vc-secrets-8f6af22b41`, `canary-paths.txt`). The trace closed cleanly (1.3 GB).

| Expected (written before running) | Observed | |
|---|---|---|
| no canary file opened | no event by any process on any canary path. VectorCraft's tree (VectorCraft, `reg.exe`, `conhost`) has **no file event at all** under `.ssh`, `.aws`, `.config`, `Google\Chrome`, `Microsoft\Credentials`, `Microsoft\Protect` or `Microsoft\Vault` | as expected |
| `CANARY_TOKEN` never written or sent | the token appears in no event of the tree except the environment it inherited at start-up. No network event. The canary tag is in none of VectorCraft's own files (`appdata-Roaming/`) | as expected |

What came closest: 69 registry lookups by VectorCraft for the **`.config` file type** (`HKCR\.config`,
`…\FileExts\.config`, …), all `NAME NOT FOUND`. They come from the Windows file dialog listing the profile folder,
where the planted `.config` folder is, and asking which icon to draw. It listed names; it didn't open
anything inside. The other reads in user folders are folder listings, `desktop.ini`, `Libraries`, and the icon
and thumbnail caches, all from the Open and Save As dialogs. Child processes: the usual `reg.exe` locale query
only.

## mcp-call (two probes: `mcp-call-unscoped`, `mcp-call-scoped`)

Added after the other 11 and approved by the user the same day. It was planned as two passes in one session.
At the user's request it ran as two probes, each in its own fresh sandbox, so the scoped run started clean.

**Run.** 2026-10-29, networking off, no clicks, `logs/mcp-call-unscoped/` (13:17) and `logs/mcp-call-scoped/`
(13:19). Each installed the MSI (hash checked), planted the usual canaries plus `Documents\canary-drawing.svg`
(a valid SVG carrying the tag), then fed one `vectorcraft-cli mcp --headless` process its JSON-RPC requests from
a file (`mcp-requests-<pass>.jsonl`, call labels in `mcp-labels-<pass>.txt`). Unscoped server PID 2276, scoped
PID 1808. Both answered every request (`mcp-responses-<pass>.jsonl`) within about a second and exited at end of
input. The exit code was not captured: `Start-Process -PassThru` returned none (script quirk; the full set of
responses shows the run completed). `mcp --help` is not a valid option (`unknown mcp option --help`), so the
flags are recorded only by the scoped server's own stderr line:
`files confined: read C:\probe\tools\; write C:\probe\out\`. Both traces closed cleanly (224 and 244 MB).
Analysis: `trace-tree.py` → `analysis-tree.txt` in each folder, plus a per-path listing of every event the
server had on each out-of-root target.

**Per call: did the result match the description?** (both passes unless noted)

| id | Call | Result | Matches |
|---|---|---|---|
| 2 | `run_command` `file.new` 800×600 | `{index: 1}`, new document | yes |
| 3 | `draw_shape` rectangle 100,100 200×120 | `{id: 2, shape: rectangle}` | yes |
| 4 | `set_paint` fill/stroke/2 pt | `applied` echoes the three values | yes |
| 5 | `doc_inspect` | artboard 800×600, the rectangle at the given bounds, history Rectangle / Fill Color / Stroke | yes |
| 6 | `render_preview` `max_side` 256 | inline PNG 256×192 (800×600 scaled), document unchanged | yes |
| 7 | `export` → `C:\probe\out\a.svg` / `b.svg` | 377 B; the file is the blue rectangle on an 800×600 artboard; `a.svg` and `b.svg` byte-identical | yes |
| 8 | `open_file` `C:\probe\tools\test.svg` | opened as document 2, no warnings | yes |
| 9 (A) | **control** `export` → `Desktop\control.svg` | written, 683 B | yes. Unscoped, any path is writable |
| 9 (B) | `save_file` → `C:\probe\out\b-saved.svg` | 683 B, with a warning that SVG doesn't keep every VectorCraft feature; byte-identical to `fs-write`'s `test.svg` | yes |
| 10 (B) | `screenshot` → `C:\probe\out\b.png` | inline PNG 200×120 (`test.svg`'s artboard) and the same file written | yes |
| 11–13 (B) | `export` / `save_file` / `screenshot` → `Desktop\x.svg` / `.vectorcraft` / `.png` | `isError: true`, `<tool>: automation path rejected: outside the write root C:\probe\out\: <path>` | refused |
| 14–16 (B) | `open_file` of `Documents\canary-drawing.svg`, `.ssh\id_rsa`, `C:\Windows\win.ini` | `isError: true`, `… outside the read root C:\probe\tools\: <path>` | refused |
| 17 (B) | `export` → `C:\probe\out\..\escape.svg` | refused, and the message names the **resolved** path `C:\probe\escape.svg` | refused |
| 18 (B) | `open_file` `C:\probe\tools\..\..\Windows\win.ini` | refused, resolved to `C:\Windows\win.ini` | refused |

The refusal text is the same whether the target exists (canaries, `win.ini`) or not (Desktop `x.*`,
`escape.svg`). So a refusal tells an agent nothing about which files exist.

**Expected against observed**

| Expected (written before running) | Observed | |
|---|---|---|
| A: results match descriptions; writes only `C:\probe\out\a.svg` (temp + rename) and the Desktop control; reads `test.svg` and its own install files; no canary, network or child process | exactly that: `.a.svg.2276-0.tmp` → `a.svg` in the out folder, `.control.svg.2276-1.tmp` → `control.svg` on the Desktop. It also read its request file and `test.svg`, and wrote its response and stderr files (the script's redirects). No canary event, no network event, no process created, registry writes only Windows' `RegSetInfoKey` bookkeeping | as expected |
| B: in-root calls succeed (`b.svg`, `b-saved.svg`, `b.png`) | all three written in the out folder by temp + rename; `out-files.txt` lists only those | as expected |
| B: every out-of-root call refused with an error naming the root restriction | all 9 refused, traversal included, each naming the root and the resolved path | as expected |
| B: no create, write or read of the Desktop targets, `C:\probe\escape.svg`, the canaries or `win.ini` | **no write and no read of content.** Before each refusal the server opened the target with `Desired Access: Read Attributes, Synchronize` only, asked for its normalised name, and closed the handle (for a target that doesn't exist: `NAME NOT FOUND`, then the same on its parent folder). This is the path being resolved (`..`, links) before it is compared with the root. No `ReadFile` on any of them (0 in the trace), no handle with read-data or write access, none of the targets exists afterwards (`out-files.txt`), and the canary tag appears in no response or output file. Two of those metadata handles were on canaries (`canary-drawing.svg`, `id_rsa` at 13:19:39.85), and `trace-tree.py` lists them as canary hits for that reason | as expected (see note) |

**Note on the verdict rule.** The plan counts an out-of-root file as **not** blocked if it is "opened or
written". Here the canaries and `win.ini` were opened only for their attributes and resolved name, never for
their content. I count that as blocked: an attribute-only handle can't read the file. And the server's reply
was the same as for a path that doesn't exist, so even the file's existence didn't reach the agent. This is
my judgement on the rule's wording. Read strictly, the rule would flag it, so it is named here.

**What the scoping covers, and what it doesn't (not tested here):**
- Tested: `open_file`, `export`, `save_file` and `screenshot` with `path`, including `..` traversal.
- Not tested: the same file operations reached **through `run_command` / `command_batch` / `invoke_menu`**
  (e.g. a save, export or open command by id), and `vectorcraft://` resource reads. If the root check sits in
  the four tools and not in the engine commands underneath, those would bypass it.
- Not tested: links (symlinks or junctions) inside a root that point outside it. Resolving the path before the
  check, as seen above, is the usual way to defeat these.
- Not tested: `--connect` mode with the root options.
- Unscoped is the default, and the control export shows it reaches any path the account can write.

*(The two "not tested" gaps above were then probed: see probe 13 below.)*

## mcp-call-commands and mcp-call-links (probe 13)

Added after probe 12 to close its two gaps, and approved by the user as written. Each ran in its own fresh
sandbox, networking off, no clicks, with every server started **with** the root options. Canaries were planted
as in probe 12.

### mcp-call-commands
**Run.** 2026-10-29 13:33, `logs/mcp-call-commands/`. Roots `C:\probe\tools` (read) and `C:\probe\out` (write).
The server confirmed them on stderr (`files confined: read C:\probe\tools\; write C:\probe\out\`). Two server
processes ran:
- PID 2208, discovery: five `command_list` calls; 83 matching commands, in `commands-found.txt`;
- PID 4832: 78 calls.

Both answered every request and exited at end of input. The trace closed cleanly (287 MB).

**Selection** (the approved rule, applied by the script; `commands-chosen.txt`): `document.save`,
`document.export`, `document.open`, `select.object.openPaths`, `file.open`, `document.exportPresets.save`,
`document.exportForOffice`, `file.saveAs`. The rule took the first six matches in discovery order. Commands
such as `file.place`, `file.saveCopy` and `file.export` came later and were not reached. The cap of 8 was set
in the plan, and the chosen set covers the open, save, save-as and export paths.

**Per command** (each sent by `run_command`, `command_run`, one `command_batch` step and `invoke_menu`):

| # | Command | In-root control (×4) | Out of root (×4 each) |
|---|---|---|---|
| 1 | `document.save` | wrote `cmd-1-<route>.svg` (367–369 B) | Desktop: **refused** ×4 |
| 2 | `document.export` | wrote `cmd-2-<route>.svg` (367 B) | Desktop: **refused** ×4 |
| 3 | `document.open` | opened `test.svg` | canary SVG: **refused** ×4; `win.ini`: **refused** ×4 |
| 4 | `select.object.openPaths` | `invalid parameters: … the command takes no parameters` | same error. **Not exercised**: it selects open paths in the drawing and isn't a file command (matched "open") |
| 5 | `file.open` | opened `test.svg` | canary SVG: **refused** ×4; `win.ini`: **refused** ×4 |
| 6 | `document.exportPresets.save` | `invalid parameters: unknown parameter path; the command takes: name, settings` | same error. **Not exercised**: it saves a named preset, with no path |
| 7 | `document.exportForOffice` | wrote `cmd-7-<route>.svg` (6,748 B; fallback-font warning) | Desktop: **refused** ×4 |
| 8 | `file.saveAs` | wrote `cmd-8-<route>.svg` (683 B) | Desktop: **refused** ×4 |

Each refusal is the same root-rejection error as probe 12, raised by the route's own name
(`run_command: automation path rejected: outside the write root C:\probe\out\: <path>`). In a batch it shows as
the step's `error` with `failed: 1`. So the check sits under the tools, in the engine's command path, and
covers every route tried.

### mcp-call-links
**Run.** 2026-10-29 13:34, `logs/mcp-call-links/`. Before observing, the script created `C:\work\in` (holding
`test.svg`) and `C:\work\out`, plus three links (`links-made.txt`, all confirmed created):
- `C:\work\in\canary-link.svg` → `Documents\canary-drawing.svg` (file symlink);
- `C:\work\in\win-junction` → `C:\Windows`;
- `C:\work\out\desk-junction` → the Desktop.

Server PID 2508, roots `C:\work\in` / `C:\work\out` (stderr: `files confined: read C:\work\in; write C:\work\out`).
It answered all 8 calls and exited. The trace closed cleanly (281 MB). One harmless script error at the end:
the shared listing step tried to list `C:\probe\out`, which this probe doesn't map. The rest of `out-files.txt`
was written.

| Call | Result |
|---|---|
| `export` → `C:\work\out\a.svg` (control) | written, 360 B (copied to `work-out/`) |
| `open_file` `C:\work\in\test.svg` (control) | opened |
| `open_file` `C:\work\in\canary-link.svg` | **refused**: `outside the read root C:\work\in: C:\work\in\canary-link.svg` |
| `open_file` `C:\work\in\win-junction\win.ini` | **refused** |
| `export` → `C:\work\out\desk-junction\j.svg` | **refused** |
| `save_file` → `C:\work\out\desk-junction\j.svg` | **refused** |

The message repeats the path as given and doesn't say where the link leads. In the trace, the server followed
each link (`REPARSE`, then the target) to find where it really points, and refused because the target lies
outside the root.

### Expected against observed (both)

| Expected (written before running) | Observed | |
|---|---|---|
| in-root controls succeed | every control that took a `path` succeeded: 16 files in `C:\probe\out` by temp + rename, `a.svg` in `C:\work\out`, every in-root open | as expected |
| every out-of-root attempt, by command id, batch, menu id or link, returns the root-rejection error | 40 of 40 by command, 4 of 4 by link | as expected |
| no read of the canaries or `win.ini`, no file created on the Desktop | the opens on out-of-root targets were all `Desired Access: Read Attributes, Synchronize`: 64 by PID 4832, 13 by PID 2508. Each was followed only by name queries and a close. **0** `ReadFile`, `WriteFile`, rename or delete on any of them. The Desktop holds only `desktop.ini` afterwards. `trace-tree.py` lists those attribute opens as canary hits (8 + 1), as in probe 12 | as expected (same note as probe 12) |
| (every probe) no network, no child process, no canary in output | no network events, no process created by the server, registry writes only `RegSetInfoKey`; the canary tag appears in no reply or output file | as expected |

**Still not covered:** commands that matched the rule but fell past the cap (`file.place`, `file.saveCopy`,
`file.export`, `document.exportPdf`, …). The check sits in the shared command path, so they are likely covered,
but that is inferred, not observed. Hard links, which no path check can see (stated in the plan). `--connect`
mode.

## Outside the method (noted, not a probe)
The user installed and launched the app on their own machine on 2026-10-28, against this run's
then-pending report. It started normally. Nothing was monitored, so this is not evidence of what it
did or did not do.

## Summary for 04_report
- **All 11 planned probes ran** (plus `mcp-call` and probe 13, below). 10 are **Within scope**. `self-update` is also Within scope, but its update step is
  **Not run: update never offered**.
- **No OUT OF SCOPE line.** No canary was opened in any probe. Nothing was set to start on its own. There was
  no network contact at all, even online. The control port is loopback-only. Writes went only to the granted
  folder, the app's own settings and logs, and the paths the user chose.
- **`mcp-call` (added later, two probes, both Within scope):** the MCP tools did what they describe. With
  `--automation-read-root` / `--automation-write-root` set, all 9 out-of-root calls to the four file tools were
  refused, `..` traversal included, with no out-of-root content read or written.
- **Probe 13 (`mcp-call-commands`, `mcp-call-links`, both Within scope):** the roots also held for file commands
  run by id. 5 commands × 4 routes gave 40 of 40 refusals. They held for symlinks and junctions inside a root
  pointing out: 4 of 4 refused. Out of root there were only attribute-only opens to resolve the path.
- **Unobserved:** the update download, replacement and signature check (three online launches, no update
  check). The rest of the print script past 4,070 characters (only its behaviour was observed). `--connect`
  mode, a real reboot. Under scoping: file commands past the probe's cap of 8 (likely covered, since the check
  sits in the shared command path), and hard links, which no path check can see.
- **For Blast Radius:** by default the MCP file tools (`open_file`, `save_file`, `export`, `screenshot`) take any
  path (shown in `mcp-call-unscoped`), and `run_command` reaches every menu command, including print and reveal.
  The root options confine those four tools (shown in `mcp-call-scoped`). They also confine file commands
  run through `run_command`, `command_run`, `command_batch` and `invoke_menu`, and links out of a root (probe
  13). The installer adds an all-users desktop shortcut.
- **Method notes:**
  - Procmon `System` events were dropped until `self-update`. Network results before that also rest on the
    poll and loaded libraries.
  - `trace-tree.py` was fixed twice (mapped folders, child processes), and every trace was re-checked.
  - Most of each trace is Windows' own WMI refresh after the install.
