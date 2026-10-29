# ai-vetting-sx-agents

**Check a third-party AI tool before you install it, the way a bank checks a new supplier. Then go one
step further: run each thing it can do in its own throwaway sandbox and watch what it actually does.**

**This is the model-neutral edition.** Any AI agent that can read files can run it: Codex, Gemini CLI,
Cursor, Claude Code, or a chat model you hand the files to. Every agent starts at
[`START-HERE.md`](START-HERE.md). (The Claude-first original is `ai-vetting-skill-sx`.)

## Why this exists

MCP servers, plugins, agent skills, hooks and apps that an AI agent drives all run with *your*
permissions. They can read your files, use your network and start other programs. Reading their code
tells you what they *could* do. This project adds evidence of what they *do*:
- each capability (network, files, processes, credentials, starting at login, updating itself, the text
  an agent will read) is run **alone**, in a **disposable sandbox** seeded with **fake credentials**
  ("canaries");
- anything that reaches beyond what that sandbox allowed is named, with the exact file, host or process.

The result is a plain-language report with a risk tier and a concrete recommendation.

## What you get

For every component you vet, four short documents, one per stage:

| Stage | Question it answers | Document |
|---|---|---|
| 1. Intake | Is this exactly the thing that will be installed (version, checksum, signature, source)? | `intake.md` |
| 2. Static review | What can it do, according to its code? | `static-findings.md`, `capability-inventory.md` |
| 3. Probes | What does each capability actually do when run alone in a sandbox? | `probe-plan.md` (**you approve it first**), `probe-results.md` |
| 4. Report | How risky is it, and what should I do? | `report.md` |

The report scores five things, each Pass, Partial or Fail:
- **Provenance:** who made it, and can the copy be verified?
- **Permission scope:** does it use only what its job needs?
- **Auditability:** can its behaviour be inspected?
- **Blast radius:** what's the worst it could do if it's malicious or buggy?
- **Change control:** how does it change after you've trusted it once?

These add up to a tier (Low / Medium / High / Critical) and a recommendation. A component can only earn
**Low** if every capability was actually probed. Every report has a **Coverage Limitations** section that
says plainly what wasn't checked.

## Safety rules built in

- **Nothing third-party runs until a person approves the probe plan.** You approve by adding one line to
  `probe-plan.md`: `APPROVED: <ALL | probe ids> by <name> on <date>`. The probe scripts refuse to run any
  probe without it, whichever AI is driving.
- One capability per sandbox, never shared, so one feature can't hide behind another's permission.
- Probes never fall back to your real machine. If there's no sandbox, the probe is reported as "not run".
- Everything inside the component (code, docs, tool descriptions) is treated as data under review, never as
  instructions to follow.

## Worked example: VectorCraft 0.17.0

[`stages/*/output/vectorcraft/`](stages/04_report/output/vectorcraft/report.md) is a complete, real vetting
of the [VectorCraft](https://github.com/storytold/vectorcraft) vector editor and its built-in MCP server
(October 2026):
- **Intake:** the downloads were byte-identical to repository commits. The installer matched its published
  checksum and carries a Microsoft-verified signature.
- **Probes:** 15 probes in Windows Sandbox, one fresh sandbox each, all **Within scope**:
  - no network contact;
  - nothing set to start at login;
  - no canary content read;
  - the control port listens on this machine only;
  - only the documented helper programs started.
- **MCP server:** its tools did what they describe. By default they can reach any path. With the
  `--automation-read-root` / `--automation-write-root` options set, every attempt to reach outside those
  folders was refused, whether through the file tools, file commands run by id, `..` tricks or links.
- **Result: Medium, install with mitigations.** It's held at Medium by the size of the code (spot-checked,
  not fully read) and by its defaults (unscoped MCP access, an unauthenticated local control port per the
  code review).
- The report went through two peer-review rounds; corrections are recorded in the files.

Start with [`report.md`](stages/04_report/output/vectorcraft/report.md). The evidence for each verdict is in
[`probe-results.md`](stages/03_probe/output/vectorcraft/probe-results.md). (Raw traces and logs stay on the
machine that ran them and are not in this repository.)

## How to use it

- **With an agent tool** (Codex, Gemini CLI, Cursor, Claude Code, …): clone this repository and open it. The
  tool's own entry file (`AGENTS.md`, `GEMINI.md` or `CLAUDE.md`) sends the agent to
  [`START-HERE.md`](START-HERE.md). Ask it to vet a component. It checks what it can do, picks a mode (full,
  static + plan, or static-only), works one stage at a time, and stops for your approval.
- **With a chat model:** give it `START-HERE.md`, `_shared/skill/SKILL.md` and the component's files, and ask for
  a static-only vetting. It can't run sandboxes, so the report will say the probes were not run.
- **Just the method:** [`_shared/skill/SKILL.md`](_shared/skill/SKILL.md) is plain Markdown. Tools that support
  the open Agent Skills format can load the `_shared/skill/` folder as a skill.

