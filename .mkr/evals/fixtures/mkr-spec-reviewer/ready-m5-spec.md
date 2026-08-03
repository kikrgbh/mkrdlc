# Eval fixture — mkr-spec-reviewer, expected READY

Grounded in a real run: `mkr-spec-reviewer`, given `specs/M5_Gates_Spec.md` rev 1 fresh, actually
returned `VERDICT: READY` (see that spec's own §13 Review history). This fixture re-uses the same
input as a regression check that a later change to `mkr-spec-reviewer`'s own prompt still recognizes
a genuinely well-formed, traceable spec as `READY`.

input: specs/M5_Gates_Spec.md

expected: READY
