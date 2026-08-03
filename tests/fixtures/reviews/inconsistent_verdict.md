# Code review — abc1234 (fixture: aggregation rule violated — one NOT READY, closing READY)

**Reviewers.** Two independent fresh agents, spawned in parallel, neither aware of the other's
findings until each had formed its own judgment.

mkr-code-reviewer: READY
mkr-security-reviewer: NOT READY (1)

**Scope.** `tests/fixtures/` only — a fixture diff, not a real one.

## Finding 1 — BLOCKING, confirmed — fixture defect, deliberately not reflected in the closing verdict

A fixture finding whose existence should force an overall NOT READY, but the closing line below
wrongly says READY — this is the defect TC-M2-11 must catch.

## Findings not pursued further

- Nothing else raised in this fixture.

## Verification discipline

Reproduced by hand in the fixture's own terms.

## Verdict

VERDICT: READY
