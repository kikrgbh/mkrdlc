# 0011 — `mkr-gate.yml` sources `EXPECTED_PRIOR_TIP` from `pull_request.base.sha` too

## Status

Accepted

## Context

`docs/adr/0010` (`ReviewRecordMergeMidChainFallback`) added an ancestor-check to
`find_review_record`: a `sha` provably at-or-behind the caller-supplied `expected_prior_tip` (via
`git merge-base --is-ancestor`) terminates the walk immediately, needing no review record of its
own. It works correctly on `push` events, where `mkr-gate.yml` sources `EXPECTED_PRIOR_TIP` from
`github.event.before` — GitHub's own record of the ref's real prior state.

On `pull_request` events, `EXPECTED_PRIOR_TIP` was forced empty. The step's own comment explained
why, as of the code prior to this decision: "the PR head is never expected to itself be a merge
commit this check's second-parent path needs to resolve" — reasonable before `docs/adr/0010`'s
ancestor-check existed, since the only prior consumer of `expected_prior_tip` was the AD-2/AD-3
merge-commit shortcut (`docs/adr/0008`), genuinely rare for an ordinary PR head. The ancestor-check
changes this: it benefits from a real `expected_prior_tip` on *any* commit reached during the walk,
not just a merge-commit `sha` specifically — including a trailing docs-only/audit-only commit whose
immediate parent (one hop into the walk) is a merge commit.

This repo's own `branch-guard.sh` hard-blocks every direct push to `main` — found directly while
attempting to land a grounding-audit record that way. Every change, including a grounding-audit
record, must go through a PR. That makes the `pull_request`-triggered "gate" check the *only* check
that runs before a human is asked to approve the merge (this repo's branch protection treats "gate"
as a required status check). Reported directly from real usage: PR #24 (landing the grounding-audit
record for `50e77f4`) failed its `pull_request`-triggered check for exactly this reason —
`EXPECTED_PRIOR_TIP` empty, so the ancestor-check never got a chance to fire on the trailing
commit's merge-commit parent — even though the identical commit resolves cleanly the moment it's
actually pushed to `main` (verified by hand before that PR was admin-merged past the failing
check). This recurs on every future `mkr-audit` run in this repo without a fix.

## Decision

1. Source `EXPECTED_PRIOR_TIP` from
   `github.event.before || github.event.pull_request.base.sha || ''`. `github.event.before` only
   exists on `push`; `github.event.pull_request.base.sha` only exists on `pull_request`; the two
   are mutually exclusive by event type, so the `||` chain resolves to exactly the right one for
   whichever event triggered the run, empty on anything else (unchanged fallback).
2. **Why `github.event.pull_request.base.sha` is a trust-equivalent anchor to
   `github.event.before`** (the same class of argument `docs/adr/0008`'s AD-3 and `docs/adr/0010`'s
   ancestor-check already received, independently re-derived at this decision's own G1 and G3
   review rounds, not merely asserted):
   - Both are GitHub-computed fields reported in the webhook payload, never derived from the
     commit (`sha`) under evaluation, and never attacker-suppliable by the PR author — a PR's
     author controls what commits they push, not what GitHub reports as the base branch's own
     state.
   - `mkr-gate.yml`'s `pull_request` trigger is scoped to `branches: [main]` — confirmed directly
     against the workflow file, not assumed. `github.event.pull_request.base.sha` in this
     workflow is therefore always GitHub's own recorded tip of the *protected* branch `main`
     itself at the time the PR event fired, never an attacker-influenceable branch.
   - A `base.sha` that is somewhat stale relative to `main`'s actual current tip (e.g. `main`
     advanced between this PR's last synchronize and this specific CI run) does not weaken the
     guarantee — it can only make the ancestor-check *more conservative* (fewer things resolve as
     "provably pre-existing"), never less: a commit genuinely introduced by the current PR is
     still, by construction, a descendant of whatever real point in history `base.sha` names,
     however stale.
   - `find_review_record`'s own use of `expected_prior_tip` (both the AD-2/AD-3 merge-commit
     shortcut and the ancestor-check) never assumes anything about *how* the value was obtained
     beyond "the caller independently knows this to be a real, trusted prior state of the
     protected branch" — both sources satisfy that precondition identically.
3. **Enabling the AD-2/AD-3 merge-commit shortcut on `pull_request` events, not just the
   ancestor-check, is an accepted, deliberate side effect.** Populating `expected_prior_tip` also
   lets a PR whose HEAD is itself a genuine merge commit resolve via that pre-existing, unmodified
   path (tree-equality via `git merge-tree --write-tree`, first-parent-equality) — the same trust
   model already accepted for `push`, now available on `pull_request` for the same underlying
   reason. AD-2/AD-3's own defenses are content-based (tree-equality) and value-based
   (first-parent-equality), not event-type-based, so they transfer without modification; no new
   gap the `push`-only precedent didn't already have to handle.
4. No new `config.sh` key, no change to `find_review_record`'s signature or logic — this is
   entirely a `mkr-gate.yml` env-var sourcing change, plus a documentation-only comment update in
   `reviewrecord.sh` naming the new source alongside the existing two.

## Consequences

- A PR whose head commit is a docs-only/audit-only trailing commit on a merge commit that equals
  or precedes the PR's own `base.sha` resolves `find_review_record` successfully on the
  `pull_request`-triggered check itself, not only on the subsequent `push`-triggered re-check after
  merge — closing the gap this repo's own `branch-guard.sh` + `docs/adr/0010`'s ancestor-check
  otherwise leave open for every future `mkr-audit` PR.
- No behavior change on `push` events.
- A PR whose HEAD is itself a genuine merge commit can now also resolve via the pre-existing
  AD-2/AD-3 shortcut on its own `pull_request` check, not just after merge — an accepted, safe
  widening (§Decision item 3), not a narrowing of what already resolved.
