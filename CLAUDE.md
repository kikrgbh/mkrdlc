# CLAUDE.md

## What this project is
`mkr-aidlc` is a self-hosted AI-Driven Development Lifecycle template for Claude Code, built inside
the repo it eventually ships. It is developed here, milestone by milestone (M0–M6), by kikrgbh; the
same loop it defines governs how it is built. See `docs/DESIGN.md` for the principles and the
loop, and `specs/` for the milestone specs.

## Stack
Bash (4.0+) and Markdown only — no runtime dependency, no interpreter beyond what ships with a
Claude Code checkout. Git is required for the git-root fallback in
`.claude/hooks/lib/config.sh`. No package manager, no build step; `tests/config_test.sh` is a
plain bash script.

## Commands
| purpose | command |
|---|---|
| test | `bash tests/config_test.sh` |
| coverage | none — bash, not instrumented |
| typecheck | none — bash, not applicable |
| lint | none yet (M3 may add shellcheck) |
| build | none — nothing to compile |
| run | n/a — nothing runs standalone at M0 |

## How we build — the AIDLC loop

triage → spec → ⟦spec approved⟧ → plan → ⟦plan conformant⟧ → design → ⟦design gate⟧
→ tests → implement → verify → review → ⟦review gate⟧ → merge → ground → ship

No code is written for a non-trivial change until its spec is agreed. Humans own intent and
guardrails; the agent runs the loop; review happens at gates, not per keystroke.

Depth: **Quick** (typo/config — implement + test + a one-line review note) ·
**Standard** (a feature in an existing module — the full loop, single pass) ·
**Deep** (new module, auth, data model, anything hard to reverse — full loop + ADR + audit).
State which you picked, and why, before starting.

At M0, only phases 0–2 exist in worked form — this project's own triage, spec and plan. Phases 3
onward (design, code review, audit, ship) land as the milestones that build their gates and
agents are themselves built (see `docs/DESIGN.md` §8, the build sequence).

## Allowed actions
- **MAY:** read code · write and run tests · draft specs, ADRs and milestone plans · surgical edits
  on a feature branch · open PRs.
- **MUST ASK FIRST:** create or modify the GitHub remote · push or merge to `main` · change the
  repo's visibility (private → public is reserved for M6) · change what
  `.claude/hooks/lib/config.sh` publishes without a spec update, since M1–M6 depend on that
  contract.
- **MUST NEVER:** commit secrets · disable a guardrail or weaken a test to make the suite pass ·
  force-push a shared branch · restate a §8 config default anywhere outside `config.sh` (AD-5).

## Gate owners
A gate without a named owner is not a gate.

| gate | owner |
|---|---|
| spec approval | kikrgbh |
| design | kikrgbh |
| review gate (G4) | kikrgbh |
| pre-merge | kikrgbh |
| pre-deploy | kikrgbh |
| incident / kill switch | kikrgbh |

## Non-negotiables
- `.claude/` is the one copy of the template — used here and shipped, never forked into a separate
  `template/` directory (AD-4).
- `.mkr/config` is never sourced into a caller; the only sanctioned read is
  `.claude/hooks/lib/config.sh`'s child-process dump, by sourcing or by CLI (AD-2).
- Every default in the config contract lives in `config.sh` and nowhere else (AD-5) — not restated
  in `seed/config`'s comments, not in this file.
- `seed/CLAUDE.md` and `seed/config` carry no fact specific to this project.
- No milestone after M0 ships without its own spec agreed at G1 by a reviewer who did not write it.

## Conventions
- Match surrounding style; smallest correct diff; no speculative abstraction.
- Conventional Commits; feature branches; every non-trivial PR links its spec.
- Any substantial or hard-to-reverse decision gets an ADR under `docs/adr/`.
- Changes to `.claude/hooks/lib/config.sh` are judged against mutation resistance, not just a
  green suite (M0 §9) — a passing case that a targeted mutation wouldn't also fail proves nothing.
