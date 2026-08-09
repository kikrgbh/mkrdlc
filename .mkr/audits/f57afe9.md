# Grounding audit — ReviewRecordMergeMidChainFallback, commit f57afe9

Fresh-context agent, no memory of the build, per DESIGN.md phase 9. Audited against
`specs/ReviewRecordMergeMidChainFallback_Spec.md` §10 AC-1…AC-8, branch `main`.

| AC | Verdict | Evidence |
|---|---|---|
| AC-1 | VERIFIED | Independent hand-built fixture (base → feature → real merge commit M → trailing docs-only commit C confined to `.mkr/audits/`) resolved via `find_review_record` sourced directly from the audited `reviewrecord.sh`: `rc=0`, output `(pre-existing, at-or-before <M's short sha>)` — the sentinel, never inspecting M's second parent. |
| AC-2 | VERIFIED | Fresh `bash tests/hooks_test.sh`: TC-RRF-01..20, TC-MRF-01..06 all `ok`; `diff ddb4b3b f57afe9 -- reviewrecord.sh` confirms the pre-existing code paths are byte-unchanged. |
| AC-3 | VERIFIED | Fresh run: TC-RRF-21 through TC-RRF-26 all `ok`, each matching §9's described behavior exactly. |
| AC-4 | VERIFIED | Fresh runs: `hooks_test.sh` exit 0 (PASS=180 FAIL=0), `mkr_artifact_test.sh` exit 0 (PASS=249 FAIL=0). |
| AC-5 | VERIFIED | `git diff ddb4b3b f57afe9 -- .claude/hooks/lib/config.sh` is empty — no key added. |
| AC-6 | VERIFIED | `find_review_record`'s signature is unchanged (5th arg still internal/defaulted); both real callers (`pre-push-review-guard.sh`, `mkr-gate.yml`) still pass exactly 4 args. |
| AC-7 | VERIFIED | `docs/adr/0010-review-record-merge-mid-chain-fallback.md` exists, Accepted, documents the ancestor-check decision and the "no loophole" reasoning. |
| AC-8 | VERIFIED | `docs/adr/0008`'s Consequences section amended with a cross-reference to `docs/adr/0010` closing the gap it named; original Decision section untouched. |

**Additional checks the auditor ran independently:**
- Cross-checked `.mkr/reviews/7083558.md`: both G4 reviewers independently READY, hand-traced the
  same fixtures this audit re-derived from scratch, and recorded matching full-suite green counts.
- Confirmed the AD-2/AD-3 merge-commit shortcut and outside-check/diff-confinement recursion paths
  remain byte-identical to before this change, consistent with the spec's own out-of-scope claim.
- Nothing here required a live CI/PR to confirm — all evidence was independently reproducible
  in-repo.

**Verdict:** PASS
