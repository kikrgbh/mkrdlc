# Review-record chain fallback: `find_review_record` walks a bounded chain of non-code commits

## 0. Triage

```
TRIAGE
depth:    deep
why:      changes find_review_record's published fallback contract (Q3); a security-gate
          correctness bug that could silently widen what counts as "reviewed" for every adopter,
          not just this repo (Q4)
scope:    one change — recurse the docs-only fallback through a bounded chain of genuinely
          non-code commits, and recognize MKR_ADR_DIR as an allowed non-code path alongside
          reviews_dir/specs_dir
touches:  .claude/hooks/lib/reviewrecord.sh, tests/hooks_test.sh (TC-RRF-*)
risky:    none matched MKR_RISKY_PATHS literally, but same guardrail class as the one entry
          (config.sh) that is listed
gates:    spec: yes / plan: yes / design: yes / review: yes / ground: yes (mandatory) /
          adr: yes / ship: no
done when: TC-RRF-06+ (new cases: fix -> ADR -> record chain, and a chain long enough to prove
          the recursion is still bounded, not unbounded) pass, TC-RRF-03's "no loophole" guarantee
          still holds under adversarial review, and the reported adopter scenario
          (fix -> ADR -> review-record commit) resolves to the real record
```

## 1. Header

| | |
|---|---|
| **Status** | DRAFT rev 3 |
| **Depth** | Deep |
| **Author** | agent |
| **Approver** | kikrgbh |

## 2. Intent

- Adopter repos of mkr-aidlc have repeatedly hit a false "review record not found" from
  `find_review_record()` (`.claude/hooks/lib/reviewrecord.sh`) whenever any docs-only commit other
  than the review record itself — most commonly an ADR — lands between a reviewed fix and its
  trailing review-record commit. This was directly reported and reproduced from a real adopter
  incident: fix commit → ADR commit → review-record commit for the fix; `find_review_record` on
  HEAD returned "not found" even though a real, valid record existed two hops back.
- The G4 lookup needs to trace through a short, bounded chain of genuinely non-code commits — not
  just exactly one — and needs to recognize `MKR_ADR_DIR` as an allowed non-code path alongside
  `MKR_REVIEWS_DIR`/`MKR_SPECS_DIR`, so a real review that happened is found instead of reported
  missing.
- The fix must not weaken the existing "no loophole" guarantee (TC-RRF-03): a commit whose diff
  carries any change outside the allowed paths must still cause the whole lookup to fail at that
  point — widening the chain must never become a way for unreviewed code to read as reviewed.
- `find_review_record`'s documented 4-argument public signature, and `config.sh`'s existing key
  set, are both load-bearing for every current caller and adopter — the fix must land as a
  behavior widening only, never as a contract or config-surface change, so nothing consuming
  either has to be touched to pick up the fix.

## 3. Scope

**In scope**
- `.claude/hooks/lib/reviewrecord.sh` — `find_review_record`'s docs-only fallback (currently lines
  ~119-137): widen the allowed-path check to include `MKR_ADR_DIR`, and make the walk recurse
  through a small, bounded number of consecutive non-code commits instead of stopping after
  exactly one parent.
- `tests/hooks_test.sh` — new `TC-RRF-06`, `TC-RRF-09` through `TC-RRF-13` (§9; `TC-RRF-08`,
  already in this file, is pre-existing and unrelated, not renumbered) covering the chained
  scenario, the exact-bound boundary case, the wider allowed-path, the still-refused
  sneaky-change-mid-chain case, and the bound-exceeded case.
- `tests/mkr_artifact_test.sh` — new `TC-RRF-14`, `TC-RRF-15` (§9; `TC-RRF-07`, already in this
  file, is pre-existing and unrelated, not renumbered) covering the "no new `config.sh` key" and
  "ADR exists and documents the bound" acceptance criteria (§10) — this is the structural/doc-check
  file, matching `TC-RRF-07`'s own existing role checking `mkr-merge/SKILL.md`'s prose.
