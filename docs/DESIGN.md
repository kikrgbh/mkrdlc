# mkr-aidlc — an open-source AIDLC template for Claude Code

A self-contained AI-Driven Development Lifecycle you copy **into your repo**. Skills, agents,
hooks, commands — all of it lands under `.claude/`, versioned in your git history, editable by
you, reviewable in your PRs. No plugin install, no marketplace, no MCP server, no API key, no
hosted dependency.

```bash
curl -fsSL https://raw.githubusercontent.com/kikrgbh/mkrdlc/main/install.sh | bash
```

**Why a template rather than a plugin.** A plugin installs at user scope: it belongs to one
developer, follows them across every repo, and can be uninstalled at will — which is why a
plugin's gates are honestly described as *soft*. A template lands in the repo and is committed,
so the whole team gets the same loop on clone, changing a gate shows up as a diff someone has to
approve, and the enforcement claim in principle 2 becomes something the repo itself carries. The
cost is updates: you pull new versions deliberately instead of getting them automatically (§7).

---

## 1. Principles

1. **Files, not fetches — and files you own.** Every skill body is a real file in your repo.
   Nothing resolves over a network, and nothing lives somewhere you can't read, diff or edit.
2. **Enforcement honesty.** *An advisory warning is not a gate.* Every gate declares which of three
   tiers it is — **BLOCK** (hook denies the tool call), **CI** (blocks the merge), **WARN**
   (surfaces, doesn't stop). Nothing claims to gate what it cannot reach.
3. **One seam for your project's facts.** Test commands, paths, protected branches, thresholds and
   which plan steps are mandatory live in `.mkr/config` — the one file the template never
   overwrites on update. Everything else is template-owned and replaceable.
4. **Right-sized.** Three depths. A typo does not pay for a spec. A process that can't be skipped
   for small work gets bypassed for everything.
5. **Evidence, not memory.** Every gate writes a file — specs, plans, reviews, ADRs, audits. All
   greppable, diffable, reviewable.
6. **Independent eyes at the two expensive moments.** Before code is written, and after. Both gates
   run two reviewers in parallel with different lenses.

---

## 2. The loop

```
                    ┌─────────────── 0 · TRIAGE ───────────────┐
                    │  Quick  ·  Standard  ·  Deep             │
                    └──────────────────┬──────────────────────┘
                                       ▼
   1 · SPEC ─────────────────────────► ⟦G1⟧ spec approved
        write:  intent · scope · reuse check · acceptance criteria · test register
        audit:  mkr-spec-reviewer → READY | NOT READY   (mkr-spec-review)
                                       ▼
   2 · PLAN ─────────────────────────► ⟦G2⟧ plan conformant
        ordered steps, reviewed against the project's declared baseline
        → CONFORMANT | BLOCKED (missingMandatory · orderingViolations)
                                       ▼
   3 · DESIGN ───────────────────────► ⟦G3⟧ design gate      ┐
        mkr-design-reviewer  ∥  mkr-architecture-reviewer     │ two reviewers,
        contracts, data model,   boundaries, scalability,     │ parallel,
        error/edge, reuse        security arch, stack fit     │ one gate
                                       ▼                      ┘
   4 · TESTS
        written from the spec's test register — before the code they cover
                                       ▼
   5 · IMPLEMENT
        one task per agent, isolated context, commit per task
        exit condition: self-review (reuse · security · standards · simplicity)
                                       ▼
   6 · VERIFY
        tests green · coverage · typecheck · lint · evals (if AI-bearing)
                                       ▼
   7 · REVIEW ───────────────────────► ⟦G4⟧ review gate      ┐
        mkr-code-reviewer  ∥  mkr-security-reviewer           │ two reviewers,
        fresh context, reads the diff against the spec        │ parallel,
        → READY | NOT READY, recorded to .mkr/reviews/<sha>.md│ one gate
        blocking findings ──────────────► back to 5           ┘
                                       ▼
   8 · MERGE ────────────────────────► ⟦G5⟧ CI green + owner approval
                                       ▼
   9 · GROUND                                            (Standard / Deep)
        fresh agent, no memory of the build: is it reachable, is it real,
        does it do what the spec claimed → triage doc
                                       ▼
  10 · SHIP ─────────────────────────► ⟦G6⟧ deploy gate           (opt-in)
        pre-flight · canary · rollback · drift + cost watch

  ═══ cross-cutting, every phase ═══
   CAPTURE   correction or incident → failure log → same class twice → a rule
   ADR       any substantial or hard-to-reverse decision → docs/adr/NNNN-*.md
```

### The change you asked about: phase 7

The loop previously ended `… → self-review → verify → [merge]`, with code review as a
*recommendation* before push. That conflates two different things:

| | Self-review | Code review |
|---|---|---|
| Who | the agent that wrote the code | a **fresh** agent, no build context |
| Reads | its own diff | the diff **against the spec** |
| Catches | slips, leftovers, obvious duplication | wrong abstraction, missed criterion, silent scope drift |
| Strength | weak — same context, same blind spots | the only independent check before merge |
| Status | exit condition of phase 5 | **phase 7, a real gate** |

So: **self-review stays inside implement as an exit condition, and code review becomes its own
phase with its own gate**, run by an agent that was not part of building the thing. Symmetric with
the design gate — two parallel reviewers with different lenses, both must return READY:

- **G3 (before code):** `mkr-design-reviewer` ∥ `mkr-architecture-reviewer` — cheapest place to
  catch a structural mistake.
- **G4 (after code):** `mkr-code-reviewer` ∥ `mkr-security-reviewer` — the last place to catch it
  before it merges.

Three mechanics worth deciding on (§9):

1. **Re-review on new HEAD.** Fixing a blocking finding creates a new commit, so the recorded
   verdict no longer matches what will be pushed. The record is keyed to the short SHA; a changed
   HEAD means the review is stale and phase 7 re-runs. Default: re-run only the reviewer whose
   finding was fixed.
2. **Where it runs.** On the local diff before push (findings fixed before anyone sees the PR,
   cheap) rather than on the PR (visible, but a round trip per finding). Default: local, pre-push.
3. **How hard it blocks.** The hook is a WARN (evadable by design); the real block is CI checking
   that a review record exists for the merge commit's parent. Default: WARN locally, CI required.

---

## 3. Phase 0 — triage

Triage is a **bounded classification pass**, not exploration. It must be cheap enough that running
it on a one-line fix is not itself the waste — a handful of reads and greps, then a verdict. If you
cannot classify within that budget, that *is* the answer: the change is Standard or Deep.

It runs in two parts.

### A. Preflight — three mechanical checks

1. **Where am I?** Current branch. On a protected branch → create a feature branch first. Uncommitted
   changes that aren't yours → stop and ask before touching anything.
2. **Am I starting or resuming?** Look for an existing spec, branch, plan record or review record for
   this work. Resuming a half-finished change is the single most common way work gets duplicated or
   silently restarted from scratch.
3. **Is this one change or several?** A request that is really three features gets split into three
   loops here — not discovered at plan time, after a spec has already been written for all of it.

### B. Classification — six questions

| # | Question | Why it's asked here |
|---|---|---|
| 1 | **What paths will this touch?** | Matched against `risky_paths` in config. Mechanical, not judgment. |
| 2 | **Does this already exist?** | A cheap reuse pre-check. If yes, the task becomes *extend X* — which often collapses the scope entirely. Discovering this in the spec has already cost the spec. |
| 3 | **Does it change a contract?** | A published API shape, a DB schema, a public interface — anything another consumer depends on. |
| 4 | **Is it reversible?** | Revertable by a commit, or does it write to a third party / migrate data / change external state? |
| 5 | **Does it have a UI or a probabilistic surface?** | These add the design gate and the eval step respectively. |
| 6 | **How will we know it's done?** | One sentence. Stating the acceptance signal now is what makes "done" arguable later. |

### The decision rule

Mechanical, so it isn't taste:

- **Deep** if **any** of: touches a `risky_paths` glob (auth, migrations, infra, CI, tenancy) · introduces
  a new module, service or package · changes a published contract · is hard to reverse · touches a
  non-negotiable listed in `CLAUDE.md`.
- **Quick** only if **all** of: a single localized fix or no behaviour change · no new file beyond a
  test · no interface change · covered by existing tests or one added test · undone by a plain revert.
- **Standard** otherwise.

**Standard is the default; ambiguity resolves upward.** The cost is asymmetric — over-processing a
small change costs minutes, under-processing a risky one costs an incident.

### The output

For Quick, one line. For Standard and Deep, this block — which becomes **§0 of the spec**, so triage
creates no artifact of its own:

```
TRIAGE
depth:    standard
why:      adds an endpoint + a screen inside an existing module; no schema or auth change
scope:    one change
reuse:    extends the existing preferences service — no parallel implementation
touches:  api/src/preferences/**, web/src/settings/**
risky:    none matched
gates:    spec ✓ · plan ✓ · design ✓ (UI) · review ✓ · ground ✓ · adr ✗ · ship ✗
done when: a user can set the preference from settings and it survives a reload
```

The `gates` line is derived, not chosen — it falls out of the depth and questions 1, 3 and 5. That
is the point of doing this first: **every later phase knows whether it applies before any code is
written.**

### Depth → what runs

| | **Quick** | **Standard** | **Deep** |
|---|---|---|---|
| 1 Spec | — | ✓ | ✓ |
| 2 Plan | — | ✓ | ✓ |
| 3 Design gate | — | UI or new contract only | ✓ always |
| 4 Tests | ✓ | ✓ | ✓ |
| 5 Implement | ✓ | ✓ | ✓ |
| 6 Verify | ✓ | ✓ | ✓ |
| 7 **Review gate** | one-line recorded note | ✓ | ✓ + ADR |
| 8 Merge | ✓ | ✓ | ✓ |
| 9 Ground | — | after the slice | ✓ mandatory |
| 10 Ship | per project | per project | per project |

### Escalation — depth is a floor, not a ceiling

Triage runs on incomplete information, so it is allowed to be wrong — but never *silently*. If a
later phase discovers something triage missed (the fix turns out to need a migration; the "small"
change touches the auth guard), **stop and re-triage**. The new depth applies from that point,
including gates already passed under the old one.

Going **down** a level requires the same explicit statement, and it never retroactively skips a gate
already recorded. Silent scope drift is the failure this phase exists to prevent — a change that
quietly grew from Quick to Deep between two turns is exactly the one that reaches production
unreviewed.

---

## 4. Gates and what actually enforces them

| Gate | Enforced by | Tier |
|---|---|---|
| G1 spec approved | `spec-gate.sh` — first source edit on a branch with no approved spec | **ASK** |
| G2 plan conformant | the `mkr-plan` skill's verdict; nothing mechanical | WARN |
| G3 design gate | two agents must both return READY; record required | WARN |
| G4 review gate | `pre-push-review-guard.sh` locally; CI checks the record exists | WARN → **CI** |
| G5 merge | branch protection + `mkr-gate.yml` (tests, coverage, lint, ADR/id collisions) | **CI** |
| G6 deploy | deploy commands are never auto-allowed → permission prompt every time | **ASK** |
| — push to protected | `branch-guard.sh` | **BLOCK** |
| — secrets | `secret-guard.sh` | **BLOCK** |
| — duplicate ADR/migration id | `id-collision-guard.sh` | **BLOCK** |

Three things block outright and work offline: pushing to a protected branch, staging secrets or
writing key material, and a duplicate ADR/migration number. Everything else is either a soft nudge
or a required CI check — and the README says exactly that, per principle 2.

---

## 5. Layout — one repo, self-hosting

**Naming rules** (settled): template **`mkr-aidlc`** · prefix **`mkr-`** on skills, commands and
agents · **skills are named for the phase** (a noun), **agents for the role** (usually `-er`) ·
project facts and evidence live under **`.mkr/`**; the tooling lives under `.claude/`, where Claude
Code already looks.

The prefix survives the pivot from plugin to template, for a different reason than before. It was
chosen to avoid marketplace collisions; there is no marketplace now, but a bare `review`,
`security-review` or `init` would collide with Claude Code's own built-in skills and commands.

### 5.1 The repo — which *is* the template

There is no `template/` directory. The repo's own `.claude/` tree is the tooling that ships, so
there is exactly one copy of every skill, agent, command and hook: the one we use every day.

```
mkr-aidlc/
├── CLAUDE.md                 OUR project file — about building this template
├── .mkr/
│   ├── config                OUR project facts (bash, sourced)
│   ├── reviews/ audits/      OUR evidence — produced by the loop, on itself
│   └── audit.jsonl
├── .claude/                  ★ THE TEMPLATE — single copy, used here and shipped
│   ├── settings.json         hook wiring                              (M3)
│   ├── commands/             mkr-init · mkr-spec · mkr-spec-review · mkr-plan ·
│   │                         mkr-design · mkr-code-review · mkr-audit ·
│   │                         mkr-merge · mkr-ship · mkr-update · mkr-adr ·
│   │                         mkr-detect · mkr-rkp
│   ├── skills/               mkr-loop ★ · mkr-spec · mkr-spec-review · mkr-plan ·
│   │                         mkr-design · mkr-code-review ★ · mkr-gates ·
│   │                         mkr-audit ★ · mkr-merge · mkr-ship · mkr-adr ·
│   │                         mkr-evals · mkr-capture · mkr-detect · mkr-rkp ·
│   │                         mkr-update
│   ├── agents/               mkr-spec-reviewer · mkr-design-reviewer ·
│   │                         mkr-architecture-reviewer · mkr-code-reviewer ·
│   │                         mkr-security-reviewer · mkr-auditor
│   └── hooks/lib/ + hooks/scripts/
├── seed/                     the two owned files an adopter is given
│   ├── CLAUDE.md             generic, placeholder-filled
│   └── config                every variable present, all values empty, each commented
├── specs/ · docs/adr/        our milestone specs and decisions
├── install.sh                                                          (M6)
├── VERSION · README.md · LICENSE (MIT-0)
```

**Why self-hosting.** Drift between "what we use" and "what we ship" is the failure mode that kills
methodology projects. With one copy there is nothing to sync: a broken skill breaks our own build
the same hour, and every skill has been exercised continuously by the time anyone else sees it.
The only carve-out is the two adopter-owned files — our `CLAUDE.md` and `.mkr/config` carry *our*
facts, so `seed/` holds the generic versions.

### 5.2 The adopter's repo — what they end up with (from M6)

```
your-repo/
├── CLAUDE.md                 yours; seeded once from seed/CLAUDE.md, never overwritten
├── .claude/
│   ├── settings.json         hooks wired — in git, so every teammate gets them on clone
│   ├── commands/ skills/ agents/ hooks/      template-owned; replaced on update
│   └── mkr-manifest          version + content hashes: the update seam
├── .mkr/
│   ├── config                yours; seeded once from seed/config
│   ├── reviews/ audits/      evidence
│   └── audit.jsonl
├── specs/ · docs/adr/
└── .github/workflows/mkr-gate.yml
```

**The update seam.** Exactly two paths are the adopter's and never overwritten: `CLAUDE.md` and
`.mkr/config`. Everything under `.claude/` is template-owned and replaced by `/mkr-update`, which
diffs before writing and distinguishes an out-of-date file from one they edited. All of that —
`install.sh`, the manifest, `--force`, portability across shells — is **M6**, because until the
repo goes public there is nobody to distribute to and nothing to upgrade from.

**What the template model buys.** Hooks are wired in a committed `settings.json`, so they apply to
everyone who clones and *removing a gate is a reviewable diff* rather than one developer's private
uninstall. That is the main reason to prefer it over a user-scope plugin.

**What it costs.** Updates are deliberate, not automatic. `/mkr-update` runs `install.sh --dry-run`
against a given `--source` checkout and renders a drift report (`created`/`restored`/`updated`/
`orphaned`/`refused`) before asking to apply it; nothing forces the upgrade, and there is no
pinned-`VERSION` default yet — the adopter supplies `--source` each time.

## 6. The sample `CLAUDE.md`

`/mkr-init` detects what it can, writes this pre-filled, and asks you to correct it. Deliberately
short — durable rules only, no status, no how-to (that lives in the skills).

```markdown
# CLAUDE.md

## What this project is
<one paragraph — what it does and for whom>

## Stack
<languages · frameworks · package manager · database · layout>

## Commands
| purpose | command |
|---|---|
| install   | <…> |
| test      | <…> |
| coverage  | <…> |
| typecheck | <…> |
| lint      | <…> |
| build     | <…> |
| run       | <…> |

## How we build — the AIDLC loop

triage → spec → ⟦spec approved⟧ → plan → ⟦plan conformant⟧ → design → ⟦design gate⟧
→ tests → implement → verify → review → ⟦review gate⟧ → merge → ground → ship

No code is written for a non-trivial change until its spec is agreed. Humans own intent and
guardrails; the agent runs the loop; review happens at gates, not per keystroke.

Depth: **Quick** (typo/config — implement + test + a one-line review note) ·
**Standard** (a feature in an existing module — the full loop, single pass) ·
**Deep** (new module, auth, data model, anything hard to reverse — full loop + ADR + audit).
State which you picked, and why, before starting.

## Allowed actions
- **MAY:** read code · write and run tests · draft specs · surgical edits on a feature branch ·
  typecheck/lint · open PRs.
- **MUST ASK FIRST:** push or merge to a protected branch · change CI/CD or infra ·
  touch auth, tenancy or the data model · read or rotate secrets · delete data · deploy.
- **MUST NEVER:** commit secrets · disable a guardrail or weaken a test to make CI pass ·
  force-push a shared branch.

## Gate owners
A gate without a named owner is not a gate.
| gate | owner |
|---|---|
| spec approval | <…> |
| design | <…> |
| pre-merge | <…> |
| pre-deploy | <…> |
| incident / kill switch | <…> |

## Non-negotiables
<3–7 project-specific invariants — the rules that must never be traded away>

## Conventions
- Match surrounding style; smallest correct diff; no speculative abstraction.
- Conventional Commits; feature branches; every PR links its spec.
- Any substantial or hard-to-reverse decision gets an ADR.
```

And the machine-readable half — **plain shell**, sourced directly by the hooks:

```sh
# .mkr/config — your project's facts. Never overwritten by an update.
MKR_CONFIG_SCHEMA=1

MKR_TEST="pnpm test"
MKR_COVERAGE="pnpm test -- --coverage"
MKR_TYPECHECK="pnpm -s typecheck"
MKR_LINT="pnpm exec eslint"
MKR_BUILD="pnpm build"

MKR_SPECS_DIR="docs/specs/"
MKR_ADR_DIR="adr/"

MKR_PROTECTED_BRANCHES="main release"
MKR_WORKTREE_POLICY="advisory"     # off | advisory | enforced
MKR_COVERAGE_MIN=85

MKR_RISKY_PATHS="**/auth/** **/migrations/** infra/** .github/**"

MKR_GATE_SPEC="@lead"
MKR_GATE_DESIGN="@lead"
MKR_GATE_MERGE="@codeowners"
MKR_GATE_DEPLOY="@oncall"
MKR_SELF_APPROVE="spec"

# The plan gate checks a presented plan against exactly this list.
MKR_PLAN_MANDATORY="spec-first reuse-check test-first self-review verify code-review"
MKR_PLAN_OPTIONAL="contract-first coverage-gate adr-for-risky design-before-tests \
                   auth-every-surface isolation-every-table api-parity"
```

Every value above except `MKR_PLAN_MANDATORY`/`MKR_PLAN_OPTIONAL` is deliberately **different**
from `config.sh`'s shipped default (AD-5, M0 §8): a sample that happened to equal the default
would look like a second source of truth rather than one project's choice. The two plan lists are
shown at their shipped values on purpose — they're what most adopters keep, and `MKR_CONFIG_SCHEMA`
replaces the retired `MKR_VERSION` name (M0 §7.3; the repo's own release version is the separate
top-level `VERSION` file, never `.mkr/config`).

**Shell, not JSON or YAML** — a decision the template model makes for us. The hooks are bash and
live in the same repo as this file, so sourcing it needs no parser, no `python3`, no `node`, no
PyYAML, and no dependency that could be missing on a teammate's machine. It is also the format a
developer can read and edit without documentation. (Under the plugin model this had to be JSON
parsed by an interpreter, because a plugin cannot assume anything about the repo it lands in.)

`MKR_PLAN_MANDATORY` is the whole de-coupling trick: the plan gate checks a presented plan against
*that list*, so each project declares its own mandatory steps and no skill file changes.

---

## 7. What is deliberately not in this template

| Left out | Why |
|---|---|
| Maturity assessment / L0–L4 ladder | Organisational transformation, not a development lifecycle. Different job. |
| Autonomy register / graduation | Same — an org-governance construct, not something a repo-local template can honour. |
| Any served constitution, domain packs, riders, certification | The project's rules live in `CLAUDE.md`, versioned in the repo. Nothing is rendered from elsewhere. |
| MCP server / API key / `.mcp.json` | No network dependency at all. |
| Product-agentification track | A product strategy playbook, not a build loop. |
| Plugin / marketplace packaging | Superseded by the template model. Gates that live in a committed `settings.json` bind the team; a user-scope plugin binds one developer and can be silently uninstalled. A plugin wrapper could be added later without changing any skill file, but nothing is built for it now. |
| Automatic updates | The price of owning the files. `/mkr-update` is explicit and diffs first. |

Everything that remains is a phase, a gate, or the enforcement of one.

---

## 8. Build sequence

| | Contents | Ship criterion |
|---|---|---|
| **M0** | The repo itself: `VERSION`, MIT-0 `LICENSE`, README, our `CLAUDE.md` + `.mkr/config`, `seed/CLAUDE.md` + `seed/config`, `.claude/hooks/lib/config.sh` | The repo can dogfood its own loop from M1 onward: `config.sh` honours its published contract, and the seed pair is generic and complete. **No `install.sh`** — distribution is M6 |
| **M1** | `mkr-loop` (incl. triage), `mkr-spec`, `mkr-spec-review`, `mkr-plan`, `mkr-adr`, `/mkr-init` + their commands | A feature runs triage → spec → G1 → plan → G2 end to end on a fresh repo |
| **M2** | `mkr-code-review`, `mkr-code-reviewer` + `mkr-security-reviewer` agents, the G4 gate, `pre-push-review-guard.sh`, review record format | Phase 7 catches something phase 5's self-review missed |
| **M3** | secret · branch · id-collision · spec-gate · stop-checks · audit-log, `settings.json` wiring, `.github/workflows/mkr-gate.yml` | Each hook has a test proving it blocks the true positive **and** clears its known false positives |
| **M4** | `mkr-audit` + `mkr-auditor`, `mkr-merge` | A grounding audit on a real repo finds something a green build missed |
| **M5** | `mkr-design` (two reviewers), `mkr-gates`, `mkr-ship`, `mkr-evals`, `mkr-capture` | A gated path splits into its own PR and the session keeps going instead of halting |
| **M6** | **Distribution.** `install.sh` (classify → stage → move, all-or-nothing), bash-only by design (`install.sh:6`), the `mkr-manifest` update seam, `/mkr-update` + drift report, the release gates (no vendor names on the shipped surface, README tier table). Plus `mkr-detect` for TS/Python/Go/Rails and the remaining agents | A cold repo adopts in one command, re-runs cleanly, upgrades without touching either owned file — and the repo goes public |

Two ordering consequences. **`settings.json` moves to M3** with the hooks it wires, so until then
the tooling is inert because nothing is wired. And **everything about distribution collapses into
M6** — the installer, the update seam, shell portability, the adopter-repo edge cases (symlinks,
gitignored `.claude/`, subdirectory installs). None of it has a consumer before the repo is public,
and specifying it early means specifying it against an imaginary adopter. M0–M5 are built and
dogfooded in this one repo, by us.

---

## 9. Decisions still open

1. **Distribution.** `install.sh` piped from raw GitHub is the primary path, because most adopters
   have an existing repo and cannot use GitHub's *Use this template* button. Do we also mark the
   repo as a template for greenfield use? Proposed: yes, it is free.
   Resolved by: M6.
2. **Update mechanism.** Proposed: `/mkr-update` re-fetches at a pinned `VERSION`, diffs
   template-owned files, refuses to overwrite locally modified ones without showing the diff, and
   never touches `CLAUDE.md` or `.mkr/config`. Alternative considered and rejected: a git subtree,
   which is cleaner in theory and reliably confusing in practice.
   Resolved by: M6 `mkr-update`.
3. **Code review — the three mechanics in §2:** re-review scope on a changed HEAD, local-vs-PR,
   and whether CI hard-requires the record. Defaults proposed; your call.
   Resolved by: M2.
4. **Does `spec-gate.sh` ship wired by default in M3?** Proposed: present but disabled in
   `settings.json`, enabled by `/mkr-init` once `.mkr/config` exists — so adopting the template
   never surprises anyone with an ASK on their first edit.
   Resolved by: M3.
5. **Is the grounding audit in the default loop or opt-in?** Proposed: in, from Standard depth up —
   it is the template's most distinctive capability and burying it as opt-in wastes it.
   Resolved by: M4 (in by default from Standard depth up).