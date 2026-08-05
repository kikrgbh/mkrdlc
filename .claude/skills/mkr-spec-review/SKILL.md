---
name: mkr-spec-review
description: Runs G1's audit step - invokes the mkr-spec-reviewer agent (fresh context, no memory of drafting) against a spec, then records its READY/NOT READY verdict into the spec's own §13 Review history. Use right after mkr-spec drafts or revises a spec, before asking a human to approve it.
---

# mkr-spec-review — phase 1's G1 audit

`mkr-spec-review` never forms its own judgment about spec quality — that's `mkr-spec-reviewer`'s
job, run in a fresh context specifically so it has no memory of drafting the spec. This skill's own
job is orchestration and recording, in this order:

## 1. Resolve `MKR_GATE_SPEC` and `MKR_SPEC_EXTRA_SECTIONS`

Run `config.sh get MKR_GATE_SPEC` and `config.sh list MKR_SPEC_EXTRA_SECTIONS` (CLI mode) in the
calling repo. The agent has no shell access, so you resolve both and pass the values in.

## 2. Invoke `mkr-spec-reviewer`

Use the Agent tool with the `mkr-spec-reviewer` custom agent type. Give it:

- the spec file's path
- the `MKR_GATE_SPEC` value from step 1
- the `MKR_SPEC_EXTRA_SECTIONS` value from step 1 (empty if none declared)

Do not summarize the spec for it, do not explain what you were trying to do while drafting it, and
do not pre-empt its verdict — the whole point of a fresh context is that it forms its own read.

## 3. Record the verdict

Append a row to the spec's `## 13. Review history` table and, if `NOT READY`, the findings
underneath it — the same shape `specs/M0_Foundation_Spec.md` and `specs/M1_Loop_Spec.md` §13 use.
Also update the Header's `Status` line:

- `READY` → leave `Status` as `DRAFT rev N` (a human still has to approve it — see step 4) unless
  the spec's own convention marks readiness differently; never write `ACCEPTED` here, only a human
  G1 approval does that.
- `NOT READY (<n>)` → set `Status` to `NOT READY rev N (mkr-spec-reviewer)`.

## 4. Re-review on revision

If the spec is edited after a `NOT READY` verdict to address findings, bump the rev number in
`Status` before re-running this skill. `mkr-spec-reviewer` is re-run against the new revision, not
assumed to still apply from before — the agent's own checklist (item 8) verifies this from its side
too, but the rev bump is what makes "which revision was this verdict about" unambiguous.

Before resubmitting: for each finding being fixed, grep the whole spec (not just the flagged
line/section) for every other assertion of the same fact or pattern the finding turned on, and fix
every occurrence in that revision. Patching only the flagged spot routinely leaves a sibling
occurrence to surface as a separate "new" finding next round — the same avoidable class of extra
round `.mkr/captures.jsonl`'s `narrow-fix-misses-sibling` entries record.

## 5. Hand off

A `READY` verdict does not itself complete G1 — DESIGN.md §2's G1 line is "spec approved," and the
gate owners table names a human (`MKR_GATE_SPEC`) as the approver. Tell the user the spec is
`READY` and ask them to approve it; only their explicit approval, recorded in `Status` as
`ACCEPTED rev N (<approver>, <date>)`, actually passes G1.
