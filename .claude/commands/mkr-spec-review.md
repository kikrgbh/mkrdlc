---
description: Run G1's audit - invoke mkr-spec-reviewer against a spec and record its verdict (phase 1 of the AIDLC loop).
---

Run the `mkr-spec-review` skill against the spec named or most recently drafted in this session.

Invariant this command exists to state, not to re-implement: the `mkr-spec-reviewer` agent must run
in a genuinely fresh context — never paraphrase the spec to it, never share the drafting session's
own opinion of it first. A `READY` verdict is not itself G1 — only a human's recorded approval is.
