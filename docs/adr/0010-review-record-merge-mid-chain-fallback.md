# 0010 — `find_review_record` terminates on any commit provably at-or-behind `expected_prior_tip`

## Status

Accepted

## Context

`docs/adr/0008` named an explicit, accepted-as-out-of-scope limitation: a merge commit landing
*mid-chain* — reached via the bounded docs-only fallback's own recursion, as opposed to being the
top-level `sha` under lookup — still isn't handled. `git diff-tree` reports an empty diff for a
merge commit by default, which the fallback's outside-check reads as "touches something outside the
allowed paths" and refuses, even though the commit immediately behind it (the real review record,
or the merge commit itself) would resolve cleanly on its own.

`docs/adr/0009` (`ReviewRecordAuditPathFallback`) fixed the common shape of the adopter-reported
"`mkr-audit` almost always wastes a CI run" bug — a docs-only trailing commit whose immediate parent
is an ordinary, non-merge commit already covered by a review record. While grounding that fix (phase
9, `mkr-audit` run for real against the merged commit `50e77f4`) and attempting to land its own
grounding-audit record as a trailing commit, the mid-chain-merge gap above was hit directly: the
audit record's immediate parent is `50e77f4` itself — a real merge commit (`mkr-merge`'s own
documented default strategy is a real merge commit, not squash or rebase) — and `find_review_record`
failed closed on it, for the exact reason `docs/adr/0008` named. This is not a rare edge case: every
`mkr-audit` record committed directly after a normal PR merge will have a real merge commit as its
immediate parent, unless the adopter uses squash/rebase merges instead — the gap sits directly on
the primary intended path of `mkr-audit`'s own post-merge hand-off.

## Decision

1. Add a new terminal check, evaluated early in `find_review_record` for any `sha` (top-level or
   reached via recursion): if `expected_prior_tip` is supplied and
   `git merge-base --is-ancestor "$sha" "$expected_prior_tip"` succeeds (git treats a commit as its
   own ancestor, so this covers both exact equality and strict ancestry with one call), treat `sha`
   as already existing, unmodified, before the current push, and succeed **immediately** — print a
   distinct, non-file sentinel string (`(pre-existing, at-or-before <short sha>)`) instead of a
   review-record path, and return 0.
2. **Immediate success, not recursion into `sha`'s first parent.** An earlier draft of the governing
   spec (`specs/ReviewRecordMergeMidChainFallback_Spec.md` rev 1) provisionally proposed recursing
   into `sha`'s first parent, continuing to hunt for a further-back review record. Hand-tracing the
   spec's own flagship scenario against that design at G1 review found it does not actually resolve:
   a merge commit's real review record lives on its **second** parent, which recursing into the
   *first* parent never reaches, since the ancestor-check fires on the merge commit itself (trivially
   true — a commit is its own ancestor) before the pre-existing AD-2/AD-3 shortcut ever gets a chance
   to inspect that second parent. Declaring immediate success is not merely simpler than recursing —
   it is the only one of the two candidates that both fixes the reported bug and preserves the
   "no loophole" guarantee: once `sha` is provably at-or-behind `expected_prior_tip`, nothing
   reachable from it could have been introduced *by the current push* under review — G4's scope is
   "did this push introduce reviewed changes," never a retroactive audit of all of history, so there
   is nothing further for this specific push to demonstrate about `sha` or anything behind it.
3. **Runs instead of the outside-check, for this `sha` specifically, not in addition to it.** The
   outside-check asks "did this commit, newly introduced by the push, touch only safe paths"; the
   ancestor-check asks "did this commit even originate from the current push at all." A commit that
   provably predates the push cannot itself be a vehicle for smuggling new, unreviewed content
   introduced *by* the push — nothing it touches is new relative to what has already been accepted
   onto the branch.
