# 0004 — Spec section extension point: core 14 plus adopter-declared extras

## Status

Accepted

## Context

`mkr-spec`'s required shape (`specs/M1_Loop_Spec.md` §7.3) is "exactly these 14 H2 sections, in
this order — no more, no fewer, and never reordered," enforced identically by `mkr-spec-reviewer`
(structural check before any content review) and referenced by `mkr-code-reviewer`'s correctness
check. Closed at exactly 14 by construction: nothing in `mkr-spec`, `mkr-spec-reviewer`, or
`mkr-code-reviewer` reads a config value for the section list, they read the literal 14 headings
baked into their own instructions.

An adopter repo (Misikiri, reported upstream) needed a domain-specific section — e.g. "Data
privacy" or "Migration" — that every spec in their repo should carry, structurally checked the same
way the other 14 are. With no extension point, their only option was forking all three files
locally: three separate patches to maintain against upstream drift, the single biggest source of
local divergence they reported. This is exactly the shape `MKR_PLAN_MANDATORY`/`MKR_PLAN_OPTIONAL`
already solved for `mkr-plan`'s own check set — a project declares tokens in `.mkr/config`, `mkr-plan`
reads them, no skill file changes — but `mkr-spec`'s section shape had no equivalent seam.

Two shapes were considered for that seam:

1. **Let a project redefine the whole 14** (arbitrary list, replacing the core shape). Rejected:
   `mkr-spec-reviewer`'s and `mkr-code-reviewer`'s own correctness checks assume specific sections
   exist at specific points (`§0 Triage` first, `§10 Acceptance criteria`/`§9 Test-case register`
   cross-checked against each other, `§13 Review history` last) — a project that dropped or
   reordered any of those would silently break review logic that has nothing to do with the
   adopter's actual complaint (wanting to *add* a section, not remove or reorder the existing ones).
2. **Core 14 fixed, adopter sections appended after them** — the shape adopted below.

## Decision

The 14 sections in `specs/M1_Loop_Spec.md` §7.3 stay fixed, in their existing order, always
required — this ADR does not reopen that shape. A new `.mkr/config` variable,
`MKR_SPEC_EXTRA_SECTIONS`, is a space-separated list of kebab-case slugs (mirroring
`MKR_PLAN_MANDATORY`/`MKR_PLAN_OPTIONAL`'s own token shape, not free text — `config.sh`'s `mkr_list`
splits on space, so a full sentence can't survive as one list item). `mkr-spec` appends one H2
section per declared slug, in the declared order, immediately after `## 13. Review history`,
numbered sequentially starting at 14, titled by a plain slug-to-Title-Case conversion
(`data-privacy` → `## 14. Data privacy`). Empty (the default) reproduces today's exact 14-section
shape with zero behavior change for every project that never sets it.

`mkr-spec-reviewer` resolves `MKR_SPEC_EXTRA_SECTIONS` (via the caller, the same way it already
receives `MKR_GATE_SPEC` — it has no shell access of its own) and checks the declared extra
sections are present, in the declared order, after §13 — the same structural-presence check the
core 14 already get, extended, not a new kind of check. `mkr-code-reviewer` is unaffected: its own
checks are against a diff and the spec's *acceptance criteria*, not the spec's section shape,
which is what G1 already settled before code review ever starts — this issue's original framing
named it as a third file to touch, but on inspection there's nothing there for it to check.

## Consequences

- An adopter declares extra sections in `.mkr/config` — no fork of `mkr-spec`, `mkr-spec-reviewer`,
  or `mkr-code-reviewer`, the same way `MKR_PLAN_OPTIONAL` already avoids forking `mkr-plan`.
- The core 14 stay a stable, unconditional contract every project shares — an adopter can extend
  the shape, never shrink or reorder the part every reviewer's cross-section logic depends on.
- A slug-to-Title-Case conversion is lossy (no control over capitalization of acronyms, hyphenated
  compound words, etc.) — an adopter wanting a title the conversion doesn't produce cleanly can
  still pick a different slug; this is the same tradeoff `MKR_PLAN_MANDATORY`'s tokens already
  accept in exchange for staying `mkr_list`-splittable.
- Two files (`mkr-spec`, `mkr-spec-reviewer`) gain one read of the same config value — a small,
  symmetric addition, not a new architecture. `mkr-code-reviewer` needed no change.
