---
run: vectorcraft
status: 11 probes DONE 2026-10-29 (all Within scope; self-update's update step Not run: never offered). Probe 12 `mcp-call` added 2026-10-29 and approved by the user as written (additions included) the same day; at the user's request its two passes then became two probes, each in its own sandbox session: `mcp-call-unscoped` and `mcp-call-scoped`. Both DONE 2026-10-29, Within scope; see probe-results.md. Probe 13 (`mcp-call-commands`, `mcp-call-links`) added 2026-10-29 and approved by the user as written the same day; both DONE 2026-10-29, Within scope.
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
  - `fs-write` and both `mcp-call-*` probes also get `C:\probe\out`, their one writable target (host side `logs/<probe>-out/`).
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
| 12 | `mcp-call-unscoped`, `mcp-call-scoped` | write `C:\probe\out`; tools folder read-only | call MCP tools for real: unscoped in one session, scoped with the root options in another (detail below) | unscoped: every call does what its description says and writes only where told; scoped: in-root calls work, **every** out-of-root call is refused with nothing read or written outside the roots | no | none |
| 13 | `mcp-call-commands`, `mcp-call-links` | as 12 (`-links`: roots on the sandbox's own disk, no out mapping) | scoped server only: out-of-root file operations through engine commands, then through links inside a root (detail below) | every out-of-root attempt refused, nothing read or written outside the roots | no | none |

### Probe 12 `mcp-call` in detail (added 2026-10-29, after the other 11 had run)
**Why:** `agent-text` only listed the tools. The report's MCP advice rests on `--automation-read-root` /
`--automation-write-root`, which nothing has tested.

**Grant:** networking off; `C:\probe\tools` read-only (as every probe); `C:\probe\logs` writable; `C:\probe\out`
writable, mapped like `fs-write` (host `logs/mcp-call-<pass>-out/`). Canaries as every probe, plus one extra canary
for this probe only: `Documents\canary-drawing.svg`, a valid SVG carrying the tag, so an `open_file` of it can't
be refused merely as an unsupported file type.

**Task** (no clicks; JSON-RPC over stdin from a file, as `agent-text`; each pass is its own probe in its own
fresh sandbox session and log folder, so pass B starts from a clean machine; each server starts with
`initialize`/`initialized`; `vectorcraft-cli mcp --help` is saved first to record the flags):
- **Pass A, `mcp-call-unscoped`:** `vectorcraft-cli mcp --headless`
  1. `run_command` `file.new` (800×600)
  2. `draw_shape` rectangle, then `set_paint` fill/stroke on it
  3. `doc_inspect`, `render_preview` (`max_side` 256)
  4. `export` → `C:\probe\out\a.svg`
  5. `open_file` `C:\probe\tools\test.svg`
  6. *control (my addition):* `export` → `%USERPROFILE%\Desktop\control.svg`, to show what "unscoped" means in
     practice, so a refusal in pass B is the root option at work and not the tool failing anyway.
- **Pass B, `mcp-call-scoped`:** `vectorcraft-cli mcp --headless --automation-read-root C:\probe\tools --automation-write-root C:\probe\out`
  1. the in-root calls again: `file.new`, `draw_shape`, `set_paint`, `doc_inspect`, `render_preview`, `export` →
     `C:\probe\out\b.svg`, `open_file` `C:\probe\tools\test.svg`; plus `save_file` → `C:\probe\out\b-saved.svg`
     and `screenshot` → `C:\probe\out\b.png`, so every write tool also has an in-root success to compare with
  2. out-of-root writes: `export` → `%USERPROFILE%\Desktop\x.svg`, `save_file` → `…\Desktop\x.vectorcraft`,
     `screenshot` → `…\Desktop\x.png`
  3. out-of-root reads: `open_file` of `Documents\canary-drawing.svg`, of `.ssh\id_rsa`, and of `C:\Windows\win.ini`
  4. *traversal (my addition):* `export` → `C:\probe\out\..\escape.svg` and `open_file`
     `C:\probe\tools\..\..\Windows\win.ini`, which start inside a root but resolve outside it
- **Not called:** print, reveal, `press_key`, `type_text`, `ui_*`, `invoke_menu`, `pointer_gesture`, or any
  `run_command` other than `file.new`.
- After its pass the script lists the Desktop, `C:\probe` and `C:\probe\out`, and checks whether each
  out-of-root target exists.

**Expected footprint (written before running):**
- Pass A: each call's result matches its description (an id from `draw_shape`, a document summary, an inline
  PNG, a written file). Writes only `C:\probe\out\a.svg` (temp file + rename, as in `fs-write`) and the control
  file on the Desktop; reads `test.svg` and its own install files. No canary, no network, no child process.
- Pass B: in-root calls succeed as in A (`b.svg`, `b-saved.svg`, `b.png` in the out folder). **Every** out-of-root
  call, traversal included, returns an error naming the root restriction, and the trace shows **no** create,
  write or read of the Desktop targets, `C:\probe\escape.svg`, the canaries or `win.ini` by the scoped server.
  A refusal that comes only after the file was opened (e.g. "unsupported format" with the file read first)
  counts as **not** blocked.
- Verdict rule: any out-of-root file opened or written in pass B → **OUT OF SCOPE** (the scoping fails), with
  the exact path.

### Probe 13 in detail (added 2026-10-29, after probe 12)
**Why:** probe 12 showed the roots confine `open_file`, `export`, `save_file` and `screenshot`. Two ways around
them were left untested. One is the same file operations run as engine commands by id. The other is a link
inside a root that points outside it. The report's Blast Radius score waits on both. Every server in this probe
is started **with** the root options. Same grant as probe 12: networking off, tools folder read-only, canaries
plus `Documents\canary-drawing.svg`. Each probe runs in its own fresh sandbox, with no clicks.

**`mcp-call-commands`** (roots `C:\probe\tools` / `C:\probe\out`, as in probe 12 pass B):
1. **Discovery** (read-only): one server process, `command_list` with `filter` `open`, `save`, `export`,
   `place` and `import` in turn. The replies are saved.
2. **Selection rule, fixed now:** the commands called are `document.save` and `document.export` (named in the
   tool text), plus at most 6 more from the discovery replies whose id or label contains open, save, export,
   place or import. Excluded: any id or label containing print, reveal, recent, revert, close, quit, browse,
   dialog, url, web or package. The script writes the chosen list to the log before anything is called.
3. **Calls**, in a second server process: `file.new` and `draw_shape` first, so there is a document. Then, for
   each chosen command:
   - in-root control: a write command → `C:\probe\out\cmd-<n>.<ext>`; a read command → `C:\probe\tools\test.svg`.
     This tells "refused by the root" apart from "wrong parameters";
   - out of root: a write → `%USERPROFILE%\Desktop\cmd-<n>.<ext>`; a read → `Documents\canary-drawing.svg`, then
     `C:\Windows\win.ini`.

   Each is sent four ways: `run_command`, `command_run`, a step in `command_batch`, and `invoke_menu`. The
   parameter is `path`, which is what `save_file` / `export` pass to `document.save` / `document.export`. A
   command that rejects `path` even in the root is recorded as "not exercised", not as a pass.
4. Not called: anything outside the selection rule, print, reveal, `press_key`, `type_text`, `ui_*`,
   `pointer_gesture`.

**`mcp-call-links`** (roots on the sandbox's own disk, so no link is ever created in a folder mapped from the
host):
1. The script creates `C:\work\in` (a copy of `test.svg`) and `C:\work\out`, plus three links, before the
   server starts:
   - `C:\work\in\canary-link.svg`: file symlink → `Documents\canary-drawing.svg`;
   - `C:\work\in\win-junction`: junction → `C:\Windows`;
   - `C:\work\out\desk-junction`: junction → `%USERPROFILE%\Desktop`.
2. Server: `mcp --headless --automation-read-root C:\work\in --automation-write-root C:\work\out`.
3. Calls:
   - in-root controls: `open_file` `C:\work\in\test.svg`, `export` → `C:\work\out\a.svg`;
   - through the links: `open_file` `C:\work\in\canary-link.svg`, `open_file`
     `C:\work\in\win-junction\win.ini`, `export` → `C:\work\out\desk-junction\j.svg`, `save_file` →
     `C:\work\out\desk-junction\j.svg`.
4. Afterwards the script copies `C:\work\out`'s listing and files and the Desktop listing to the log folder.

**Expected footprint (written before running):**
- Both: in-root controls succeed. Every out-of-root attempt, whether by command id, batch, menu id or link,
  returns the root-rejection error. The trace shows no read of the canaries or `win.ini` and no file created
  on the Desktop by the server. As in probe 12, attribute-only handles used to resolve a path are noted but
  don't count as a read.
- Verdict rule: out-of-root content read, or a file written outside the roots → **OUT OF SCOPE**, naming the
  command or link and the path.
- **Known limit, not tested:** a *hard* link inside a root is the same file as its target, and no path check
  can see that. Path-based confinement doesn't cover it, so it is out of this probe's scope. The report notes
  it as such.

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
00. **Probe 13** (`mcp-call-commands`, `mcp-call-links`): the task above, including the command-selection rule
    (some commands are picked from the discovery reply inside the sandbox) and the three links created on the
    sandbox's own disk. Networking stays off.
0. **Probe 12 `mcp-call`** (added after the others ran): the task above, including my two additions (the
   unscoped Desktop control in pass A and the two traversal attempts in pass B). Networking stays off.
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
