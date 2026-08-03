---
name: mkr-design
description: Runs phase 3's G3 gate (docs/DESIGN.md §2) - spawns mkr-design-reviewer and mkr-architecture-reviewer (fresh context, parallel, independent) against an ACCEPTED spec's §6/§7/§8, then writes a design record to MKR_DESIGN_DIR in the specs/M5_Gates_Spec.md §7.3 shape. Use after G1 (spec approved) and G2 (plan conformant), before tests/implement, on a Deep spec always or a Standard spec with a UI or contract change.
---

# mkr-design — phase 3's G3 gate

`mkr-design` never forms its own judgment about the design — that's the two reviewer agents' job,
each run in a fresh context specifically so neither has any memory of drafting the spec or any
knowledge of the other's findings. This skill's job is orchestration and recording, in this order.

## 1. Confirm the spec is ACCEPTED

G3 runs after G1 and G2, on a spec that has already cleared both (docs/DESIGN.md §2's phase order).
Read the spec's `Status` line; if it does not read `ACCEPTED rev N (...)`, stop — G3 has nothing to
review yet.

## 2. Does the design gate even apply?

Check the spec's own `## 0. Triage` block's `gates:` line. If it does not mark `design: ✓`, this
skill has nothing to do — report that plainly and stop, rather than running two reviewers against a
spec that never required this gate (Deep is always `✓`; Standard is `✓` only if the triage's Q3 or
Q5 was yes).

## 3. Is this a first review or a re-review?

Read the spec's `Status` line for its rev number `N`. Check whether
`<MKR_DESIGN_DIR><Slug>-rev<N-1>.md` exists (i.e., a prior round already ran against an earlier
revision of the same spec, and that revision was `NOT READY`).

- **First review:** spawn both `mkr-design-reviewer` and `mkr-architecture-reviewer` on §6/§7/§8.
- **Re-review:** spawn both again (unlike G4's re-review, there is no per-file "did this reviewer
  cover this text" scoping to do — the whole of §6/§7/§8 is short enough that both reviewers simply
  re-read it), giving each the prior round's record so it can check whether its own earlier finding
  was actually addressed in the new text, not assumed from the new revision's own claim that it was.

## 4. Resolve `MKR_DESIGN_DIR`

Run `config.sh get MKR_DESIGN_DIR` (CLI mode). The agents have no shell access, so you resolve this
yourself and use it to place the record.

## 5. Spawn the reviewers

Use the Agent tool, **in the same message** so they run in parallel. Give each: the spec's path
and, on a re-review, the prior round's record. Do not summarize the spec's design for either agent,
do not mention what the other agent is checking, and do not pre-empt either verdict.

## 6. Collect verdicts and merge findings

Each agent ends with `VERDICT: READY` or `VERDICT: NOT READY (<n> blocking)` plus a findings list.
Overall gate result is `READY` only if **both** agents' verdicts are `READY`; otherwise `NOT READY`,
with the total blocking count being the sum across both. When merging both agents' findings into
the one record, renumber them into a single running sequence, not two lists each restarting at 1.

## 7. Write the design record

Write `<MKR_DESIGN_DIR><Slug>-rev<N>.md` (specs/M5_Gates_Spec.md §7.3), where `<Slug>` and `<N>` are
read directly from the spec's own filename and `Status` line:

```
# Design review — <Slug> rev <N>

**Reviewers.** Two independent fresh agents, spawned in parallel [or: re-run, naming why], neither
aware of the other's findings until each had formed its own judgment.

mkr-design-reviewer: READY|NOT READY (<n>)
mkr-architecture-reviewer: READY|NOT READY (<n>)

**Scope.** <spec path>, rev <N>, §6/§7/§8. [On a re-review: what changed in the text since the
prior round's record.]

[zero or more:]
## Finding <n> — <blocking|non-blocking>, <confirmed|plausible> — <one-line description>

<the finding, and — for a blocking finding — the fix if any and how it was independently verified>

**Findings not pursued further** — <anything raised and explicitly declined, with why — or "None.">

**Verdict.** READY|NOT READY (<n> blocking)
```

The two `mkr-*-reviewer: ` lines are this skill's own translation of each agent's raw
`VERDICT:` output into the record's per-reviewer sub-verdict line. **The closing `**Verdict.**`
line must read `READY` if and only if both sub-verdicts above are `READY`** — never write a closing
verdict that contradicts the two sub-verdicts stated in `Reviewers`, the same discipline
`mkr-code-review`'s `VERDICT:` aggregation already applies at G4.

A `READY` record with zero findings omits the `## Finding` section entirely (six elements total,
not seven with an empty body).

## 8. Report the result

If `NOT READY`, state which findings block — these route back to the spec itself (a revision, not
phase 5), since G3 runs before any code exists. The next `/mkr-design` invocation after a spec
revision lands is a re-review (step 3), not a fresh first review.
