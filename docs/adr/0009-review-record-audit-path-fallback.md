# 0009 — `find_review_record`'s docs-only fallback also allows `MKR_AUDITS_DIR`

## Status

Accepted

## Context

`docs/adr/0008` widened `find_review_record()`'s (`.claude/hooks/lib/reviewrecord.sh`) docs-only
fallback to walk a bounded chain of non-code commits confined to `MKR_REVIEWS_DIR`, `MKR_SPECS_DIR`,
or `MKR_ADR_DIR`. It did not include `MKR_AUDITS_DIR`.

`mkr-audit` (phase 9's ground step, `specs/M4_Audit_Spec.md` §7.3) writes a grounding-audit record
to `<MKR_AUDITS_DIR><short-sha>.md` after merge (`mkr-merge/SKILL.md` step 10 hands off to it
explicitly, against the commit the merge itself just produced — already on the protected branch).
In real adopter use the record
lands as its own commit on that branch — the same "separate trailing commit, naming a sha it can
never itself equal" shape `mkr-code-review`'s G4 review record already uses, for the same
structural reason. Until this fix, `mkr-audit/SKILL.md` never actually said to commit the record
that way, unlike `mkr-code-review/SKILL.md`'s explicit "commit the record alone, in its own commit,
touching nothing else" — a real gap, found during this fix's own G3 design review: the widened
allowed-path set below only matters in practice if that commit's diff is genuinely confined to
`MKR_AUDITS_DIR` alone, and nothing was making that true by contract. Closed as part of this same
decision (§Decision item 4).

When such a commit reaches `main`, `mkr-gate.yml`'s `push`/`pull_request` trigger runs
`find_review_record` against it. The commit is never an exact match, and its own diff is confined
to `MKR_AUDITS_DIR` alone — a directory the fallback's outside-check did not recognize — so the
walk fails on the very first hop, even though the commit immediately behind it (the real review
record, or the merge commit itself) resolves cleanly. This was reported directly from real adopter
repos: running `mkr-audit` almost always produced a wasted, failing CI run afterward.

## Decision

1. Read `MKR_AUDITS_DIR` internally via `mkr_get`, exactly the way `docs/adr/0008` already reads
   `MKR_ADR_DIR` — not as a new positional parameter. `find_review_record`'s documented 4-argument
   signature stays unchanged for every existing caller.
2. Add it to the docs-only fallback's outside-check allowed-path set, alongside `reviews_dir`,
   `specs_dir`, and `adr_dir`. No other part of the fallback — the recursion mechanism, the hop
   bound (`_RRF_MAX_CHAIN_HOPS`, still 5), the internal `_hops` parameter — changes.
3. No new `config.sh` key: `MKR_AUDITS_DIR` already exists as a published default (`.mkr/audits/`),
   consumed by `mkr-audit` since M4.
4. Scope the widening to `MKR_AUDITS_DIR` specifically, not a broader "anything under `.mkr/`"
   rule. It is the one artifact class, beyond the three `docs/adr/0008` already allowed, meant to
   be committed directly to a protected branch as a standalone trailing commit after merge —
   `mkr-audit/SKILL.md` is updated in this same change to actually say so ("commit the record
   alone, in its own commit, touching nothing else," mirroring `mkr-code-review/SKILL.md`'s
   pre-existing wording for the G4 review record), closing the gap found at this fix's own G3
   design review: without that explicit instruction, nothing guaranteed the audit-record commit
   this widening exists for would ever actually be diff-confined to `MKR_AUDITS_DIR` alone. Nothing
   else under `.mkr/` is committed that way today.
5. The outside-check's "no loophole" guarantee — any commit whose diff touches something outside
   all four allowed paths fails the whole lookup — re-runs at every hop, unchanged. Widening the
   allowed-path set by one more `mkr_get`-resolved directory does not touch that check's control
   flow, only the literal set of directories it accepts.

Same residual risk `docs/adr/0008` already named, unchanged in shape by this widening: the outside-
check's per-hop confinement is the only thing verified — nothing here authenticates an audit
record's *content*, or proves a real `mkr-auditor` run actually produced it, only that whatever
commit carries it touches nothing else. This is convention-enforced (the new `mkr-audit/SKILL.md`
instruction), not runtime-enforced against a caller who ignores it — the same trust boundary
`docs/adr/0008` already accepted for `MKR_ADR_DIR` and the review-record commit itself.

## Consequences

- A grounding-audit-record commit, pushed to `main` after the underlying fix's G4 record already
  exists, no longer produces a false "no G4 review record for this commit" CI failure — this is
  the exact adopter-reported scenario, now fixed at the same shared function `docs/adr/0008`
  already fixed for a trailing ADR commit.
- `mkr-merge`'s local G4 check gains the same widening: a branch whose HEAD is itself a
  grounding-audit-record commit no longer falsely reports "G4 hasn't run."
- `mkr-audit/SKILL.md` now explicitly requires the same "own commit, touching nothing else"
  discipline `mkr-code-review/SKILL.md` already required — a future `mkr-audit` run has a real,
  documented contract to produce the diff-confined commit this fix's allowed-path widening assumes,
  not just an unstated convention.
- No behavior change for the common case (review-record commit is the fix's immediate child, no
  audit commit involved) — the new behavior is a strict superset of before.
- A chain mixing ADR and audit commits (or either alone) still resolves as long as it stays within
  the existing 5-hop bound — unchanged, since the bound itself is untouched by this decision.
