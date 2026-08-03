# Design gate, mid-session re-triage, ship gate, evals, and capture

## Intent

Adds tooling for three loop phases that previously existed only as prose in `docs/DESIGN.md`:
the design gate (G3), ship (G6), and the cross-cutting CAPTURE mechanism. Also closes two
smaller gaps: judging whether a reviewer/auditor agent's *findings* are correct (not just
well-formed), and turning a mid-session scope escalation into an actual branch split instead of
halting the session for a human to sort out by hand.

Five components:
- `mkr-design` — G3: two fresh-context reviewers check an ACCEPTED spec's design sections.
- `mkr-gates` — re-triages a sub-slice of in-flight work and, where safe, splits it onto its own
  branch/PR so it can go through its own loop while the rest of the session continues.
- `mkr-ship` — G6: ASK-gated, opt-in deploy pre-flight.
- `mkr-evals` — runs a reviewer/auditor agent against golden fixtures and reports match/mismatch.
- `mkr-capture` — appends corrections/incidents to a durable log; flags recurrence.

## Scope

**In scope**
- `mkr-design-reviewer`, `mkr-architecture-reviewer` agents.
- `mkr-design` skill + command.
- `mkr-gates` skill (no command — invoked by other skills or a human naming a sub-slice).
- `mkr-ship` skill + command.
- `mkr-evals` skill (no command).
- `mkr-capture` skill (no command).
- `config.sh`: `MKR_DESIGN_DIR`, `MKR_DEPLOY`, `MKR_EVALS_DIR`, `MKR_CAPTURE_LOG`.

**Out of scope**
- Automated canary analysis, automatic rollback triggers, drift/cost monitoring — stays a
  per-project, human-run procedure `mkr-ship` documents but does not automate.
- Judging `mkr-evals`' own judgment — its comparison is a deterministic string-compare, not
  recursive.
- Seeding golden fixtures for every existing agent — only `mkr-spec-reviewer` is seeded.
- A CI-enforced G3 or G6 gate — both stay WARN/ASK, not CI-blocking.
- Multi-platform deploy support — only a `gh`-shaped preflight-and-execute path.
- Rewriting already-committed history to perform a split — only an uncommitted sub-slice is
  split automatically; an already-committed one gets a disclosed manual-split ask.

## Architecture & key decisions

```
.claude/
├── agents/
│   ├── mkr-design-reviewer.md         fresh context; contracts/data-model/error-edge/reuse
│   └── mkr-architecture-reviewer.md   fresh context; boundaries/scalability/security-arch/stack-fit
├── skills/
│   ├── mkr-design/SKILL.md            G3: spawn both reviewers, record verdict
│   ├── mkr-gates/SKILL.md             re-triage a sub-slice; split via stash+worktree, no command
│   ├── mkr-ship/SKILL.md              G6: ASK-gated, opt-in via MKR_DEPLOY
│   ├── mkr-evals/SKILL.md             judge agent-verdict correctness vs. golden fixtures
│   └── mkr-capture/SKILL.md           append + same-class-twice rule proposal, no command
├── commands/
│   ├── mkr-design.md                  thin door onto mkr-design
│   └── mkr-ship.md                    thin door onto mkr-ship
└── hooks/lib/config.sh                + MKR_DESIGN_DIR, MKR_DEPLOY, MKR_EVALS_DIR, MKR_CAPTURE_LOG

.mkr/
├── designs/<Slug>-rev<N>.md            G3 records
└── evals/
    ├── fixtures/<agent-name>/*.md      golden input/expected-verdict pairs
    └── <agent-name>-<run>.md           eval run reports
```

- **G3's two reviewers mirror G4's** — parallel, fresh context, different lenses, both must
  return `READY`. Unlike G4 there is no diff yet; the reviewers check the already-ACCEPTED
  spec's own §6 (Architecture), §7 (Interfaces/contracts), §8 (Data model).
  `mkr-design-reviewer` takes contracts/data-model/error-edge/reuse; `mkr-architecture-reviewer`
  takes boundaries/scalability/security-architecture/stack-fit.
- **Design records key on spec slug + revision, not a commit SHA** — no commit exists yet at G3
  time. Re-review after a spec revision produces `<Slug>-rev<N+1>.md`.
- **`mkr-gates`' split mechanic: `git stash push -u -- <paths>`, then a new branch created
  without checking it out, then `git worktree add` for a physically separate checkout, then pop
  the stash there.** Restricted to still-uncommitted paths. A plain `git stash branch` checks the
  new branch out in the same working directory, which leaves the session's own remaining,
  untouched work visible on both branches at once — the worktree isolates it instead. An
  already-committed sub-slice is not rebased or cherry-picked automatically; the situation and
  the specific commits/paths are disclosed and the human is asked to split it by hand.
- **`mkr-gates` re-triages using `mkr-loop`'s own six-question classification** rather than a
  second, parallel decision rule. Re-runs those six questions against just the sub-slice's own
  scope; only splits if the resulting gates aren't already covered by the current session's
  existing depth.
