---
run: vectorcraft
date: 2026-10-28
component: VectorCraft (vector illustration editor; desktop app, CLI, MCP server)
publisher: storytold / ArtCraft ("Learning Machines" in the binaries)
installed_version: 0.17.0 (windows-x64 MSI)
---

# Intake: VectorCraft

## What the user will install
The Windows desktop app from the official release MSI. The user first downloaded two source zips, then
chose the release installer. Installed to `C:\Program Files\VectorCraft\` (`vectorcraft.exe`,
`vectorcraft-cli.exe`) and launched on 2026-10-28.

## Copies checked against their source

| Copy | Claimed source | Check | Result |
|---|---|---|---|
| `vectorcraft-main.zip` (13.0 MB, downloaded ~2026-10-08) | github.com/storytold/vectorcraft | zip comment names commit `752a67e16c3a72558e6cc4e10c4fd0bc98c663c3`; all 1,340 files compared by git blob hash | **byte-identical** to that commit (Oct 8, "Merge pull request #462") |
| `vectorcraft-main (1).zip` (24.5 MB, 2026-10-28) | same repo | commit `9997ff021503e4f323f084fb7e64618d209d0126`; all 2,300 files by blob hash | **byte-identical**; repo HEAD on 2026-10-28; the old commit is its ancestor |
| `vectorcraft-0.17.0-windows-x64.msi` (106,770,432 bytes) | release v0.17.0, published 2026-10-25, uploaded by `github-actions[bot]` | SHA-256 against the release's `SHA256SUMS.txt` | **match**: `861f4e9fe943dacddfd30bc6512a20a4db2fbc554a6daa4101595c2fc85d11c1` |
| same MSI | signed by the publisher | Authenticode | **Valid**, timestamped. Signer `CN=Learning Machines Inc, Atlanta, Georgia, US`; issuer `Microsoft ID Verified CS EOC CA 03` (Microsoft-verified identity); cert valid 2026-10-24 to 2026-10-27 (short-lived Trusted Signing cert, timestamp inside the window) |

## Maintainer
- GitHub org `storytold`; product site getartcraft.com (ArtCraft "Craft" app suite). Licence MIT OR Apache-2.0.
- Very active: 5,053 commits between Oct 8 and Oct 27; ~600k lines added. Top committers in that range:
  BFlat (1,888), bflatastic (844), dotCooCoo (632), aiongg (187), then many smaller contributors,
  including a `Cursor Agent` account.
- Small naming mismatch: source code says "Learning Machines **LLC**", the signing cert "Learning Machines **Inc**".
  Probably the same company; not verified.

## Notes
- The repo was cloned to a short temp path (`%LOCALAPPDATA%\Temp\vcv`); the session's scratch path was
  too long for git on Windows.
- The MSI's binaries were not compared with a build from source; hash, signature and CI origin only.
