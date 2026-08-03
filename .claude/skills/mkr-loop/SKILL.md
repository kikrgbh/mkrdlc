---
name: mkr-loop
description: Use at the start of any non-trivial change in this repo (or any repo carrying this template) to run phase 0 of the AIDLC loop - triage. Classifies the change as Quick, Standard, or Deep per docs/DESIGN.md §3, produces the TRIAGE block, and routes to the next phase. Invoke this before writing code, drafting a spec, or making a plan - "start a feature", "fix a bug", "add X", "let's build Y" are all triggers.
---

# mkr-loop — triage (phase 0)

This skill implements `docs/DESIGN.md` §3 exactly. It is a **bounded classification pass**, not
exploration — a handful of reads and greps, then a verdict. If you cannot classify within that
budget, that is itself the answer: the change is Standard or Deep, not Quick.

## A. Preflight — three mechanical checks, in order

1. **Where am I?** Check the current branch (`git branch --show-current`). If it is one of
   `MKR_PROTECTED_BRANCHES` (`config.sh get MKR_PROTECTED_BRANCHES`, CLI mode — default `main`),
   stop and create a feature branch before touching anything. If there are uncommitted changes that
   aren't yours (i.e., you didn't just make them this session), stop and ask before touching
   anything.
2. **Am I starting or resuming?** Look for an existing spec (`MKR_SPECS_DIR`, `config.sh get
   MKR_SPECS_DIR`), branch, plan record, or review record for this work. Resuming a half-finished
   change and re-starting it from scratch is the single most common way work gets duplicated —
   check before assuming this is new.
3. **Is this one change or several?** A request that is really three features gets split into three
   loops here, not discovered at plan time after a spec has already been written for all of it.

## B. Classification — six questions

Ask these in order. Answer each with what you actually found, not a guess.

| # | Question | How to answer |
|---|---|---|
| 1 | **What paths will this touch?** | **Mechanical.** Run `config.sh list MKR_RISKY_PATHS` (CLI mode). For each glob returned, check whether any path you expect to touch matches it. Report the matched globs, or "none matched" — never a judgment call. |
| 2 | **Does this already exist?** | Judgment. A cheap reuse pre-check — grep/search for the capability before assuming it needs building. If yes, the task becomes *extend X*, which often collapses the scope. |
| 3 | **Does it change a contract?** | Judgment. A published API shape, a DB schema, a public interface — anything another consumer depends on. |
| 4 | **Is it reversible?** | Judgment. Revertable by a commit, or does it write to a third party / migrate data / change external state? |
| 5 | **Does it have a UI or a probabilistic surface?** | Judgment. Adds the design gate and the eval step respectively. |
| 6 | **How will we know it's done?** | One sentence. State the acceptance signal now — that's what makes "done" arguable later. |

## C. The decision rule (mechanical, not taste)

- **Deep** if **any** of: Q1 matched a `MKR_RISKY_PATHS` glob · introduces a new module, service or
  package · Q3 changes a published contract · Q4 is hard to reverse · touches a non-negotiable
  listed in `CLAUDE.md`.
- **Quick** only if **all** of: a single localized fix or no behaviour change · no new file beyond a
  test · no interface change · covered by existing tests or one added test · undone by a plain
  revert.
- **Standard** otherwise.

**Standard is the default; ambiguity resolves upward.** Over-processing a small change costs
minutes; under-processing a risky one costs an incident.

## D. The output

**Quick** — one line, no file:

```
TRIAGE: quick — <why in one clause>
```

**Standard / Deep** — the `TRIAGE` block below, which becomes spec `## 0. Triage` verbatim once
`mkr-spec` runs. This skill does not write a file of its own — the block is only durable once a
spec embeds it.

```
TRIAGE
depth:    <standard|deep>
why:      <one or two clauses>
scope:    <one change | split into: ...>
reuse:    <what was checked, and what it found — never bare "no duplicate found">
touches:  <paths/globs>
risky:    <matched MKR_RISKY_PATHS globs, or "none matched">
gates:    <derived — see below>
done when: <the one-sentence acceptance signal from Q6>
```

**The eight fields, in that exact order, are mandatory** — a spec's `mkr-spec-reviewer` audit (and
`tests/mkr_artifact_test.sh`, TC-M1-12) checks this shape mechanically.

**Deriving the `gates` line** (DESIGN.md §3: "derived, not chosen — falls out of the depth and
questions 1, 3 and 5"):

- `spec` — ✗ for Quick (no block is emitted at all); ✓ for Standard/Deep.
- `plan` — same as `spec`.
- `design` — ✓ always for Deep; for Standard, ✓ only if Q3 (contract change) or Q5 (UI) is yes,
  else ✗; ✗ for Quick.
- `review` — Quick gets a one-line recorded note (not a full gate, per DESIGN.md §3's depth table);
  Standard/Deep get ✓.
- `ground` — ✗ for Quick; ✓ (after the slice) for Standard; ✓ (mandatory) for Deep.
- `adr` — ✓ if Q4 found the decision hard to reverse, or it is otherwise substantial per
  `CLAUDE.md`'s cross-cutting ADR rule; ✗ otherwise. Not mechanically tied to depth — a Standard
  change can still need one.
- `ship` — per-project; no ship tooling exists before M5/M6, so mark ✗ until then regardless of
  what the config implies.

## E. Escalation — depth is a floor, not a ceiling

Triage runs on incomplete information, so it is allowed to be wrong — but never *silently*. If a
later phase discovers something this pass missed (the fix turns out to need a migration; the
"small" change touches the auth guard), **stop and re-triage**. State the revised depth explicitly,
apply it from that point forward, and — if a spec already exists — note the escalation in that
spec's `## 13. Review history`. Going *down* a level requires the same explicit statement and never
retroactively skips a gate already recorded.

## F. Routing

- **Quick** → proceed directly (implement + test + the one-line review note). No spec, no plan.
- **Standard / Deep** → invoke the `mkr-spec` skill next, carrying the `TRIAGE` block forward as its
  `## 0. Triage`.
