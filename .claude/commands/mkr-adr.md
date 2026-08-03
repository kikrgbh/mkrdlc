---
description: Write a numbered ADR for a substantial or hard-to-reverse decision, in the existing docs/adr/NNNN-*.md shape.
---

Run the `mkr-adr` skill to draft an ADR for the decision named in this session.

Invariant this command exists to state, not to re-implement: re-check the next unused `NNNN` in
`MKR_ADR_DIR` immediately before writing, not from an earlier tool call — two ADRs drafted close
together in time is exactly when a stale number gets reused.
