# mkr-aidlc

A self-hosted AI-Driven Development Lifecycle template for Claude Code. Skills, agents, hooks, and
commands land under `.claude/` **in your own repo** — versioned in your git history, editable by
you, reviewable in your PRs. No plugin install, no marketplace, no MCP server, no API key, no
hosted dependency.

This template lands in the repo and gets committed, so the whole team gets the same loop on clone, 
and removing a gate shows up as a diff someone has to approve. The cost is updates: you pull new 
versions deliberately with `/mkr-update` instead of getting them automatically.

## The loop

Every non-trivial change moves through the same phases, with a gate wherever an independent check
earns its keep:

```
0 triage → 1 spec ⟦G1 spec approved⟧ → 2 plan ⟦G2 plan conformant⟧ → 3 design ⟦G3 design gate⟧
→ 4 tests → 5 implement → 6 verify → 7 review ⟦G4 review gate⟧ → 8 merge ⟦G5⟧ → 9 ground → 10 ship ⟦G6⟧
```

- **Triage** (phase 0) decides how much process a change earns — see Depth below — and that
  decision, not guesswork, is what turns each later gate on or off before any code is written.
- **G1, G3, and G4** each spawn two independent, fresh-context reviewer agents with different
  lenses — spec review against the named approver; design review as contracts+data-model vs.
  boundaries+security-architecture; code review as correctness vs. security — and both must return
  READY.
- **Ground** (phase 9) is this template's most distinctive step: a fresh agent with no memory of
  the build re-verifies the merged commit actually does what the spec claimed, writing an
  independently checkable record to `.mkr/audits/<sha>.md` — not trusting the build's own
  Definition-of-Done checkboxes.
- **Capture and ADR** run alongside every phase, not as a phase of their own: a correction or
  incident that recurs twice becomes a proposed rule; any substantial or hard-to-reverse decision
  gets a record under `docs/adr/` (ADR - Artchitecture Decision Record).

See `docs/DESIGN.md` §2 for the full diagram and the reasoning behind each phase.

## Principles

1. **Files, not fetches — and files you own.** Every skill body is a real file in your repo.
   Nothing resolves over a network, and nothing lives somewhere you can't read, diff, or edit.
2. **Enforcement honesty.** An advisory warning is not a gate. Every gate below names exactly how
   it's enforced — a hook that denies the tool call, a CI check that blocks the merge, or a warning
   that surfaces without stopping you.
3. **One seam for your project's facts.** Test commands, protected branches, thresholds, and which
   plan steps are mandatory all live in `.mkr/config` — the one file an update never overwrites.
4. **Right-sized.** Three depths (below). A typo doesn't pay for a spec; a process that can't be
   skipped for small work gets bypassed for everything.
5. **Evidence, not memory.** Every gate writes a file — specs, plans, reviews, ADRs, audits. All
   greppable, diffable, reviewable — including this repo's own `NOT READY` rounds, kept as evidence
   of the method working, not scrubbed from the history.
6. **Independent eyes at the two expensive moments.** Before code is written, and after. Both gates
   run two reviewers in parallel with different lenses, and both must agree.

## Depth: how much process a change earns

| Depth | When | What runs |
|---|---|---|
| **Quick** | A typo or config fix — no behaviour change, no new file beyond a test | Implement + test + a one-line review note |
| **Standard** | A feature in an existing module | The full loop, single pass |
| **Deep** | A new module, auth, the data model, or anything hard to reverse | The full loop + an ADR + a mandatory grounding audit |

Depth falls out of a handful of mechanical questions asked during triage — does this touch a risky
path, does it change a contract, is it reversible — not chosen by feel. It's a floor, not a
ceiling: if a later phase discovers the change needs more process than triage guessed, the depth
goes up from that point on, stated out loud, never silently.

## Gates

