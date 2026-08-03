---
name: mkr-evals
description: Judges whether a fresh-context reviewer or auditor agent's verdict is actually correct, not just well-formed - runs a named agent against golden fixtures under MKR_EVALS_DIR (an input paired with an expected verdict) and reports per-fixture match/mismatch. Closes the judgment-quality gap M1/M2/M4 each named and deferred as "M5's mkr-evals territory." Use to spot-check an agent's judgment quality, e.g. after changing its prompt, or periodically to confirm it hasn't drifted.
---

# mkr-evals — judging an agent's verdict against a known-correct one

Every fresh-context reviewer/auditor agent in this repo is checked, elsewhere, for *shape*:
`tests/mkr_artifact_test.sh` confirms its frontmatter and tool contract are well-formed. None of
that checks whether the agent's actual *judgment* — is this spec really `READY`, is this diff really
`NOT READY` — is correct. `mkr-evals` is what closes that gap, deterministically: it does not judge
judgment itself (that would recurse); it compares an agent's real verdict against a fixture's
already-known-correct one.

## 1. Resolve the fixture directory

Input: an agent name (one of the fresh-context reviewer/auditor agents — `mkr-spec-reviewer`,
`mkr-code-reviewer`, `mkr-security-reviewer`, `mkr-auditor`, `mkr-design-reviewer`,
`mkr-architecture-reviewer`). Run `config.sh get MKR_EVALS_DIR` (CLI mode) and look under
`<MKR_EVALS_DIR>fixtures/<agent-name>/`.

If that directory doesn't exist or has no fixtures, report so plainly — this milestone seeds real
fixtures for exactly one agent (`mkr-spec-reviewer`); widening coverage to another agent means
adding fixtures for it first, not something this skill can conjure.

## 2. For each fixture

Each fixture file names an input (a spec, a diff, or a commit reference — whatever the named agent
reviews) and a line reading exactly `expected: READY` or `expected: NOT READY`. For each fixture:

1. Spawn the named agent, fresh context, against the fixture's input exactly as it would run for
   real — the same inputs that skill/command would give it, nothing paraphrased or hinted.
2. Read the agent's actual `VERDICT: READY` or `VERDICT: NOT READY (<n> blocking)` line.
3. Compare: `READY` matches `expected: READY`; `NOT READY (...)` matches `expected: NOT READY`
   (the blocking count is not part of the comparison — a fixture only states the binary verdict it
   expects). Record `MATCH` or `MISMATCH (got <actual>, expected <expected>)`.

## 3. Write the report

Write `<MKR_EVALS_DIR><agent-name>-<run-label>.md`: one row per fixture (`<fixture name> |
<MATCH|MISMATCH> | <expected> | <got>`), and a closing pass count (`<k>/<n> matched`).

## 4. Report the result

There is no aggregate `PASS`/`FAIL` gate here — this is an evidence report a human reads to decide
whether they still trust an agent's judgment, the same posture `mkr-audit`'s own `FAIL` already has:
read, not mechanically blocking. A run with mismatches is a signal to look at the agent's prompt,
not a build failure.
