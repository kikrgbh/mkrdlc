# `install.sh` ships `.github/workflows/mkr-gate.yml`

## Intent

`install.sh` ships `.github/workflows/mkr-gate.yml` alongside `.claude/`, so an adopter's repo
gets the CI enforcement (G5: branch protection + tests/coverage/lint/ADR-collision checks)
`README.md`'s Gates table promises, not just the local hook-based gates.

## Scope

**In scope**
- `install.sh` walks and ships `.github/` the same way it walks `.claude/` — recursively, if present.
- A source with no `.github/` directory is not an error; nothing is shipped for it.

**Out of scope**
- The workflow file's own job logic, triggers, or commands.
- Any other file under `.github/` beyond `mkr-gate.yml`.
- A config variable for `.github/`'s location — GitHub Actions fixes that path itself.

## Architecture & key decisions

- `.github/` is walked the same way `.claude/` is: present → shipped, absent → skipped, never an
  error.
- The combined path list sorts once, not per-directory (`.claude` and `.github` interleave
  correctly under a plain sort).
- No new config variable — `.github/workflows/` is a fixed GitHub Actions convention, not a
  per-project setting.

## Interfaces / contracts

- `install.sh`: no new flags. Its path-enumeration step also walks `.github/` when present; every
  other function already operates on the enumerated path list generically, so nothing else changes.
- `/mkr-update` inherits this automatically (it shells out to `install.sh`).

## Data model

No change. The install manifest's format is unchanged — it simply gains lines for `.github/`-rooted
paths alongside the existing `.claude/`-rooted ones.
