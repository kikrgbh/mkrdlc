# `mkr-rkp` adopter-declared topic shape

## 0. Triage

```
TRIAGE
depth:    deep
why:      touches .claude/hooks/lib/config.sh (a MKR_RISKY_PATHS glob) to add a new published
          config contract entry; CLAUDE.md requires asking first + a spec update for that file
scope:    one change — generalize mkr-rkp's fixed 9-topic bootstrap shape to recognize and adopt
          an adopter-declared existing RKP shape, via a new .mkr/config seam
reuse:    checked specs/, docs/adr/, branches, captures.jsonl — no prior work on this gap; found
          strong precedent in docs/adr/0004-spec-section-extension-point.md, which solved the
          same class of problem for mkr-spec (MKR_SPEC_EXTRA_SECTIONS) after the same Misikiri
          adopter reported the same "no extension point, forced to fork" failure mode
touches:  .claude/skills/mkr-rkp/SKILL.md, .claude/hooks/lib/config.sh, seed/config (comment only,
          no restated default per AD-5), tests/config_test.sh, tests/mkr_artifact_test.sh
risky:    .claude/hooks/lib/config.sh
gates:    spec:✓ plan:✓ design:✓ review:✓ ground:✓ adr:✓ ship:✗
done when: mkr-rkp adopts an adopter-declared existing RKP shape via a new .mkr/config variable
          instead of requiring a SKILL.md hand-patch, with zero behavior change when unset;
          verified by a config_test.sh case plus a fixture simulating an existing RKP
```

## 1. Header

| | |
|---|---|
| **Status** | ACCEPTED rev 6 (kikrgbh, 2026-08-13) |
| **Depth** | Deep |
| **Author** | agent |
| **Approver** | kikrgbh |

## 2. Intent

`mkr-rkp` (`.claude/skills/mkr-rkp/SKILL.md`) ships one fixed, signal-derived topic shape for the
Repo Knowledge Package: nine numbered docs (`01-architecture.md` … `09-dev-environment-runbook.md`),
five always-applicable and four gated on a detected signal. That shape assumes a fresh install with
no prior `docs/rkp/` — every repo starts from the same table and either gets a topic or doesn't,
based on what `mkr-detect`-style signals find.

