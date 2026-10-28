# ai-vetting-skill-sx

**Vet third-party AI tooling before you install it the way a bank vets a vendor, and then go one step
further: give every capability its own sandbox and watch what it actually does.**

MCP servers, plugins, skills, hooks and agent-driven apps run with your permissions. Reading their
code tells you what they *can* do. This adds runtime evidence: each capability (network, files,
processes, credentials, persistence, self-update, text an agent will read) is probed alone in a
disposable sandbox seeded with fake credentials, and anything that reaches past its grant is named.

## The idea in one table

| One capability | Its sandbox allows | Flagged if it… |
|---|---|---|
| `net-out` | network, logged | contacts a host not found in the code, touches a canary |
| `fs-write` | one output folder | writes anywhere else |
| `secrets` | one configured fake credential | opens any of the other planted ones |
| `persist` | its home folder, logged | adds startup entries, tasks, shell rc lines |
| `baseline` | nothing at all | does *anything*: unprompted behaviour |

…and so on for `install`, `net-listen`, `fs-read`, `exec`, `self-update` and `agent-text`. Probes never
share a sandbox, so one capability's behaviour can't hide behind another's permission. Findings feed a
five-category scorecard (provenance, permission scope, auditability, blast radius, change control) and a
risk tier, and a component can only earn **Low** if every capability was actually probed.

## How it works

Two layers:

1. **A Claude skill** ([`_shared/skill/`](_shared/skill/SKILL.md)): the method, report format, the
   capability/sandbox reference, and two scripts: `probe.sh` (Linux/WSL2: bubblewrap + strace, one probe
   per run) and `audit_npm_package.sh`. Native Windows apps are probed in Windows Sandbox, one `.wsb` per probe.
2. **An [ICM](https://arxiv.org/abs/2603.16021) workspace** around it, so a person checks each step:

| Stage | What happens | What you check |
|---|---|---|
| `01_intake` | pin down the exact version; verify the copy (commits, checksums, signatures) | is this exactly what will be installed? |
| `02_static` | read the code; list every capability | does the inventory miss anything? |
| `03_probe` | write the probe plan → **you approve** → run → results | **nothing third-party runs before you approve** |
| `04_report` | scorecard, tier, coverage limits, concrete recommendation | is every Pass backed by evidence? |

## Worked example: VectorCraft

`stages/*/output/vectorcraft/` is a real vetting of the [VectorCraft](https://github.com/storytold/vectorcraft)
vector editor (2026-10-28):
- Two downloaded zips proved byte-identical to repository commits.
- The MSI checked against published checksums and a Microsoft-verified signature.
- An auto-updater found and read: it asks before installing, and verifies hash and signature.
- The result: **Medium**, install with mitigations. Capped there because no sandbox was available to
  run the probes, which the report says plainly instead of hiding it.

## Use it

- **Just the skill:** upload `_shared/skill/` to claude.ai, or copy it to `~/.claude/skills/ai-vetting-skill-sx/`.
  Ask Claude to vet something "with sandbox probes".
- **The workspace:** clone, open in Claude Code, start a run at [`stages/01_intake/CONTEXT.md`](stages/01_intake/CONTEXT.md).

Sandboxes: Linux/WSL2 with `bubblewrap` and `strace`; Windows 10/11 Pro with Windows Sandbox (turned on
by you); Docker/Podman; macOS `sandbox-exec`. No sandbox → probes are reported as not run, never run on the host.

## Honest limits

- **`probe.sh` is tested against fake components, not yet against a real one.** `scripts/test_probe.sh`
  runs 11 cases in WSL2 (Ubuntu 26.04, bubblewrap 0.11.1, strace 6.19): a well-behaved write, a stolen
  SSH key, a leaked token, writes outside the grant, a `.bashrc` persistence line, network with and
  without the grant, a child program with and without the grant, and a sandbox that fails to start
  (reported as failed, never as a pass). All pass. The first run found and fixed three bugs.
- A secret copied by the kernel (`sendfile`, `copy_file_range`) can't be matched by content; the probe
  still flags the credential file being opened, and notes the copy.
- Probes see what happens during the probe task; logic triggered later or remotely can still hide.
- Static review of a large codebase is a careful search, not a full read; reports say which.
- This is due diligence, not a guarantee. Shared as is.

## Credits

Built by [The Compliant Neuron](https://thecompliantneuron.com) with Claude (Anthropic), extending
its static-only [`ai-component-vetting`](https://github.com/Radic-ode/ai-component-vetting) skill.
Workspace structure follows the Interpretable Context Methodology (Van Clief & McDermott, arXiv:2603.16021).

MIT licensed. See [LICENSE](LICENSE).
