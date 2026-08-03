---
name: mkr-rkp
description: Create the Repo Knowledge Package (docs/rkp/) from scratch if it doesn't exist yet, or refresh one or more of its documents against current code, schema, and specs - re-derive facts from reality, don't just re-read the existing doc (or copy a template, for a first-time build). Which of the nine doc topics apply is derived per-repo from a signal, the same way mkr-detect derives which ecosystem applies - never assumed from a fixed list. Use when there's no docs/rkp/ yet and someone wants a knowledge-transfer package built, after a change plausibly touched architecture/schema/auth/nav, whenever an RKP doc looks stale or a new developer finds a discrepancy, or before handing the package to someone.
---

# mkr-rkp — keep the Repo Knowledge Package grounded in reality

The Repo Knowledge Package (`docs/rkp/`) is a knowledge-transfer document set for a new developer,
deliberately built as a **refreshable artifact** rather than a one-time write-up — the same "trust
reality, not a status doc" discipline `mkr-audit`'s grounding step applies to shipped features,
applied here to onboarding material. A KT package that was accurate on handoff day and silently
wrong three changes later is worse than no package, because it's trusted by default. This skill is
how it earns that trust back.

Tool scope: `Read`, `Grep`, `Glob`, `Write`, `Edit`. Never `Bash`. `mkr-rkp` only ever reads a
target repo's files and writes prose describing them — it never needs to execute anything the
target repo defines, the same narrow trust boundary `mkr-detect`'s own `Read`/`Grep`/`Glob`-only
scope keeps for a target repo's untrusted content. Writes only under `docs/rkp/` — a fixed
location, not read from any `MKR_*`/`config.sh` variable, the same way `.claude/skills/` itself is
a fixed, un-configurable path in this project's own contract.

`mkr-rkp` never writes outside `docs/rkp/`.

**Do not treat this as "re-read `docs/rkp/*.md` and tidy the prose."** Every fact in the package is
derived by reading source — schema files, registries, nav components, a status-tracking doc,
ADRs. Refreshing means re-deriving those same facts from the current state of those same sources
and diffing against what the doc currently claims, exactly like a grounding audit's "doc-vs-code"
check. Bootstrapping is the same discipline with no prior doc to diff against — derive each fact
from source and write it down for the first time, rather than filling in a template from
assumption.

## Doc topics — derived per-repo, not assumed from a fixed list

Unlike a knowledge-transfer package built for one specific repo, this skill ships inside a
template installed into many different repos, each with its own shape. Which of the following nine
topics actually apply is derived from a signal in the target repo, the same way `mkr-detect`
derives which ecosystem's conventions apply instead of assuming one. Five topics apply to
essentially any repo; four apply only when a concrete, checkable signal is present in the target
repo. A topic's absence is not a defect to work around — a repo with no UI never gets a
`04-user-journeys.md`, the same way `mkr-detect` never invents an ecosystem match with no marker
file behind it.