- `.claude/skills/mkr-merge/SKILL.md` step 2 — wording update: today it says "One-level parent
  fallback... Only exactly one level back; do not walk further," which becomes false once this
  ships. Update to describe the bounded chain accurately; keep the word "parent" present so
  `TC-RRF-07` (`tests/mkr_artifact_test.sh`) keeps passing.
- `.claude/hooks/scripts/pre-push-review-guard.sh` — WARN message wording ("checked %s/%s.md and,
  if applicable, its parent") updated for accuracy; stays a WARN, never becomes a blocking exit.
- An ADR (`docs/adr/000N-*.md`, next unused number at implement time) documenting the bounded-chain
  decision and the chosen hop limit.

**Out of scope**
- The merge-commit AD-2/AD-3 recursive path (currently lines ~66-112) — untouched. Its own
  recursive call keeps omitting the new internal recursion-depth argument, so it always starts a
  fresh budget; it is independently bounded by its own tree-equality/`expected_prior_tip` checks.
- CI hard-enforcement of the review-record check — not applicable to this fix; this stays the
  WARN-only local hook, unrelated to this change, no future spec named for it here.
- Any change to `MKR_REVIEW_VERDICT_STRING` or the review-record file's own required shape — not
  applicable to this fix; both are orthogonal to the fallback-walk logic being changed here.
- Retroactively fixing history in any already-affected adopter repo — that is the adopter's own
  call to make (this spec does not take a position on it beyond what already went into the
  incident report).

## 4. Affected users & journey change

- Any adopter of the mkr-aidlc template whose real commit sequence between a reviewed fix and its
  review-record commit includes an ADR or another genuinely docs-only commit. Journey change:
  `git push` no longer produces a false WARN for that sequence; `mkr-merge`'s G4 check no longer
  falsely reports "G4 hasn't run" for a fix that was, in fact, reviewed.
- No behavior change for the common case (review-record commit is the fix's immediate child) —
  the new behavior is a strict superset of today's; nothing that resolved before stops resolving.

## 5. Reuse check

- Checked `.claude/hooks/lib/reviewrecord.sh` for an existing multi-hop or bounded-recursion
  helper — none exists. The only recursion in the file today is the separate, structurally
  unrelated merge-commit AD-2/AD-3 path.
- Checked `config.sh` for an existing "allowed non-code paths" list beyond the two positional
  arguments (`reviews_dir`, `specs_dir`) already accepted by `find_review_record` — none.
  `MKR_ADR_DIR` already exists as a published default (`docs/adr/`, `config.sh` line ~95) and is
  reused as-is rather than inventing a new config key.
- Checked `_reviewrecord_is_ready`'s own precedent for reading a config value directly inside a lib
  function via `mkr_get` rather than requiring the caller to pass it in as a parameter (it already
  does this for `MKR_REVIEW_VERDICT_STRING`) — followed the same pattern for `MKR_ADR_DIR`, which
  keeps `find_review_record`'s documented 4-argument public contract unchanged.

## 6. Architecture & key decisions

- **Read `MKR_ADR_DIR` internally via `mkr_get`, not as a new positional parameter.** Matches
  `_reviewrecord_is_ready`'s existing precedent and keeps `find_review_record`'s documented
  4-argument signature (`<sha> <reviews_dir> <specs_dir> [expected_prior_tip]`) unchanged for every
  existing caller (`pre-push-review-guard.sh`, every existing test call site) — none of them need
  to change their call.
- **Recursion, not iteration, for the docs-only fallback.** `find_review_record` calls itself on
  the parent commit instead of doing one flat parent-check, so the exact-match check already at
  the top of the function is re-run at every hop for free — a hop's parent might itself be an
  exact match, not just another docs-only commit to walk past.
- **A 5th, internal-only parameter carries the recursion depth.** It is never documented as part
  of the public contract, defaults to `0` when omitted, so no existing caller needs to change.
  Only `find_review_record`'s own recursive call for this path ever supplies it.
- **Bounded at a fixed constant, not a new config knob.** The bound is a safety ceiling against
  walking arbitrarily far back through history, not a per-project preference — unlike
  `MKR_REVIEW_VERDICT_STRING`, there is no legitimate reason a project would want this larger or
  smaller, and a new key here would touch `config.sh` (itself a `MKR_RISKY_PATHS` entry) for no
  real benefit. Chosen bound: **5 hops**. The walk only ever passes through the three allowed
  path types (a spec-doc commit under `specs_dir`, an ADR under `MKR_ADR_DIR`, or the trailing
  review-record commit under `reviews_dir` itself) before reaching the reviewed fix's own
  exact-match commit — a real chain shaped like this is on the order of 1-3 such commits; 5 gives
  headroom without being unbounded. (A design or plan record chronologically precedes the fix, so
  it is never itself a hop in this *backward* walk from record to fix — not part of the bound's
  rationale.) Documented inline next to the constant at implement time.
- **The merge-commit AD-2/AD-3 recursive call is left exactly as-is** — it keeps omitting the new
  5th argument, so it always starts a fresh depth-0 budget for whatever it resolves on the second
  parent. That path is out of scope and must not regress (§9).
- **The outside-check (TC-RRF-03's "no loophole" guarantee) runs before any recursion decision, at
  every hop.** A commit whose diff touches anything outside `reviews_dir`/`specs_dir`/
  `MKR_ADR_DIR` returns 1 immediately, exactly as today. Widening the allowed-path set and adding
  recursion are structurally independent of that guarantee — every hop re-checks it fresh, not
  just the first, so a sneaky change riding along at hop 3 is refused exactly like one at hop 1.

## 7. Interfaces / contracts

- `find_review_record <sha> <reviews_dir> <specs_dir> [expected_prior_tip]` — **public signature
  unchanged.** Behavior widens (strictly more shas now resolve to a record) but never narrows: any
  case that found a record before still finds the same record via the same or a shorter path. A
  5th positional argument is reserved for internal recursion bookkeeping; no caller may supply it.
- `pre-push-review-guard.sh`'s WARN text updates from "...and, if applicable, its parent" to
  reflect that more than one ancestor may now be checked. Exact wording decided at implement time;
  it must stay a WARN and must never escalate to a blocking exit (unchanged posture).
- `.claude/skills/mkr-merge/SKILL.md` step 2 — prose-only update. Still names "parent" (keeps
  `TC-RRF-07` passing as written), but stops claiming exactly one level and describes the bound.

## 8. Data model

No data model change.

## 9. Test-case register

- **TC-RRF-01..05** (existing) — must stay green, unmodified. They are the exact-match,
  two-directory, no-loophole, no-record-at-either-level, and root-commit cases; all remain valid
  subsets of the new behavior by construction.
**ID assignment note:** `TC-RRF-06` is unused and free. `TC-RRF-07` (`mkr-merge/SKILL.md` wording,
in `tests/mkr_artifact_test.sh` ~line 1937) and `TC-RRF-08` (a fabricated or `NOT READY` record
refused at both the exact-match and fallback paths, in `tests/hooks_test.sh` ~line 2050) already
exist as *different*, unrelated tests in two different files — new cases below start at
`TC-RRF-09` to avoid overwriting either.

- **TC-RRF-06** (new) — fix → ADR commit → trailing review-record commit for the fix: resolves to
  the fix's real record. Reproduces the reported adopter incident directly.
- **TC-RRF-07** (existing, `mkr-merge/SKILL.md` wording, unrenumbered) — must still pass after the
  wording update; "parent" stays present in step 2's section.
- **TC-RRF-08** (existing, fabricated/`NOT READY` record, unrenumbered) — must still pass
  unmodified; unrelated to this change but shares the same exact-match/fallback code paths being
  touched.
- **TC-RRF-09** (new) — a chain of consecutive docs-only commits totaling *exactly* the chosen hop
  bound (5): resolves successfully. This is the boundary case: it is what actually distinguishes
  the bound comparison being a correct inclusive ceiling from an accidental off-by-one exclusion —
  neither TC-RRF-06 (well under the bound) nor the longer-than-bound case below would catch a
  `<` → `<=` (or the reverse) mutation at the boundary; only a case sitting exactly on it does.
- **TC-RRF-10** (new) — fix → ADR → ADR → trailing review-record commit (two consecutive docs-only
  hops, well under the bound): resolves. Proves the walk is genuinely multi-hop, not just widened
  from one to two.
- **TC-RRF-11** (new) — fix → ADR → [a commit that also touches a non-doc file] → trailing
  review-record commit: fails. Proves the outside-check still applies at every hop, not only the
  first.
- **TC-RRF-12** (new) — a chain of consecutive docs-only commits one hop longer than the chosen
  bound: fails cleanly (returns 1; no hang, no crash, no garbage on stdout). Paired with
  TC-RRF-09: together they bracket the exact boundary from both sides.
- **TC-RRF-13** (new) — the existing merge-commit path test cases (currently ~lines 2081-2237)
  re-run unmodified against the changed file, confirming no regression from the new internal
  parameter or the `mkr_get MKR_ADR_DIR` read.
- **TC-RRF-14** (new, `tests/mkr_artifact_test.sh`) — grep every `mkr_get`/`mkr_list` call site
  added to `.claude/hooks/lib/reviewrecord.sh` by this change and assert each argument is one of
  the pre-existing published keys (`MKR_REVIEW_VERDICT_STRING`, `MKR_ADR_DIR`) — no new key name
  appears anywhere in the diff. Directly backs §10's "no new `config.sh` key is introduced" AC,
  which no other case exercises.
- **TC-RRF-15** (new, `tests/mkr_artifact_test.sh`) — a file matching `docs/adr/000N-*.md` exists
  whose body names `find_review_record`/`reviewrecord.sh` and states the chosen hop-bound value —
  same structural-doc-check shape as `TC-RRF-07`'s existing `mkr-merge/SKILL.md` assertion.
  Directly backs §10's "an ADR exists... documenting... the chosen hop limit" AC, which no other
  case exercises.
- **Mutation check** (per `CLAUDE.md`'s mutation-resistance expectation for this file's class):
  flip the outside-check's pass-through to a fall-through (caught by TC-RRF-11), the hop-bound
  comparison's strict inequality to non-strict or vice versa (caught by TC-RRF-09 paired with
  TC-RRF-12 — the only cases sitting on the boundary), or delete the `mkr_get MKR_ADR_DIR` read
  (caught by TC-RRF-06), and confirm each mutation is caught by name, not just asserted in the
  abstract. A suite that survives one of these mutations unmodified is itself a gap in the
  register, not a pass.

## 10. Acceptance criteria

- The exact reported adopter scenario (fix → ADR → trailing review-record commit) resolves
  `find_review_record` to the fix's real record.
- TC-RRF-01 through TC-RRF-05, TC-RRF-07, TC-RRF-08 (pre-existing) remain green, unmodified.
- TC-RRF-06, TC-RRF-09 through TC-RRF-15 (new, per §9) are green.
- `bash tests/hooks_test.sh` and `bash tests/mkr_artifact_test.sh` both exit 0.
- No new `config.sh` key is introduced (TC-RRF-14).
- `find_review_record`'s documented 4-argument public signature is unchanged; every existing
  caller needs no argument-list change.
- An ADR exists at `docs/adr/000N-*.md` documenting the bounded-chain decision and the chosen hop
  limit (TC-RRF-15).

## 11. Definition of Done

- All §10 acceptance criteria met.
- `mkr-design` (G3) run against this spec's §6/§7/§8 before implementation starts (mandatory at
  Deep depth).
- `mkr-code-review` (G4) run against the diff; both reviewers READY; review record committed.
- Full test suite (`config_test.sh`, `hooks_test.sh`, `install_test.sh`, `mkr_artifact_test.sh`)
  green.
- Ground (phase 9) run post-merge, per Deep's mandatory-ground requirement.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. spec-first — this document, through G1.
2. reuse-check — §5 (done above); re-confirm at implement time nothing landed in the interim.
3. design (G3, mandatory at Deep) — `mkr-design` against §6/§7/§8.
4. test-first — write TC-RRF-06, TC-RRF-09..13 (`tests/hooks_test.sh`) and TC-RRF-14..15
   (`tests/mkr_artifact_test.sh`) against the *current*, unfixed state first; confirm each fails
   for the expected reason (a false negative on the chain, a missing ADR, etc — not a fixture
   bug), and confirm TC-RRF-07/08 (pre-existing) still pass unmodified.
5. implement — the `mkr_get MKR_ADR_DIR` read, the recursive rewrite of the docs-only fallback,
   the internal hop-bound constant, the `pre-push-review-guard.sh` WARN wording, the
   `mkr-merge/SKILL.md` step-2 wording, and the ADR (`mkr-adr`, for the bounded-chain decision) —
   done here, not deferred to after code-review, so TC-RRF-15 goes green in this same pass rather
   than staying red until a later step.
6. self-review — re-read the diff cold against §6-§8 before requesting code-review.
7. verify — full suite green (§11).
8. code-review (G4) — `mkr-code-review`; both reviewers READY; record committed.
9. merge (G5) — `mkr-merge`.
10. ground (phase 9, mandatory for Deep) — `mkr-audit`.

## 13. Review history

| rev | reviewer | verdict | notes |
|---|---|---|---|
| 1 | mkr-spec-reviewer | NOT READY (1 blocking) | §9's mutation-check claim wasn't backed by an actual test case sitting exactly on the hop-bound boundary (TC-RRF-08/10 as drafted only covered 2-hop and longer-than-bound, missing the boundary itself) — fixed in rev 2 by adding TC-RRF-09 (chain of exactly the bound length, resolves) and renumbering to avoid colliding with the pre-existing, unrelated TC-RRF-07/08 tests. Non-blocking: §6's bound-rationale example incorrectly cited a design/plan-note commit as part of the walkable chain (MKR_DESIGN_DIR isn't in the allowed-path set) — corrected; §3's two out-of-scope bullets lacking an explicit handler — tightened; §10's two architecture-constraint ACs lacking a §2 antecedent — closed by adding a stability-constraint bullet to §2. |
| 2 | mkr-spec-reviewer | NOT READY (2 blocking) | Confirmed rev 1's fixes actually landed correctly (boundary case, corrected example, closed AC antecedent). New findings: §10's "no new `config.sh` key is introduced" AC and "an ADR exists... documenting... the hop limit" AC both had zero §9 backing — fixed in rev 3 by adding TC-RRF-14 (`tests/mkr_artifact_test.sh`, greps `reviewrecord.sh`'s `mkr_get` call sites against the pre-existing key set) and TC-RRF-15 (`tests/mkr_artifact_test.sh`, asserts the ADR file exists and documents the bound), and by moving the ADR-writing task earlier in §12 so TC-RRF-15 can go green in the same implement pass. Non-blocking: `TC-RRF-07` was mis-attributed to `tests/hooks_test.sh` in §3's in-scope bullet — it actually lives in `tests/mkr_artifact_test.sh`; corrected throughout §3/§9. |
| 3 | mkr-spec-reviewer | READY | Independently re-verified every prior fix against the live repo rather than trusting rev 3's own changelog (file/line citations for `reviewrecord.sh`, `config.sh`, `mkr-merge/SKILL.md`, `pre-push-review-guard.sh` all confirmed accurate; new TC-RRF IDs confirmed non-colliding). No blocking findings. Non-blocking, not actioned before human approval: the "ADR exists" AC still lacks as direct a §2 antecedent as its sibling architecture-constraint ACs got in rev 1 (it's test-backed via TC-RRF-15, so left as-is); the mutation-check paragraph's "`CLAUDE.md`'s mutation-resistance expectation for this file's class" reads as a citation of a rule that literally names only `config.sh`, when it is actually a reasoned extension by analogy — worth rewording at the next natural touch, not blocking. |
