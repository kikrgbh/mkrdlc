# Design review — WorktreeGuard rev 3

**Reviewers.** Two independent fresh agents, re-run per this skill's re-review process (the whole of
§6/§7/§8 is short enough that both reviewers simply re-read it, unlike G4's per-file scoping), each
given the prior round's record (`.mkr/designs/WorktreeGuard-rev2.md`) so it could check whether
anything from that round still held, plus context that this revision was triggered by a G4
security-review finding, not a prior G3 finding.

mkr-design-reviewer: READY
mkr-architecture-reviewer: NOT READY (1)

**Scope.** `specs/WorktreeGuard_Spec.md`, rev 3, §6/§7/§8. Changed since rev 2: §3 corrected (no
longer claims "nothing found... suggests either algorithm is wrong"); §6 gained a new "Discovered
gap 2" paragraph (later labeled "Discovered gap 1"/"Discovered gap 2" in rev 4 for consistent
cross-referencing); new `AC6`/`TC-WGSPEC-07`; `docs/adr/0012-worktree-guard-policy-tiers.md` updated
to match.

Both reviewers independently re-read `.claude/hooks/lib/procwalk.sh` directly and confirmed the new
"Discovered gap 2" content (the `git commit-tree`+`git update-ref` keyword-matching bypass) is a
faithful transcription of that file's own "KNOWN, ACCEPTED SCOPE BOUNDARY" comment, not a
spec-invented claim — this was the central thing rev 3 needed to get right, and both reviewers
verified it independently rather than taking the revision's own word.

## Finding 1 — blocking, confirmed — §7.3/§7.4 don't carry the "Discovered gap 2" caveat §6 introduces

`mkr-architecture-reviewer`: both guard scripts cite `§7.3`/`§7.4` by number as their own contract of
record (not §6) — that is the entire premise §7's own preamble states for why it was renumbered to
match. For "Discovered gap 1" (the advisory-tier asymmetry), §7.4 already carries the caveat forward
explicitly ("...the AD-2/AD-3 asymmetry documented in §6"). For "Discovered gap 2" — the one this
entire revision exists to surface — neither §7.3 nor §7.4 said anything: §7.4 still read "Gates: ...
every real, non-excluded `git commit` occurrence" with no caveat that this is keyword-matched, not
effect-matched, and known-bypassable. Given §2's own stated purpose ("an adopter never needs to open
the spec file, let alone the source"), and specifically why §7 was renumbered to match the scripts'
own citations, an adopter following the header comment's literal pointer into §7.3/§7.4 would get an
incomplete picture of what "gates: every real ... occurrence" actually guarantees. Fixed in rev 4:
both §7.3 and §7.4 now state their respective keyword-matching boundary inline, with an explicit
backlink to §6's now-labeled "Discovered gap 1"/"Discovered gap 2".

## Findings not pursued further

`mkr-design-reviewer`'s two non-blocking rev-3 observations (§6's worked example for the bypass only
covers the commit gate, not checkout/switch; the typo'd-`MKR_WORKTREE_POLICY` silent-fail-open gap
still has no "documented, not fixed" callout) — both are polish items, not defects, and neither
reviewer required a revision on them. Not pursued in rev 4 either; left as future-polish candidates.

**Verdict.** NOT READY (1 blocking)
