# Review-record pull_request prior-tip: `mkr-gate.yml` sources `EXPECTED_PRIOR_TIP` on `pull_request` events too

## 0. Triage

```
TRIAGE
depth:    deep
why:      changes the trust-anchor sourcing for a security-relevant CI gate (mkr-gate.yml's G4
          check) — same class as docs/adr/0008/0009/0010, Q3; a correctness gap that hard-blocks
          every PR carrying a trailing docs-only/audit-only commit whose immediate parent is a
          merge commit, in a repo (this one) whose own branch-guard.sh forces all changes,
          including grounding-audit records, through a PR — Q4
scope:    one change — mkr-gate.yml's "Require a G4 review record for this commit" step sources
          EXPECTED_PRIOR_TIP from github.event.pull_request.base.sha on pull_request events
          (currently forced empty there), in addition to the existing github.event.before on push;
          no change to find_review_record itself, which already accepts and correctly uses
          expected_prior_tip regardless of which event supplied it
touches:  .github/workflows/mkr-gate.yml, tests/mkr_artifact_test.sh, a new docs/adr/0011-*.md
risky:    none matched MKR_RISKY_PATHS literally, but same guardrail class as the one entry
          (config.sh) that is listed, and the same file docs/adr/0008/0009/0010 already treated as
          risky
gates:    spec: yes / plan: yes / design: yes / review: yes / ground: yes (mandatory) /
          adr: yes / ship: no
done when: a PR whose head commit is a docs-only/audit-only trailing commit on a merge commit that
          equals the PR's own base.sha resolves find_review_record successfully on the
          pull_request-triggered check itself, not only on the subsequent push-triggered re-check
          after merge; the existing "no loophole" guarantee is independently re-verified for this
          newly-populated trust anchor specifically, not just carried over from the push case
```

## 1. Header

