---
name: mkr-ship
description: Runs phase 10's G6 gate (docs/DESIGN.md §2) - ASK-gated, opt-in via MKR_DEPLOY. Reports "not configured, no action" when MKR_DEPLOY is empty; otherwise states the pre-flight and the exact command, then asks the human named by MKR_GATE_DEPLOY before ever running it. Never auto-runs a deploy command. Use once a change is merged and ground (phase 9) has run, on a project that has somewhere to deploy to.
---

# mkr-ship — phase 10's G6 gate

`mkr-ship` never deploys on its own judgment — deploying is `docs/DESIGN.md` §4's own example of a
gate that is never auto-allowed, a permission prompt every time. Its job is to state plainly what it
is about to do and then actually ask — never to proceed unprompted — and, just as importantly, to
say honestly when there is nothing configured to do at all.

## 1. Not-configured check

Run `config.sh get MKR_DEPLOY` (CLI mode). If `MKR_DEPLOY` is empty: report "ship is opt-in
(`MKR_DEPLOY` is not set) — nothing to do for this project" and stop here. Do not proceed to step 2.
This is an honest "not configured," not a stub that looks like it succeeded — this repo's own
`.mkr/config` takes this path today, since nothing in this template runs standalone or is deployed.

## 2. Pre-flight, and state the exact command

If `MKR_DEPLOY` is set: run whatever this project names as its own pre-flight (documented in that
project's own `.mkr/config` comments — not invented here; a project with no separate pre-flight step
skips straight to naming the deploy command itself). State the exact command about to run.

**A project whose deploy is a GitHub Actions `workflow_dispatch`, not a literal binary/script**
(issue #12): `MKR_DEPLOY`'s contract (`.claude/hooks/lib/config.sh` §7) is a shell command string,
not a named-workflow reference — there is no separate "workflow" value shape, and adding one would
be a config.sh contract change requiring its own spec (CLAUDE.md's `MUST ASK FIRST` on
`MKR_RISKY_PATHS`), not something this skill can introduce unilaterally. In the meantime, the
existing shell-command contract already covers this case indirectly: set `MKR_DEPLOY` to the `gh`
CLI invocation that triggers it, e.g. `gh workflow run deploy.yml -f env=prod` — step 4 runs that
command exactly like any other, and its result (including `gh`'s own dispatch confirmation, not the
triggered run's actual outcome) is reported the same way. Say so explicitly if a project's
`MKR_DEPLOY` looks like a `gh workflow run`/`gh api` invocation, so nobody mistakes step 4's report
of a successful *dispatch* for a report of the deploy itself having finished.

## 3. Ask

**Ask.** Name `MKR_GATE_DEPLOY`'s resolved approver (`config.sh get MKR_GATE_DEPLOY`, CLI mode) as
the required approver, and require their explicit go-ahead in this session before step 4. Never
proceeds unprompted, on any path.

## 4. Execute

Only after explicit confirmation in this session: run `MKR_DEPLOY`. Report its result plainly (exit
code, output tail) — success or failure, not assumed.

## 5. What this skill does not attempt

Canary analysis, automatic rollback triggers, and drift/cost watching are this project's own
documented, human-run procedures (specs/M5_Gates_Spec.md §3) — `mkr-ship` does not attempt any of
them. State this plainly if a project's own pre-flight notes mention any of the three, so nobody
mistakes their absence here for an oversight.
