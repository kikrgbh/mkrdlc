# Grounding audit — M4 fixture, commit `abc1234`

Fresh-context agent, no memory of the build, per DESIGN.md phase 9. Audited against the fixture
spec's §10 AC-1…AC-3, branch `fixture-branch`.

| AC | Verdict | Evidence |
|---|---|---|
| AC-1 | VERIFIED | Fixture evidence for AC-1. |
| AC-2 | VERIFIED | Fixture evidence for AC-2, first occurrence. |
| AC-2 | VERIFIED | Fixture evidence for AC-2, duplicated; AC-3 silently dropped. |

**Additional checks the auditor ran independently:**
- Fixture check 1.

**Verdict:** PASS
