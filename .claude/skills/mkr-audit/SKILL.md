---
name: mkr-audit
description: Runs phase 9's ground step (docs/DESIGN.md §2) - spawns mkr-auditor (fresh context, no memory of the build) against a spec's acceptance criteria and the real commit they claim, then writes a grounding-audit record to MKR_AUDITS_DIR in the specs/M4_Audit_Spec.md §7.3 shape. Use after a merge, on any Standard/Deep change (mkr-loop's own gates-derivation rule already marks ground as required from Standard depth up).
---

# mkr-audit — phase 9's ground step

`mkr-audit` never forms its own judgment about whether an acceptance criterion actually holds —
that's `mkr-auditor`'s job, run in a fresh context specifically so it has no memory of building the
change and no reason to trust a Definition of Done's own say-so. This skill's job is orchestration
and recording, in this order.

## 1. Resolve the spec and the target SHA

Input: a spec path (default — the newest spec on the current branch whose `Status` reads
`ACCEPTED`, using the same branch-diff notion `spec-gate.sh` already applies) and a commit SHA
(default: `HEAD`). Compute the target's **short SHA** — the first 7 characters of the full SHA, the
same fixed length `mkr-code-review` established for `.mkr/reviews/` (specs/M2_CodeReview_Spec.md
§7.1), not git's own variable-length `--short` abbreviation.

## 2. Resolve `MKR_AUDITS_DIR`

Run `config.sh get MKR_AUDITS_DIR` (CLI mode). The agent has no shell access, so you resolve this
yourself and use it to place the record.

## 3. Is this a first audit or a re-audit?

Check whether `<MKR_AUDITS_DIR><short-sha>.md` already exists for this exact commit. If so, this is
a re-audit — give `mkr-auditor` the prior round's record so it can state explicitly whether an
earlier finding was actually fixed, rather than take the new commit's claim on faith (the same
re-review discipline `mkr-code-review` and `mkr-spec-review` already apply).

## 4. Spawn `mkr-auditor`

Use the Agent tool. Give it: the spec's path, the target SHA, the current branch name, and — on a
re-audit — the prior round's record. Do not summarize the spec's claims for it, do not explain what
you expect it to find, and do not pre-empt its verdict — the whole point of a fresh context is that
it forms its own read.

## 5. Write the audit record

Write (first audit) or replace (re-audit — the record is keyed to the commit under audit now, not
the prior round's) `<MKR_AUDITS_DIR><short-sha>.md` in this exact shape
(specs/M4_Audit_Spec.md §7.3):

```
# Grounding audit — <milestone/change label, or omitted for a non-milestone change>, commit <short-sha>

Fresh-context agent, no memory of the build, per DESIGN.md phase 9. Audited against
<spec path> §10 AC-1…AC-<n>, branch `<branch>`.

| AC | Verdict | Evidence |
|---|---|---|
| AC-1 | VERIFIED | <evidence> |
| AC-2 | NOT VERIFIED (<reason>) | <evidence> |
...

**Additional checks the auditor ran independently:**
- <anything checked beyond the AC table proper>

[optional:]
**Outstanding, not a defect:**
- <open DoD items not yet checked at this commit, named so they aren't mistaken for AC violations>

**Verdict:** PASS|FAIL (<n> not verified)
```

Every AC the spec's §10 names must appear exactly once, in the table, in order — no silent
omission, no duplicate. `Verdict` cells are exactly `VERIFIED` or `NOT VERIFIED (<reason>)`; the
closing `**Verdict:**` line reads `PASS` if and only if every row above is `VERIFIED`, otherwise
`FAIL (<n> not verified)` naming the count — a deterministic rule, not a narrative summary, the
same discipline `mkr-code-review`'s own `VERDICT:` aggregation already applies.

**Commit the record alone, in its own commit, touching nothing else** — the same convention
`mkr-code-review/SKILL.md` already requires for a G4 review record, and for the same reason:
`reviewrecord.sh`'s bounded non-code-commit-chain fallback (`docs/adr/0008`, widened to recognize
`MKR_AUDITS_DIR` by `docs/adr/0009`) only walks past this commit toward the real review record
covering the audited fix when this commit's own diff is confined to `MKR_AUDITS_DIR` alone. Before
committing the record file, confirm nothing else is staged or about to be swept in (`git status`;
never `git commit -a`/`-am` here) — a record committed alongside even one unrelated change trips
`mkr-gate.yml`'s hard-blocking G4 check on the next push to a protected branch, since the fallback
sees a diff reaching outside every allowed path and refuses the whole lookup at that hop.

## 6. Report the result

Report the closing `PASS`/`FAIL (<n> not verified)` verdict back to the invoking session. A `FAIL`
does not block anything mechanically — the grounding audit sits after merge in the loop diagram
(docs/DESIGN.md §2, phase 8 → phase 9), so it cannot be a pre-merge gate. It is read the same way a
Definition of Done checkbox is read, by whoever is deciding whether the change is actually done.
