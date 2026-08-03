---
description: Check a presented plan against MKR_PLAN_MANDATORY/MKR_PLAN_OPTIONAL and return CONFORMANT or BLOCKED (phase 2 of the AIDLC loop, G2).
---

Run the `mkr-plan` skill against the plan presented in this session (normally the spec's `## 12.
Task breakdown`, if one exists).

Invariant this command exists to state, not to re-implement: the verdict is exactly `CONFORMANT` or
`BLOCKED(missingMandatory=[...], orderingViolations=[...])` — DESIGN.md §2's own vocabulary, never a
paraphrase of it.
