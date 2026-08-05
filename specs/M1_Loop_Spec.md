# The AIDLC loop: triage, spec, spec-review, plan, and ADR skills

## Intent

- `mkr-loop` triages a change as Quick/Standard/Deep and routes to the next phase.
- `mkr-spec` drafts a spec file into a fixed, enforced section shape.
- `mkr-spec-review` invokes a fresh-context reviewer agent and records a READY/NOT READY verdict — G1.
- `mkr-plan` checks a presented plan against required steps and returns a CONFORMANT/BLOCKED verdict — G2.
- `mkr-adr` writes a numbered ADR into the existing ADR shape.
- `/mkr-init` interviews an adopter's repo and seeds its `CLAUDE.md`/`.mkr/config`, never touching this repo's own.

## Scope

**In scope**
- `.claude/skills/mkr-loop/SKILL.md` — triage plus routing to the next phase skill.
- `.claude/skills/mkr-spec/SKILL.md` + `.claude/commands/mkr-spec.md` — drafts a spec file into `MKR_SPECS_DIR`.
- `.claude/skills/mkr-spec-review/SKILL.md` + `.claude/agents/mkr-spec-reviewer.md` + `.claude/commands/mkr-spec-review.md` — the READY/NOT READY audit.
- `.claude/skills/mkr-plan/SKILL.md` + `.claude/commands/mkr-plan.md` — the CONFORMANT/BLOCKED audit.
- `.claude/skills/mkr-adr/SKILL.md` + `.claude/commands/mkr-adr.md` — writes a numbered ADR into `MKR_ADR_DIR`.
- `.claude/commands/mkr-init.md` (+ skill body) — interviews an adopter, seeds their `CLAUDE.md`/`.mkr/config` from `seed/`.

**Out of scope**
- The design gate's two reviewer agents, `mkr-design`/`mkr-gates` skills.
- `mkr-code-review`, its reviewer agents, G4.
- Hooks (`spec-gate.sh`, `branch-guard.sh`, …), `settings.json` wiring, CI enforcement — nothing built here is mechanically enforced; G1/G2 are exercised only when a session chooses to run the skill.
- `mkr-audit`/`mkr-auditor`, `mkr-merge`.
- `install.sh`, the manifest, `/mkr-update`, `mkr-detect`, making the repo public. `/mkr-init` is written and tested against a scratch directory; it is not distributed yet.

## Architecture & key decisions

- Skills carry the behaviour; commands are the explicit, invokable door. Each command states its phase's invariant and delegates to the matching skill. `mkr-loop`/triage is the one exception with no standalone command — it's the first thing every other phase's command runs before doing its own work.
- No mechanical gate exists yet (a hook-based gate is a later addition) — a skill's verdict, written to disk, is what makes G1/G2 real, not a BLOCK/WARN mechanism.
- `mkr-spec-reviewer` cannot review the spec that specifies it, since the agent doesn't exist until the spec is implemented — G1 for this spec is a human reading it directly.
- The plan verdict vocabulary is exactly `CONFORMANT | BLOCKED(missingMandatory, orderingViolations)`.
- `/mkr-init` refuses to run against this repo's own root using a content check, not a path or git-remote check: it reads the target root's `docs/DESIGN.md` first line and refuses if it matches this repo's own title exactly. A path/remote check would break on a rename, fork, or different checkout location; a content check survives all three, and an adopter's repo never receives that file in the first place.
- The design gate (G3) for this milestone is satisfied by direct grounding against `docs/DESIGN.md` rather than a spike or a reviewer agent — no reviewer agent exists until a later milestone, and every contract below cites the design-doc line it implements, making the match directly checkable.

## Interfaces / contracts

### `mkr-loop` — triage
Preflight (branch check, resume check, split check), then six classification questions, then a decision rule, then a `TRIAGE` block. Q1 (paths touched) is matched mechanically against `MKR_RISKY_PATHS` via `config.sh`'s CLI mode; the rest are judgment calls, stated as such. Output: Quick — one line, no file. Standard/Deep — the `TRIAGE` block, carried forward as spec §0; triage itself writes no file. If a later phase finds triage was wrong, the session stops, re-runs `mkr-loop`, and records the revised depth.

