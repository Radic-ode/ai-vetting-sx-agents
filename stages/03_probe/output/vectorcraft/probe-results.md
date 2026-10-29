---
run: vectorcraft
date: 2026-10-29
backend: Windows Sandbox, one fresh session per probe (see probe-plan.md)
---

# Probe results: VectorCraft 0.17.0

| Probe | Verdict |
|---|---|
| baseline | Within scope (run 2, 2026-10-29), with two notes and one gap below |
| install | Not run yet |
| persist | Not run yet |
| net-out | Not run yet |
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

**Trace size.** It is still 2.9 GB. 90% (4.83 M events) is svchost PID 1104 (`-k netsvcs`, which hosts WMI)
doing registry, AMSI and Defender lookups. That is the cost of the backup poll's WMI process list, which ran
every 5 s. The poll now uses `Get-Process` instead (no WMI). VectorCraft's whole tree was 18,026 events.