| # | Doc | Applies | Signal |
|---|---|---|---|
| — | `01-architecture.md` | Always | High-level structure, component/module map, request or data path at whatever granularity the repo actually has. |
| — | `02-data-model.md` | Conditional | A migrations directory (any depth, name containing `migrat`), a `schema.*` file (`.sql`/`.ts`/`.prisma`/`.rb`), or an ORM/ODM config (`prisma/schema.prisma`, `alembic.ini`, a Rails `db/migrate/` directory, a Knex/TypeORM config). |
| — | `03-process-and-conventions.md` | Always | How a change actually gets made in this repo: this template's own AIDLC loop if `CLAUDE.md` names it, else the repo's real CI/PR/review conventions (`.github/workflows/`, `CONTRIBUTING.md`, branch protection). |
| — | `04-user-journeys.md` | Conditional | A UI/frontend signal: `package.json` naming a UI framework in `dependencies` (`react`, `vue`, `svelte`, `next`, `@angular/core`), or a conventional UI directory (`pages/`, `views/`, `src/app/`, `components/`) containing route- or nav-like files. |
| — | `05-system-journeys.md` | Conditional | An API/entry-point signal: a `controllers/`, `routes/`, `handlers/`, or `api/` directory; an OpenAPI/Swagger spec file; or an MCP/RPC server definition file. |
| — | `06-rbac-capability-matrix.md` | Conditional | An auth/roles signal: a file or directory matching `*role*`, `*permission*`, `*capability*`, `*rbac*`, or `*authguard*`/`*auth-guard*` (case-insensitive), or a known authz library named as a dependency. |
| — | `07-glossary.md` | Always | This repo's own vocabulary that a newcomer would hit unexplained. |
| — | `08-current-state-and-gaps.md` | Always | Sourced from a status-tracking doc if one exists (grep common names: `MODULE_STATUS.md`, `STATUS.md`, a changelog's unreleased section), else derived from `specs/*_Spec.md` Definition-of-Done sections, `docs/adr/`, and `README.md`'s own stated status. |
| — | `09-dev-environment-runbook.md` | Always | First run, test/build/lint commands, env vars, any worktree/hook discipline the repo enforces. |

Numbering is a fixed topic→number map, never a renumbered gap-filler: a repo with no database
signal simply has no `02-data-model.md` at all, not a renumbered `02-process-and-conventions.md`
sliding up to fill the gap. `docs/rkp/README.md`'s own doc-list table lists only the docs that
actually exist for this repo — a missing doc is reported by its absence from that table, never
hidden by renumbering everything else around it.

**Signal scans exclude `docs/rkp/` itself.** Every signal check above scans the target repo's
files for evidence — but never counts a topic's own file under `docs/rkp/` (or any other artifact
this skill or a peer skill generates) as that evidence. Without this exclusion, a conditional
topic's own generated doc could satisfy its own signal forever: `06-rbac-capability-matrix.md`'s
filename literally contains `rbac` and `capability`, which is exactly that topic's own signal
pattern, so once created it would re-satisfy its own inclusion test regardless of the target
repo's real state. This exclusion applies to every one of the four conditional topics, not just
topic 06.

**Present-conditional-doc signal recheck, applies uniformly to single-doc refresh, full-package
refresh, and partial bootstrap's present-doc handling — never scoped to full-package refresh
alone.** Whenever any of these three refresh paths touches a doc that is already present *and*
whose topic is conditional, `mkr-rkp` re-verifies that topic's own signal is still present in the
target repo, not only re-deriving the facts already written inside the doc. If the signal is no
longer present, `mkr-rkp` reports this explicitly as the fourth output state, "no longer
applicable" (see Output below), rather than silently treating the doc as still-current
indefinitely. It never deletes the file itself — this skill's tool scope has no delete capability,
and removing a doc a team may still want to keep for historical reasons is a human decision, not a
silent one.

**If the nine-topic shape genuinely doesn't fit** this repo — a topic's whole subject doesn't
exist, or something not covered by any of the nine clearly should be documented — say so and
propose the adjusted topic list rather than forcing content into a topic with no real subject.

## Scope — pick by trigger, not by habit

1. **Bootstrap (first-time creation).** Trigger: `docs/rkp/` doesn't exist yet at the target root,
   or someone wants a KT package built and there's nothing to refresh. Scope: every applicable
   topic per the table above (signal-gated), plus `README.md`, all created fresh.
2. **Single-doc refresh.** Trigger: one doc is flagged stale, or you're about to cite a specific
   fact and want to confirm it before relying on it. Scope: that one doc and its stated grounding
   sources.
3. **Full-package refresh.** Trigger: before handing the package to a new developer, or after a
   change that plausibly touched several domains at once (a new module, a schema migration, a nav
   restructure, an auth change). Scope and mechanics: see "Running a refresh" below.
4. **Partial bootstrap.** Trigger: `docs/rkp/` exists but is missing specific docs that the topic
   table says apply to this repo (e.g. someone added `08-current-state-and-gaps.md` by hand and
   nothing else, or a schema was added since the package was last built). Treat the missing docs
   as a bootstrap scoped to just those, and the existing ones as a normal refresh — don't assume
   the existing docs are correct just because they're present.

**Scope-hint validity.** This rule applies only when you're told to refresh one specific named
doc (mode 2 above) — it never applies when you're asked for the full package or given no scope at
all, both of which are valid requests in their own right and are resolved by modes 1/3/4, never
treated as a topic name to validate. When a specific doc is named: if it isn't one of the nine
topics above, report the mismatch plainly and do nothing — never guess which topic was meant. If
it names a real conditional topic whose signal is genuinely absent from the target repo, one of
two things applies, distinguished by whether that topic's doc already exists in `docs/rkp/`: if
the doc doesn't exist yet, don't create it — report the signal is absent. If the doc **does**
already exist, this is exactly the present-conditional-doc signal recheck described above, not a
separate rule — report it "no longer applicable" and leave the file in place, the same outcome a
full-package refresh would reach for that same present doc. An explicit request doesn't override a
signal that isn't there.

