# Grounding audit and merge: `mkr-audit`, `mkr-auditor`, `mkr-merge`

## Intent

- `mkr-audit` (skill) + `mkr-auditor` (agent) run a fresh-context grounding audit: independently
  reproduce a spec's acceptance criteria against real repo state, and write a structurally-checkable
  record to `.mkr/audits/<short-sha>.md`.
- `mkr-merge` (skill) is a G5 preflight: checks a review record exists, CI status, and the branch's
  spec is `ACCEPTED`, states the findings, and asks the human named by `MKR_GATE_MERGE` before ever
  touching a protected branch. It never merges unprompted.
- The grounding audit stays evidence-gathering, checked at DoD time — not a new blocking gate. The
  loop's own phase ordering places ground *after* merge, so it cannot be a pre-merge gate.

## Scope

**In scope**
- `mkr-audit` (skill + command) — resolves the spec and commit under audit, spawns `mkr-auditor`
  fresh-context, writes/updates `.mkr/audits/<short-sha>.md`.
- `mkr-auditor` (agent) — fresh-context, no memory of the build, reproduces acceptance criteria
  against the real repo rather than trusting a DoD's say-so.
- The audit record format (below) — a mechanically-checkable contract.
- `mkr-merge` (skill + command) — G5 preflight plus gated, human-confirmed merge execution.
- New structural test cases for the artifacts above.

**Out of scope**
- Judging whether an audit's *findings* are correct, not just well-formed.
- A new blocking CI/hook gate requiring an audit record before the next merge — ground follows
  merge in the loop's phase ordering, so it stays evidence-gathering, checked at DoD time.
- Deploy/ship tooling.
- CI-status verification on any platform other than GitHub — `mkr-merge` degrades to a disclosed,
  lower-confidence manual-confirmation path when `gh` is unavailable, rather than assuming a
  specific platform.
- Widening the passive tool-call log to record `PreToolUse` denials, not just completed calls —
  `mkr-auditor` reads the completed-calls log as corroborating evidence only; a completed-calls-only
  trail is sufficient for that.

## Architecture & key decisions

- **`mkr-auditor` gets `Bash`, unlike the read-only spec/code-review reviewer agents** (`Read,
  Grep, Glob` only). Judging a diff or spec against its own claims doesn't require executing
  anything; grounding does — reproducing "is it reachable, is it real, does it do what was
  claimed" needs running the real test suite, hand-building fixtures, and piping real input at hook
  scripts directly. No `Edit`/`Write`: an auditor reproduces and reports, it does not fix what it
  finds.
- **`mkr-merge`'s default strategy is a real merge commit** (`gh pr merge --merge`), not squash or
  rebase.
- **A merge conflict is proposed, never auto-resolved; a branch deletion is its own separate ask**
  (docs/adr/0006-mkr-merge-conflict-and-branch-cleanup.md) — two hard-to-reverse-adjacent actions
  `mkr-merge` gained after this milestone, each gated the same "never proceed unprompted" way as
  the merge itself, never bundled into that single confirmation.
- **`mkr-merge` never executes a merge unilaterally.** It gathers evidence (review record present,
  CI green, spec `ACCEPTED`), states the findings, and asks the human named by `MKR_GATE_MERGE` by
  name before running anything that touches a protected branch. When `gh` is unavailable or
  unauthenticated, or the branch has no open PR, it cannot mechanically confirm CI status — it says
  so explicitly (never silently assumes green) and requires the human to state CI is green as part
  of the confirmation. Its fallback path creates the merge commit locally
  (`git merge --no-ff`) only — it never follows with a `git push` to the protected branch, since
  that push would itself be denied by branch-guard's BLOCK tier; pushing the resulting local commit
  is the human's own action, outside the skill. Both paths ask; neither acts autonomously.
- **Data flow**: `mkr-audit` resolves the spec path and target commit (default: `HEAD` on the
  current branch), spawns `mkr-auditor` with the spec's path, the commit, and the branch name, with
  explicitly no memory of having built the change under audit. `mkr-auditor` reads the spec's
  acceptance criteria, and for each one: reads the relevant source, re-runs the real test suite
  fresh, hand-builds fixtures reproducing the criterion's true-positive/false-positive behavior
  where applicable, and cross-checks the passive tool-call log as corroborating evidence that
  claimed commands actually ran. `mkr-audit` writes the result to `.mkr/audits/<short-sha>.md`
  using the same fixed 7-character short-SHA convention used elsewhere in this repo for
  commit-named records.

## Interfaces / contracts

