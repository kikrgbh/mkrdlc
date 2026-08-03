# Release gates: README gate-tier table and install one-liner

## Intent

- `README.md` has a real gate-tier table matching `docs/DESIGN.md` §4's five tiers
  (`ASK`/`WARN`/`WARN → CI`/`CI`/`BLOCK`) across all nine gates/guardrails.
- `README.md` has an install one-liner section, including the `--dry-run`-passing form.

## Scope

**In scope**
- `README.md`'s `## Gates` table (nine rows, matching `docs/DESIGN.md` §4 cell-by-cell).
- `README.md`'s install one-liner section: plain form and `bash -s -- --dry-run` form.

**Out of scope**
- Flipping the repo's visibility to public, or marking it a GitHub template.

## Interfaces / contracts

- `README.md` `## Gates` table — one row per `docs/DESIGN.md` §4 gate/guardrail (G1–G6 plus three
  unconditional `BLOCK` guardrails), columns `Gate | Enforced by | Tier`, `Enforced by` and `Tier`
  copied verbatim from `docs/DESIGN.md` §4.
- `README.md` install one-liner section (placed after `Gates`, before `Layout`):

  ```
  curl -fsSL https://raw.githubusercontent.com/kikrgbh/mkrdlc/main/install.sh | bash

  curl -fsSL https://raw.githubusercontent.com/kikrgbh/mkrdlc/main/install.sh | bash -s -- --dry-run
  ```

## Data model

No change.
