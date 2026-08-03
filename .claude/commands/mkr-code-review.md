---
description: Run G4's audit - spawn mkr-code-reviewer and mkr-security-reviewer against the current diff and record a verdict (phase 7 of the AIDLC loop).
---

Run the `mkr-code-review` skill against the diff currently under review in this session (the
working tree against the branch's merge-base, or a named commit range).

Invariant this command exists to state, not to re-implement: both reviewer agents must run in
genuinely fresh, independent contexts — never paraphrase the diff's intent to either of them, never
share one reviewer's findings with the other before both verdicts are formed. Overall `READY`
requires **both** agents to return `READY`; a single `NOT READY` blocks and routes back to
implement. The written record, not this command's own report, is the evidence.
