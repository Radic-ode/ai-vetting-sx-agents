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
| self-update | Not run yet |
| net-listen | Not run yet |
| fs-read | Not run yet |
| fs-write | Not run yet |
| exec | Not run yet |
| secrets | Not run yet |
| agent-text | Not run yet |

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