An adopter repo (Misikiri) already had a real, human-curated, 11-doc knowledge-transfer package at
`docs/rkp/` — built and maintained by a predecessor tool before this template was installed — with
its own topic names, its own splits (`04-data-flow.md` and `07-system-journeys.md` as standalone
docs the generic table folds into others), and its own numbering. The generic shape didn't fit and
had no seam to bend: the only way to keep `mkr-rkp` usable against their real package was to hand-
edit their installed copy of `SKILL.md` in place, replacing the signal-derived table with a
hardcoded one. That local patch is now a permanent fork nobody upstream benefits from, and every
future `mkr-update` risks clobbering it (this is exactly the class of drift `install.sh`'s
refuse/`--force` machinery exists to protect, at the cost of every other file in the same run — see
the adopter's separate, already-captured `installer-selective-apply-gap` report).

This is not a Misikiri-only problem. Any repo adopting this template with a pre-existing knowledge
base — or any repo that simply wants a different topic split from day one — hits the same wall:
`mkr-rkp`'s topic shape is baked into its own instructions with no declared-by-the-adopter seam,
unlike `mkr-spec`'s section shape, which already got exactly this seam in
`docs/adr/0004-spec-section-extension-point.md` after the same adopter reported the same failure
mode. This change gives `mkr-rkp` the analogous seam: a way to declare "this repo's topic shape is
X" once, in `.mkr/config`, so the skill describes the repo's actual package instead of forcing its
own default onto it — with zero behavior change for every repo that never sets it.

## 3. Scope

**In scope**
- A new `.mkr/config` variable, `MKR_RKP_TOPICS` — a space-separated, `mkr_list`-splittable list of
  `docs/rkp/`-relative filenames, in the adopter's declared order. Read by `mkr-rkp` via
  `config.sh list MKR_RKP_TOPICS` (CLI mode — a skill file cannot source a shell library, the same
  reason `mkr-spec` reads `MKR_SPEC_EXTRA_SECTIONS` the same way).
- `mkr-rkp` (`.claude/skills/mkr-rkp/SKILL.md`): a new section describing the declared-shape mode —
  when `MKR_RKP_TOPICS` is non-empty, it wholesale replaces the signal-derived nine-topic table for
  every mode (bootstrap, single-doc refresh, full-package refresh, partial bootstrap, scope-hint
  validity) for that repo. Every declared filename unconditionally applies (it was declared, not
  signal-gated) — the existing signal column, the self-exclusion rule, and the present-conditional-
  doc signal recheck are specific to the *default* signal-derived table and do not run against a
  declared shape (there is no signal to lose).
- `.claude/hooks/lib/config.sh`: add `MKR_RKP_TOPICS` to `_mkr_names()` (published variable list),
  no new `_mkr_default()` case needed — its default is the empty string, same as
  `MKR_SPEC_EXTRA_SECTIONS`, via the existing `*) printf '' ;;` fallback.
- `seed/config`: one new commented, empty-valued line, generic in wording (no Misikiri-specific
  content, per `CLAUDE.md`'s "`seed/CLAUDE.md` and `seed/config` carry no fact specific to this
  project" — that non-negotiable generalizes to *any* one project, including an adopter's).
- `tests/config_test.sh`: add `MKR_RKP_TOPICS` to `MKR_NAMES_SPEC`/`MKR_DEFAULT_SPEC` (default `''`)
  — the existing generic default-value loop and CLI `dump` test cover it with zero new test code,
  the same way `MKR_SPEC_EXTRA_SECTIONS` needed none beyond those two array entries.
- `tests/mkr_artifact_test.sh`: a new `TC-RKP-17` mechanical check (declared-shape section present,
  states wholesale replacement + unconditional-apply + non-application of the signal-recheck
  machinery, mutation-resistant per this file's own established pattern for `TC-RKP-*`), plus
  confirmation that every existing `TC-RKP-*` check (`TC-RKP-01` through `TC-RKP-16`, minus the
  never-issued `TC-RKP-12`) still passes unmodified (the new section is additive, never edits an
  existing checked sentence).
- `docs/adr/0013-rkp-declared-topic-shape.md` — records this decision, its two considered shapes,
  and why the "wholesale replace" shape (not `MKR_SPEC_EXTRA_SECTIONS`'s "append after the fixed
  core" shape) fits this problem, per `CLAUDE.md`'s cross-cutting ADR rule.

**Out of scope**
- Copying Misikiri's actual 11-doc table (filenames, re-check-against sources, topic splits) into
  the template. That content is repo-specific; it stays in Misikiri's own `.mkr/config`, never in
  `seed/config` or `SKILL.md`.
- Customizing the *signal rules* for the four conditional topics in the default (undeclared) mode.
  Handled by: nothing changes — those signal rules stay exactly as they are today, untouched by
  this spec.
- Encoding per-topic grounding-source file lists in `MKR_RKP_TOPICS` itself. A declared topic's
  grounding sources are discovered the same judgment-driven way the five always-applicable topics
  already are today (Grep/Glob guided by the topic's own name, and — for an already-existing doc —
  its own header/citations, per `SKILL.md`'s existing "match the established shape" discipline).
  Handled by: `mkr-rkp`'s existing bootstrap/refresh procedure, unchanged.
- `mkr-detect`, `install.sh`, `mkr-update` — untouched. This is `mkr-rkp`'s own seam, not a change
  to how the template is installed or updated. (The adopter's separate `mkr-update` all-or-nothing
  gap, captured in `.mkr/captures.jsonl` as `installer-selective-apply-gap`, is different work,
  already tracked on its own branch.)
- Semantic validation of `MKR_RKP_TOPICS`'s own contents beyond the bare-filename/path-safety check
  AD-3 requires (numbering gaps, duplicate filenames, a `.md` file that's actually empty or
  malformed prose). Handled by: nothing — treated the same trust boundary as any other
  adopter-authored config list's *content* (`MKR_PLAN_MANDATORY`'s tokens, `MKR_SPEC_EXTRA_SECTIONS`'s
  slugs); a malformed-but-safe declaration is the adopter's own config to fix, not something this
  skill enforces. **In scope, not out of scope (AD-3, corrected rev 4):** whether a token is safe to
  use as a write-path filename at all — that a token isn't a bare `docs/rkp/`-relative filename
  ending in `.md` is refused before any write, not merely left to the adopter to notice later, since
  an unsafe token here is a write-path hazard, not a content-quality question.

## 4. Affected users & journey change

- **An adopter with a pre-existing, differently-shaped RKP** (Misikiri today; any future adopter in
  the same position): today, their only path is a local, unmaintainable fork of `SKILL.md`. After
  this change: set `MKR_RKP_TOPICS` once in `.mkr/config` to their real doc list, delete their local
  patch, and every future `mkr-update` run treats their installed `SKILL.md` as unmodified template
  content — the same "no fork, declare instead" outcome `MKR_SPEC_EXTRA_SECTIONS` already gives
  `mkr-spec` adopters.
- **A brand-new repo that wants a custom topic split from day one** (no prior `docs/rkp/` at all):
  the same variable serves them for free — declare `MKR_RKP_TOPICS` before ever running `mkr-rkp`,
  and bootstrap creates exactly that shape instead of the generic nine. No separate mechanism needed
  for "adopt existing" versus "declare fresh."
- **Every repo that never sets `MKR_RKP_TOPICS`** (the default, and every repo this template has
  ever been installed into so far): zero behavior change. `mkr_get`/`mkr_list` on an unset variable
  return empty, `mkr-rkp` falls straight through to the signal-derived table exactly as it does
  today.

## 5. Reuse check

Checked `specs/` (no existing spec covers `mkr-rkp` — it has never had one; this is its first),
`docs/adr/` (found `docs/adr/0004-spec-section-extension-point.md` — the direct precedent, same
adopter, same failure mode, described above), branches (`git branch -a`, no in-flight work on this),
and `.mkr/captures.jsonl` (one unrelated capture, `installer-selective-apply-gap`, about
`mkr-update`, not `mkr-rkp`). No duplicate capability exists. The chosen mechanism reuses
`config.sh`'s existing `mkr_list`/CLI-`list` machinery verbatim — no new parsing code, the same
reuse `MKR_SPEC_EXTRA_SECTIONS` and `MKR_PLAN_MANDATORY`/`MKR_PLAN_OPTIONAL` already get from that
one shared implementation.

## 6. Architecture & key decisions

**AD-1 (this spec, formalized in `docs/adr/0013-rkp-declared-topic-shape.md`): wholesale replace,
not additive append.** `docs/adr/0004-spec-section-extension-point.md` solved `mkr-spec`'s version
of this problem by keeping the core 14 sections fixed and letting a project *append* extra ones
after them — appropriate there because every `mkr-spec`/`mkr-spec-reviewer`/`mkr-code-reviewer`
cross-check assumes the core 14 exist at fixed positions (`§0` first, `§13` last, `§9`↔`§10`
cross-checked). `mkr-rkp` has no such positional cross-check between topics, but it does have a
problem `mkr-spec` didn't: Misikiri's real shape isn't the generic nine *plus* two extras — it is a
different split of the *same underlying subjects* (their `03-db-design.md` is the generic
`02-data-model.md`'s subject, renumbered and renamed; their `06-user-journeys.md` is the generic
`04-user-journeys.md`'s subject, moved). An additive-only seam can't rename, resplit, or reorder the
fixed nine — only a wholesale replacement can. So `MKR_RKP_TOPICS`, when set, replaces the
applicable-topic list entirely for that repo, rather than extending it.

**AD-2: declared topics are unconditional, never signal-gated.** The default table's four
conditional topics exist because a template installed into unknown repos can't assume a UI, an API,
or an auth layer exists — signals are how it finds out. An adopter naming `MKR_RKP_TOPICS`
explicitly already knows their own repo's shape; re-deriving a signal for a topic they just declared
would be redundant at best and could spuriously "no-longer-applicable" a doc they deliberately kept
(the present-conditional-doc signal recheck exists specifically to police the *default* table's
signal-derived inclusions, not an adopter's own fiat). So the recheck, and the signal-scan self-
exclusion rule that exists to protect it (`SKILL.md`'s current, unlabeled "Signal scans exclude
`docs/rkp/` itself" paragraph — `SKILL.md` carries no internal AD-numbering of its own beyond the
single, unrelated "AD-1" citation for its no-spawned-subagent rule), apply only to the
undeclared/default mode.

**AD-3: the location stays fixed; only the shape becomes declarable — and every declared token is
validated as a bare filename before it's ever used to write.** `mkr-rkp`'s existing, load-bearing
invariant is "writes only under `docs/rkp/` — a fixed location, not read from any `MKR_*`/
`config.sh` variable" (`TC-RKP-01`). `MKR_RKP_TOPICS` configures *which filenames* apply under that
fixed location, never the location itself — `docs/rkp/` is not parameterized by this change, and
`TC-RKP-01`'s check is untouched, still true, still passing. **Correction (G4 security review,
rev 3 → rev 4):** rev 3 stated declared filenames were "trusted the same as any other
adopter-authored config content — no path-escape check is performed," treating this as the same
trust boundary §3 already states for a declared list's *contents*. That equivalence doesn't hold: a
`MKR_SPEC_EXTRA_SECTIONS` slug becomes a heading title, a `MKR_PLAN_MANDATORY` token is matched
against a fixed enum — neither ever picks *where a file is written*. `MKR_RKP_TOPICS` is the first
declared list whose tokens reach a filesystem write path, and `mkr-rkp`'s "writes only under
`docs/rkp/`" invariant has no technical (hook-based) enforcement — it holds only if every write
instruction in this file keeps it true. So each declared token is validated before any write: it
must be a bare filename — no `/`, no leading `.`, not literally `.` or `..` — ending in `.md`. A
token that fails this check is never written; refuse that one entry and report it by name, and
proceed normally with every other valid entry in the same list.

**Correction, part 2 (G3 re-review, rev 4 → rev 5):** the rev-4 fix above specified the write step
correctly but left four other places §7 lists in the same breath — bootstrap/full-package
reporting, `README.md`'s doc-list table, single-doc refresh's scope-hint validity, and partial
bootstrap's missing-vs-present enumeration — silent on what happens to a token that's declared but
refused. Each of those unconditional-sounding claims ("lists exactly this list," "valid iff it's in
this list") only ever meant *a valid entry*; §7 now says so explicitly and states each of the four
behaviors' actual treatment of a refused entry: reported by name in bootstrap/full-package refresh,
never listed in `README.md`, refused at the scope-hint-check step with its own message distinct
from "not in the declared list," and excluded from partial bootstrap's missing/present count. See
§7 for the complete, per-mode statement — this AD's own text is the single source of the *rule*;
§7's is the single source of *where it applies*.

**Correction, part 3 (G3 re-review, rev 5 → rev 6):** part 2's partial-bootstrap clause resolved
only which bucket (missing/present) a refused token falls into — it left open whether the token is
still *reported* in that mode at all, unlike the other three behaviors, which each got an explicit
reporting statement. A reader could take "excluded from the enumeration" to mean the token vanishes
from partial bootstrap's output entirely — exactly the silent-refusal outcome this AD exists to
rule out. Corrected: exclusion from the missing/present buckets is never exclusion from reporting —
partial bootstrap still reports a refused token by name, the same report bootstrap and full-package
refresh give it, alongside whatever it reports for the docs actually in scope.

**AD-4: no per-topic grounding-source config.** `mkr_list` splits strictly on whitespace — a token
can't itself contain a file path list without inventing a second delimiter inside a single config
value, the same constraint `MKR_SPEC_EXTRA_SECTIONS`'s slugs already accept (a slug can't be a full
sentence either). Rather than invent nested syntax, a declared topic is grounded the same
judgment-driven way the five always-applicable default topics already are: read the target repo
(Grep/Glob, guided by the topic's own filename/slug), and — for an already-existing doc being
refreshed — its own header and citations, which `SKILL.md`'s existing "match the established shape"
step already requires every bootstrapped doc to carry. No new discovery mechanism, just the existing
one applied to a declared list instead of a signal-derived one.

**AD-5: same code path serves "adopt existing" and "declare fresh."** Nothing in `MKR_RKP_TOPICS`'s
own semantics distinguishes a repo with a pre-existing `docs/rkp/` from one bootstrapping for the
first time under a declared shape — both simply consult the declared list instead of the signal
table wherever `SKILL.md` currently says "the topic table above." This is a consequence of AD-1, not
a separate design decision, and it means the change needs no new scope-mode (bootstrap/refresh/
partial-bootstrap/single-doc-refresh keep exactly their current four triggers and mechanics —
only which table they consult changes).

## 7. Interfaces / contracts

### `.mkr/config`: `MKR_RKP_TOPICS`

- **Shape**: space-separated list, `mkr_list`-splittable (no internal spaces per token). Each token
  is a `docs/rkp/`-relative markdown filename, e.g. `01-product-workflow.md 02-architecture.md
  03-db-design.md`. Order is the declared order — this becomes the topic list's order everywhere
  `mkr-rkp` enumerates it (bootstrap sequence, `README.md`'s doc-list table, single-doc-refresh
  scope-hint validation).
- **Default**: empty (unset). Read via `config.sh get MKR_RKP_TOPICS` returns `''`;
  `config.sh list MKR_RKP_TOPICS` yields zero lines. `mkr-rkp` treats this identically to today's
  behavior — the signal-derived nine-topic table governs every mode.
- **Non-empty**: `mkr-rkp` treats this list as the repo's fixed topic shape, replacing the
  signal-derived table wholesale for: bootstrap (topic set = this list, no signal gating), full-
  package refresh (scope = this list), partial bootstrap (missing-vs-present is checked against
  this list, not the default nine), single-doc refresh's scope-hint validity (a named doc is valid
  iff it's in this list, mismatch reported the same way an unrecognized default-table name is
  reported today), and `README.md`'s own doc-list table (lists exactly this list, in this order).
  The present-conditional-doc signal recheck does not run — every entry in a declared list
  unconditionally applies, by AD-2. **Every claim in this bullet describes a *valid* declared
  entry** — see the next bullet for what a token that fails validation does to each of these five
  behaviors; that bullet's rules take precedence over this one's wherever they conflict.
- **Every declared token is validated as a bare filename before any write, and that validation
  result is threaded through every mode above, not just the write step (AD-3, corrected rev 4/5).**
  A token containing `/`, starting with `.`, or not ending in `.md` is refused. Concretely, for a
  refused token: it is never written, and is reported by name as refused, in bootstrap and
  full-package refresh, the same way any other refused entry is reported; `README.md`'s doc-list
  table never lists it — that table lists only entries that were actually written, so a refused
  token produces no row pointing at a file that will never exist; single-doc refresh's scope-hint
  validity refuses it at the scope-hint-check step itself, before any write is attempted, with its
  own "refused" report — a materially different message from the existing "not in the declared
  list" mismatch case, since the token *is* declared, it just isn't safe to write; partial
  bootstrap's missing-vs-present enumeration excludes it from *both* buckets — it is neither
  "missing" (which would attempt a write that will only be refused again) nor "present" (nothing
  was ever written) — but exclusion from the enumeration is never silence: partial bootstrap still
  reports the refused token by name, the same report bootstrap and full-package refresh give it,
  alongside whatever it reports for the docs actually in scope. A refused token never disappears
  from a run's output just because it doesn't fit either bucket. Every other, valid entry in the
  same declared list still runs normally through all five behaviors
  regardless of a sibling entry's refusal. This is what keeps `mkr-rkp`'s existing "writes only
  under `docs/rkp/`" invariant true for a declared list, not merely stated for it, in every mode
  that touches the list — not only the write step in isolation.
- **A `docs/rkp/` file present on disk but not (or no longer) named in a non-empty
  `MKR_RKP_TOPICS`** is left untouched and unreported by every `mkr-rkp` mode — the same
  never-deletes, human-decides posture the present-conditional-doc signal recheck already takes for
  its own "no longer applicable" case in the default mode, and consistent with §3's existing
  "adopter-authored list contents get no validation" trust boundary. Reconciling a dropped or
  renamed entry against what's actually on disk (the exact scenario AD-1 itself uses as its
  motivating example — a repo resplitting/renaming docs) is the adopter's own call to make by
  editing `MKR_RKP_TOPICS`, not something `mkr-rkp` infers or flags on its own.
- **No new `.mkr/config` reader outside `mkr-rkp`.** No other skill or hook consumes
  `MKR_RKP_TOPICS`.

### `.claude/hooks/lib/config.sh`

- `_mkr_names()` (line ~120): append `MKR_RKP_TOPICS` after `MKR_SPEC_EXTRA_SECTIONS` — the existing
  list's declared order is append-only by convention (each new variable is added where its
  introducing spec's task lands it; matches how `MKR_SPEC_EXTRA_SECTIONS` itself was appended after
  `MKR_REVIEW_VERDICT_STRING`).
- `_mkr_default()`: no new case. Falls through to the existing `*) printf '' ;;` — identical
  treatment to `MKR_SPEC_EXTRA_SECTIONS`, which also has no dedicated case.
- No change to `mkr_get`, `mkr_list`, CLI mode, or the two-stage child-process dump — this is a pure
  data addition to an existing, already-generic mechanism.

### `mkr-rkp` (`.claude/skills/mkr-rkp/SKILL.md`)

New subsection, placed immediately after the existing "Doc topics — derived per-repo, not assumed
from a fixed list" section (after its closing "If the nine-topic shape genuinely doesn't fit…"
paragraph, which stays verbatim — it still describes the default mode correctly) and before
"Scope — pick by trigger, not by habit". Working title: "Adopter-declared topic shape —
`MKR_RKP_TOPICS`". Content (for `mkr-code-review`/`mkr-spec-reviewer` and the mechanical test to
verify against, not final prose — final wording is an implementation-phase task):

- States the seam: `config.sh list MKR_RKP_TOPICS` (CLI mode), non-empty → wholesale replace.
- States AD-2 (unconditional, no signal recheck) and AD-3 (location still fixed, every declared
  token validated as a bare filename before any write, a failing token refused-and-reported not
  silently written or skipped) explicitly, so a reader doesn't have to infer them from the ADR.
- States that every scope mode (bootstrap/single-doc/full-package/partial-bootstrap/scope-hint
  validity) consults this list in place of the default table when set — one sentence per mode is not
  required; a single "wherever this file says 'the topic table above', substitute the declared list
  when `MKR_RKP_TOPICS` is set" framing is sufficient and avoids duplicating the four mode
  descriptions.
- States the present-but-undeclared-file rule above: left untouched, unreported, reconciling it is
  the adopter's own call.
- Cross-references `docs/adr/0013-rkp-declared-topic-shape.md`.

Tool scope, write-location invariant (`docs/rkp/` fixed), and every other existing contract in this
file are unchanged.

## 8. Data model

One new `.mkr/config` variable, `MKR_RKP_TOPICS` — documented above (§7). No database, no schema,
no new generated artifact. `docs/rkp/README.md`'s doc-list table format is unchanged (still a table
of doc names); only the source of *which rows* it lists changes (declared list vs. signal-derived
table).