**`mkr-audit`** (skill + command). Input: a spec path (defaults to the newest `ACCEPTED` spec
touched on the current branch) and a commit SHA (defaults to `HEAD`). Steps: resolve the spec and
target SHA and compute its short SHA; spawn `mkr-auditor` fresh-context; receive a per-AC verdict
table plus evidence; write (or update, on a re-audit of the same SHA) the audit record; report the
closing `PASS`/`FAIL (<n> not verified)` verdict back to the invoking session. A `FAIL` does not
block anything mechanically — it is read by whoever is deciding whether the milestone is done.

**`mkr-auditor`** (agent). Tools: `Read, Grep, Glob, Bash`. Input: the spec's path, the target
commit SHA, the branch name, and (for a re-audit) the prior round's record, so a re-audit can state
whether an earlier finding was actually fixed rather than take a newer diff's claim on faith.
Method, per acceptance criterion: read the relevant source directly; re-run the project's real test
suite fresh; where the criterion names a true-positive/false-positive behavior, hand-build an
independent fixture and exercise it directly (not just the project's own test harness, which could
share a blind spot with the code it tests); cross-check the passive tool-call log for corroborating
evidence. Discloses, rather than silently omits, anything that remains genuinely unverifiable.
Output: a per-AC verdict, `VERIFIED` or `NOT VERIFIED (<reason>)`, each with an evidence string
describing exactly what was independently reproduced. A `VERIFIED` row may still carry a disclosed,
non-blocking caveat found along the way.

**Audit record format**, written to `<MKR_AUDITS_DIR><short-sha>.md`, required elements in order:
1. `# Grounding audit — <milestone/change label>, commit <short-sha>` (or, absent a milestone
   label, `# Grounding audit — <short-sha>`).
2. One provenance paragraph: states the auditor is fresh-context with no memory of the build,
   names the spec, the AC range under audit, and the branch.
3. A table, exactly `| AC | Verdict | Evidence |`, one row per acceptance criterion named in the
   spec, in order, no silent omission. `Verdict` is exactly `VERIFIED` or `NOT VERIFIED (<reason>)`
   — a strict two-literal vocabulary, mandatory for mechanical checkability.
4. **Additional checks the auditor ran independently** — a bullet list of anything checked beyond
   the AC table proper.
5. **Outstanding, not a defect** — optional; open DoD items not yet checked at this commit, named
   so they aren't mistaken for AC violations.
6. Closing `**Verdict:**` paragraph. Must read `PASS` if and only if every AC row's `Verdict` is
   exactly `VERIFIED`; otherwise `FAIL (<n> not verified)` naming which.

**`mkr-merge`** (skill + command). Input: none — operates on the current branch. Steps:
1. Resolve the current branch; confirm it is not itself a protected branch.
2. **Review check.** Confirm a review record exists for the branch's HEAD short SHA.
3. **CI check.** If `gh` is available, authenticated, and the branch has an open PR: require all
   required checks passing. Otherwise: disclose explicitly that CI status cannot be mechanically
   confirmed, rather than assuming green.
4. **Spec check.** Confirm the branch's own spec(s) carry `**Status** | ACCEPTED rev N (...)`.
5. **Conflict check** (docs/adr/0006-mkr-merge-conflict-and-branch-cleanup.md). Dry-run the merge
   (`git merge-tree`, no working tree/index touched). Clean → continue. Conflicting → stop, name
   the conflicting files, propose one specific resolution, and require its own separate explicit
   approval before it is ever applied — never auto-resolved, never folded into step 6's merge ask.
6. State all findings plainly, then **ask** — never proceed unprompted — naming
   `MKR_GATE_MERGE`'s resolved value as the required approver, requiring their explicit go-ahead.
7. Only after explicit confirmation: if `gh` is available, `gh pr merge --merge`; otherwise
   `git merge --no-ff` into the target protected branch locally, creating the merge commit only —
   never followed by `git push`. Report the resulting merge commit SHA (or, on the fallback path,
   that the local commit is ready and pushing it is the human's own action).
8. **Bookkeeping** — real, pushed merge only. Confirm the PR body's `Closes #N`/`Fixes #N` linkage
   actually closed the named issue(s) (`gh issue view`); if the linkage was missing, close them
   explicitly instead of leaving them open. Post a closing PR comment naming the merge SHA, the G4
   record, and the spec.
9. **Branch cleanup** — a second, separate ask (docs/adr/0006), only after a real, pushed merge.
   A "yes" to step 6's merge ask is never read as a "yes" here; only an explicit yes to this
   question deletes the now-merged source branch.
10. Hand off: state that `mkr-audit` should run next, against the newly merged commit.

## Data model

No new `config.sh` variable. `MKR_AUDITS_DIR` and `MKR_GATE_MERGE` already exist as published
contract stubs with real resolved values; this milestone builds their first real consumers.

One new artifact shape, not a config variable: the audit record, per the format above.
