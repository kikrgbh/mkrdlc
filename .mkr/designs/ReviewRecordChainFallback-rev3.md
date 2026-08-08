# Design review — ReviewRecordChainFallback rev 3

**Reviewers.** Two independent fresh agents, `mkr-design-reviewer` and `mkr-architecture-reviewer`,
spawned in parallel against §6/§7/§8, neither aware of the other's findings until each had formed
its own judgment.

mkr-design-reviewer: READY
mkr-architecture-reviewer: READY

**Scope.** `specs/ReviewRecordChainFallback_Spec.md`, rev 3 (commit `a6c7fa0`), §6 (Architecture &
key decisions), §7 (Interfaces / contracts), §8 (Data model).

## Finding 1 — non-blocking, confirmed — merge commit mid-chain isn't addressed

A merge commit landing *mid-chain* (between the reviewed fix and the trailing review-record
commit, as distinct from being the top-level `sha` under lookup) would break the docs-only walk:
`git diff-tree` reports an empty diff for a merge commit by default, which the outside-check
reads as "touches something outside the allowed paths" and refuses. This is a pre-existing
limitation of today's single-hop fallback too, not a regression introduced by this change, and
real-world chains reported so far are linear. Not fixed — out of scope for this fix, worth a
one-line acknowledgment in the ADR for a future reader.

## Finding 2 — non-blocking, confirmed — §7 doesn't restate the bound value itself

§7 (the canonical contract section) never states the chosen hop-bound value or its
exceeded-behavior directly — both live only in §6's narrative and §9's tests. Not a real ambiguity
(§6+§9 together fully pin the behavior, and TC-RRF-09/TC-RRF-12 operationally define the boundary
regardless of the internal comparison operator chosen at implement time), just an organizational
nit for a reader who'd expect §7 alone to be self-contained. Not fixed — no behavior is ambiguous
as a result.

## Finding 3 — non-blocking, confirmed — hop-bound ceiling is convention-enforced, not runtime-enforced

The 5th, internal-only recursion-depth parameter that enforces the hop ceiling is an ordinary
positional bash argument with no runtime guard stopping a future caller from supplying an
arbitrary value and defeating the bound. This matches existing precedent in the file (e.g.
`expected_prior_tip`'s trust already rests on caller discipline) and isn't exploitable by today's
only real caller (`pre-push-review-guard.sh`, which never supplies it) — not a live boundary gap.
Worth a one-line note in the ADR that this is convention-enforced, not runtime-enforced.

## Finding 4 — non-blocking, confirmed — §6 doesn't state `expected_prior_tip` propagation through the new recursive path

§6 explicitly says the *existing* merge-commit recursive call (line ~108) omits the 5th argument
and always starts a fresh depth-0 budget, but doesn't state whether `expected_prior_tip` itself is
propagated unchanged through the *new* docs-only-fallback's recursive calls. Either propagation
choice leans over-conservative (a false "not found" rather than opening a review-bypass), so this
is a contract/edge-case clarity gap, not an architectural boundary gap. Worth a sentence in the
ADR for future readers.

**Findings not pursued further.** None — both reviewers' non-blocking findings above are recorded
as-is; none were raised and then explicitly declined.

**Verdict.** READY
