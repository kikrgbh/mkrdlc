# Review-record merge-mid-chain fallback: `find_review_record` walks past a pre-existing merge commit reached mid-chain

## 0. Triage

```
TRIAGE
depth:    deep
why:      changes find_review_record's published fallback contract again (same class as
          docs/adr/0008, docs/adr/0009, Q3); a security-gate correctness bug that could silently
          block a legitimate post-merge commit for every adopter whose merge convention produces
          real merge commits (this repo's own mkr-merge default), Q4
scope:    one change — let the bounded docs-only fallback walk past a merge commit reached
          mid-chain (not the top-level sha under lookup) when that merge commit is provably
          at-or-behind the caller-supplied expected_prior_tip, recursing into its first parent
          instead of failing closed on git diff-tree's empty-for-merge-commits behavior
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
| **Status** | DRAFT rev 1 — pending kikrgbh G1 approval (spec-only pass; this task was scoped, not implemented, per explicit instruction) |
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
  for any `sha` reached during the docs-only walk (top-level or recursed), that succeeds when `sha`
  is provably at-or-behind the caller-supplied `expected_prior_tip` and continues the walk into
  `sha`'s first parent — closing the mid-chain-merge-commit gap as a side effect, without special-
  casing "is this specifically a merge commit" (see §6).
- `tests/hooks_test.sh` — new test cases (§9) reproducing: the reported real scenario (docs-only
  commit directly on top of a pre-existing merge commit that equals `expected_prior_tip`); the
  broader ancestor case (`expected_prior_tip` several hops ahead of the merge commit reached); the
  no-loophole case (a *new*, unreviewed commit is never mistaken for "pre-existing" merely because
  it shares an old ancestor); the no-anchor case (`expected_prior_tip` unset — no regression from
  today's behavior); and hop-bound interaction (the ancestor-check path still respects
  `_RRF_MAX_CHAIN_HOPS`, no infinite loop, no crash).
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
  the new ancestor-check path still increments and is still bounded by the same counter.
- Retroactively fixing history in any already-affected adopter repo.
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
  existing, unmodified, before the current push** and recurse into `sha`'s first parent
  (`git rev-parse "${sha}^"`, same call already used by the ordinary docs-only path), incrementing
  the same bounded `_hops` counter. This check runs *instead of* the outside-check (§ existing code,
  the `git diff-tree`-based confinement test) for this specific `sha` — not in addition to it —
  because the question being answered is different: the outside-check asks "did this commit, newly
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
  found a record before still finds the same record via the same or a shorter path (the new check
  only ever short-circuits a walk that would otherwise have needed more hops or failed outright on
  a merge commit's empty diff-tree).
- No change to any skill/workflow's own documented contract beyond a stale-comment correction (if
  any is found necessary at implement time, mirroring `docs/adr/0008`'s own `mkr-gate.yml`
  comment-only touch).

## 8. Data model

No data model change. No new `config.sh` key.

## 9. Test-case register

Described here at spec stage (per this task's "scope, don't implement" framing); full working
fixtures to be written test-first at implement time, following this file's own established
`fixture_repo`/`rrf_commit` helper conventions.

- **TC-RRF-21** (new) — the reported real scenario: `base` commit → `feature` branch → real
  `git merge --no-ff` merge commit `M` (second parent has a valid, exact-match review record) →
  a trailing docs-only commit `C` confined to `MKR_AUDITS_DIR` (mirroring `TC-RRF-17`'s shape),
  called with `expected_prior_tip = M`. `find_review_record(C, ...)` resolves successfully
  (via `C`'s outside-check into `M`, then the new ancestor-check on `M` itself, since `M ==
  expected_prior_tip`, recursing into `M`'s first parent and onward to the feature branch's real
  record via the existing merge-commit path... **note for implement time**: since the ancestor-check
  fires on `M` and recurses into `M^1` — the *base*, pre-feature-branch history — not into `M`'s
  second parent, the actual assertion here is simply that the lookup *succeeds without erroring*,
  reflecting "everything at-or-behind `M` needs no further review" rather than re-discovering the
  feature branch's specific record; confirm at implement time this framing is what's actually
  wanted (see §11 Open question).
- **TC-RRF-22** (new) — same shape, but `expected_prior_tip` is a commit *several hops ahead of* the
  merge commit `M` (e.g., `M` itself has a docs-only parent that also predates the push) — proves
  the `--is-ancestor` check, not just direct equality, is what's actually exercised.
- **TC-RRF-23** (new, no-loophole) — a genuinely new, unreviewed fix commit is pushed as a child of
  `expected_prior_tip`, with a docs-only trailing commit on top. `find_review_record` on the
  trailing commit still fails — the ancestor-check must not fire for the new fix commit (it is a
  descendant of `expected_prior_tip`, not an ancestor), and the existing outside-check must still
  refuse it.
- **TC-RRF-24** (new, no-anchor regression check) — the exact TC-RRF-21 shape, but
  `expected_prior_tip` omitted entirely: `find_review_record` still fails exactly as it does today
  (no new implicit trust is introduced when the external anchor isn't available) — mirrors
  `TC-RRF-04`'s own "no anchor, no shortcut" spirit for this specific new path.
- **TC-RRF-25** (new, hop-bound interaction) — the ancestor-check path still respects
  `_RRF_MAX_CHAIN_HOPS`: a chain long enough that walking through several ancestor-check hops would
  exceed the bound fails cleanly (no infinite loop, no crash, no garbage on stdout).
- **Mutation check**: deleting the new `git merge-base --is-ancestor` call (or its `-n
  "$expected_prior_tip"` guard) is caught by TC-RRF-21 (reverts to the reported failure); inverting
  the ancestor direction (checking `expected_prior_tip` is an ancestor of `sha`, the wrong way
  round) is caught by TC-RRF-23 (would then wrongly trust the new fix commit, since a new commit's
  own `expected_prior_tip` argument, if ever mistakenly supplied as an ancestor-direction check,
  could be gamed).

## 10. Acceptance criteria

- The reported real scenario (a docs-only trailing commit landing directly on a pre-existing merge
  commit that equals or precedes the caller-supplied `expected_prior_tip`) resolves
  `find_review_record` successfully.
- TC-RRF-01 through TC-RRF-20 (pre-existing) remain green, unmodified in behavior.
- TC-RRF-21 through TC-RRF-25 (new, per §9) are green.
- `bash tests/hooks_test.sh` and `bash tests/mkr_artifact_test.sh` both exit 0.
- No new `config.sh` key is introduced.
- `find_review_record`'s documented 4-argument public signature is unchanged.
- An ADR exists documenting the ancestor-check decision and its security reasoning.
- `docs/adr/0008`'s Consequences section is updated to note the mid-chain-merge limitation it named
  is now closed, cross-referencing the new ADR.

## 11. Definition of Done

- All §10 acceptance criteria met.
- `mkr-design` (G3) run against this spec's §6/§7/§8, mandatory at Deep depth — with explicit
  instruction to the architecture-lens reviewer to independently re-derive (not just check) the
  "why this doesn't create a loophole" argument in §6, the same way `mkr-architecture-reviewer` did
  for `ReviewRecordAuditPathFallback_Spec.md`.
- `mkr-code-review` (G4) run against the diff; both reviewers READY; review record committed.
- Full test suite green.
- Ground (phase 9) run post-merge, per Deep's mandatory-ground requirement.
- **Open question for design review**: TC-RRF-21 as drafted above notes the ancestor-check, once it
  fires on the merge commit `M`, recurses into `M`'s *first* parent (continuing to hunt for a
  record further back in `M`'s own pre-merge history) rather than declaring immediate, unconditional
  success the moment `M` is confirmed at-or-behind `expected_prior_tip`. Both are defensible:
  recursing preserves the property that *some* real record must eventually be found (or the walk
  legitimately bottoms out at a root commit / the hop bound); declaring immediate success is
  simpler and matches the intuition "everything before this push is already someone else's
  problem," but would make `find_review_record` succeed even for a chain with *zero* real review
  records anywhere in reachable history, provided the walk reaches something old enough — a
  materially different, broader guarantee than any existing behavior. This spec provisionally
  proposes recursing (the more conservative option), but flags it explicitly for G3's independent
  judgment before implementation proceeds, rather than silently picking the broader option.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. spec-first — this document, through G1. **Not yet done**: this pass is scoping only, per
   explicit instruction; G1 approval and everything after it (§12 tasks 2-9 below) await a
   separate "go ahead" from kikrgbh.
2. reuse-check — §5 (done above); re-confirm at implement time nothing landed in the interim.
3. design (G3, mandatory at Deep) — resolve §11's open question first; then `mkr-design` against
   §6/§7/§8.
4. test-first — write TC-RRF-21..25 (`tests/hooks_test.sh`) against the current, unfixed tree;
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