### `mkr-spec` — required spec shape
Every Standard/Deep spec has exactly these sections, in order: `0. Triage` · `1. Header` · `2. Intent` · `3. Scope` · `4. Affected users & journey change` · `5. Reuse check` · `6. Architecture & key decisions` · `7. Interfaces / contracts` · `8. Data model` · `9. Test-case register` · `10. Acceptance criteria` · `11. Definition of Done` · `12. Task breakdown` · `13. Review history`. A project may additionally declare `MKR_SPEC_EXTRA_SECTIONS` (docs/adr/0004-spec-section-extension-point.md) — kebab-case slugs appended as numbered H2 sections after §13, in the declared order; empty (the default) keeps the shape at exactly these 14.

- Header `Status` is one of `DRAFT rev N`, `NOT READY rev N (<reviewer>)`, or `ACCEPTED rev N (<approver>, <date>)`.
- Filename: `<MKR_SPECS_DIR><Milestone-or-feature-slug>_Spec.md`.
- `Approver` is set from `MKR_GATE_SPEC`'s value at draft time; if unset, the field reads `<unset — MKR_GATE_SPEC not configured>` rather than a name.
- `§8 Data model` is always present as a heading; a spec with nothing to add states "No data model change" rather than omitting it.
- `mkr-spec` never marks its own `Status` as `ACCEPTED` (unless `MKR_SELF_APPROVE` permits it) and never invents acceptance criteria beyond what `§2 Intent` supports.

### `mkr-spec-review` + `mkr-spec-reviewer`
Invokes the `mkr-spec-reviewer` agent (fresh context, no memory of drafting, read-only tools) against a spec file. Output: `READY` or `NOT READY (<n> blocking)` plus findings, each citing a spec section. Checks at minimum: all required sections present and ordered; every acceptance criterion traceable to `§2 Intent`; the test register covers every acceptance criterion; every out-of-scope item names a milestone; the reuse check names what was actually checked; the `Approver` field matches the calling repo's `MKR_GATE_SPEC`. The verdict is appended to the spec's own `§13 Review history`. A spec edited after `NOT READY` bumps its rev number and is re-reviewed against the new revision.

### `mkr-plan`
Input: a presented plan (ordered steps) and `MKR_PLAN_MANDATORY`. Output: `CONFORMANT` or `BLOCKED` with `missingMandatory` (required steps absent) and `orderingViolations` (a required step present but out of order). `MKR_PLAN_OPTIONAL` steps are informative only — their absence never blocks. A plan has no required file shape of its own; for Standard/Deep it is embedded as the spec's `§12 Task breakdown`.

### `mkr-adr`
Writes into the existing `docs/adr/NNNN-*.md` shape (Status / Context / Decision / Consequences). Numbering: the next unused `NNNN` in `MKR_ADR_DIR`, zero-padded to 4 digits — the higher of the local working tree's own max and a best-effort `origin/main` fetch's max (a courtesy, not an enforced guarantee; `id-collision-guard.sh` is the real backstop).

### `/mkr-init`
Free-form interview that fills `seed/CLAUDE.md` and `seed/config`'s placeholders for the calling repo, writing the results to that repo's `CLAUDE.md` and `.mkr/config`.

- Root resolution: `$CLAUDE_PROJECT_DIR` if set, else `git rev-parse --show-toplevel`, else refuse with "no project root found."
- Refuses to run if `<root>/docs/DESIGN.md` exists and its first line matches this repo's own title exactly.
- Refuses to overwrite an existing non-placeholder `CLAUDE.md` or `.mkr/config` without confirmation.

## Data model

No new `config.sh` variable — this milestone only consumes the existing contract, each read via `config.sh`'s CLI mode, never sourced directly:

| Variable | Consumed by | For |
|---|---|---|
| `MKR_SPECS_DIR` | `mkr-spec` | where a drafted spec file is written |
| `MKR_ADR_DIR` | `mkr-adr` | where a drafted ADR file is written |
| `MKR_RISKY_PATHS` | `mkr-loop` | Q1's mechanical match |
| `MKR_GATE_SPEC` | `mkr-spec` (write), `mkr-spec-reviewer` (check) | populates and later verifies the spec Header's `Approver` field |
| `MKR_SELF_APPROVE` | `mkr-spec` | whether the drafting session may mark its own `Status: ACCEPTED` |
| `MKR_PLAN_MANDATORY` | `mkr-plan` | the CONFORMANT/BLOCKED check |
| `MKR_PLAN_OPTIONAL` | `mkr-plan` | informative-only steps |
| `MKR_SPEC_EXTRA_SECTIONS` | `mkr-spec` (write), `mkr-spec-reviewer` (check) | adopter-declared sections appended after §13 (docs/adr/0004-spec-section-extension-point.md) |
