---
description: Run phase 8's G5 preflight - check G4/CI/spec status and ask MKR_GATE_MERGE's named approver before merging the current branch. Never merges unprompted.
---

Run the `mkr-merge` skill against the current branch.

Invariant this command exists to state, not to re-implement: merging to `main` is CLAUDE.md's
own "MUST ASK FIRST" action. This skill gathers evidence — a G4 review record, CI status (or an
explicit disclosure that it can't be mechanically confirmed), and an `ACCEPTED` spec — states it
plainly, and then asks the human named by `MKR_GATE_MERGE` by name. It never merges without that
explicit, in-session go-ahead, on either the `gh`-available or the git-only fallback path.