## 9. Test-case register

| ID | Covers | Mechanics |
|---|---|---|
| `TC-CFG-RKP-01` | `MKR_RKP_TOPICS` default is `''` (`config_test.sh`'s generic default-value loop, `MKR_NAMES_SPEC`/`MKR_DEFAULT_SPEC` entries) | AC1 |
| `TC-CFG-RKP-02` | `config.sh dump` includes `MKR_RKP_TOPICS=` (existing generic `dump` test, extended by the new array entry) | AC1 |
| `TC-CFG-RKP-03` | `config.sh list MKR_RKP_TOPICS` splits a multi-token declared value correctly | AC1 — covered by the existing generic `mkr_list` mechanics tests (`MKR_PLAN_MANDATORY`-driven), no bespoke code needed since `MKR_RKP_TOPICS` reuses the same splitter |
| `TC-RKP-17a` | Declared-shape section present in `SKILL.md`, states wholesale replacement | AC2 |
| `TC-RKP-17b` | Declared-shape section states AD-2 (unconditional, no signal recheck for declared topics) | AC2 |
| `TC-RKP-17c` | Declared-shape section states AD-3's fixed `docs/rkp/` location clause (location unaffected) | AC2 |
| `TC-RKP-17f` | Declared-shape section states AD-3's token-validation clause: a token must be a bare filename | AC2, AC7 |
| `TC-RKP-17g` | Declared-shape section states AD-3's refuse-and-report clause: a token failing that check is never written | AC2, AC7 |
| `TC-RKP-17h` | Declared-shape section states a refused token is excluded from `README.md`'s doc-list table (G3 rev-5 finding's fix) | AC2, AC7 |
| `TC-RKP-17i` | Declared-shape section states a refused token is refused at the scope-hint-check step with its own distinct report (G3 rev-5 finding's fix) | AC2, AC7 |
| `TC-RKP-17j` | Declared-shape section states a refused token is excluded from partial bootstrap's missing-vs-present *buckets* (G3 rev-5 finding's fix) | AC2, AC7 |
| `TC-RKP-17k` | Declared-shape section states that exclusion from those buckets is never exclusion from reporting — partial bootstrap still reports a refused token by name (G3 rev-6 finding's fix) | AC2, AC7 |
| `TC-RKP-17d` | Declared-shape section states the present-but-undeclared-file rule (left untouched, unreported — G3 finding 1's fix) | AC2 |
| `TC-RKP-17e` | Each of the ten claims above independently detected when removed (mutation resistance, matching this file's own `TC-RKP-*` pattern) | AC2 |
| Every existing `TC-RKP-*` check (regression) | Every existing RKP mechanical check — `TC-RKP-01` through `TC-RKP-16`, noting the suite's own numbering has no `TC-RKP-12` (it jumps 11→13) — still passes unmodified against the edited `SKILL.md` | AC3 |
| `TC-RKP-FIXTURE-01` | A hand-built fixture repo with an existing, differently-shaped `docs/rkp/` and `MKR_RKP_TOPICS` declared to match it: a full-package refresh scoped run consults the declared list, not the default nine, and reports each declared doc's state (clean/updated) rather than reporting the un-declared default-table docs as missing | AC4 |
| `TC-RKP-FIXTURE-02` | A hand-built fixture repo with `MKR_RKP_TOPICS` declaring one path-traversal token (`../../../evil.md`) alongside two safe ones: a bootstrap run against it must write only the two safe docs (strictly inside the fixture's own `docs/rkp/`), refuse the hostile entry by name, and never attempt a write outside `docs/rkp/` — manually verified against the actual filesystem state after the run, not just the refusal message | AC7 |
| `TC-ADR-0013a`/`b` | `docs/adr/0013-rkp-declared-topic-shape.md` exists, has the 4 required ADR sections in order (`check_adr_shape`, the same mechanism `TC-M1-05` already uses), and documents AD-1 through AD-5 (`**AD-1:` … `**AD-5:` all present) — a real mechanical test in `tests/mkr_artifact_test.sh`, not just a cited-but-nonexistent row (G1 rev-5 finding's fix) | AC5 |
| `TC-M0-19` (existing, `tests/config_test.sh:420-433`) | Already iterates `MKR_NAMES_SPEC` and verifies every listed variable is empty in `seed/config` with a comment line directly above its assignment. Adding `MKR_RKP_TOPICS` to `MKR_NAMES_SPEC` (task 4a) puts it inside this existing generic loop with zero new test code — the same reuse `TC-CFG-RKP-01`/`02` above already get from `config_test.sh`'s generic default-value/`dump` loops | AC6 |

## 10. Acceptance criteria

- **AC1** — `MKR_RKP_TOPICS` is a published `.mkr/config` variable: default `''`, listed in
  `config.sh dump`, split correctly by `config.sh list`. *(traces to §2 intent: a declarable seam
  that doesn't require a `SKILL.md` fork)*
- **AC2** — `mkr-rkp`'s `SKILL.md` documents the declared-shape mode: what triggers it, that it
  replaces the table wholesale, that declared topics are unconditional (no signal recheck), that the
  fixed `docs/rkp/` write location is unaffected, that every declared token is validated as a bare
  filename before any write and a failing token is refused-and-reported rather than written or
  silently skipped (AD-3, corrected rev 4 — G4 security finding), and that a present-on-disk file no
  longer named in a declared list is left untouched and unreported (G3 finding 1). *(traces to §2
  intent: describe the adopter's real shape instead of forcing the template's default)*
- **AC3** — Every existing `TC-RKP-*` mechanical check in `tests/mkr_artifact_test.sh` (`TC-RKP-01`
  through `TC-RKP-16`, minus the never-issued `TC-RKP-12`) still passes against the edited
  `SKILL.md`, unmodified. *(traces to §3 scope: additive change, zero regression to the default
  signal-derived mode)*
- **AC4** — Given a fixture repo with `MKR_RKP_TOPICS` declared and an existing `docs/rkp/` matching
  it, a full-package refresh run operates against the declared list (not the default nine) and
  reports per-declared-doc state. *(traces to §2 intent: closes the adopter's actual gap)*
- **AC5** — `docs/adr/0013-rkp-declared-topic-shape.md` exists and documents AD-1 through AD-5 from
  §6. *(traces to §0 gates line: `adr: ✓`)*
- **AC6** — `seed/config` gains one new commented, empty-valued `MKR_RKP_TOPICS` line with generic
  (non-Misikiri-specific) wording, caught by `tests/config_test.sh`'s existing generic `TC-M0-19`
  check once `MKR_RKP_TOPICS` is added to `MKR_NAMES_SPEC` — no bespoke test needed.
  *(traces to §3 scope, AD-5 non-negotiable in `CLAUDE.md`)*
- **AC7** — A declared `MKR_RKP_TOPICS` token that isn't a bare `docs/rkp/`-relative filename ending
  in `.md` (contains `/`, starts with `.`, or is literally `.`/`..`) is never written to; it is
  refused and reported by name, and every other valid entry in the same declared list still runs
  normally. *(traces to §2 intent — a declared list reaching a filesystem write path is exactly the
  kind of adopter-controlled surface this spec's "describe reality, don't force a shape onto it"
  goal has to hold safely, not just conveniently; found missing by G4 security review, rev 3 →
  rev 4)*

## 11. Definition of Done

- [x] AC1–AC7 above all met. AC4 verified manually against `tests/fixtures/rkp_declared_shape/`: the
      two declared docs report `clean`, the present-but-undeclared `03-legacy-orphan.md` is left
      untouched and unreported, no default-table doc is invented. **AC7 verified manually against
      `tests/fixtures/rkp_hostile_topics/`** (declares `01-overview.md ../../../evil.md
      02-notes.md`): a bootstrap run wrote exactly the two safe docs under that fixture's own
      `docs/rkp/`, refused `../../../evil.md`, and — confirmed by an actual filesystem search
      (`find ... -iname evil.md`) across the whole worktree, not just the absence of a crash or a
      spot-check — no file named `evil.md` exists anywhere. This is the concrete evidence G1's
      rev-4 finding asked for: not that the prose says refusal happens, but that it actually does.
- [x] `bash tests/config_test.sh` green (124 passed, 0 failed).
- [x] `bash tests/mkr_artifact_test.sh` green (all existing `TC-RKP-*` plus updated `TC-RKP-17*`
      and new `TC-ADR-0013a`/`b`; 253 passed, 0 failed).
- [x] `docs/adr/0013-rkp-declared-topic-shape.md` filed and linked from this spec's §6, and (rev 6)
      actually verified by `TC-ADR-0013a`/`b`, not just cited.
- [x] G1 (`mkr-spec-review`) READY on rev 6.
- [x] G3 (`mkr-design`) re-review READY on rev 6 (both sub-reviewers).
- [x] G4 (`mkr-code-review`) READY — `.mkr/reviews/31f05c7.md`.
- [ ] Merged via `mkr-merge`'s G5 preflight.
- [ ] Grounding audit (`mkr-audit`) run against the merged commit.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. **spec-first** — this spec (done, pending G1).
2. **reuse-check** — done (§5): `docs/adr/0004-spec-section-extension-point.md` is the load-bearing
   precedent; mechanism reuses `config.sh`'s existing `mkr_list` verbatim.
3. **design** — G3 gate (`mkr-design`, both reviewers) against this spec's §6/§7/§8, required
   unconditionally at Deep depth.
4. **test-first** —
   a. Add `MKR_RKP_TOPICS` to `tests/config_test.sh`'s `MKR_NAMES_SPEC`/`MKR_DEFAULT_SPEC` arrays.
   b. Write `TC-RKP-17a`–`j` in `tests/mkr_artifact_test.sh` (new `check_rkp_declared_topic_shape`
      helper, mirroring the file's existing `check_rkp_*` pattern), against the *not-yet-written*
      `SKILL.md` section — expected to fail red first.
   c. Build the `TC-RKP-FIXTURE-01` fixture repo (a small `docs/rkp/` with a non-default shape) and
      the `TC-RKP-FIXTURE-02` fixture (a declared list with one path-traversal token) and their
      harnesses.
5. **implement** —
   a. `.claude/skills/mkr-rkp/SKILL.md`: add the declared-shape subsection (§7 above).
   b. `.claude/hooks/lib/config.sh`: append `MKR_RKP_TOPICS` to `_mkr_names()`.
   c. `seed/config`: add the new commented, empty-valued line.
   d. File `docs/adr/0013-rkp-declared-topic-shape.md`.
6. **self-review** — re-read the diff cold against this spec's AC1–AC7 before requesting `verify`.
7. **verify** — `bash tests/config_test.sh` and `bash tests/mkr_artifact_test.sh`, both green;
   manually run `mkr-rkp` against `TC-RKP-FIXTURE-01` and confirm AC4 by hand; manually run
   `mkr-rkp` against `TC-RKP-FIXTURE-02` and confirm AC7 by hand — specifically confirm no file
   exists anywhere outside that fixture's own `docs/rkp/` after the run, not just that a refusal
   message was produced.
8. **code-review** — G4 (`mkr-code-review`: `mkr-code-reviewer` + `mkr-security-reviewer`).
9. Merge via `mkr-merge` (G5); ground via `mkr-audit` post-merge.

## 13. Review history

| rev | verdict | reviewer(s) | notes |
|---|---|---|---|
| 1 | NOT READY (1 blocking) | `mkr-spec-reviewer` | Blocking: AC6 had no §9 test-case register row — `seed/config`'s new commented, empty-valued line was an acceptance criterion with no cited test, even though `tests/config_test.sh`'s existing generic `TC-M0-19` would cover it once `MKR_RKP_TOPICS` joins `MKR_NAMES_SPEC`. Fixed in rev 2: new §9 row citing `TC-M0-19`, AC6 updated to name it. Non-blocking, also fixed in rev 2: §6 AD-2's inaccurate "AD-5 in SKILL.md's own numbering" citation corrected (SKILL.md has no such internal numbering); §9/§10 AC3's `TC-RKP-01`…`TC-RKP-16` continuous-range wording corrected to note the suite has no `TC-RKP-12`. Non-blocking, not fixed (reviewer found acceptable as-is): AC5/AC6 trace to §0/§3/`CLAUDE.md` rather than a §2 intent claim — both are process-driven deliverables (ADR, config-contract non-negotiable), not product-intent claims, so a §2 trace doesn't apply the same way it does for AC1–AC4. |
| 2 | READY | `mkr-spec-reviewer` | No blocking findings. Independently re-verified rev-1's fix (AC6/`TC-M0-19` row) and both non-blocking corrections (SKILL.md AD-numbering, `TC-RKP-12` gap) against the real files rather than taking the rev-1 row on faith. Non-blocking, not further changed: AC5/AC6 trace to §0/§3/`CLAUDE.md` rather than a §2 intent claim (same as rev-1, reviewer independently agrees this is acceptable — both are process-mandated deliverables, not product-intent assertions); §11 DoD doesn't flag that AC4's `TC-RKP-FIXTURE-01` verification (§12 task 7) is manual rather than an automated `mkr_artifact_test.sh` assertion, consistent with this project's convention that skill runtime behavior isn't mechanically scripted. |
| 2 | **G1 APPROVED** | kikrgbh, 2026-08-13 | Human approval of rev 2 (`READY` verdict above). `Status` set to `ACCEPTED rev 2 (kikrgbh, 2026-08-13)`. |
| 2 | **G2: CONFORMANT** | `mkr-plan` | §12's steps map onto `MKR_PLAN_MANDATORY` in order: `spec-first`(1) → `reuse-check`(2) → `test-first`(4) → `self-review`(6) → `verify`(7) → `code-review`(8), each preceding `implement`(5) or `merge`(9) as required — no `missingMandatory`, no `orderingViolations`. Optional coverage: `adr-for-risky` (task 5d files `docs/adr/0013-...`), `design-before-tests` (step 3 design precedes step 4 test-first). `contract-first`/`coverage-gate`/`auth-every-surface`/`isolation-every-table`/`api-parity`/`ui-feedback-per-wave`/`build-directive-conformance` not applicable — no API contract beyond §7 (already spec'd, not a separate plan step), no coverage tooling in this bash project, no auth/DB/UI/wave surface touched. |
| 2 | **G3: NOT READY (1 blocking)** | `mkr-design-reviewer` (NOT READY, 1), `mkr-architecture-reviewer` (READY) | Full record: `.mkr/designs/RkpTopicShape-rev2.md`. Blocking: §7 never specified behavior for a `docs/rkp/` file present on disk but not (or no longer) named in `MKR_RKP_TOPICS` — only the missing-doc direction (partial bootstrap) was covered, leaving the AD-1-motivating rename/resplit scenario undefined. Fixed in rev 3: §7's `MKR_RKP_TOPICS` contract and `SKILL.md`-content list gain an explicit rule (left untouched, unreported — adopter's own call), §9 gains `TC-RKP-17d`/renumbered `17e`, §10 AC2 updated to name it, §12 task 4b's range updated to `a`–`e`. Non-blocking, also fixed in rev 3: architecture reviewer's path-escape-trust observation — AD-3 gains one clause stating declared filenames carry the same no-validation trust boundary §3 already states for list contents generally. Non-blocking, left as-is (design reviewer's own findings, reasons given inline): the pre-existing "fixed topic→number map" sentence's default-mode scoping (already covered by §7's general table-substitution framing); `README.md`'s doc-list table during partial bootstrap (already resolved by the existing "write `README.md` last" procedural ordering). |
| 3 | **G1: READY** | `mkr-spec-reviewer` | Independently re-verified against real files, not just the spec's own claims (`SKILL.md` landmarks cited by §7 all confirmed present; `config.sh`'s `_mkr_names()` confirmed to still end at `MKR_SPEC_EXTRA_SECTIONS`). Non-blocking: this §13 table's own rev-3 row (below, for G3) originally misattributed the present-but-undeclared-file fix to "§6 AD-1 area and §7" — on inspection the rule exists only in §7, not §6; corrected in that row above. Non-blocking: §3's second out-of-scope item lacked the explicit "Handled by:" label the other four carry — added. |
| 3 | **G3: READY** | `mkr-design-reviewer` (READY), `mkr-architecture-reviewer` (READY) | Full record: `.mkr/designs/RkpTopicShape-rev3.md`. Both reviewers independently re-verified their own prior finding's fix against the actual current §6/§7 text (not the review-history row's claim): the present-but-undeclared-file rule is confirmed present in §7 (design-reviewer), and AD-3's path-escape-trust clause is confirmed present in §6 (architecture-reviewer). Zero new findings from either reviewer on a fresh full re-read of §6/§7/§8. |
| 3 | **G1 APPROVED** | kikrgbh, 2026-08-13 | Human approval of rev 3 (`READY` verdict above, G3 also `READY`). `Status` set to `ACCEPTED rev 3 (kikrgbh, 2026-08-13)`. |
| 3 | **G4: NOT READY (1 blocking)** | `mkr-code-reviewer` (READY), `mkr-security-reviewer` (NOT READY, 1) | Full record: `.mkr/reviews/<pending>.md`. Blocking (security): `MKR_RKP_TOPICS` tokens become `docs/rkp/` write-path filenames; rev 3's AD-3 stated "no path-escape check is performed," claiming the same trust boundary as `MKR_SPEC_EXTRA_SECTIONS`/`MKR_PLAN_MANDATORY` — reviewer verified by inspection that neither precedent ever lets an adopter token pick a write location (a slug becomes a heading title; a token is matched against a fixed enum), so the equivalence was inaccurate and both G3 reviewers signed off on it without testing a hostile token (e.g. `../../../.github/workflows/pwn.yml`) against `mkr-rkp`'s "writes only under `docs/rkp/`" invariant, which has no technical (hook-based) enforcement. Non-blocking (code-reviewer): `tests/config_test.sh:18`'s "The 28 §8 variable names" comment is pre-existing stale count, not introduced or worsened by this diff — left as-is, out of this spec's scope. Fixed in rev 4: AD-3 (§6) corrected — every declared token is now validated as a bare filename (no `/`, no leading `.`, not literally `.`/`..`, ending `.md`) before any write; a failing token is refused and reported by name, every other valid entry still runs. New AC7, new `TC-RKP-17f`/`17g`, `SKILL.md` and `docs/adr/0013-...` both updated to match, §3's out-of-scope item narrowed to exclude write-path safety (now in scope) while keeping content-quality validation out of scope. |
| 4 | **G1: NOT READY (1 blocking)** | `mkr-spec-reviewer` | Blocking: AC7 — the criterion added specifically because rev 3's write-path validation was untested — was covered only by `TC-RKP-17f`/`17g`, string-presence checks confirming certain sentences exist in `SKILL.md`, never anything exercising `mkr-rkp`'s actual behavior against a hostile token, unlike AC4's real fixture-based manual verification. AD-3 itself says the invariant has no technical enforcement, which is exactly why prose-presence alone can't back a security-critical AC. Fixed in rev 5: new `tests/fixtures/rkp_hostile_topics/` fixture (declares `01-overview.md ../../../evil.md 02-notes.md`), manually run — the two safe docs written, the hostile token refused, confirmed by an actual `find`-across-the-worktree search that no `evil.md` exists anywhere, recorded in §11's DoD line and a new `TC-RKP-FIXTURE-02` §9 row. |
| 4 | **G3: NOT READY (1 blocking)** | `mkr-design-reviewer` (NOT READY, 1), `mkr-architecture-reviewer` (READY) | Full record: `.mkr/designs/RkpTopicShape-rev4.md`. Architecture reviewer adversarially re-tested the rev-4 fix against the exact hostile example G4 cited and confirmed it's genuinely closed, not relocated — `READY`. Blocking (design reviewer): the rev-4 token-validation rule was specified correctly for the write step itself, but §7's "Non-empty" bullet still made four other, unqualified-sounding claims in the same breath (`README.md`'s table "lists exactly this list," scope-hint validity "valid iff it's in this list," partial bootstrap's missing-vs-present enumeration, bootstrap/refresh reporting) without saying what a *refused* (as opposed to valid) declared entry does to each — a gap the validation rule itself introduced, since before it existed every declared entry could safely be assumed to "unconditionally apply." Fixed in rev 5: §6 AD-3 and §7 both now state, explicitly, that a refused token is excluded from `README.md`'s table, refused at the scope-hint-check step with its own distinct report (not conflated with "not in the declared list"), and excluded from partial bootstrap's missing/present count entirely; `SKILL.md` gains the same explicit paragraph; three new mechanical checks (`TC-RKP-17h`/`17i`/`17j`). |
| 5 | **G1: NOT READY (1 blocking)** | `mkr-spec-reviewer` | Blocking: independently verified the AC7 fixture fix was genuine (real path-traversal token, real filesystem search confirming refusal) — credible, no findings there. But while checking every AC's cited test for real existence (not just a row in the table), found `TC-ADR-0013` (AC5's sole citation) had never actually been implemented anywhere in `tests/mkr_artifact_test.sh`/`config_test.sh`, despite this project's own established `check_adr_shape()` mechanism (already used for `TC-M1-05`) being exactly the right tool — a pre-existing gap present unchanged since rev 1, not introduced by rev 5, but still a real defect: AC5 had zero actual enforcement. Fixed in rev 6: new `TC-ADR-0013a`/`b` in `tests/mkr_artifact_test.sh` (4-section shape via `check_adr_shape`, plus a content check for `**AD-1:`…`**AD-5:` all present) — a real mechanical test, not a phantom row. |
| 5 | **G3: NOT READY (1 blocking)** | `mkr-design-reviewer` (NOT READY, 1) — `mkr-architecture-reviewer` not re-run per AD-2 (its rev-4 `READY` covered this exact §6/§7 range with no blocking finding, so it carries forward unchanged) | Full record: `.mkr/designs/RkpTopicShape-rev5.md`. Blocking: rev 5's partial-bootstrap fix (previous row) resolved which bucket a refused token falls into (neither missing nor present) but never said whether it's still *reported* in that mode — unlike the other three behaviors, which each got an explicit reporting statement — leaving room for a silent refusal in exactly the mode AD-3 exists to prevent one in; confirmed the same silence already existed in the implemented `SKILL.md` text, not just the spec prose. Fixed in rev 6: §6 AD-3 ("Correction, part 3") and §7 both now state explicitly that exclusion from the missing/present buckets is never exclusion from reporting — partial bootstrap still reports a refused token by name, the same as bootstrap/full-package refresh; `SKILL.md` updated to match; new mechanical check `TC-RKP-17k`. Also fixed, cosmetic: AD-3's "Correction, part 2" recap parenthetical now lists all four behaviors it corrected, not three. |
| 6 | **G1: READY** | `mkr-spec-reviewer` | Independently confirmed `TC-ADR-0013a`/`b` genuinely exist and pass (not phantom), spot-checked AC1/AC3/AC6/AC7's cited tests against the real files (all genuine), confirmed section shape/Status/Approver/traceability/reuse-check all still hold, confirmed nothing else regressed. Non-blocking, pre-existing (not introduced by rev 6): the `TC-RKP-17a-d` console label under-names its own scope — the single aggregate check it labels actually covers all ten content rules (`a,b,c,d,f,g,h,i,j,k`), not just `a`-`d` — cosmetic only, the underlying check and `TC-RKP-17e`'s mutation loop genuinely exercise all ten. |
| 6 | **G3: READY** | `mkr-design-reviewer` (READY), `mkr-architecture-reviewer` (READY, carried forward from rev 4 per AD-2) | Full record: `.mkr/designs/RkpTopicShape-rev6.md`. Design reviewer independently confirmed the rev-5 finding's fix is genuinely present in both spec text and the actual implemented `SKILL.md`, `TC-RKP-17k` is wired to the exact corrected sentence, and a fresh full re-read of §6/§7/§8 found no new gaps. |
| 6 | **G1 APPROVED** | kikrgbh, 2026-08-13 | Human approval of rev 6 (`READY` verdict above, G3 also `READY`). `Status` set to `ACCEPTED rev 6 (kikrgbh, 2026-08-13)`. |
