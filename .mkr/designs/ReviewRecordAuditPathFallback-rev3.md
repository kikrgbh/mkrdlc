# Design review — ReviewRecordAuditPathFallback rev 3

**Reviewers.** Two independent fresh agents, `mkr-design-reviewer` and `mkr-architecture-reviewer`,
spawned in parallel against §6/§7/§8, neither aware of the other's findings until each had formed
its own judgment. This is the formal G3 run — an earlier informal pass (before G1 was granted) is
recorded separately in the spec's own §13, rev-1/rev-2 rows; it surfaced and fixed one real defect
but did not itself discharge this gate.

mkr-design-reviewer: READY
mkr-architecture-reviewer: READY

**Scope.** `specs/ReviewRecordAuditPathFallback_Spec.md`, rev 3 (`ACCEPTED`, kikrgbh), §6
(Architecture & key decisions), §7 (Interfaces / contracts), §8 (Data model) — cross-checked
against the real, already-implemented code (`.claude/hooks/lib/reviewrecord.sh`,
`.claude/hooks/lib/config.sh`, `.claude/skills/mkr-audit/SKILL.md`, `.claude/skills/mkr-merge/
SKILL.md`, `.github/workflows/mkr-gate.yml`, `docs/adr/0009-review-record-audit-path-fallback.md`,
`tests/hooks_test.sh`, `tests/mkr_artifact_test.sh`), not just the spec's own account of it.

## Findings

None blocking from either reviewer.

**mkr-design-reviewer** (contracts/data-model/error-edge/reuse lens): independently re-verified
`find_review_record`'s unchanged 4-argument signature, `MKR_AUDITS_DIR`'s pre-existing `config.sh`
entry, and every doc-wording update (`mkr-gate.yml`, `mkr-merge/SKILL.md`, `mkr-audit/SKILL.md`)
against the real files. Non-blocking nit: `TC-RRF-18`'s fixture puts the "sneaky" outside-path file
in a separate, earlier commit in the chain (mirroring `TC-RRF-11`'s multi-hop shape) rather than
combined into the audit-record commit's own diff (mirroring `TC-RRF-03`'s same-commit shape) — so
no test exercises a single commit mixing an audit-record file with a smuggled outside file. Not a
novel gap: the identical substitution was already made for `MKR_ADR_DIR` at `docs/adr/0008`
(`TC-RRF-11` vs. `TC-RRF-03`), and the per-file outside-check loop has no early-exit vulnerability
regardless of which shape is tested. Left as a documented, pre-existing, non-blocking gap.

**mkr-architecture-reviewer** (boundaries/scalability/security-architecture/stack-fit lens):
independently re-traced the "could unreviewed code ride through `MKR_AUDITS_DIR`" concern against
the real `reviewrecord.sh` — the exact-match check never reads `audits_dir` (cannot manufacture a
false match), and the per-hop outside-check still fails closed the instant any hop's diff carries a
file outside all four allowed paths (cannot admit a mixed-content commit), confirmed directly
against `TC-RRF-18`. Confirmed `mkr-audit/SKILL.md`'s new "commit the record alone" instruction is
real and closes the loop §6's rationale depends on. No new `config.sh` key, no signature change,
hop bound and merge-commit path both untouched.

## Verification discipline

Both reviewers read the real, already-implemented diff directly rather than trusting the spec's
own claims — confirming line numbers, checking the named test IDs actually exist and assert what
the spec says they assert, and independently re-deriving the "no loophole" security argument rather
than accepting the prior informal pass's conclusion on its word.

## Verdict

VERDICT: READY
