# 0013 — `mkr-rkp` adopter-declared topic shape: wholesale replace, not additive append

## Status

Accepted

## Context

`mkr-rkp`'s topic shape for the Repo Knowledge Package (`docs/rkp/`) has been a single, fixed,
signal-derived nine-topic table (`01-architecture.md` … `09-dev-environment-runbook.md`) baked into
`.claude/skills/mkr-rkp/SKILL.md`'s own instructions, with no seam for a project to declare a
different shape — the same closed-by-construction problem `docs/adr/0004-spec-section-extension-
point.md` already solved once for `mkr-spec`'s fixed 14-section shape.

An adopter repo (Misikiri, reported upstream — the same adopter `docs/adr/0004` names) already had a
real, human-curated, 11-doc knowledge-transfer package at `docs/rkp/`, built and maintained by a
predecessor tool before this template was installed: its own topic names, its own splits
(`04-data-flow.md` and `07-system-journeys.md` as standalone docs the generic table folds into
others), its own numbering. With no extension point, their only option was hand-editing their
installed copy of `SKILL.md` in place — a local fork that every future `mkr-update` risks
clobbering, and that upstream never benefits from.

## Decision

**AD-1: wholesale replace, not additive append.** `docs/adr/0004` kept `mkr-spec`'s core 14 sections
fixed and let a project *append* extra ones after them — appropriate there because every
`mkr-spec`/`mkr-spec-reviewer`/`mkr-code-reviewer` cross-check assumes the core 14 exist at fixed
positions. `mkr-rkp` has no such positional cross-check between topics, but Misikiri's real shape
isn't the generic nine *plus* extras — it's a different split of the *same underlying subjects*
(their `03-db-design.md` is the generic `02-data-model.md`'s subject, renumbered and renamed). An
additive-only seam can't rename, resplit, or reorder the fixed nine — only a wholesale replacement
can. `MKR_RKP_TOPICS` (`.mkr/config`, space-separated `docs/rkp/`-relative filenames, `mkr_list`-
splittable, mirroring `MKR_PLAN_MANDATORY`/`MKR_SPEC_EXTRA_SECTIONS`'s own token-list convention),
when non-empty, replaces the signal-derived table entirely for that repo, rather than extending it.

**AD-2: declared topics are unconditional, never signal-gated.** The default table's four
conditional topics exist because a template installed into unknown repos can't assume a UI, an API,
or an auth layer exists — signals are how it finds out. An adopter naming `MKR_RKP_TOPICS`
explicitly already knows their own repo's shape; re-deriving a signal for a topic they just declared
would be redundant at best and could spuriously "no-longer-applicable" a doc they deliberately kept.
So the present-conditional-doc signal recheck, and the signal-scan self-exclusion rule that protects
it, apply only to the undeclared/default mode.

**AD-3: the location stays fixed; only the shape becomes declarable — and every declared token is
validated as a bare filename before it's ever used to write (corrected — see below).** `mkr-rkp`'s
existing, load-bearing invariant is "writes only under `docs/rkp/` — a fixed location, not read from
any `MKR_*`/`config.sh` variable." `MKR_RKP_TOPICS` configures *which filenames* apply under that
fixed location, never the location itself.

*Correction, found on G4 security review (spec rev 3 → rev 4):* this ADR originally treated declared
filenames as carrying "the same trust boundary" as `MKR_SPEC_EXTRA_SECTIONS`'s slugs or
`MKR_PLAN_MANDATORY`'s tokens, with no path-escape check. That equivalence doesn't hold — a
`MKR_SPEC_EXTRA_SECTIONS` slug becomes a heading title, a `MKR_PLAN_MANDATORY` token is matched
against a fixed enum; neither ever picks *where a file is written*. `MKR_RKP_TOPICS` is the first
declared list whose tokens reach a filesystem write path, and `mkr-rkp`'s "writes only under
`docs/rkp/`" invariant has no technical (hook-based) enforcement — it holds only if every write
instruction in `SKILL.md` keeps it true. So each declared token is validated before any write: it
must be a bare filename — no `/`, no leading `.`, not literally `.` or `..` — ending in `.md`. A
token that fails this check is never written; refuse that one entry and report it by name, and
proceed normally with every other valid entry in the same list.

**AD-4: no per-topic grounding-source config.** `mkr_list` splits strictly on whitespace — a token
can't itself contain a file path list without inventing a second delimiter inside a single config
value, the same constraint `MKR_SPEC_EXTRA_SECTIONS`'s slugs already accept. A declared topic is
grounded the same judgment-driven way the five always-applicable default topics already are: read
the target repo (Grep/Glob, guided by the topic's own filename/slug), and — for an already-existing
doc — its own header and citations. No new discovery mechanism.

**AD-5: same code path serves "adopt existing" and "declare fresh."** Nothing in `MKR_RKP_TOPICS`'s
own semantics distinguishes a repo with a pre-existing `docs/rkp/` from one bootstrapping for the
first time under a declared shape — both simply consult the declared list instead of the signal
table. A consequence of AD-1, not a separate decision: no new scope-mode was needed
(bootstrap/refresh/partial-bootstrap/single-doc-refresh keep their current four triggers).

**Discovered during G3 design review, folded into the decision above:** a `docs/rkp/` file present
on disk but not (or no longer) named in a non-empty `MKR_RKP_TOPICS` — the exact resplit/rename
scenario AD-1's own motivating example describes, applied to a list edited after first declaration —
is left untouched and unreported by every `mkr-rkp` mode, the same never-deletes, human-decides
posture the present-conditional-doc signal recheck already takes for its own "no longer applicable"
case. Reconciling a dropped or renamed entry against what's on disk is the adopter's own call, made
by editing `MKR_RKP_TOPICS`, not something `mkr-rkp` infers or flags.

## Consequences

- An adopter with an existing, differently-shaped RKP declares it once in `.mkr/config` — no fork of
  `mkr-rkp`'s `SKILL.md`, the same way `MKR_SPEC_EXTRA_SECTIONS` already avoids forking `mkr-spec`.
- A brand-new repo wanting a custom topic split from day one gets the same mechanism for free (AD-5)
  — no separate "adopt" vs. "declare fresh" code path.
- The default signal-derived table, its four conditional topics' signal rules, and the present-
  conditional-doc recheck are all unchanged for every repo that never sets `MKR_RKP_TOPICS` — zero
  behavior change by default.
- Declared-list *content quality* (numbering gaps, duplicate filenames, drifted on-disk/declared
  reconciliation) gets no validation from `mkr-rkp` itself — a malformed-but-safe declaration is the
  adopter's own config to fix, the same trust boundary `MKR_PLAN_MANDATORY`'s tokens and
  `MKR_SPEC_EXTRA_SECTIONS`'s slugs already accept. *Write-path safety is different and is
  validated* (AD-3, corrected above): a token that isn't a bare `docs/rkp/`-relative filename ending
  in `.md` is refused, not left for the adopter to notice later.
- One new `.mkr/config` variable (`MKR_RKP_TOPICS`), one new `SKILL.md` subsection — no new
  architecture, no new discovery mechanism, no change to `mkr-rkp`'s existing scope-mode triggers.

See `specs/RkpTopicShape_Spec.md`.
