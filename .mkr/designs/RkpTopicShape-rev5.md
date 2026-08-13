# Design review — RkpTopicShape rev 5

**Reviewers.** `mkr-design-reviewer` re-run per AD-2 (had a blocking finding at rev 4).
`mkr-architecture-reviewer` not re-run per AD-2 — its rev-4 `READY` verdict already covered this
exact §6/§7/§8 range with no blocking finding, so it carries forward unchanged rather than being
re-run for no new information.

mkr-design-reviewer: NOT READY (1)
mkr-architecture-reviewer: READY (carried forward from rev 4, `.mkr/designs/RkpTopicShape-rev4.md`)

**Scope.** `specs/RkpTopicShape_Spec.md`, rev 5, §6/§7. Changed since rev 4: §6 AD-3 and §7 both
gained explicit statements of what happens to a *refused* declared token in each of the four
list-consuming behaviors §7 lists (bootstrap/full-package reporting, `README.md`'s table,
single-doc refresh's scope-hint validity, partial bootstrap's missing-vs-present enumeration);
`SKILL.md` gained the same paragraph; new mechanical checks `TC-RKP-17h`/`17i`/`17j`.

`mkr-design-reviewer` independently re-read §6/§7 fresh and confirmed three of the four rev-4 gaps
are now concretely resolved: `README.md`'s table excludes refused entries, scope-hint validity
gives a refused token its own distinct report (not conflated with "not in the declared list"), and
bootstrap/full-package refresh report a refused entry by name.

## Finding 1 — blocking, confirmed — partial bootstrap's fix resolves classification but not
reporting

The fourth item's fix ("excludes it entirely — neither missing nor present") only answers which
bucket a refused token falls into; it never states whether the token is still reported to the user
in that mode at all. Unlike the other three behaviors, which each got an explicit reporting
statement, partial bootstrap's clause is scoped only to bucket-exclusion — and bucket-exclusion is
literally that mode's whole reporting mechanism (missing vs. present is how it communicates state).
Two implementers could reasonably diverge: one adds a third report line outside the missing/present
buckets; the other reads "excluded entirely" as excluded from the only channel that mode has,
i.e. silent. This is the exact security property AD-3 exists to guarantee ("never silently written
or skipped") — and the reviewer confirmed the same silence already existed in the *implemented*
`SKILL.md` text, not merely the spec's prose, so this isn't a hypothetical drafting gap.

**Not fixed in this round** — routed back to the spec for rev 6.

**Findings not pursued further.** None.

**Verdict.** NOT READY (1 blocking)
