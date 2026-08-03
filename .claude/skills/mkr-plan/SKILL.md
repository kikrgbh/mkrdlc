---
name: mkr-plan
description: Checks a presented plan (an ordered list of steps, usually a spec's §12 Task breakdown) against the project's MKR_PLAN_MANDATORY/MKR_PLAN_OPTIONAL and returns CONFORMANT or BLOCKED. Phase 2's G2 gate. Use after a spec is drafted, before implementation starts.
---

# mkr-plan — phase 2 (plan), G2

Input: a presented plan — an ordered list of step names or short descriptions, normally a spec's
`## 12. Task breakdown`. DESIGN.md §2 phase 2 says only "ordered steps," so a plan has no §7.3-style
required section shape of its own to enforce.

## 1. Resolve the config

`config.sh list MKR_PLAN_MANDATORY` and `config.sh list MKR_PLAN_OPTIONAL` (CLI mode). Each is a
space-separated list, one item per line via `list`.

## 2. Match the plan's steps against the mandatory list

For each `MKR_PLAN_MANDATORY` token, decide whether the presented plan has a step that satisfies it
— by judgment, not exact string match (a task titled "write the fixtures and checker before any
skill file" satisfies `test-first`; you don't need the literal word). A token with no satisfying
step goes into `missingMandatory`. `MKR_PLAN_OPTIONAL` tokens are informative only — never block on
their absence, but mention which ones the plan does cover, since a project may care later.

## 3. Check ordering against the loop's own order

DESIGN.md §2 fixes the loop's phase order: `triage → spec → plan → design → tests → implement →
verify → review → merge → ground → ship`. The six default `MKR_PLAN_MANDATORY` tokens map onto it
like this:

| token | belongs at/before |
|---|---|
| `spec-first` | before everything else in the plan |
| `reuse-check` | within/just after spec, before implement |
| `test-first` | before implement |
| `self-review` | end of implement, before verify |
| `verify` | after implement, before review |
| `code-review` | after verify, before merge |

A mandatory step present but ordered **after** a step this table (or, for a project's own custom
tokens, the DESIGN.md §2 order applied by the same reasoning) places strictly later than it is an
`orderingViolations` entry — e.g. an `implement` step appearing before a `test-first` step. If the
project has customized `MKR_PLAN_MANDATORY` with a token not in this table, still try to place it
in the DESIGN.md §2 order by what it evidently means; if you genuinely can't, check presence only
for that token and say so rather than guessing at an ordering violation.

## 4. Verdict

Exactly one of:

```
CONFORMANT
```

```
BLOCKED(missingMandatory=[<comma-separated tokens>], orderingViolations=[<step> before <token it violates>, ...])
```

Empty brackets are fine (e.g. `missingMandatory=[]` if only ordering failed). Never invent a third
verdict shape — DESIGN.md §2's G2 line names exactly these two.

## 5. `code-review` before M2

`mkr-code-review` doesn't exist until M2. Until then, a plan's `code-review` step is satisfied by
"self-review, recorded" — the same substitution `specs/M0_Foundation_Spec.md` §11 and
`specs/M1_Loop_Spec.md` §12 both use explicitly. Note this substitution in the verdict's reasoning
if you rely on it; don't silently treat a missing `code-review` step as satisfied without saying why.