4. **Ordering: exact-match → ancestor-check → AD-2/AD-3 merge-commit shortcut → outside-check.**
   Placing the ancestor-check before AD-2/AD-3 is an ordering/cost optimization (skips the more
   expensive `git merge-tree` call when it isn't needed), not a security-relevant choice: the two
   checks' preconditions are provably, not just empirically, mutually exclusive — AD-2/AD-3 only
   fires when `sha^1 == expected_prior_tip`, which makes `sha` a *child* of `expected_prior_tip`,
   and by git's own DAG acyclicity a commit can never be `--is-ancestor`-true of its own parent.
5. **No new `config.sh` key, no change to `find_review_record`'s documented 4-argument public
   signature.** `git merge-base --is-ancestor` is called directly, using the already-passed `sha`
   and `expected_prior_tip` parameters.
6. **New, additive return-value shape.** On success, the function has always printed a resolved
   review-record path and returned 0. This decision adds a second, distinguishable success shape —
   a sentinel string, never shaped like a real `reviews_dir/<sha>.md` path — for the ancestor-check
   case. Every existing caller (`mkr-gate.yml`, `pre-push-review-guard.sh`) already treats exit code
   as the sole pass/fail signal and just echoes the printed string for a human to read, so this is
   additive, not breaking.

### Why this doesn't create a loophole

`expected_prior_tip` is, unchanged from `docs/adr/0008`'s own AD-3 reasoning, an externally supplied
value the caller obtains from git's own trusted event data (`github.event.before` on `push`; the
real `remote_sha1` from git's pre-push protocol) — never derived from `sha` or anything reachable
from it. This decision does not change how that value is obtained or trusted; it only uses it in one
additional place, in the same direction of trust already established.

`git merge-base --is-ancestor sha expected_prior_tip` can only succeed if `sha` is reachable by
walking *backward* from `expected_prior_tip` through real parent links already present in the git
object database — i.e. `sha` was part of the branch's history *before* this push happened, by the
same immutable-history guarantee the AD-3 exact-equality check already relies on for
`expected_prior_tip` itself. A commit newly created *by* the current push (a fresh fix commit, a
fresh forged commit, or a fresh merge commit) is a *descendant* of `expected_prior_tip`, never an
ancestor of it — `--is-ancestor` returns false for a descendant, so the check cannot fire for
anything the current push actually introduces. Stress-tested by hand, and independently re-derived
(not merely re-checked) at this decision's own G3 design review, against every existing adversarial
shape already on file in `tests/hooks_test.sh` — `TC-RRF-03/11/18`'s "sneaky change riding along"
shapes, and `TC-MRF-04`'s stolen-tree forgery and `TC-MRF-05`'s shared-common-ancestor forgery — in
every case the attacker-controlled `sha` is a descendant of, or diverged from, `expected_prior_tip`,
so the ancestor-check never fires and control correctly falls through to the pre-existing
AD-2/AD-3/outside-check machinery, unchanged.

Same residual risk `docs/adr/0008`/`0009` already named, unchanged in shape by this decision: the
ancestor-check verifies a commit's *position in history*, never its content — it does not
authenticate that whatever the commit contains was itself legitimately reviewed at the time it was
first accepted onto the branch, only that it predates the current push under evaluation. This is the
same trust boundary the exact-match check's own residual-risk note already accepts.

## Consequences

- The reported real scenario (`mkr-audit`'s grounding-audit record, landing directly on top of a
  real merge commit that is itself the branch's real, unmodified prior tip) resolves
  `find_review_record` successfully instead of failing closed on the merge commit's empty
  `git diff-tree`.
- `docs/adr/0008`'s previously-named, accepted-as-out-of-scope mid-chain-merge-commit gap is closed.
- No behavior change for the common case (review-record commit is the fix's immediate child, no
  merge commit involved) — the new behavior is a strict superset of before.
- `find_review_record` now has two distinguishable success shapes (a real record path, or a
  pre-existing-commit sentinel); no existing caller parses the printed string structurally, so this
  is additive, not breaking.
- This repo's own held-back grounding-audit record for `50e77f4` (produced during
  `ReviewRecordAuditPathFallback`'s own ground step, deliberately not committed pending this fix)
  becomes landable.
