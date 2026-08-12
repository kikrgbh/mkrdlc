# Design review — WorktreeGuard rev 4

**Reviewers.** Two independent fresh agents, re-run per this skill's re-review process, each given
the rev-3 record (`.mkr/designs/WorktreeGuard-rev3.md`) so it could check whether its own (or the
other reviewer's) prior finding was actually addressed, not assumed from the new revision's own
claim that it was.

mkr-design-reviewer: READY
mkr-architecture-reviewer: READY

**Scope.** `specs/WorktreeGuard_Spec.md`, rev 4, §6/§7/§8. Changed since rev 3: §7.3 and §7.4 each
now state their respective keyword-matching boundary inline with an explicit backlink to §6; §6's
original gap paragraph is now explicitly labeled "Discovered gap 1" for consistent
cross-referencing with "Discovered gap 2"; §3's out-of-scope bullet widened to cover both guards.

Both reviewers independently re-verified `mkr-architecture-reviewer`'s rev-3 blocking finding is
genuinely fixed — read the current §7.3/§7.4 text directly and confirmed an adopter following either
guard script's own header citation straight into those subsections would now learn, at the "Gates:"
clause itself, that the match is keyword-based and would be pointed at the concrete bypass. Both also
did a fresh full pass over §6/§7/§8 (AD-1..AD-5, target-resolution precedence, `.claude/settings.json`
wiring, the live `TC-WG-*` count) with no drift found against current source.

**Findings not pursued further** — Two non-blocking observations were raised (§7.1's field table
attributes `tool_name` to both guards though `worktree-collision-guard.sh` never reads it, relying on
`settings.json`'s matcher instead; §7.4's resolution description doesn't restate the
`procwalk_resolve_target_dirs` precedence already given in §7.1/§7.3, though the two converge in
practice) plus two carried-over non-blocking items from rev 3 (asymmetric worked example; the
typo'd-policy-value silent-fail-open gap has no dedicated callout). None required a fix. One reviewer
claim was independently checked and found inaccurate, not carried forward: `mkr-design-reviewer`
stated `docs/adr/0012-worktree-guard-policy-tiers.md` "does not yet exist on disk" — verified false
(`ls`/`git log` both confirm it exists, committed in `3217c3a`, updated in `46854ee`); the file's
existence was likely checked from a stale or wrong working directory. Does not affect the verdict.

**Verdict.** READY
