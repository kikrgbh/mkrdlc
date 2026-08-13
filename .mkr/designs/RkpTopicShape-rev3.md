# Design review — RkpTopicShape rev 3

**Reviewers.** Two independent fresh agents, re-run (unlike G4's re-review, no per-file scoping —
both simply re-read the whole of §6/§7/§8 again), each given the rev-2 record
(`.mkr/designs/RkpTopicShape-rev2.md`) for context but forming its own independent verdict on the
current rev-3 text rather than trusting the spec's own rev-3 review-history claim.

mkr-design-reviewer: READY
mkr-architecture-reviewer: READY

**Scope.** `specs/RkpTopicShape_Spec.md`, rev 3, §6/§7/§8. Changed since rev 2: §7's `MKR_RKP_TOPICS`
contract and `SKILL.md`-content list gain an explicit rule for a `docs/rkp/` file present on disk
but not (or no longer) named in a declared list (left untouched, unreported — rev-2 finding 1's
fix); §6 AD-3 gains a clause naming declared filenames' path-escape trust boundary (rev-2 finding
4's fix); §9/§10/§12 updated to match (`TC-RKP-17d`/renumbered `17e`, AC2, task 4b's range).

`mkr-design-reviewer` independently confirmed rev-2 finding 1's fix is present in §7 as described
(not merely claimed) — the new rule directly answers the present-but-undeclared scenario, framed
consistently with the existing present-conditional-doc "no longer applicable... human decision, not
silent" posture and §3's existing no-validation trust boundary for declared-list contents.
`mkr-architecture-reviewer` independently confirmed rev-2 finding 4's fix is present in AD-3 (§6) as
described. Both reviewers re-checked their own prior non-blocking observations (design-reviewer's
findings 2/3, left as-is by design) and found the reasoning still holds — both are already resolved
by mechanisms already present in `SKILL.md` (the general table-substitution framing; the "write
`README.md` last" procedural ordering), not by new spec text. No new findings from either reviewer
on a fresh full re-read.

**Findings not pursued further.** None — both rev-2 findings closed; no new findings this round.

**Verdict.** READY
