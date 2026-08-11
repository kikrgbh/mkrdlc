# Design review — WorktreeGuard rev 2

**Reviewers.** Two independent fresh agents, spawned in parallel, neither aware of the other's
findings until each had formed its own judgment.

mkr-design-reviewer: READY
mkr-architecture-reviewer: READY

**Scope.** `specs/WorktreeGuard_Spec.md`, rev 2, §6/§7/§8.

**Required AC2/`TC-WGSPEC-06` judgment.** Both reviewers independently read only the two deny/warn
strings quoted in §6 (no other context) and independently concluded an adopter can already
correctly identify which of the two failure conditions — not-a-registered-worktree vs.
live-process-collision — a given message describes, without reading source. `worktree-edit-guard.sh`'s
"create a worktree first" remedy signals registration; `worktree-collision-guard.sh`'s "another live
process has this worktree open" plus a pid list signals collision. **AC2 is satisfied as drafted —
no message-wording fix is required; `TC-WGSPEC-05` is not triggered.**

Both reviewers independently re-verified every factual claim in §5/§6/§7/§8 against current repo
state (not taken on the spec's word) — including a byte-for-byte diff of the quoted deny/warn
strings against the actual source, and an independent re-derivation of the `TC-WG-*` case count
(62, matching the spec).

## Finding 1 — non-blocking, confirmed — symmetry gap in "documented, not fixed" treatment

`mkr-architecture-reviewer`: §6 gives the advisory-tier asymmetry (AD-2/AD-3) its own explicit
"documented, not fixed" callout, but a related, equally adopter-relevant gap — an unrecognized/typo'd
`MKR_WORKTREE_POLICY` value silently fails open on both guards, with no warning at any tier — gets
no equivalent callout. Not blocking (pre-existing, tested behavior; redesigning validation is out of
scope per §3), but the same explicit treatment would improve traceability if a future "guard didn't
fire when I expected" report turns out to trace back to a typo.

## Finding 2 — non-blocking, confirmed — asymmetric explicitness between the two deny/warn messages

`mkr-design-reviewer`: `worktree-collision-guard.sh`'s message identifies its condition explicitly
("another live process...open"); `worktree-edit-guard.sh`'s message identifies its condition
inferentially (absence of process language, inferred from the remedy). Both are correctly
distinguishable today (AC2 holds), but a future tightening could make the edit-guard message equally
explicit (e.g. "this directory is not a registered worktree") for symmetry. Does not rise to
"cannot tell" and does not trigger the §3/`TC-WGSPEC-05` wording-fix path.

**Findings not pursued further** — None; both findings above are optional polish, not defects, and
neither reviewer asked for a revision.

**Verdict.** READY
