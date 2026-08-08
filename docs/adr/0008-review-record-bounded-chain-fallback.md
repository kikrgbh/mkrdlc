# 0008 — `find_review_record`'s docs-only fallback recurses through a bounded chain of non-code commits

## Status

Accepted

## Context

`.claude/hooks/lib/reviewrecord.sh`'s `find_review_record()` had a docs-only fallback that walked
exactly one parent commit, and only tolerated that commit's own diff touching `MKR_REVIEWS_DIR` or
`MKR_SPECS_DIR`. Real adopter repos repeatedly hit a false "review record not found" because their
actual commit sequence between a reviewed fix and its trailing review-record commit included an
ADR commit — which lives in `docs/adr/`, outside both allowed directories. The lookup could not
traverse two non-code hops, and even a recursive walk would still have failed the old allowed-path
check on the ADR commit specifically. This was reported directly from a real adopter incident: fix
commit → ADR commit → review-record commit for the fix; `find_review_record` returned "not found"
for a real, valid record two hops back.

## Decision

1. Widen the allowed non-code paths to include `MKR_ADR_DIR` (already a published config default,
   `docs/adr/`) alongside `MKR_REVIEWS_DIR`/`MKR_SPECS_DIR`, read internally via `mkr_get` —
   matching `_reviewrecord_is_ready`'s existing precedent for `MKR_REVIEW_VERDICT_STRING` — rather
   than as a new positional parameter. This keeps `find_review_record`'s documented 4-argument
   public signature unchanged for every existing caller.
2. Make the fallback recursive instead of a single flat parent-check: `find_review_record` calls
   itself on the parent, re-running the exact-match check already at the top of the function for
   free at every hop.
3. Bound the recursion at a fixed constant (`_RRF_MAX_CHAIN_HOPS = 5`), not a new config knob.
   Deliberately: the bound is a safety ceiling against walking arbitrarily far back through
   history, not a per-project preference — unlike `MKR_REVIEW_VERDICT_STRING`, there is no
   legitimate reason a project would want this larger or smaller, and a new config key would touch
   `config.sh` (itself a `MKR_RISKY_PATHS` entry) for no real benefit. A real docs-only chain (an
   ADR, or a few, plus the trailing record commit) is on the order of 1-3 commits; 5 gives headroom
   without being unbounded.
4. A 5th, internal-only positional parameter (`_hops`) carries the recursion depth. It defaults to
   `0`, is never documented as part of the public contract, and no existing caller supplies it.
5. The pre-existing, structurally separate merge-commit path (its own AD-2/AD-3 tree-equality and
   `expected_prior_tip` checks) is left untouched and out of scope. Its own recursive call keeps
   omitting the 5th argument, so it always starts a fresh depth-0 budget; it is independently
   bounded by its own checks, unaffected by this bound.
6. The existing "no loophole" guarantee — any commit whose diff touches something outside the
   allowed paths causes the whole lookup to fail — re-runs at every hop, not just the first. This
   is structurally independent of both the widened path set and the added recursion, so a sneaky
   code change riding along two hops back is refused exactly like one riding along at the first
   hop.

Two things worth naming explicitly, both raised as non-blocking findings during this decision's G3
design review (`.mkr/designs/ReviewRecordChainFallback-rev3.md`):

- The hop-bound ceiling is convention-enforced (an ordinary bash argument), not runtime-enforced
  against a caller supplying an arbitrary `_hops` value. This matches existing precedent in this
  same file — `expected_prior_tip`'s trust also rests on caller discipline — and isn't exploitable
  by the only real caller, `pre-push-review-guard.sh`, which never supplies it.
- `expected_prior_tip` is propagated unchanged through the new docs-only-fallback's own recursive
  calls, unlike the separate merge-commit path's recursive call, which deliberately omits it and
  resets to a fresh budget. Either propagation choice leans over-conservative (a false "not found")
  rather than opening a review-bypass, so this is a contract clarity note, not a live boundary gap.
- A merge commit landing *mid-chain* (as opposed to being the top-level sha under lookup) still
  isn't handled by this fix — `git diff-tree` reports an empty diff for a merge commit by default,
  which the outside-check reads as "touches something outside the allowed paths" and refuses. This
  is a pre-existing limitation of the old single-hop fallback too, not a regression introduced
  here; out of scope for this fix, since real-world reported chains are linear.

Rejected alternative: make the hop bound a new `MKR_*` config key. Rejected because there is no
real per-project reason to tune a safety ceiling, and it would touch `config.sh` — itself a
`MKR_RISKY_PATHS` entry — for no benefit (point 3 above).

## Consequences

- Any adopter whose real commit sequence between a reviewed fix and its review-record commit
  includes up to 5 consecutive genuinely non-code (reviews/specs/ADR-only) commits no longer gets
  a false "review record not found."
- No config surface change — `find_review_record`'s public contract is a strict superset of
  before: anything that resolved before still resolves the same way.
- A chain of more than 5 non-code commits still fails, by design — the bound is a deliberate
  ceiling, not a bug.
- A merge commit landing mid-chain still fails — a known, pre-existing, unaffected gap, not
  addressed by this decision.
- **`.github/workflows/mkr-gate.yml`'s "Require a G4 review record for this commit" CI step — a
  real, hard-blocking (`exit 1`) check on `push`/`pull_request` to `main`, not an advisory WARN —
  already calls this same `find_review_record` and is fixed by this same change, with no code
  change needed there beyond a stale comment. This was found during this fix's own G4 code review
  (`mkr-security-reviewer`): an earlier draft of the governing spec had wrongly scoped CI
  enforcement as "not applicable," when it is in fact the change's most consequential blast
  radius — a false negative here could previously (and, before this fix, sometimes did) hard-block
  a real merge, not just print an advisory warning. `mkr-gate.yml`'s checkout already uses
  `fetch-depth: 0` (full history), so the bounded backward walk added here resolves correctly
  there with no shallow-clone gap.