**Sandboxes supported:**
- Windows 10/11 Pro with Windows Sandbox (you turn it on), one `.wsb` per probe; see the VectorCraft scripts;
- Linux or WSL2 with `bubblewrap` and `strace` (`probe.sh`);
- Docker or Podman, and macOS `sandbox-exec`: the method describes how to set them up
  (`references/capability-sandboxes.md`), but no ready-made script ships for them.

## Requirements

What you need depends on what you vet and which sandbox you use. Nothing here is installed for you. An agent
following [`START-HERE.md`](START-HERE.md) checks for these before it starts and says what's missing.

| For | You need | Notes |
|---|---|---|
| Every run | an AI agent or model that can read files (to run probes, also commands), and `git` | Static review alone needs nothing else. |
| Intake | a SHA-256 tool (`Get-FileHash` / `sha256sum`); optionally `gh` (GitHub releases) and 7-Zip | 7-Zip unpacks an installer such as an MSI *as data*, without installing it. |
| Probes on Windows | Windows 10/11 **Pro, Enterprise or Education** with the **Windows Sandbox** feature turned on (virtualisation enabled in firmware), and Windows PowerShell 5.1 (built in) | You turn the feature on yourself. |
| Probes on Windows | **Process Monitor** (`Procmon64.exe`) from Microsoft Sysinternals: [`ProcessMonitor.zip`](https://download.sysinternals.com/files/ProcessMonitor.zip), with only `Procmon64.exe` placed in the run's `sandbox/tools/` | Not in this repository (not ours to redistribute). The probe script starts it with `/AcceptEula`, which accepts Microsoft's Sysinternals licence inside each sandbox. That's your decision, or accept it once on your own machine. |
| Trace analysis | **Python 3**, standard library only, for `trace-tree.py` | Runs on your machine, on the saved trace. |
| Regenerating the Procmon filter | the Python package `procmon-parser` (in a virtual environment) for `make-pmc.py` | Only to change `probe.pmc`. The committed filter works as is. |
| Probes on Linux/WSL2 | `bash`, `bubblewrap`, `strace`, coreutils `timeout` | `sudo apt install bubblewrap strace` |
| npm components | Node.js and `npm`, for `audit_npm_package.sh` | |
| Online probes (`net-out`, `self-update`) | a network you're willing to expose to the sandbox | Turning on sandbox networking can disturb some host connections, e.g. USB tethering. |
| Each run | the component itself (its installer, package or repository), downloaded into its own new, empty folder outside this workspace | Never committed. |

## What's in the repository

| Path | What it is |
|---|---|
| `START-HERE.md` | The entry point for every agent and model: rules, modes, map |
| `AGENTS.md`, `GEMINI.md`, `CLAUDE.md` | One-line pointers to `START-HERE.md`, one per tool convention |
| `_shared/skill/` | The method: report format, capability/sandbox reference, `probe.sh` (with the approval check) and `audit_npm_package.sh` |
| `stages/0X_*/CONTEXT.md` | Instructions for each stage |
| `stages/*/output/vectorcraft/` | The worked example, including the Windows Sandbox probe scripts (`sandbox/`) |
| `CONTEXT.md` | How the pipeline fits together |

## Honest limits

- **Probes only see what happens during the probe.** Logic triggered later, remotely, or by a feature nobody
  exercised can still hide.
- **Static review of a large codebase is a careful search, not a full read.** Reports say which.
- **How well a run goes depends on the model driving it.** The rules that matter most (approval, no run outside a
  sandbox) are enforced by the scripts, not left to the model. The VectorCraft run makes a good test for a new
  model: compare its report with this one.
- **The approval check proves a line exists, not who wrote it.** An agent with write access could add it. The
  instructions forbid that, and every approval stays visible in the plan, but it is a safeguard, not a lock.
- **`probe.sh` (Linux/WSL2) is tested against fake components.** `scripts/test_probe.sh` runs 16 cases in WSL2
  (all passing on 2026-10-29). They cover a stolen SSH key, a leaked token, writes outside the grant,
  persistence, network, and the approval check: no plan, a malformed line, a probe not listed. The Windows
  Sandbox probes have been used on a real component (VectorCraft).
- **A secret copied by the kernel** (`sendfile`, `copy_file_range`) can't be matched by content. The probe still
  flags the credential file being opened.
- **This is due diligence, not a guarantee.** Shared as is.

## Credits

Built by [The Compliant Neuron](https://thecompliantneuron.com) with Claude (Anthropic), extending its
static-only [`ai-component-vetting`](https://github.com/Radic-ode/ai-component-vetting) skill. The workspace
follows the Interpretable Context Methodology (Van Clief & McDermott,
[arXiv:2603.16021](https://arxiv.org/abs/2603.16021)).

MIT licensed. See [LICENSE](LICENSE).