| | |
|---|---|
| **Status** | ACCEPTED rev 3 (kikrgbh, 2026-08-09 — granted via explicit "fix it now" instruction, issued through this session's own `kikrgbh`-authenticated GitHub identity) |
| **Depth** | Deep |
| **Author** | agent |
| **Approver** | kikrgbh |

## 2. Intent

- `docs/adr/0010` (`ReviewRecordMergeMidChainFallback`, merged as `f57afe9`) added an ancestor-check
  to `find_review_record` that lets the bounded fallback terminate immediately on any commit
  provably at-or-behind the caller-supplied `expected_prior_tip`. It works correctly on `push`
  events, where `mkr-gate.yml` sources `EXPECTED_PRIOR_TIP` from `github.event.before` — GitHub's
  own record of the ref's real prior state.
- On `pull_request` events, `EXPECTED_PRIOR_TIP` is currently forced empty. The existing comment
  explains why, as of the code this session found it in: "the PR head is never expected to itself
  be a merge commit this check's second-parent path needs to resolve" — a reasonable assumption
  *before* `docs/adr/0010`'s ancestor-check existed, since the only prior consumer of
  `expected_prior_tip` was the AD-2/AD-3 merge-commit shortcut, genuinely rare for an ordinary PR
  head. `docs/adr/0010`'s ancestor-check changes this: it benefits from a real `expected_prior_tip`
  on *any* commit reached during the walk, not just a merge-commit `sha` specifically — including a
  trailing docs-only/audit-only commit whose immediate parent (reached one hop into the walk) is a
  merge commit.
- This repo's own `branch-guard.sh` hard-blocks every direct push to `main` (found directly, this
  session, attempting to land a grounding-audit record that way) — every change, including a
  grounding-audit record, must go through a PR. That means the `pull_request`-triggered check is
  not a secondary path here; for a grounding-audit record specifically, it is often the *only*
  check that runs before a human is asked to approve the merge, since `mkr-gate.yml` treats "gate"
  as (presumably, per this repo's branch protection) a required status check.
- Reported directly from this session's own real usage: PR #24 (landing the grounding-audit record
  for `50e77f4`, itself produced by `ReviewRecordAuditPathFallback`'s own ground step) failed its
  `pull_request`-triggered "gate" check for exactly this reason — `EXPECTED_PRIOR_TIP` empty on
  `pull_request`, so the ancestor-check never got a chance to fire on the trailing commit's merge-
  commit parent, even though the identical commit resolves cleanly the moment it's actually
  pushed to `main` (verified by hand, `rc=0`, sentinel output, before that PR was admin-merged past
  the failing check). This will recur on every future `mkr-audit` run in this repo unless fixed.

## 3. Scope

**In scope**
- `.github/workflows/mkr-gate.yml` — the "Require a G4 review record for this commit" step's
  `EXPECTED_PRIOR_TIP` env var: source it from `github.event.pull_request.base.sha` on
  `pull_request` events (currently unset there), falling back to the existing `github.event.before`
  on `push`, empty otherwise. Update the step's own stale comment, which currently states
  `EXPECTED_PRIOR_TIP` is "empty on `pull_request`" as a flat fact.
- `tests/mkr_artifact_test.sh` — a new structural test confirming `mkr-gate.yml`'s `EXPECTED_PRIOR_TIP`
  line sources both `github.event.before` and `github.event.pull_request.base.sha` (`TC-GATE-01`,
  the positive half), and that the step's own comment no longer flatly claims it's empty on
  `pull_request` (`TC-GATE-02`, the negative half) — together mirroring `TC-RRF-16`'s existing role
  checking this same file's own comment accuracy, split across two cases since `TC-RRF-16` checks
  both halves in one test and these are cleaner asserted separately.
- `.claude/hooks/lib/reviewrecord.sh`'s own comment (lines ~55-59) enumerating the caller-trusted
  sources of `expected_prior_tip` — updated to also name `github.event.pull_request.base.sha`,
  documentation-only, no logic change (found stale at this spec's own G1 review). Backed by a
  dedicated new test, `TC-GATE-04` (§9) — rev 2 wrongly claimed `TC-RRF-16` already covers this;
  found incorrect at rev 2's own G1 re-check: `TC-RRF-16` (`tests/mkr_artifact_test.sh` lines
  ~1980-1994) is scoped to `mkr-gate.yml`'s own inline comment only and cannot detect staleness in
  `reviewrecord.sh`'s separate comment block.
- A new ADR (`docs/adr/0011-*.md`) documenting the decision, including the security reasoning for
  why `github.event.pull_request.base.sha` is a trust-equivalent anchor to `github.event.before`
  (§6).

**Out of scope**
- Any change to `.claude/hooks/lib/reviewrecord.sh`'s *logic* — `find_review_record` already
  accepts and correctly uses `expected_prior_tip` regardless of which event supplied it; only its
  own comment (above, in scope) needs a documentation-only touch.
- Any change to `pre-push-review-guard.sh` — it already sources its own `expected_prior_tip`
  correctly, from git's real pre-push protocol data (`remote_sha1`), independent of GitHub Actions
  event types entirely.
- Any change to `TARGET_SHA`'s own sourcing (`github.event.pull_request.head.sha || github.sha`) —
  unaffected, already correct (a prior, separate security-review-caught fix, per the step's own
  existing comment).
- Retroactively re-running CI on any already-failed PR — not applicable; this fix changes future
  `pull_request`-triggered runs, not history.

## 4. Affected users & journey change

- Any adopter whose `branch-guard.sh` (or equivalent branch protection) forces every change,
  including a grounding-audit record, through a PR, and who runs `mkr-audit` per its normal
  post-merge hand-off. Journey change: the resulting PR's own `pull_request`-triggered "gate" check
  resolves correctly instead of requiring an admin override, then self-correcting only on the
  subsequent `push`-triggered re-check after merge.
- This repo itself: every future `mkr-audit`-produced PR (this session alone produced two —
  the held-back `50e77f4` record, and this fix's own upcoming `f57afe9` record) resolves on its own
  check.
- No behavior change for `push` events — `EXPECTED_PRIOR_TIP`'s sourcing there is untouched.

## 5. Reuse check

- Checked `find_review_record`'s own contract (`.claude/hooks/lib/reviewrecord.sh`) — no change
  needed; it already accepts `expected_prior_tip` as a generic 4th argument, agnostic to which
  GitHub event produced it. Confirms this is purely a caller-side sourcing fix.
- Checked whether `pre-push-review-guard.sh` has the same gap — no, it doesn't use GitHub Actions
  event context at all; its own `expected_prior_tip` already comes from git's real pre-push
  protocol data unconditionally.
- Checked `docs/adr/0008/0009/0010` for existing precedent on trusting a GitHub-computed event
  field as an anchor — `github.event.before`'s own trust justification (docs/adr/0008 AD-3) is
  reused directly as the template for justifying `github.event.pull_request.base.sha` (§6).

## 6. Architecture & key decisions

- **Source `EXPECTED_PRIOR_TIP` from `github.event.before || github.event.pull_request.base.sha || ''`.**
  `github.event.before` only exists on `push`; `github.event.pull_request.base.sha` only exists on
  `pull_request`; the two are mutually exclusive by event type, so the `||` chain resolves to
  exactly the right one for whichever event triggered the run, empty on anything else (unchanged
  fallback).
- **Why `github.event.pull_request.base.sha` is a trust-equivalent anchor to `github.event.before`
  (the core argument, expected to draw the same adversarial scrutiny `docs/adr/0008`'s AD-3 and
  `docs/adr/0010`'s ancestor-check both already received):**
  - Both are GitHub-computed fields reported in the webhook payload, never derived from the commit
    (`sha`) under evaluation, and never attacker-suppliable by the PR author — a PR's author
    controls what commits they push, not what GitHub reports as the base branch's own state.
  - `github.event.before` answers "what was this ref's real tip immediately before this push";
    `github.event.pull_request.base.sha` answers "what was the base ref's real tip at the moment
    this PR event (open/synchronize/reopen) fired" — structurally the same class of fact (a
    real, immutable, GitHub-attested point in the base branch's history), just keyed to a
    different event shape.
  - `find_review_record`'s own use of `expected_prior_tip` (both the AD-2/AD-3 merge-commit
    shortcut and `docs/adr/0010`'s ancestor-check) never assumes anything about *how* the value was
    obtained beyond "the caller independently knows this to be a real, trusted prior state of the
    protected branch" — both `github.event.before` and `github.event.pull_request.base.sha` satisfy
    that precondition identically.
  - **A `pull_request.base.sha` that is somewhat stale relative to `main`'s actual current tip
    (e.g., `main` advanced between this PR's last synchronize and this specific CI run) does not
    weaken the guarantee** — it can only make the ancestor-check *more conservative* (fewer
    ancestors resolve as "provably pre-existing"), never less: a genuinely new commit introduced by
    the current PR is still, by construction, a descendant of whatever `base.sha` GitHub reports,
    however stale, since the PR's own commits are built on top of *some* real point in `main`'s
    history that predates them.
- **Enabling the AD-2/AD-3 merge-commit shortcut on `pull_request` events, not just the ancestor-
  check, is an accepted, deliberate side effect, not a scope creep.** Before this fix,
  `EXPECTED_PRIOR_TIP` being empty on `pull_request` meant the merge-commit shortcut (`docs/adr/0008`'s
  own AD-2/AD-3) could never fire there either — the original step comment's own reasoning ("the PR
  head is never expected to itself be a merge commit") was an assumption about typical PR shapes in
  this repo, not a security boundary. Populating `expected_prior_tip` now also lets a PR whose HEAD
  is itself a genuine merge commit (e.g. a real `git merge --no-ff` performed within the PR branch)
  resolve via that pre-existing, unmodified path too — the same trust model already accepted for
  `push`, now available on `pull_request` for the same underlying reason.
- **No new `config.sh` key, no change to `find_review_record`'s signature.** This is entirely a
  `mkr-gate.yml` env-var sourcing change.

## 7. Interfaces / contracts

- `mkr-gate.yml`'s `EXPECTED_PRIOR_TIP` env var — widened sourcing, `push` behavior unchanged,
  `pull_request` behavior newly populated instead of forced empty. No change to
  `find_review_record`'s own public contract or logic.
- `.claude/hooks/lib/reviewrecord.sh` — documentation-only touch (§3): its comment enumerating
  `expected_prior_tip`'s trusted sources gains a third entry. No contract or logic change.
- `pre-push-review-guard.sh` — untouched, out of scope (§3).

## 8. Data model

No data model change. No new `config.sh` key.

## 9. Test-case register

- **TC-GATE-01** (new, `tests/mkr_artifact_test.sh`) — structural check: `mkr-gate.yml`'s
  `EXPECTED_PRIOR_TIP` line names both `github.event.before` and
  `github.event.pull_request.base.sha`. Mirrors `TC-RRF-16`'s existing role for this same file.
- **TC-GATE-02** (new, `tests/mkr_artifact_test.sh`) — the step's own comment no longer states flatly
  that `EXPECTED_PRIOR_TIP` is "empty on `pull_request`" — must be updated for accuracy, the same
  class of check `TC-RRF-16` already runs for a different stale claim in this same file.
- **TC-GATE-03** (new, `tests/mkr_artifact_test.sh`) — an ADR exists specifically documenting this
  decision (`find_review_record`/`reviewrecord.sh` or `mkr-gate.yml` named, plus
  `pull_request.base.sha` or `EXPECTED_PRIOR_TIP` named) — found missing at this spec's own G1
  review: §10 asserted an ADR-existence acceptance criterion with no corresponding test, unlike
  every comparable prior decision in this file (`TC-RRF-15`/`19`'s own established pattern, reused
  directly here rather than inventing a new check shape).
- **TC-GATE-04** (new, `tests/mkr_artifact_test.sh`) — `.claude/hooks/lib/reviewrecord.sh`'s own
  comment enumerating trusted sources of `expected_prior_tip` names
  `pull_request.base.sha`/`EXPECTED_PRIOR_TIP`, not just `github.event.before` and
  `pre-push-review-guard.sh`'s `remote_sha1` — found missing at rev 2's own G1 re-check: rev 2
  claimed `TC-RRF-16` already covered this drift, which is false (`TC-RRF-16` is scoped to
  `mkr-gate.yml`'s own comment only, confirmed by reading it directly). Same defect class as
  `TC-GATE-03` above (an acceptance criterion asserted with no backing test), found and fixed one
  revision later, on a different item this same revision itself introduced.
- **Manual/documented verification (not bash-testable — GitHub Actions expression evaluation
  happens outside the shell, per `docs/adr/0008`'s own precedent for `mkr-gate.yml`-level changes
  not needing a `hooks_test.sh`-level fixture):** `find_review_record`'s own existing test suite
  (`TC-RRF-21` through `TC-RRF-26`, `TC-MRF-01..06`) already exhaustively covers every way
  `expected_prior_tip` is consumed once it reaches the function — this fix only changes which
  GitHub event supplies that value, not how it's used, so no new `reviewrecord.sh`-level fixture is
  needed. The real end-to-end proof is `mkr-audit`'s own next PR (this fix's own grounding record)
  resolving on its `pull_request`-triggered check, not just the subsequent `push` re-check — named
  explicitly as this fix's own acceptance criterion (§10) and DoD item (§11).

## 10. Acceptance criteria

- `mkr-gate.yml`'s `EXPECTED_PRIOR_TIP` sources `github.event.pull_request.base.sha` on
  `pull_request` events, `github.event.before` on `push`, unchanged fallback otherwise.
- The step's own comment accurately describes both cases.
- `TC-GATE-01` through `TC-GATE-04` (new) are green; `bash tests/mkr_artifact_test.sh` exits 0.
- No new `config.sh` key; no change to `find_review_record`'s signature or logic (its own comment,
  §3, gets a documentation-only update, backed by `TC-GATE-04`).
- An ADR exists documenting the decision and the trust-equivalence argument (§6), backed by
  `TC-GATE-03`.
- This fix's own grounding-audit record for `f57afe9` (§11 DoD, deferred from
  `ReviewRecordMergeMidChainFallback`'s own ground step) resolves on the `pull_request`-triggered
  check of the PR that lands it — the real, live proof this fix works, not merely a claim.

## 11. Definition of Done

- All §10 acceptance criteria met.
- `mkr-design` (G3) run against this spec's §6/§7/§8, mandatory at Deep depth — with explicit
  instruction to the architecture-lens reviewer to independently re-derive the trust-equivalence
  argument in §6, the same way prior reviewers did for `docs/adr/0008`'s AD-3 and `docs/adr/0010`'s
  ancestor-check, and to specifically consider whether enabling the AD-2/AD-3 merge-commit shortcut
  on `pull_request` events (§6, accepted side effect) opens any gap the push-only precedent didn't
  have to consider.
- `mkr-code-review` (G4) run against the diff; both reviewers READY; review record committed.
- Full test suite green.
- Ground (phase 9) run post-merge, per Deep's mandatory-ground requirement — and, per §10's own
  acceptance criterion, this also finally lands `ReviewRecordMergeMidChainFallback`'s own
  still-outstanding grounding-audit record for `f57afe9`, resolving on its own `pull_request`
  check as this fix's live proof.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. spec-first — this document, through G1.
2. reuse-check — §5 (done above).
3. design (G3, mandatory at Deep) — `mkr-design` against §6/§7/§8.
4. test-first — write `TC-GATE-01` through `TC-GATE-04` against the current, unfixed tree; confirm each
   fails for the expected reason.
5. implement — the `EXPECTED_PRIOR_TIP` sourcing change and comment update in `mkr-gate.yml`, the
   new ADR.
6. self-review — re-read the diff cold against §6-§8 before requesting code-review.
7. verify — full suite green.
8. code-review (G4) — `mkr-code-review`; both reviewers READY; record committed.
9. merge (G5) — `mkr-merge`.
10. ground (phase 9, mandatory for Deep) — `mkr-audit` against this fix's own merge commit; land
    `f57afe9`'s still-outstanding grounding-audit record in the same PR pass, proving §10's live
    acceptance criterion.

## 13. Review history

| rev | reviewer | verdict | notes |
|---|---|---|---|
| 1 | mkr-spec-reviewer (G1) | NOT READY (1 blocking) | Trust-equivalence argument (§6) independently stress-tested and confirmed sound — no way to forge or influence `github.event.pull_request.base.sha`, staleness only narrows the ancestor-check's scope, and the newly-enabled AD-2/AD-3 shortcut on `pull_request` transfers its existing content-based (not event-based) defenses without a new gap. Blocking: §10's "an ADR exists" acceptance criterion had no `TC-GATE-03`-shaped test backing it, unlike this file's own established `TC-RRF-15`/`TC-RRF-19` precedent. Fixed in rev 2 by adding `TC-GATE-03` (§9, §10). Non-blocking, also fixed: `reviewrecord.sh`'s own comment enumerating trusted `expected_prior_tip` sources would go stale once `mkr-gate.yml` gains a third source — moved from out-of-scope to a documentation-only in-scope touch (§3); `TC-GATE-01`'s "mirrors TC-RRF-16" framing clarified as the positive half of a split pair, not a 1:1 mirror. |
| 2 | mkr-spec-reviewer (G1, re-check of rev 2) | NOT READY (1 blocking) | Confirmed `TC-GATE-03` genuinely mirrors `TC-RRF-15`/`19`/`27`'s real pattern (checked `tests/mkr_artifact_test.sh` directly) and would catch a missing ADR. New finding: rev 2's own justification for skipping a dedicated test on the newly-in-scope `reviewrecord.sh` comment update — claiming `TC-RRF-16` already covers it — is factually wrong; `TC-RRF-16` (read directly, `tests/mkr_artifact_test.sh` lines ~1980-1994) is scoped to `mkr-gate.yml`'s own comment only and cannot detect drift in `reviewrecord.sh`'s separate comment block. The same defect class as rev 1's blocking finding (an acceptance criterion asserted with no backing test), recurring one revision later on an item rev 2 itself introduced. Fixed in rev 3 by adding `TC-GATE-04` (§9, §10) and correcting §3's rationale. Non-blocking, also fixed: §7 now names the `reviewrecord.sh` documentation-only touch, which rev 2 had left unmentioned despite §3/§10 referencing it. Confirmed §6's trust-equivalence argument, §5's reuse check, and §3's out-of-scope handlers remain unaffected and sound. |
| 3 | mkr-spec-reviewer (G1, re-check of rev 3) | READY | Confirmed `TC-GATE-04` genuinely distinguishes the stale/updated `reviewrecord.sh` comment (grepped the live file: neither `pull_request` nor `EXPECTED_PRIOR_TIP` appears there today, confirming the test currently fails for the right reason). Confirmed rev 3's factual correction of rev 2's `TC-RRF-16` claim is itself accurate. Full §10↔§9 cross-check across all six acceptance criteria found no orphan criterion and no orphan intent claim. Independently re-derived §6's trust-equivalence argument and found a stronger confirmation than the spec itself states: `mkr-gate.yml`'s `pull_request` trigger is scoped to `branches: [main]`, so `pull_request.base.sha` is always GitHub's own recorded tip of the protected branch itself, never an attacker-influenceable branch. No blocking findings. |
