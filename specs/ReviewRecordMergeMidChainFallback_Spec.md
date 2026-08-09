# Review-record merge-mid-chain fallback: `find_review_record` walks past a pre-existing merge commit reached mid-chain

## 0. Triage

```
TRIAGE
depth:    deep
why:      changes find_review_record's published fallback contract again (same class as
          docs/adr/0008, docs/adr/0009, Q3); a security-gate correctness bug that could silently
          block a legitimate post-merge commit for every adopter whose merge convention produces
          real merge commits (this repo's own mkr-merge default), Q4
scope:    one change — let the bounded docs-only fallback succeed immediately when it reaches a
          commit (merge or not, mid-chain or top-level) that is provably at-or-behind the
          caller-supplied expected_prior_tip, instead of failing closed on git diff-tree's
          empty-for-merge-commits behavior when that commit happens to be a merge commit
touches:  .claude/hooks/lib/reviewrecord.sh, tests/hooks_test.sh, tests/mkr_artifact_test.sh,
          docs/adr/0008-review-record-bounded-chain-fallback.md (Consequences update — the
          limitation it named is now closed), a new docs/adr/001N-*.md
risky:    none matched MKR_RISKY_PATHS literally, but same guardrail class as the one entry
          (config.sh) that is listed, and the same file docs/adr/0008/0009 already treated as risky
gates:    spec: yes / plan: yes / design: yes / review: yes / ground: yes (mandatory) /
          adr: yes / ship: no
done when: the reported scenario (a docs-only trailing commit — e.g. mkr-audit's own grounding
          record — landing directly on top of a real merge commit that is itself the branch's
          real, unmodified prior tip) resolves find_review_record successfully instead of failing
          closed on the merge commit's empty git diff-tree; the existing "no loophole" guarantee
          (TC-RRF-03/11/18, TC-MRF-03/04/05) still holds, independently re-verified for the new
          ancestor-check path specifically; TC-RRF-01..20 (pre-existing) remain green, unmodified
```

## 1. Header

| | |
|---|---|
| **Status** | DRAFT rev 5 |
| **Depth** | Deep |
| **Author** | agent |
| **Approver** | kikrgbh |

## 2. Intent

- `docs/adr/0008` named an explicit, accepted-as-out-of-scope limitation: "A merge commit landing
  *mid-chain* (as opposed to being the top-level `sha` under lookup) still isn't handled by this
  fix — `git diff-tree` reports an empty diff for a merge commit by default, which the outside-check
  reads as 'touches something outside the allowed paths' and refuses."
- This task (`specs/ReviewRecordAuditPathFallback_Spec.md`, merged as commit `50e77f4`) fixed the
  reported "mkr-audit almost always wastes a CI run" bug for the *common* shape (a docs-only
  trailing commit whose immediate parent is an ordinary, non-merge commit already covered by a
  review record). While grounding that fix (phase 9, `mkr-audit` run for real against the merged
  commit) and attempting to land its own audit record as a trailing commit, the mid-chain-merge gap
  named above was hit directly: the audit record's immediate parent is `50e77f4` itself — a real
  merge commit (this repo's `mkr-merge` skill's default strategy is a real merge commit, not squash
  or rebase) — and `find_review_record` fails closed on it, for the exact reason `docs/adr/0008`
  named.
