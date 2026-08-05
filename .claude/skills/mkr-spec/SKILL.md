---
name: mkr-spec
description: Drafts a spec for a Standard/Depth change into the required 14-section shape (specs/M1_Loop_Spec.md §7.3), ready for mkr-spec-review and G1 approval. Use after mkr-loop's triage has classified a change as Standard or Deep, carrying its TRIAGE block forward as §0.
---

# mkr-spec — phase 1 (spec)

Drafts one spec file for the change `mkr-loop` just triaged as Standard or Deep. Never invoked for
Quick — Quick skips straight to implement + test + a one-line review note.

## Required shape

Exactly these H2 sections, in this order — no more, no fewer, and never reordered:

```
## 0. Triage
## 1. Header
## 2. Intent
## 3. Scope
## 4. Affected users & journey change
## 5. Reuse check
## 6. Architecture & key decisions
## 7. Interfaces / contracts
## 8. Data model
## 9. Test-case register
## 10. Acceptance criteria
## 11. Definition of Done
## 12. Task breakdown
## 13. Review history
```

`## 8. Data model` is present even when there's nothing to add — write "No data model change."
rather than omitting the heading, so a mechanical section-presence check never needs a per-spec
exception list.

## Adopter-declared extra sections (docs/adr/0004-spec-section-extension-point.md)

The 14 above are fixed — never renumbered, reordered, or dropped. A project can additionally
declare its own sections via `config.sh list MKR_SPEC_EXTRA_SECTIONS` (CLI mode; space-separated
kebab-case slugs, e.g. `data-privacy migration-plan`). When non-empty, append one H2 per slug,
**in the declared order**, immediately after `## 13. Review history`, numbered sequentially
starting at 14, titled by converting the slug to Title Case (`data-privacy` → `## 14. Data
privacy`). Write each one for real, the same standard as §2–§13 — a project declared it because it
needs the content, not the heading alone. Empty `MKR_SPEC_EXTRA_SECTIONS` (the default) means the
spec stays at exactly 14 sections, unchanged from today.

## §0 Triage

Paste the `TRIAGE` block `mkr-loop` produced, verbatim, as a fenced block. Do not re-derive it —
`mkr-spec` is not where triage happens.

## §1 Header

A table with at least these rows:

```
| | |
|---|---|
| **Status** | DRAFT rev 1 |
| **Depth** | <Standard\|Deep, from §0> |
| **Author** | agent |
| **Approver** | <MKR_GATE_SPEC's value> |
```

**Status** is one of exactly three literal shapes — a mechanical check (`tests/mkr_artifact_test.sh`
TC-M1-04, and `mkr-spec-reviewer`) reads this string, so don't paraphrase it:

- `DRAFT rev N` — while drafting, before any review.
- `NOT READY rev N (<reviewer>)` — after a review round finds blocking issues.
- `ACCEPTED rev N (<approver>, <date>)` — after G1 passes. **Only a human G1 approval sets this** —
  see "Never" below.

**Approver.** Run `config.sh get MKR_GATE_SPEC` (CLI mode) and put its value here at draft time, not
left blank for later. If it's empty, write `<unset — MKR_GATE_SPEC not configured>` literally —
failing loudly beats silently accepting anyone's approval. `mkr-spec-reviewer` checks that a
recorded G1 approval in §13 was made by whoever this field names.

## Filename

`<MKR_SPECS_DIR><Slug>_Spec.md` — get `MKR_SPECS_DIR` via `config.sh get MKR_SPECS_DIR` (CLI mode;
default `specs/`). `<Slug>` is a short PascalCase-or-similar name for the change, matching the
existing `M0_Foundation_Spec.md` / `M1_Loop_Spec.md` convention for milestone work, or a feature
name for anything else (e.g. `UserPreferences_Spec.md`).

## §2–§13 content

Write each section for real — §2 Intent states who's affected and why it matters; §3 Scope lists
in-scope items and out-of-scope items (each named to what handles it, if anything does); §5 Reuse
check names *what was checked*, not just "no duplicate found"; §9's test register should cover
every §10 acceptance criterion at least once, and every §10 criterion should trace back to a §2
intent claim — `mkr-spec-reviewer` checks both directions. §12 Task breakdown is also this
milestone/change's *plan* (phase 2) — order it against `MKR_PLAN_MANDATORY`
(`spec-first reuse-check test-first self-review verify code-review`, unless the project's
`.mkr/config` overrides it) so `mkr-plan` (or a by-hand check, if `mkr-plan` doesn't exist yet in
this project) has something conformant to check.

## What `mkr-spec` must never do

- Invent acceptance criteria the intent section doesn't support.
- Mark its own `Status` as `ACCEPTED`. Check `config.sh list MKR_SELF_APPROVE` (CLI mode) — only if
  `spec` is literally in that list may the drafting session itself accept; otherwise `Status` stays
  `DRAFT`/`NOT READY` until a human with the `Approver` name says otherwise, out loud, in this
  session.
- Silently drop a required section because a change "felt too small" — that's a Quick-depth call
  `mkr-loop` makes *before* this skill is ever invoked, not a call this skill gets to make on its
  own.

## Handoff

Once drafted (`Status: DRAFT rev 1`), invoke `mkr-spec-review` next — G1 is not satisfied by
drafting alone.