| Gate | Enforced by | Tier |
|---|---|---|
| G1 spec approved | `spec-gate.sh` — first source edit on a branch with no approved spec | ASK |
| G2 plan conformant | the `mkr-plan` skill's verdict; nothing mechanical | WARN |
| G3 design gate | two agents must both return READY; record required | WARN |
| G4 review gate | `pre-push-review-guard.sh` locally; CI checks the record exists | WARN → CI |
| G5 merge | branch protection + `mkr-gate.yml` (tests, coverage, lint, ADR/id collisions) | CI |
| G6 deploy | deploy commands are never auto-allowed → permission prompt every time | ASK |
| — push to protected | `branch-guard.sh` | BLOCK |
| — secrets | `secret-guard.sh` | BLOCK |
| — duplicate ADR/migration id | `id-collision-guard.sh` | BLOCK |

Three things block outright and work offline: pushing to a protected branch, staging secrets or
writing key material, and a duplicate ADR/migration number. Everything else is either a soft nudge
or a required CI check. See `docs/DESIGN.md` §4 for the full rationale.

## Installing

```sh
curl -fsSL https://raw.githubusercontent.com/kikrgbh/mkrdlc/main/install.sh | bash
```

To preview what would change before applying it:

```sh
curl -fsSL https://raw.githubusercontent.com/kikrgbh/mkrdlc/main/install.sh | bash -s -- --dry-run
```

## Build status

This template is self-hosting: every skill, agent, and guardrail hook it ships has been exercised
against this repo's own commits, not just described. See `docs/DESIGN.md` §8 for the full
phase-by-phase build sequence and what each milestone landed.

## Layout

```
CLAUDE.md · .mkr/config          this project's own facts
install.sh                       classify → stage → move installer/updater, all-or-nothing,
                                  never deletes (M6 slice 1)
.claude/mkr-manifest             generated by install.sh — hash+mode per template-owned path
.claude/settings.json            the first committed hook wiring — PreToolUse/PostToolUse/Stop
.claude/hooks/lib/config.sh      the config reader — sourced by hooks, executed by skills/CI
.claude/hooks/lib/hookio.sh      shared, jq-free hook I/O — stdin JSON in, decision JSON out
.claude/hooks/scripts/           pre-push-review-guard.sh — G4's local WARN-only half; six
                                  Claude-Code tool-hooks — secret/branch/id-collision-guard.sh
                                  (BLOCK), spec-gate.sh (ASK), stop-checks.sh, audit-log.sh
.claude/skills/                  mkr-loop · mkr-spec · mkr-spec-review · mkr-plan · mkr-adr ·
                                  mkr-code-review · mkr-audit · mkr-merge · mkr-design · mkr-gates ·
                                  mkr-ship · mkr-evals · mkr-capture · mkr-update · mkr-detect ·
                                  mkr-rkp
.claude/commands/                the thin, explicit doors onto those skills, + /mkr-init
.claude/agents/                  mkr-spec-reviewer (G1) · mkr-code-reviewer + mkr-security-reviewer
                                  (G4) · mkr-auditor (ground) · mkr-design-reviewer +
                                  mkr-architecture-reviewer (G3) — fresh-context, read-only except
                                  mkr-auditor's added Bash
.github/workflows/mkr-gate.yml   CI: test/coverage/typecheck/lint/build, ADR-uniqueness, G4 record
seed/                            the generic CLAUDE.md/config pair handed to adopters — the source
                                  install.sh seeds the owned pair from (M6)
docs/DESIGN.md · docs/adr/       design note and decision records
docs/rkp/                        this repo's own Repo Knowledge Package — built/refreshed by
                                  mkr-rkp, on demand
specs/                           milestone specs
tests/                           the config reader's suite, the artifact-shape suite, the
                                  guardrail-hooks suite, the installer suite
.mkr/reviews/ · .mkr/audits/ ·   code-review records (G4), grounding audits, and design-gate
.mkr/designs/                    records (G3), produced on this project's own work
.mkr/audit.jsonl                 audit-log.sh's own append-only trail of tool calls
```

## Running the tests

```sh
bash tests/config_test.sh
bash tests/mkr_artifact_test.sh
bash tests/hooks_test.sh
bash tests/install_test.sh
```
