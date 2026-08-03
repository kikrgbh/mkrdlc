# Eval fixture — mkr-spec-reviewer, expected NOT READY

`tests/fixtures/specs/missing_heading.md` is missing `## 9. Test-case register` entirely — an
objective, mechanically-checkable violation of the required 14-section shape
(`specs/M1_Loop_Spec.md` §7.3) `mkr-spec-reviewer` is instructed to check first. A fresh reviewer
reading this file should reliably find and name the missing section.

input: tests/fixtures/specs/missing_heading.md

expected: NOT READY
