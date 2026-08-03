# Eval run — mkr-spec-reviewer, seed set (M5 dogfood)

Fresh-context `mkr-spec-reviewer`, one spawn per fixture, run for real (not simulated).

| fixture | result | expected | got |
|---|---|---|---|
| ready-m5-spec.md | MATCH | READY | READY |
| not-ready-missing-section.md | MATCH | NOT READY | NOT READY (5 blocking) |

**2/2 matched.**

Side effect of running the `ready-m5-spec.md` fixture for real: the fresh reviewer found two small,
real, non-blocking issues in `specs/M5_Gates_Spec.md` that its own prior (rev 1) review round had
missed — `TC-M5-08`'s §9 `AC` column read `AC-4` instead of `AC-5`, and §11 DoD's "Spec agreed at
G1" checkbox was left unchecked despite the spec already being `ACCEPTED`. Both fixed directly in
the spec; verdict on the fixture itself is unaffected (still `READY` either way — both were
non-blocking).
