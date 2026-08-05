---
name: mkr-merge
description: Runs phase 8's G5 preflight (docs/DESIGN.md §2) - checks a G4 review record exists, that CI is green or its status is explicitly disclosed as unconfirmable, and that the branch's spec is ACCEPTED, then asks the human named by MKR_GATE_MERGE before merging. Never merges unprompted. Use once verify + code-review (phases 6-7) are done and you're ready to land the branch.
---

# mkr-merge — phase 8's G5 preflight

`mkr-merge` never merges on its own judgment — merging to `main` is CLAUDE.md's own example of a
"MUST ASK FIRST" action, a durable, standing instruction this skill does not get to interpret away.
Its job is to gather the evidence a human needs to say yes, state it plainly, and then actually
ask — never to proceed unprompted.

## 1. Resolve the branch

Confirm the current branch is not itself an entry in `MKR_PROTECTED_BRANCHES` (`config.sh get
MKR_PROTECTED_BRANCHES`, CLI mode) — there is nothing to merge from a protected branch into itself.

## 2. G4 check — a review record exists

Compute the branch's HEAD short SHA (the same fixed 7-character convention
`pre-push-review-guard.sh` already uses) and confirm `<MKR_REVIEWS_DIR><short-sha>.md` exists —
re-confirmed locally here, not just trusted from `mkr-gate.yml`'s CI-side check.

**One-level parent fallback** (`.claude/hooks/lib/reviewrecord.sh`): if no
record matches HEAD exactly, and HEAD's own diff touches nothing outside `MKR_REVIEWS_DIR` or
`MKR_SPECS_DIR`, check HEAD's immediate parent instead. This repo's own convention commits a
review record as a separate trailing commit naming the *previous* commit's sha (a commit cannot
contain a file naming its own not-yet-computed hash) — so HEAD itself, the review commit, will
never have a record matching its own sha by construction. Checking the parent is what actually
finds it. Only exactly one level back; do not walk further.

If no review record exists, stop here — do not proceed to step 5 (this includes the parent
fallback above: check both before concluding none exists). State plainly that G4 hasn't run
yet; the fix is `/mkr-code-review`, not this skill.

## 3. G5/CI check — CI is green, or explicitly disclosed as unconfirmable

If `gh` is available, authenticated, and the branch has an open PR: run `gh pr checks` and read the
result.

If CI is not green, stop here — do not proceed to step 5; name which check is failing — unless
*both* of the following hold, checked in this order:

1. **The job never actually executed.** Run `gh run view <run-id> --json jobs` and confirm the
   `gate` job's own `steps` array is empty (`[]`) — meaning the workflow never got past GitHub's
   own platform-level scheduling to run even `actions/checkout`, let alone this repo's configured
   `MKR_TEST`/etc. commands. This is not a formality: once this repo is public, `mkr-gate.yml`'s job
   runs whatever a PR's own `.mkr/config`/test content says, so any
   script that *did* execute — including a fork PR's own — could itself print a misleading
   `::error::` annotation designed to look like a genuine non-code failure. An empty `steps` array
   is the one signal a PR's own code cannot forge, because it means that code never ran. Skip this
   whole branch entirely if `steps` is non-empty — treat the failure as unconfirmed/real and stop,
   full stop, regardless of what the annotation says.
2. **Only once (1) is confirmed**, read the check's own run annotation (`gh run view`) and confirm
   it names a cause unrelated to code correctness (a CI provider account/billing failure, an infra
   outage — not a test, lint, build, or coverage failure).

Only when both hold: name the check, the failure, the empty-`steps` confirmation, and the
annotation's confirmed cause explicitly, and carry that disclosure into step 5's ask the same way
the `gh`-unavailable case below already does — requiring the human to state they accept that
specific, named reason and want to proceed anyway. If the annotation shows a real code-quality
failure, the job's `steps` array is non-empty, or the cause can't be confirmed as non-code, the
stop above still applies — do not proceed to step 5. If CI is green, continue to step 4.

If `gh` is unavailable, unauthenticated, or there's no open PR: this check cannot confirm CI status
mechanically — do not silently assume green.

CI status cannot be mechanically confirmed in this case; carry that disclosure into step 5's ask
instead of treating it as a silent pass.

## 4. Spec check — the branch's spec is `ACCEPTED`

Identify the branch's own spec(s) — the same set `spec-gate.sh` already computes as "added since
the branch's merge-base with a protected branch" — and confirm each carries
`**Status** | ACCEPTED rev N (...)`.

If the branch's spec is not `ACCEPTED`, stop here — do not proceed to step 5; name which spec and
its current `Status` line.

## 5. Conflict check — propose, never auto-resolve (docs/adr/0006)

