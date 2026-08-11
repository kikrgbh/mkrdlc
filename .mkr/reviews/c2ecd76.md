# Code review — c2ecd76 (specs/WorktreeGuard_Spec.md, ACCEPTED rev 6, plus its G3 design records and ADR)

**Reviewers.** Re-run per AD-2 (specs/M2_CodeReview_Spec.md §6): `mkr-security-reviewer` had a
blocking finding on the rev-2 diff and was re-run fresh on the rev-4 diff (its scope covers the same
lines rev 5/rev 6 later touched); `mkr-code-reviewer` had a blocking finding on the rev-4 diff and
was re-run fresh on this final rev-6 diff. Neither reviewer was aware of the other's findings until
each had formed its own judgment, at each round.

mkr-code-reviewer: READY
mkr-security-reviewer: READY

**Scope.** `specs/WorktreeGuard_Spec.md` (rev 2 → rev 6), `.mkr/designs/WorktreeGuard-rev{2,3,4}.md`,
`docs/adr/0012-worktree-guard-policy-tiers.md` — five new files against merge-base `a98a37a`, no
existing file modified or deleted; no guard source (`.claude/hooks/scripts/*.sh`) touched at any
revision. Three rounds ran across this change's revision history:

- **Round 1** (rev-2 diff, commit `e43150d`): `mkr-code-reviewer` READY. `mkr-security-reviewer`
  NOT READY (1 blocking) — the spec claimed "nothing found... suggests either algorithm is wrong"
  while omitting a real, source-documented commit-guard bypass class (`procwalk.sh`'s own "KNOWN,
  ACCEPTED SCOPE BOUNDARY" comment: a git alias/shell function/`eval`/`git commit-tree`+
  `git update-ref` sequence unconditionally bypasses `worktree-edit-guard.sh`'s keyword-based commit
  gating, no TOCTOU sophistication required). Routed back to the spec (rev 3), not fixed at this
  gate directly.
- **Round 2** (rev-4 diff, commit `ff3b7fd`, after human approval of rev 4): `mkr-security-reviewer`
  re-run, independently re-verified its own round-1 finding against live source and returned READY.
  `mkr-code-reviewer` re-run fresh, found 1 blocking — §9's `TC-WGSPEC-01` row asserted `Status` was
  `Pending`/`DRAFT rev 3` while §1/§11 already said `ACCEPTED rev 4`, a stale row never synced when
  `Status` changed. Routed back to the spec (rev 5), which itself introduced the identical desync in
  the opposite direction (caught at G1 by `mkr-spec-reviewer`, not at this gate) before rev 6 closed
  it structurally.
- **Round 3** (this record, rev-6 diff, commit `c2ecd76`, after human approval of rev 6):
  `mkr-code-reviewer` re-run per AD-2 (it had round 2's blocking finding); `mkr-security-reviewer`
  not re-run (its round-2 `READY` scope already covers the lines rev 5/rev 6 touched, and it had no
  blocking finding to re-check). `mkr-code-reviewer` independently confirmed `TC-WGSPEC-01`'s fix is
  durable (stress-tested against a hypothetical future revision — nothing in the row's current text
  needs editing when `Status` changes again) and did a full fresh correctness/reuse/standards/
  simplicity pass, finding no new blocking defect.

## Findings not pursued further

Three non-blocking observations survived across rounds without ever being required to fix:
`§7.1`'s field table attributes `tool_name` to both guards though `worktree-collision-guard.sh`
never reads it (relies on `settings.json`'s matcher instead); `§10`'s AC2/AC4 cite `§4`/`§0` as their
trace anchor rather than `§2`, a labeling nit; and `§13`'s rev-6 row still reads "Pending human G1
approval" even though `§1` now shows it done — acceptable, since `§13` is append-only historical
narrative, not a live fact meant to stay synced (the class of bug this whole chain was about was a
restated *live* fact going stale, not a historical log entry).

## Verification discipline

Every substantive factual claim in the diff (both guards' deny/warn message text, the `MKR_WORKTREE_POLICY`
tiers, the registration-vs-collision distinction, the registry-based anti-spoofing check, the
bootstrap-commit exemption's scoping, the `TC-WG-*` case count, the commit-guard bypass class, and
the ADR's Decision/Consequences) was independently re-verified against live source — `worktree-edit-guard.sh`,
`worktree-collision-guard.sh`, `procwalk.sh`, `config.sh`, `tests/hooks_test.sh` — by at least one
reviewer in at least one round, not accepted on the spec's or design records' own word. The one
finding that did land (`mkr-security-reviewer`'s round-1 bypass-class finding) was itself
independently reproduced by re-reading `procwalk.sh` directly before being accepted as blocking.

## Verdict

VERDICT: READY
