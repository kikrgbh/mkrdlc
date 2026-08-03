---
description: Draft a spec for the change just triaged (phase 1 of the AIDLC loop). Requires a completed mkr-loop triage first.
---

Run the `mkr-spec` skill for the current change.

If `mkr-loop` hasn't triaged this change yet in this session, run it first — `mkr-spec` needs a
`TRIAGE` block to embed as `## 0. Triage`, it does not re-derive one.

Invariant this command exists to state, not to re-implement (the skill owns the actual logic):
never mark the drafted spec's `Status` as `ACCEPTED` — only a human G1 approval does that, per
`MKR_SELF_APPROVE`. Never overwrite an already-`ACCEPTED` spec's `§0`–`§6` in place without bumping
its rev number in `Status`.