Dry-run the merge against the target protected branch: `git merge-tree <target> HEAD` (no working
tree or index touched, the same mechanism `reviewrecord.sh`'s own merge-commit verification
already uses elsewhere in this repo). A clean result: continue to step 6. A conflicting result:
stop here — do not proceed to step 6. State which files conflict, summarize what each side
changed in the conflicting hunks, and propose one specific resolution. This is a finding to
report and a fix to propose, not an action to take — never apply a resolution without the human
approving that exact proposal, in this session, as its own explicit decision (approving the merge
in step 6's ask does not also approve a conflict resolution; they are different decisions with
different consequences).

## 6. State findings, then ask

Only once steps 2–5 have all cleared (or step 3's degraded path was taken and disclosed, or step
5's conflict was found, proposed, and separately approved): state all findings plainly — the G4
record's path, the CI result (or the explicit cannot-be-mechanically-confirmed disclosure), the
spec's `ACCEPTED` status, and, if step 5 found a conflict, the approved resolution.

**Ask.** Then ask — never proceed unprompted — naming `MKR_GATE_MERGE`'s resolved value
(`config.sh get MKR_GATE_MERGE`, CLI mode) as the required approver, and require their explicit
go-ahead in this session before step 7. If step 3 took the degraded path, the ask must restate that
CI status could not be mechanically confirmed and require the human to state CI is green themselves
as part of their go-ahead — never silently treated as satisfied.

## 7. Execute the merge

Only after explicit confirmation in this session:

- If `gh` is available: attempt `gh pr merge --merge` first — a real merge commit, not squash or
  rebase, matching this repo's own established practice (specs/M4_Audit_Spec.md §6 AD-2). If GitHub
  rejects it because branch protection's required check hasn't passed, and step 3's non-code-cause
  disclosure already happened and the human already confirmed that specific reason and their
  go-ahead, re-run as `gh pr merge --merge --admin` and say so plainly in the report — the flag is
  the record that an override happened, not a silent retry. Absent that specific prior
  disclosure-and-confirmation, `--admin` is never used.
- Otherwise: `git merge --no-ff` into the target protected branch locally, creating the merge
  commit. **Do not follow it with `git push`** in a repo where `branch-guard.sh` is wired
  (`.claude/settings.json`) — it denies any `git push` targeting a protected branch outright
  (BLOCK tier, CLAUDE.md's own non-negotiable: never disable a guardrail to get past it). Report
  the local merge commit is ready and that pushing it is the human's own action to take, outside
  this skill.

Either way, report the resulting merge commit SHA back to the session.

## 8. Bookkeeping — PR description and linked issues

After a real, pushed merge (the `gh pr merge` path only — the local-merge fallback above has
nothing to update yet, since GitHub never learns about an unpushed commit; say so explicitly
rather than silently skipping this step):

- Confirm the PR body already names the issue(s) this change closes (`Closes #N` / `Fixes #N` /
  `Resolves #N`, cross-checked against the spec's own `§2 Intent` if it names issue numbers there).
  If it does, GitHub closes them automatically on merge — verify with `gh issue view <N>` and
  report which closed. If the linkage was missing, GitHub closes nothing automatically: name the
  issue(s) and close them explicitly (`gh issue close <N> --comment "..."`, citing the merge commit
  SHA), rather than leaving a fixed issue open because the syntax was never there.
- Post a short closing comment on the PR (`gh pr comment`) naming the merge commit SHA, the G4
  review record's path, and the spec that governed the change — the durable pointer from "this PR"
  to "the evidence that justified merging it," for anyone reading the PR later without this
  session's own context.

## 9. Branch cleanup — a separate ask (docs/adr/0006)

Only after step 7's merge actually happened, and — critically — only after it is actually pushed
(never for the local `git merge --no-ff` fallback; deleting the source branch before its merge
commit reaches the remote would strand that commit with nothing pointing at it): ask, as its own
explicit question, separate from step 6's merge approval, whether to delete the now-merged source
branch. A "yes" to merging is never read as a "yes" to deleting the branch too — a human who wants
the merge but wants to keep the branch (a hotfix backport, an audit trail, anything) must say so
by simply not answering yes to this second question. This ask always comes after step 7's merge is
already done, so it is never folded into that same `gh pr merge` call (its own `--delete-branch`
flag is not used here for exactly that reason — using it would mean deleting on an approval this
step hasn't asked for yet). Only on an explicit yes here: delete via `git push origin --delete
<branch>` / `gh api` as appropriate and report it.

## 10. Hand off

State that phase 9 (`mkr-audit`) should run next, against the commit `gh pr merge`/`git merge` just
produced — the loop diagram's own `8 · MERGE → 9 · GROUND` sequence (docs/DESIGN.md §2).
