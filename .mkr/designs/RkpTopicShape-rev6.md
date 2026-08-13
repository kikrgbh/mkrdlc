# Design review — RkpTopicShape rev 6

**Reviewers.** `mkr-design-reviewer` re-run per AD-2 (had a blocking finding at rev 5).
`mkr-architecture-reviewer` not re-run per AD-2 — its rev-4 `READY` verdict already covered this
exact §6/§7/§8 range with no blocking finding, so it carries forward unchanged for a second round.

mkr-design-reviewer: READY
mkr-architecture-reviewer: READY (carried forward from rev 4, `.mkr/designs/RkpTopicShape-rev4.md`)

**Scope.** `specs/RkpTopicShape_Spec.md`, rev 6, §6/§7. Changed since rev 5: §6 AD-3 ("Correction,
part 3") and §7 both now state explicitly that exclusion from partial bootstrap's missing/present
buckets is never exclusion from reporting — a refused token is still reported by name in that mode,
the same report bootstrap and full-package refresh give it. `SKILL.md` updated to match. New
mechanical check `TC-RKP-17k`. Also fixed, cosmetic: AD-3's "Correction, part 2" recap parenthetical
now names all four corrected behaviors, not three.

`mkr-design-reviewer` independently re-read §6/§7/§8 fresh, confirmed the rev-5 finding's fix is
genuinely present in both the spec text and the actual implemented `SKILL.md` (not just spec
prose), confirmed `TC-RKP-17k`'s literal-match assertion is wired to the exact corrected sentence,
and found no new gaps on a full fresh read of the section.

**Findings not pursued further.** None.

**Verdict.** READY