- This is not a rare edge case for this repo's own real usage: **every** `mkr-audit` record
  committed directly after a normal PR merge (`mkr-merge`'s documented, default hand-off shape,
  `mkr-merge/SKILL.md` step 10) will have a real merge commit as its immediate parent, unless the
  adopter happens to use squash/rebase merges instead. The gap this spec closes sits directly on
  the primary intended path of the very feature (`mkr-audit`'s post-merge grounding record) that
  `ReviewRecordAuditPathFallback_Spec.md` just fixed the CI-blocking behavior for.
- The fix must preserve every existing "no loophole" guarantee: a genuinely new, unreviewed commit
  must never resolve merely because *some* ancestor of it happens to be old. The mechanism proposed
  below (§6) is deliberately scoped to only ever trust a commit that is provably **at-or-behind**
  the externally-supplied `expected_prior_tip` — i.e., already existed, immutably, before the
  current push — never a commit newly introduced by the push under evaluation.

## 3. Scope

**In scope**
- `.claude/hooks/lib/reviewrecord.sh` — `find_review_record`: add a new terminal check, evaluated
  for any `sha` reached during the docs-only walk (top-level or recursed), that succeeds
  **immediately** (prints a sentinel, returns 0 — does not recurse further) when `sha` is provably
  at-or-behind the caller-supplied `expected_prior_tip` — closing the mid-chain-merge-commit gap as
  a side effect, without special-casing "is this specifically a merge commit" (see §6).
- `tests/hooks_test.sh` — new test cases (§9) reproducing: the reported real scenario (docs-only
  commit directly on top of a pre-existing merge commit that equals `expected_prior_tip`); the
  uniformity case (the ancestor-check fires identically for a pre-existing non-merge commit, not
  just a merge commit — §6's "applies uniformly" claim, exercised rather than only asserted); the
  no-loophole case (a *new*, unreviewed commit is never mistaken for "pre-existing" merely because
  it shares an old ancestor); the no-anchor case (`expected_prior_tip` unset — no regression from
  today's behavior); and a sentinel-output-shape check (the new success
  path's printed output can never be mistaken for a real review-record file path).
- `tests/mkr_artifact_test.sh` — a structural check that the new `git merge-base --is-ancestor` (or
  equivalent) call reads no new `config.sh` key, mirroring `TC-RRF-14`'s existing role.
- `docs/adr/0008-review-record-bounded-chain-fallback.md` — Consequences section updated: the
  mid-chain-merge-commit limitation it named is now closed by this decision; cross-referenced, not
  rewritten (the original ADR's own decision stands unchanged).
- A new ADR (`docs/adr/001N-*.md`, next unused number at implement time) documenting this decision,
  including the security reasoning for why the ancestor-check cannot be exploited to smuggle
  unreviewed content (§6).

**Out of scope**
- Any change to the top-level AD-2/AD-3 merge-commit shortcut (§6 of `docs/adr/0008`, the
  `expected_prior_tip == sha^1` + tree-equality path) — untouched; that path already correctly
  handles a *brand-new* merge commit sitting at the top of the push (e.g. a fresh `gh pr merge
  --merge` output). This spec's new check is a separate, additional terminal condition, not a
  modification of that one.
- Any change to `_RRF_MAX_CHAIN_HOPS` or the internal `_hops` bookkeeping parameter's semantics —
  untouched. The new ancestor-check path, resolved to an immediate `return 0` (§6, rev 2), never
  recurses and so never consumes a hop at all; it sits entirely outside the existing bounded walk
  rather than extending it.
- Retroactively fixing history in any already-affected adopter repo — same as `docs/adr/0008`'s
  own precedent (§3 out-of-scope), that remains the adopter's own call to make; not applicable here
  since this fix widens, rather than requires rewriting, what already resolves.
- Landing this repo's own now-unblocked grounding-audit record for commit `50e77f4` (the
  `ReviewRecordAuditPathFallback` change) — that record was independently produced (PASS verdict,
  all 8 ACs verified) during this task's own ground step, but was deliberately left uncommitted
  pending this fix, since pushing it today would trip CI for exactly the reason this spec exists to
  fix. Landing it is this spec's own first real, end-to-end test case once implemented (§12).

## 4. Affected users & journey change

- Any adopter whose merge convention produces a real merge commit (`mkr-merge`'s own documented
  default strategy) and who runs `mkr-audit` per its normal post-merge hand-off. Journey change:
  the grounding-audit record's own trailing commit — landing directly on the merge commit — no
  longer trips `mkr-gate.yml`'s hard-blocking G4 check.
- This repo itself: the `ReviewRecordAuditPathFallback` fix's own grounding-audit record (already
  produced, PASS, currently held back — see §3 out-of-scope) becomes landable once this fix ships.
- No behavior change for the common case (a docs-only trailing commit whose immediate parent is a
  non-merge commit, or a brand-new merge commit sitting at the very top of the push) — this is a
  strict widening, not a narrowing, of what resolves.

## 5. Reuse check

- Checked for an existing ancestor-check helper in `reviewrecord.sh` or `config.sh` — none;
  `git merge-base --is-ancestor` is a standard, already-available git subcommand, no new
  dependency (matches `CLAUDE.md`'s Bash-only stack).
- Checked whether the existing AD-2/AD-3 merge-commit shortcut's own tree-equality/`expected_prior_tip`
  machinery could be reused/extended for the mid-chain case instead of adding a new check — no: that
  path answers a different question ("is this brand-new merge commit an honest merge of its two
  parents, one of which is the real prior tip"), not "does this commit already exist, unmodified,
  from before the push." Reusing it would require faking a synthetic tree-equality comparison
  against nothing, which doesn't fit the shape of the actual fact being established.
- Checked `docs/adr/0008`'s own Consequences section, which already named this exact gap and its
  reasoning — reused directly as this spec's own problem statement (§2) rather than re-deriving it.

## 6. Architecture & key decisions

- **New terminal check, evaluated early in `find_review_record`, for any `sha`** (top-level or
  reached via recursion): if `expected_prior_tip` is supplied and
  `git merge-base --is-ancestor "$sha" "$expected_prior_tip"` succeeds (git treats a commit as its
  own ancestor, so this also covers exact equality with one call), treat `sha` as **already
  existing, unmodified, before the current push** and **succeed immediately** — print a distinct,
  non-file sentinel string (e.g. `(pre-existing, at-or-before <expected_prior_tip's short sha>)`,
  exact wording decided at implement time) instead of a review-record path, and return 0. **This
  resolves §11 rev-1's open question**, settled by tracing the spec's own flagship scenario by hand
  during rev 2 drafting (§13): recursing into `sha`'s first parent, as rev 1 provisionally proposed,
  does not actually resolve that scenario — the real record covering the merge commit's *feature*
  side lives on its **second** parent, which the recursing design never reaches, since the
  ancestor-check fires on the merge commit itself (trivially true — a commit is its own ancestor)
  before the existing AD-2/AD-3 shortcut ever gets a chance to inspect that second parent. Declaring
  immediate success is not merely simpler than recursing, it is the *only* one of the two rev-1
  candidates that actually fixes the reported bug: once `sha` is provably at-or-behind
  `expected_prior_tip`, nothing reachable from it could have been introduced *by the current push*
  under review — G4's scope is "did this push introduce reviewed changes," never a retroactive
  audit of all of history, so there is nothing further for this specific push to demonstrate about
  `sha` or anything behind it. This check runs *instead of* the outside-check (§ existing code, the
  `git diff-tree`-based confinement test) for this specific `sha` — not in addition to it — because
  the question being answered is different: the outside-check asks "did this commit, newly
  introduced by the push, touch only safe paths"; the ancestor-check asks "did this commit even
  originate from the current push at all." A commit that provably predates the push cannot itself be
  a vehicle for smuggling new, unreviewed content introduced *by* the push — nothing it touches is
  new relative to what has already been accepted onto the branch.
- **Why this doesn't create a loophole (the core security argument, expected to draw adversarial
  scrutiny at G3/G4 — deliberately spelled out here for reviewers to independently verify, not just
  assert):**
  - `expected_prior_tip` is, unchanged from `docs/adr/0008`'s own AD-3 reasoning, an externally
    supplied value the caller obtains from git's own trusted event data (`github.event.before` on
    `push`; the real `remote_sha1` from git's pre-push protocol) — never derived from `sha` or
    anything reachable from it. This spec does not change how that value is obtained or trusted; it
    only uses it in one additional place, in the same direction of trust already established.
  - `git merge-base --is-ancestor sha expected_prior_tip` can only succeed if `sha` is reachable by
    walking *backward* from `expected_prior_tip` through real parent links already present in the
    git object database — i.e., `sha` was part of the branch's history *before* this push happened,
    by the same immutable-history guarantee the AD-3 exact-equality check already relies on for
    `expected_prior_tip` itself. A commit newly created *by* the current push (a fresh fix commit, a
    fresh forged commit, or a fresh merge commit) is a *descendant* of `expected_prior_tip`, never an
    ancestor of it — `--is-ancestor` returns false for a descendant, so the check cannot fire for
    anything the current push actually introduces.
  - Concretely stress-tested against every existing adversarial shape this file's tests already
    cover: a genuinely new, unreviewed fix commit sitting as a child of `expected_prior_tip` is
    never itself an ancestor of `expected_prior_tip` (it's the reverse relationship) — the
    ancestor-check does not fire for it, and the existing outside-check/diff-confinement path
    still correctly refuses it exactly as today (see §9 TC-RRF-2x "no loophole" cases, worked
    through by hand in this spec's own drafting before being handed to test-first).
  - This generalizes, rather than replaces, `_reviewrecord_is_ready`'s exact-match short-circuit:
    both are terminal "this needs no further review" conditions, just keyed on different evidence
    (a literal review-record file vs. provable pre-existence relative to an externally-attested
    prior tip).
- **Applies uniformly, not merge-commit-specific.** The check is evaluated for *any* `sha`, not
  gated behind "is this a merge commit" — a non-merge ancestor that happens to equal or precede
  `expected_prior_tip` is handled identically (though in practice it would usually already resolve
  via the ordinary outside-check path first, since a non-merge commit's diff is rarely `git
  diff-tree`-empty). This keeps the fix minimal and avoids a second, parallel special-case branch.
- **Ordering**: exact-match check (unchanged, first) → **new ancestor-check** → existing
  top-level AD-2/AD-3 merge-commit shortcut (unchanged) → existing outside-check +
  diff-confinement recursion (unchanged). Placing the ancestor-check before the AD-2/AD-3 shortcut
  is deliberate: if `sha` already provably predates the push, there is no need to also attempt the
  (more expensive, `merge-tree`-invoking) tree-equality dance — this is purely an ordering/cost
  optimization, not a security-relevant choice, since the AD-2/AD-3 shortcut's own preconditions
  (fresh `sha`, `sha^1 == expected_prior_tip`) essentially never overlap with the ancestor-check's
  precondition (`sha` itself at-or-behind `expected_prior_tip`) in practice.
- **No new `config.sh` key, no change to `find_review_record`'s documented 4-argument public
  signature.** `git merge-base --is-ancestor` is called directly, using the already-passed `sha`
  and `expected_prior_tip` parameters — no new positional argument, no new published default.

## 7. Interfaces / contracts

- `find_review_record <sha> <reviews_dir> <specs_dir> [expected_prior_tip]` — public signature
  unchanged. Behavior widens (strictly more shas now resolve) but never narrows: any case that
  found a record before still finds the same record via the same or a shorter path.
- **New return-value case, additive to the existing contract.** On success, the function has always
  printed a resolved review-record path and returned 0. This spec adds a second, distinguishable
  success shape: when the ancestor-check (§6) fires, the function prints a sentinel string — never
  shaped like a real `reviews_dir/<sha>.md` path (§9 TC-RRF-25) — and returns 0. Every existing
  caller (`mkr-gate.yml`, `pre-push-review-guard.sh`) already treats "exit 0" as the pass condition
  and just echoes the printed string for a human to read; neither parses or pattern-matches it
  structurally, so this is additive, not breaking — but it is a real, new observable output shape
  worth naming explicitly here, not left implicit in §6 alone. Exact sentinel wording decided at
  implement time (§9 TC-RRF-25 constrains its shape, not its exact text).
- No change to any skill/workflow's own documented contract beyond a stale-comment correction (if
  any is found necessary at implement time, mirroring `docs/adr/0008`'s own `mkr-gate.yml`
  comment-only touch).

## 8. Data model

No data model change. No new `config.sh` key.

## 9. Test-case register

Described here at spec stage (per this task's "scope, don't implement" framing); full working
fixtures to be written test-first at implement time, following this file's own established
`fixture_repo`/`rrf_commit` helper conventions.

- **TC-RRF-21** (new) — the reported real scenario, traced by hand against the resolved
  immediate-success design (§6) before being handed to test-first: `base` commit → `feature` branch
  → real `git merge --no-ff` merge commit `M` (second parent carries a valid, exact-match review
  record — present in the fixture to prove the new check doesn't depend on it, not because it's
  needed for resolution) → a trailing docs-only commit `C` confined to `MKR_AUDITS_DIR` (mirroring
  `TC-RRF-17`'s shape), called with `expected_prior_tip = M`. `find_review_record(C, ...)` resolves
  successfully: `C`'s outside-check passes it into `M`; at `M`, the ancestor-check fires (`M` is
  trivially its own ancestor, so `--is-ancestor M M` succeeds) and returns 0 immediately with the
  sentinel string, *without* ever inspecting `M`'s second parent or its review record. Assert
  exit code 0 and that the printed output is the sentinel form (not a `reviews_dir` path) —
  distinguishing this from every other passing `TC-RRF-*` case, which all assert a real file path.
- **TC-RRF-22** (new, rewritten in rev 3, precondition made explicit in rev 4 — see §13) —
  exercises §6's "applies uniformly, not merge-commit-specific" claim end-to-end, rather than
  leaving it backed only by prose: `base` → `feature` → merge `M` (record on `M`'s second parent,
  as in TC-RRF-21) → a further, **also pre-existing** non-merge commit `D` (landed in an earlier
  push, before the one under test — e.g. an old docs commit) → a trailing **new** docs-only commit
  `C`, called with `expected_prior_tip = D` (`D`'s own sha). **`D` must not itself have an
  exact-match record at `reviews_dir/<D's short sha>.md`** — the fixture must construct `D` without
  one (rev 3's drafting omitted stating this explicitly; found at rev-3 G1 re-check, §13). Without
  that precondition, `D`'s own exact-match check (evaluated before the new ancestor-check in every
  case, per §6's stated ordering) could resolve first and the test would silently fail to exercise
  the new check at all — the same defect class as rev 2's original TC-RRF-22 bug, just on a
  different unguarded path. With the precondition explicit: `find_review_record(C, ...)` resolves
  via the ancestor-check firing on `D` itself (trivially its own ancestor) — succeeding without ever
  reaching `M`, `M`'s second parent, or its review record, proving the check is evaluated for *any*
  `sha` reached during the walk, not gated behind "is this specifically a merge commit."
- **TC-RRF-23** (new, no-loophole) — a genuinely new, unreviewed fix commit is pushed as a child of
  `expected_prior_tip`, with a docs-only trailing commit on top. `find_review_record` on the
  trailing commit still fails — the ancestor-check must not fire for the new fix commit (it is a
  descendant of `expected_prior_tip`, not an ancestor), and the existing outside-check must still
  refuse it once reached.
- **TC-RRF-24** (new, no-anchor regression check) — the exact TC-RRF-21 shape, but
  `expected_prior_tip` omitted entirely: `find_review_record` still fails exactly as it does today
  (no new implicit trust is introduced when the external anchor isn't available) — mirrors
  `TC-RRF-04`'s own "no anchor, no shortcut" spirit for this specific new path.
- **TC-RRF-25** (new, sentinel-not-mistaken-for-a-file check) — confirm the sentinel string the
  ancestor-check prints on success can never collide with, or be misread by a caller as, a real
  `reviews_dir/<sha>.md` path — e.g. it lacks the `reviews_dir` prefix entirely and/or carries a
  leading marker no real filename could produce. This matters because `mkr-gate.yml` and
  `pre-push-review-guard.sh` both just print whatever `find_review_record` returns verbatim as
  "the found record" — a sentinel indistinguishable from a path would be misleading, not incorrect
  (exit code is still correctly 0), but should be legible to a human reading CI output. (Rev 1's
  hop-bound interaction case is dropped in rev 2: the immediate-success design consumes zero
  additional hops when it fires — there is nothing left to bound.)
- **TC-RRF-26** (new, rev 4; `base`'s own missing precondition closed in rev 5 — see §13) — the
  ancestor-check firing on a **strict, non-equal** ancestor of `expected_prior_tip`, reached via the
  *existing, pre-existing* AD-2/AD-3 second-parent recursion combined with the bounded docs-chain
  fallback — not a shape this spec's own new code introduces, but a genuinely realistic one the
  rev-3 G1 re-check constructed by hand and this rev adopts as a real test rather than arguing it
  away. Fixture: an early commit `base` (**no exact-match record of its own** — same precondition
  discipline as `D`/`F`, made explicit here after rev-4's own G1 re-check found it missing exactly
  here, the one place in this fixture needing it most); a further commit `X` on `base`'s own line
  (`X` becomes `expected_prior_tip` — the real, correct immediate prior tip of the push under test);
  a `feature` branch forked from `base` (**not** from `X`), **exactly one docs-only commit** `F`
  (single-commit, not "commits," to remove any ambiguity about further intermediate commits'
  own record-freedom — rev 4's plural wording was itself imprecise, per the rev-4 G1 re-check),
  with no exact-match record of its own; a real `git merge --no-ff` merge commit `M2` merging
  `feature` into `X` (`M2^1 = X`, `M2^2 = F`). Called as `find_review_record(M2, ...,
  expected_prior_tip = X)`: the ancestor-check on `M2` itself correctly does not fire (`M2` is `X`'s
  descendant, not ancestor); the AD-2/AD-3 shortcut fires (`M2^1 == X`, tree-equality holds for an
  honest merge) and recurses into `F` with a fresh hop budget (existing, unmodified behavior,
  `docs/adr/0008`); at `F`, exact-match fails (by construction) and the *new* ancestor-check
  `is-ancestor(F, X)` also fails (`F` is on the diverged `feature` line, not reachable from `X`);
  the existing outside-check passes (`F`'s diff is docs-only) and recurses into `F`'s parent, `base`
  (unmodified existing behavior, one hop, unambiguous since `F` is `feature`'s only commit); at
  `base`, exact-match fails (precondition now explicit above) and the new ancestor-check
  `is-ancestor(base, X)` **succeeds non-trivially** — `base` is a genuine ancestor of `X`, not equal
  to it — firing the sentinel/`return 0` path. Assert exit 0 and sentinel output, proving the
  check's `--is-ancestor` call is exercised in its non-equal form by a concrete, buildable fixture,
  not merely argued to be unnecessary.
- **Mutation check**: deleting the new `git merge-base --is-ancestor` call (or its `-n
  "$expected_prior_tip"` guard) is caught by TC-RRF-21 (reverts to the reported failure); inverting
  the ancestor direction (checking `expected_prior_tip` is an ancestor of `sha`, the wrong way
  round) is caught by TC-RRF-23 (would then wrongly trust the new fix commit) and by TC-RRF-26
  (which specifically requires the non-inverted direction — `base` really is an ancestor of `X`,
  not the reverse — to resolve at all); changing the immediate-`return 0` into a recursion into
  `sha`'s first parent (reverting to rev 1's rejected design) is caught by TC-RRF-21 itself, which —
  per the hand-traced fixture — only resolves under the immediate-success design and fails under
  the recursing one.

## 10. Acceptance criteria

- The reported real scenario (a docs-only trailing commit landing directly on a pre-existing merge
  commit that equals or precedes the caller-supplied `expected_prior_tip`) resolves
  `find_review_record` successfully.
- TC-RRF-01 through TC-RRF-20 (pre-existing) remain green, unmodified in behavior.
- TC-RRF-21 through TC-RRF-26 (new, per §9) are green.
- `bash tests/hooks_test.sh` and `bash tests/mkr_artifact_test.sh` both exit 0.
- No new `config.sh` key is introduced.
- `find_review_record`'s documented 4-argument public signature is unchanged.
- An ADR exists documenting the ancestor-check decision, its security reasoning, and the
  recurse-vs-immediate-success resolution (§6, §13 rev 2).
- `docs/adr/0008`'s Consequences section is updated to note the mid-chain-merge limitation it named
  is now closed, cross-referencing the new ADR.

## 11. Definition of Done

- All §10 acceptance criteria met.
- `mkr-design` (G3) run against this spec's §6/§7/§8, mandatory at Deep depth — with explicit
  instruction to the architecture-lens reviewer to independently re-derive (not just check) the
  "why this doesn't create a loophole" argument in §6, the same way `mkr-architecture-reviewer` did
  for `ReviewRecordAuditPathFallback_Spec.md`, and to independently re-trace TC-RRF-21's fixture
  against the resolved immediate-success design (§13 rev 2) rather than taking rev 2's own trace on
  faith.
- `mkr-code-review` (G4) run against the diff; both reviewers READY; review record committed.
- Full test suite green.
- Ground (phase 9) run post-merge, per Deep's mandatory-ground requirement.
- **Resolved in rev 2 (was rev 1's open question)**: does the ancestor-check, once it fires,
  recurse into `sha`'s first parent hunting for a further-back record, or declare immediate
  success? Rev 1 provisionally proposed recursing; `mkr-spec-reviewer`'s rev-1 G1 review hand-traced
  TC-RRF-21's own fixture against that design and found it does not actually resolve the spec's
  flagship scenario (the real record lives on the merge commit's *second* parent, never reached by
  recursing into its *first*). Rev 2 adopts immediate success instead (§6, §7, §9) — the only one of
  the two candidates that both fixes the reported bug and preserves the "no loophole" guarantee,
  per the resolved reasoning in §6.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. spec-first — this document, through G1. **Not yet done**: this pass is scoping only, per
   explicit instruction; G1 approval and everything after it (§12 tasks 2-9 below) await a
   separate "go ahead" from kikrgbh.
2. reuse-check — §5 (done above); re-confirm at implement time nothing landed in the interim.
3. design (G3, mandatory at Deep) — resolve §11's open question first; then `mkr-design` against
   §6/§7/§8.
4. test-first — write TC-RRF-21..26 (`tests/hooks_test.sh`) against the current, unfixed tree;
   confirm each fails for the expected reason.
5. implement — the `git merge-base --is-ancestor` check in `reviewrecord.sh`, the `docs/adr/0008`
   Consequences update, and the new ADR.
6. self-review — re-read the diff cold against §6-§8 before requesting code-review.
7. verify — full suite green.
8. code-review (G4) — `mkr-code-review`; both reviewers READY; record committed.
9. merge (G5) — `mkr-merge`.
10. ground (phase 9, mandatory for Deep) — `mkr-audit`; this also finally unblocks landing this
    repo's own already-produced, currently-held-back `50e77f4` grounding-audit record (§3
    out-of-scope note) as this fix's first real end-to-end validation.

## 13. Review history

| rev | reviewer | verdict | notes |
|---|---|---|---|
| 1 | mkr-spec-reviewer (G1) | NOT READY (1 blocking) | §6/§9/§10/§11: rev 1's provisionally-proposed "recurse into `sha`'s first parent" design, traced by hand against TC-RRF-21's own fixture (`base → feature → merge M with the real record on M's second parent → trailing commit C`, `expected_prior_tip=M`), does not actually resolve — the ancestor-check fires on `M` itself (trivially its own ancestor) and recurses into `M^1`, the pre-feature-branch base history, never reaching `M^2` where the real record lives; `find_review_record` returns 1, contradicting §10's own first acceptance criterion. Fixed in rev 2 by resolving §11's open question in favor of immediate success instead of recursing (§6), rewriting TC-RRF-21/22 to assert the correct outcome (exit 0, sentinel output, no second-parent inspection), dropping the now-inapplicable hop-bound case (TC-RRF-25 replaced with a sentinel-shape check), and adding an explicit new-return-value-shape note to §7. Independently re-verified: the security argument in §6 (why a genuinely new commit can never satisfy the ancestor-check) was checked by the reviewer against `TC-RRF-03/11/18`/`TC-MRF-03/04/05` and confirmed sound — unaffected by this fix, carried forward unchanged into rev 2. Non-blocking, also fixed: §3's "retroactively fixing history" bullet now names `docs/adr/0008`'s own precedent as its handler; §1's `Status` line simplified to the bare `DRAFT rev N` shape. |
| 2 | mkr-spec-reviewer (G1, re-check of rev 2) | NOT READY (1 blocking) | Independently hand-traced TC-RRF-21 against the resolved immediate-success design and confirmed it genuinely resolves (exact-match → ancestor-check fires trivially on `M` → sentinel, `return 0`, never reaching `M^2`) — rev 1's fix is real, not just claimed. Independently re-derived the §6 security argument under immediate-success specifically (not just carried over from rev 1) and found no counterexample. New finding: TC-RRF-22 as drafted in rev 2 was internally contradictory (described `expected_prior_tip` as both "ahead of `M`" and "`M`'s own further parent," opposite directions) and, hand-traced as literally written, never exercised the new ancestor-check at all — `--is-ancestor M P` (`P` = `M`'s parent) correctly fails, so execution instead fell into the *pre-existing* AD-2/AD-3 merge shortcut (since `P` happened to equal `M^1` by the fixture's own construction) and returned a real file path, not the sentinel TC-RRF-22 asserted. Fixed in rev 3 by replacing TC-RRF-22 with a fixture that actually exercises a distinct, meaningful case — §6's "applies uniformly, not merge-commit-specific" claim, via a pre-existing *non-merge* commit `D` sitting ahead of `M` — and by noting explicitly (rev 3's own TC-RRF-22 text) that a genuine "proper ancestor, not equal" case doesn't arise from any real caller's legitimate `expected_prior_tip` sourcing (always the ref's true immediate prior tip), so forcing one was the rev-2 fixture's underlying mistake, not just a labeling slip. Confirmed rev-1's two non-blocking findings were genuinely addressed, not just claimed. |
| 3 | mkr-spec-reviewer (G1, re-check of rev 3) | NOT READY (2 blocking) | Confirmed TC-RRF-21 still traces correctly and rev 3's edits didn't disturb it; confirmed no stray references to the rejected recursing design or the old broken TC-RRF-22 framing survive outside proper historical context. Two new findings, both in the rewritten TC-RRF-22: (1) the fixture never states `D` lacks its own exact-match record — since `D` is described as an ordinary pre-existing docs commit, exactly what the pre-existing exact-match check is designed to resolve, the fixture as drafted wasn't guaranteed to reach the new ancestor-check at all, the same silent-fall-through defect class as rev 2's bug, just relocated to a different unguarded path; (2) rev 3's own justification for not testing a genuine "proper ancestor, not equal" case — that it "doesn't arise from any real caller's legitimate `expected_prior_tip` sourcing" — conflates how `expected_prior_tip` is *sourced* (independently re-verified correct against the real `mkr-gate.yml`/`pre-push-review-guard.sh` callers) with what `sha` the recursive walk can *reach*; the reviewer hand-constructed a fully realistic counterexample using the pre-existing, unmodified AD-2/AD-3 second-parent recursion into an all-docs feature branch, reaching a genuine strict ancestor of a realistic `expected_prior_tip`. Fixed in rev 4: TC-RRF-22 now states the "`D` has no own record" precondition explicitly; the retracted "never arises" claim is replaced with `TC-RRF-26`, a new test built directly from the reviewer's own hand-constructed counterexample (`base` → `X` (= `expected_prior_tip`) on one line, `feature` (forked from `base`, docs-only, tip `F`, no own record) merged into `X` as `M2` via the existing AD-2/AD-3 path, recursing through `F` into `base` via the existing docs-chain fallback, where the new ancestor-check fires non-trivially) — proving the non-equal case by construction rather than arguing it away. |
| 4 | mkr-spec-reviewer (G1, re-check of rev 4) | NOT READY (1 blocking) | Confirmed TC-RRF-22 now genuinely holds (D's precondition closes the exact rev-3 gap). Hand-traced TC-RRF-26 in full, step by step (exact-match/ancestor-check at M2, AD-2/AD-3 firing into F with a fresh hop budget, F's own checks, recursion into base) and confirmed every step except the last: the fixture states `D`/`F` must lack their own exact-match records but never states this for `base` — the one commit the test's entire non-trivial ancestor-check assertion actually hinges on. Since the exact-match check runs before the new ancestor-check for every sha (§6's own ordering), a `base` constructed with its own record (or naturally planted one, per this file's own `TC-RRF-01`-style convention) would resolve via the ordinary exact-match path and never exercise the new check — the identical silent-fall-through defect class rev 3 found in `D`, now recurring one commit further back in the same fixture rev 4 itself wrote. Also flagged: `feature`'s "docs-only commits" (plural) left the hop count to `base` ambiguous. Fixed in rev 5: `base`'s own "no own record" precondition made explicit (the missing piece, closing this fixture's actual chain of preconditions completely — `F` and `base` both now stated, matching TC-RRF-22's own `D`); `feature` narrowed to exactly one commit `F`, removing the intermediate-commit ambiguity entirely rather than stating a precondition for commits that no longer exist in the fixture. |
