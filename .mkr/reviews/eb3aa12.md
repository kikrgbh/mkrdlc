# Code review — eb3aa12 (README.md: document the MKR_WORKTREE_POLICY permission-scope gotcha)

**Reviewers.** Two independent fresh agents, spawned in parallel, neither aware of the other's
findings until each had formed its own judgment.

mkr-code-reviewer: READY
mkr-security-reviewer: READY

**Scope.** `README.md` (new "Worktrees" section, 12 lines) and `specs/WorktreePermissionScope_Spec.md`
(the spec itself, `ACCEPTED rev 3`), against merge-base `origin/main`. No source, hook, or config
file touched.

Both reviewers independently confirmed the one falsifiable claim the diff depends on —
`specs/WorktreeGuard_Spec.md` (the file the new section links to) actually exists on this branch
and reads `Status: ACCEPTED rev 11` — rather than taking the spec's own §3/§11 dependency claim on
faith. `mkr-code-reviewer` additionally confirmed `EnterWorktree` is a real, already-exercised
mechanism (referenced in `tests/hooks_test.sh`), not an invented tool name.

Both independently walked AC1–AC4/`TC-WPS-01..04` against the actual added text and found each
satisfied: the section states the registration requirement and links the companion spec (AC1), the
permission-scope gotcha and its `EnterWorktree` workaround (AC2), without restating either guard's
own registration/collision-check logic inline (AC3/`TC-WPS-04`), and touches no source/hook/config
file (AC4/`TC-WPS-03`).

## Findings not pursued further

None blocking. One non-blocking observation (`mkr-security-reviewer`): the section doesn't caveat
that staying in-session via `EnterWorktree` also carries the session's existing broad permissions
into whatever the new worktree checks out — relevant if a worktree is ever used to review an
untrusted branch rather than continue existing work. This describes pre-existing Claude Code
harness behavior accurately; it isn't a defect this diff introduces, and wasn't required to be
fixed. One minor imprecision noted by `mkr-code-reviewer`: AC4's literal wording ("only README.md
changed") is technically satisfied loosely rather than exactly, since the spec file itself also
shows as new in a branch-vs-`main` diff — the ordinary, expected artifact of drafting a spec
alongside its own implementation on the same branch, not a scope violation.

## Verification discipline

The dependency claim (`specs/WorktreeGuard_Spec.md` merged, `ACCEPTED`) and the `EnterWorktree`
mechanism claim were both independently reproduced against actual repo state, not accepted from the
spec's or README's own text.

## Verdict

VERDICT: READY
