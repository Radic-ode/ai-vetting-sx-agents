---
run: vectorcraft
reviewed: old zip (752a67e) in full scan; new zip (9997ff0) by delta from the old one
---

# Static findings: VectorCraft

## Inventory (old zip, 752a67e)
- 1,340 files: 929 Rust sources, 266 SVG icons, fonts (OFL), PNG/ICO/ICNS app icons, docs.
- Binaries: one 60 KB `crates/plugins/tests/fixtures/desaturate.wasm` (test fixture). No `.exe`, `.dll`, `.so`.
- Dependencies: 546 packages, all `registry+crates.io`, checksums in `Cargo.lock`. No git dependencies, no `[patch]`.
- Build-time code (`build.rs`): `apps/vectorcraft` (embeds Windows icon/version info via `winresource`),
  `crates/text` (optional fonts from `CRAFT_FONTS_DIR`, `include_bytes!`), `crates/ui-egui` (credits page).
  None use the network or spawn processes. (`crates/cad/src/import/build.rs` is a module, not a build script.)
- `vendor/windows-link`: a documented patch (CoTaskMemFree from ole32.dll) used only by the experimental
  Windows 7 build.

## Behaviour found in the code
- **Network:** no HTTP client in the old version. Only socket: the **control server**
  (`apps/vectorcraft/src/control_server.rs`), started only with `--control <port>` or
  `VECTORCRAFT_CONTROL_PORT`, binds `127.0.0.1`, rejects any line that is not a JSON object with a
  `method` (browser cross-origin fetches get one error and are closed), max 4 MiB line, 16 connections.
  Any local process can drive the app while it is on.
- **Processes spawned:** `explorer`/`open`/`xdg-open` (reveal a file); printing: `lpstat`/`lp` (Unix),
  PowerShell `Get-CimInstance Win32_Printer` and `Start-Process -Verb Print/PrintTo` (Windows, hidden window);
  `reg.exe query HKCU\Control Panel\International /v LocaleName` by full path (read-only, language);
  `/usr/bin/defaults read -g AppleLanguages` (macOS); `sysctl` (CLI perf).
- **Plug-ins:** WebAssembly in `wasmi` with no host imports (no WASI, files, network, clock), memory and
  recursion caps.
- **Persistence:** no Run keys, scheduled tasks, services, LaunchAgents or shell rc writes found
  (`RegSetValue`, `CurrentVersion\Run`, `LaunchAgents`, `crontab`, `systemd` searched; the hits were
  PostScript's `systemdict`).
- **Agent-facing text:** `CLAUDE.md`/`AGENTS.md` are ordinary coding guidelines; no directives to fetch,
  run or send anything.
- **Downloads in scripts:** only maintainer packaging/signing (`appimagetool` from GitHub, NuGet signing
  client) and `xtask` test corpus (`curl` of PngSuite). Not run by a normal build or install.

## What changed in the new version (9997ff0), relevant to risk
- **Auto-updater (`craft-update`)**: the desktop app checks for updates **at every start**
  (`set_startup_update_check(true)`). Contacts only `api.github.com/repos/storytold/<app>/releases` and
  `github.com/storytold/...` release downloads (via `ureq` + `rustls`). Shows a prompt with "Later";
  installs only on the user's choice. Verifies the download's SHA-256 (GitHub digest or `SHA256SUMS.txt`)
  and, on Windows, the Authenticode publisher (`verifysign`). Development builds don't self-update unless
  `CRAFT_UPDATE_DEV` is set. Its tests cover path-traversal and attacker-URL cases. Writes the registry
  (`winreg`) for install records.
- **32 packages from the developer's own GitHub forks**, pinned to exact commits: `storytold/craft-libs`
  @92d392c (15, incl. `craft-update`, `craft-pdf`, and `[patch.crates-io]` replacements for `hayro-*`,
  `krilla`), `storytold/egui` @6d518fc (14), `storytold/winit` @a517b38, `storytold/winprint.rs` (2 revs).
  672 crates.io packages otherwise.
- **New process spawns:** `rundll32.exe printui.dll,PrintUIEntry` (printer setup), `ps`, `gsettings`,
  restarting itself (`current_exe`), `dbus-daemon` (tests).
- `reqwest` and `aws-lc-rs` appear in the lockfile (TLS stack; `aws-lc-rs` via `rustls`/`sigstore`);
  which crate pulls in `reqwest` was not traced.

## Not reviewed
- The full 606k-line delta between the two versions (searched by pattern, not read).
- `craft-libs` beyond the `update` crate; the `egui`, `winit` and `winprint.rs` forks.
- The MCP server's tool descriptions (`vectorcraft-cli mcp`) as agent-facing text.
- The MSI's contents beyond hash and signature (install actions, file associations, shortcuts).