- **`mkr-ship` is ASK-tier and opt-in via `MKR_DEPLOY`; it never auto-runs a deploy command**,
  and no deploy command is ever added to a `settings.json` auto-allow list. Empty `MKR_DEPLOY`
  reports "not configured" and takes no action. Set, it states the pre-flight and the exact
  command, then asks — naming `MKR_GATE_DEPLOY`'s resolved approver — before ever executing it.
- **`mkr-evals` judges agent-verdict correctness against golden fixtures**, seeded for one agent
  this milestone: `mkr-spec-reviewer`, with two fixtures (one expected `READY`, one expected
  `NOT READY`).
- **`mkr-capture`'s same-class-twice threshold is a fixed 2**, not a config knob — matches the
  literal threshold `docs/DESIGN.md` states for the mechanism.
- **Bootstrap: `mkr-design` cannot review the spec that builds it** — this spec's own G3 was
  satisfied by direct human review against `docs/DESIGN.md`, the same bootstrap exemption earlier
  milestones used for their own first gate.

## Interfaces / contracts

**`mkr-design` (skill + command).** Input: a spec path, defaulting to the newest
`Status: ACCEPTED` spec on the current branch. Applies only when triage derived `design: ✓` for
this spec. Confirms `Status: ACCEPTED`, spawns both reviewers in parallel against §6/§7/§8 only,
aggregates to `READY` only if both are, writes `<MKR_DESIGN_DIR><Slug>-rev<N>.md`. Blocking
findings route back to the spec (a revision), since no code exists yet at G3 time.

**`mkr-design-reviewer` / `mkr-architecture-reviewer` (agents).** Tools: `Read, Grep, Glob` only.
Input: the spec's path, and on a re-review, the prior round's design record. Output:
`VERDICT: READY` or `VERDICT: NOT READY (<n> blocking)` plus findings, each citing a section
(§6/§7/§8) rather than a file:line.

**Design record format**, written to `<MKR_DESIGN_DIR><Slug>-rev<N>.md`:
1. `# Design review — <Slug> rev <N>`
2. Reviewers — both agents' own lens and sub-verdict.
3. Scope — spec, revision, sections reviewed; on a re-review, what changed since the prior round.
4. One `##` per finding — omitted entirely when there are none.
5. Findings not pursued further, with why.
6. Verdict — `READY` iff both sub-verdicts in element 2 are `READY`.

**`mkr-gates` (skill, no command).** Input: a description of a sub-slice. Re-runs `mkr-loop`'s
six-question classification against just that sub-slice. If its derived gates are already
covered by the session's existing depth, reports "no split needed." If not and the paths are
still uncommitted: stash, branch, worktree, pop (as above), then push and open a PR if `gh` is
available, else report the worktree path and branch name for manual push. If already committed:
report the situation and ask for a manual split. Either way, confirms back to the calling session
that its own remaining, already-in-scope work is untouched and can continue.

**`mkr-ship` (skill + command).** Input: none. Reads `MKR_DEPLOY`; if empty, reports "not
configured" and stops. If set, runs the project's own documented pre-flight, states the exact
command, and asks — naming `MKR_GATE_DEPLOY`'s resolved approver — before running it. Only after
confirmation does it run the command and report its result. States plainly that canary analysis,
rollback, and drift/cost watching are the project's own human-run procedures, not attempted here.

**`mkr-evals` (skill, no command).** Input: an agent name, implicitly reading
`<MKR_EVALS_DIR>fixtures/<agent-name>/`. For each fixture: read its input and its
`expected: <verdict>` line, spawn the named agent fresh against the input, compare its actual
verdict to the expected one, record `MATCH` or `MISMATCH`. Writes
`<MKR_EVALS_DIR><agent-name>-<run-label>.md`: one row per fixture plus a pass count. No aggregate
PASS/FAIL gate — an evidence report a human reads to decide whether they still trust the agent.

**`mkr-capture` (skill, no command).** Input: a class slug, a one-line description, optionally a
spec/commit reference. Appends one JSONL line to `MKR_CAPTURE_LOG`. Counts existing entries
sharing that class; at 2 or more, states the recurrence explicitly and proposes a durable rule (a
`CLAUDE.md` non-negotiable, an ADR, or a skill/hook change). At 1, logs only.

## Data model

| Variable | Default | Consumed by | For |
|---|---|---|---|
| `MKR_DESIGN_DIR` | `.mkr/designs/` | `mkr-design` (write) | where G3 records live |
| `MKR_DEPLOY` | (empty — opt-in) | `mkr-ship` (read; empty ⇒ not configured) | the project's own deploy command |
| `MKR_EVALS_DIR` | `.mkr/evals/` | `mkr-evals` (read fixtures, write reports) | where golden fixtures and eval reports live |
| `MKR_CAPTURE_LOG` | `.mkr/captures.jsonl` | `mkr-capture` (append) | the failure/correction log's path |

No `MKR_CAPTURE_THRESHOLD` — the same-class-twice threshold is fixed at 2 in `mkr-capture`'s own
skill body, not a config variable. No new `MKR_GATE_*` variable — `MKR_GATE_DESIGN` and
`MKR_GATE_DEPLOY` already exist as published config-contract stubs; this spec activates them
with real consumers.
