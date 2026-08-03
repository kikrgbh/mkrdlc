---
description: Run install.sh --dry-run against a source checkout, show a human-readable drift report, and ask before applying the update for real. Never applies unprompted.
---

Run the `mkr-update` skill against the source checkout named (asked for, if omitted).

Invariant this command exists to state, not to re-implement: `mkr-update` runs `install.sh` twice —
a dry run to build the drift report, and the real run only after the human's explicit go-ahead. A
nonzero exit from the dry run means a precondition failed before any classification happened; the
skill reports that error and stops, rather than asking permission for a run that would fail
identically. It never edits `CLAUDE.md` or `.mkr/config`, and never writes anything on the dry-run
pass.