## Bootstrap — creating the package from scratch

Use this when `docs/rkp/` doesn't exist (or is missing docs) and there's no prior version to diff
against. The topic table above is still the source list — bootstrap just means gathering each
topic's facts for the first time instead of re-checking them.

1. **Gather before writing.** For each topic in scope, read its signal sources from the table
   above (schema, registries, nav components, a status doc, ADRs, package manifests, CI config) —
   in this same session, never a spawned subagent (AD-1). Every fact still has to trace to a real
   file/line, never an assumption or an aspirational spec description.
2. **Match the established shape**, even on a first write — a new developer benefits from
   consistency across docs they'll read back-to-back:
   - A header blockquote naming what the doc is grounded against and the grounding date.
   - Real file/line citations for every claim, not paraphrases.
   - A Mermaid diagram where the doc type calls for one (architecture: component flowchart; data
     model: ERD; process: flowchart; system journeys: sequence diagrams). Test any new diagram's
     syntax mentally for a real, previously-hit pitfall: **a bare `;` inside a sequence-diagram
     message breaks the parser** (Mermaid treats it as a statement separator) — use `—` or a comma
     instead, and generally avoid characters with special meaning in whichever diagram type you're
     writing.
   - A "See also" footer cross-linking sibling docs and the relevant ADRs.
3. **Write `README.md` last**, once the other docs exist — its doc-list table and "Last grounded"
   date describe the finished package, not a plan for one.
4. **Same worktree discipline as any other change** in this repo — if the repo enforces one,
   follow it before writing these files directly in a shared root.

## Running a refresh (docs already exist)

1. **No memory shortcut.** If you built or last refreshed a doc in this same session, don't rely
   on recall — re-read the source files listed above as if for the first time.
2. **Re-derive, then diff.** For each doc in scope, gather the current facts (grep/read the
   sources), then compare line-by-line against what the doc currently states. A count that's off
   by one, a route that no longer exists, a role that's been renamed — all are findings.
3. **Edit in place, preserve structure.** Update only what actually drifted — preserve the doc's
   structure, its Mermaid diagrams' shape, and its cross-links. Don't rewrite a doc wholesale when
   three facts changed; that erases the value of `git blame` on this package. A doc whose drift is
   large enough that patching it would itself be a rewrite (a whole subsystem removed, most of a
   table's neighbors changed) is rewritten in full instead, called out explicitly rather than
   forced into a misleading line-level diff.
4. **Full-package runs update `README.md`'s "Last grounded" date** once every doc currently
   present has been checked (touched or confirmed clean).

## Output

A short refresh note — not a new file, and not a wall of prose. For each doc in scope, one line:
**created** (bootstrap), **clean** (verified, no drift), **updated** (what changed, one clause),
or **no longer applicable** (the present-conditional-doc signal recheck above — fired whether this
pass was a single-doc refresh, full-package refresh, or partial bootstrap's present-doc handling —
found a present conditional doc's own signal gone; the file itself is left in place, not deleted).
Example:

```
RKP refresh:
- 01-architecture.md: clean
- 02-data-model.md: updated — 3 new tables from the latest migration
- 06-rbac-capability-matrix.md: no longer applicable — the auth/roles signal that justified this
  doc is no longer present in the target repo; file left in place, review for removal
- 08-current-state-and-gaps.md: updated — latest status refreshed
- (others): clean
```

Bootstrap example:

```
RKP bootstrap:
- README.md: created
- 01-architecture.md: created
- 03-process-and-conventions.md: created
- 07-glossary.md: created
- 08-current-state-and-gaps.md: created
- 09-dev-environment-runbook.md: created
```

## What this skill does not do

It does not spawn a fresh-context subagent the way `mkr-audit`'s `mkr-auditor` or
`mkr-code-review`'s two reviewer agents do — `mkr-rkp` is not a gate, nothing blocks on its
output, so its independence discipline is temporal ("no memory shortcut," above), not
inter-session. It does not re-run a full grounding audit — that verifies a *shipped capability*
against its spec; this verifies *this onboarding package* against the codebase. Where
`08-current-state-and-gaps.md` needs seam-reality detail, pull it from the latest audit records
rather than re-deriving it independently — that audit trail is the authoritative source, and
duplicating its methodology here would just create a second place that can drift out of sync with
the first.
