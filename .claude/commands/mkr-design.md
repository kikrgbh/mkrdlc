---
description: Run phase 3's G3 gate - spawn mkr-design-reviewer and mkr-architecture-reviewer against an ACCEPTED spec's §6/§7/§8, and record a design-gate verdict.
---

Run the `mkr-design` skill against the spec named (default: the newest `ACCEPTED` spec on this
branch whose triage `gates:` line marks `design: ✓`).

Invariant this command exists to state, not to re-implement: both reviewers must run in a genuinely
fresh context, with no memory of drafting the spec — never paraphrase its design intent to either
of them, never share what you expect them to find. `mkr-design-reviewer` takes a contracts/
data-model/error-edge/reuse lens; `mkr-architecture-reviewer` takes boundaries/scalability/
security-architecture/stack-fit. Both must return `READY` for an overall `READY`; a `NOT READY`
routes back to the spec, not to code that doesn't exist yet.
