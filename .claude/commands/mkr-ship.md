---
description: Run phase 10's G6 gate - check MKR_DEPLOY, and if configured, state the pre-flight and ask before running it. Never auto-deploys.
---

Run the `mkr-ship` skill against this project's own `MKR_DEPLOY` (via `config.sh get MKR_DEPLOY`,
CLI mode).

Invariant this command exists to state, not to re-implement: deploying is never auto-allowed —
`mkr-ship` always states the exact command and asks, naming `MKR_GATE_DEPLOY`'s resolved approver,
before ever executing it, on every path. If `MKR_DEPLOY` is empty, it reports that plainly and takes
no action — it does not simulate success.
