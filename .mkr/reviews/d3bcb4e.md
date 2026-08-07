# Code review — d3bcb4e (fix(spec-gate): resolve git root from the edited file, not the hook's cwd)

**Reviewers.** Two independent fresh agents, spawned in parallel, neither aware of the other's
findings until each had formed its own judgment. Re-run in a second round (AD-2) since the first
round's security reviewer had blocking findings: both reviewers re-ran, since the fix touched the
exact region `mkr-code-reviewer`'s round 1 had already covered and introduced the
`procwalk_is_registered_worktree` call `mkr-security-reviewer`'s round 1 had flagged as missing.

mkr-code-reviewer: READY (round 2, carried forward from round 1's own READY — no blocking finding
either round)
mkr-security-reviewer: READY (round 2; round 1 was NOT READY (2))

**Scope.** `.claude/hooks/scripts/spec-gate.sh` and `tests/hooks_test.sh`, the full diff against
base commit `797454a` (i.e. everything this branch adds on top of `main`) — round 1's initial fix
(commit `5ebf6c3`, already pushed and reviewed) plus round 2's follow-up fix (this commit,
`d3bcb4e`), reviewed together as one cumulative diff since round 2 revises the exact lines round 1
introduced. Both reviewers re-ran against the full cumulative diff, not just round 2's delta.

## Finding 1 — blocking, confirmed (round 1) — TARGET_ROOT-unresolvable silently bypassed the gate

Round 1's fix introduced `TARGET_ROOT`, resolved from the edited file's own directory, and used it
for every branch/merge-base/spec-lookup query in place of the cwd-derived `ROOT`. When
`TARGET_ROOT` resolution failed (the edited file's path has no git ancestor at all — e.g. a
scratch file outside every repo), round 1's code exited 0 unconditionally, silently allowing the
write with no ASK check ever attempted. Pre-round-1 code always evaluated the gate against `ROOT`
regardless of `FILE_PATH`, so this was a new, total bypass for out-of-repo writes that did not
exist before round 1's own fix.

Fixed by falling back to `TARGET_ROOT="$ROOT"` when resolution fails
(`.claude/hooks/scripts/spec-gate.sh:57-62`), restoring the pre-round-1 behavior for this case
exactly. Verified independently by both reviewers via hand-trace and by the new regression test
TC-M3-50 (`tests/hooks_test.sh`), which asserts an `ask` decision (not a silent allow) for a file
path outside any git repo.

## Finding 2 — blocking, confirmed (round 1) — an unrelated repository's TARGET_ROOT was trusted

Round 1's fix trusted any `TARGET_ROOT` the edited file's path resolved to, including a wholly
unrelated repository — not a linked worktree of the project the hook is running in. Since
`MKR_PROTECTED_BRANCHES`/`MKR_SPECS_DIR`/`MKR_ADR_DIR` are read once from `ROOT`'s own config, this
mixed one project's policy with a foreign repository's branch/spec state; a protected-branch-name
mismatch between the two (a realistic case, not contrived) fails `BASE` resolution and the whole
gate open on a genuinely unspecced foreign branch.

Fixed by cross-checking any `TARGET_ROOT != ROOT` against
`procwalk_is_registered_worktree "$ROOT" "$TARGET_ROOT"` — an existing, already-hardened helper in
`.claude/hooks/lib/procwalk.sh` that verifies against git's own `worktree list --porcelain`
registry rather than a spoofable path string — falling back to `ROOT` when the check fails
(`.claude/hooks/scripts/spec-gate.sh:63-70`). Verified independently by both reviewers: the
argument order (`<root> <dir>`) matches the call site, and the new regression tests TC-M3-48 (a
real `git worktree add` linked worktree is correctly trusted) and TC-M3-49 (a genuinely unrelated
`git init`-only repo is correctly rejected, falling back to `ROOT`) were hand-traced by both
reviewers against the actual helper logic, not accepted from the diff's own comments.

## Findings not pursued further

- Round 1's `mkr-code-reviewer` non-blocking notes (near-duplicate ancestor-walk-up logic already
  present in `worktree-edit-guard.sh`; the same underlying cwd-vs-edited-file defect still present,
  unaddressed, in `id-collision-guard.sh`) — both left as-is: the first mirrors an already-accepted
  in-repo pattern of not sharing this specific snippet, and the second is a separate hook script
  outside this narrow bug fix's stated scope (no spec covers a broader sweep).
- Round 2's `mkr-security-reviewer` non-blocking note that `has_accepted_spec()`'s substring match
  for `**Status**...ACCEPTED` has no independent verification the spec was actually approved — this
  behavior is unchanged by this diff (only `ROOT`→`TARGET_ROOT` was substituted in existing logic)
  and the hook is documented as ASK-tier, never-blocking, by design.

## Verification discipline

Both rounds' agents traced the fix against the actual script and helper source, not just the
diff's own comments; round 2 in particular hand-traced `procwalk_is_registered_worktree`'s
`worktree list --porcelain` cross-reference against both the accept case (TC-M3-48) and the reject
case (TC-M3-49) rather than taking the helper's own header comment on faith. Independently of the
agents, `tests/hooks_test.sh` was run locally after each round's fix: 167/167 passing (up from
165/165 before this change), including TC-M3-48/49/50; `tests/config_test.sh` has 3 pre-existing,
unrelated failures (a `chmod 000`-unreadable-file case that doesn't work running as root),
reproduced identically on unmodified `main`.

## Verdict

VERDICT: READY
