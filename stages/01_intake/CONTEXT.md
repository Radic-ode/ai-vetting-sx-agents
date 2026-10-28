# 01_intake — what exactly is being installed

One job: pin down the exact component and version the user will install, and verify where the copy
under review came from.

## Inputs
- Working (this run): the user's link, file, package name or marketplace page
- Reference (every run): `../../_shared/skill/SKILL.md` (category 1, Provenance, and Process step 1)

Do NOT load: `capability-sandboxes.md` (03's), other runs' outputs.

## Process
1. Get a copy of exactly what will be installed into its own new, empty folder outside this workspace
   (a zip, a clone at a fixed commit, the release asset). Never run anything from it.
2. Verify the copy against its claimed source: the commit it was built from, file-by-file blob hashes
   against that commit, release checksums (`SHA256SUMS`), code signatures.
3. Record the maintainer: who publishes it, how they can be verified, repo age and activity,
   contributors, licence.
4. Write `output/<run>/intake.md` from the vectorcraft run's as a template: component, version, every
   source checked and the result, hashes, and what the user intends to do with it.

## Outputs
- `intake.md` → `output/<run>/`

## Human check
Confirm with the user that this is exactly what they will install (same version, same file). A clean
review of the wrong version is worthless.
