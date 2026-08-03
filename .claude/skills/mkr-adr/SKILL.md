---
name: mkr-adr
description: Writes a numbered Architecture Decision Record into MKR_ADR_DIR, matching this repo's existing docs/adr/NNNN-*.md shape. Use for any substantial or hard-to-reverse decision (CLAUDE.md's cross-cutting ADR rule), typically one a spec's §6 Architecture section names as an AD.
---

# mkr-adr

Reuses the shape already established by `docs/adr/0001-template-over-plugin.md`,
`0002-shell-config-out-of-process-bash-only.md`, and `0003-mit0-over-mit.md` verbatim — this skill
does not invent a new one.

## Shape

```
# NNNN — <short decision title>

## Status

Accepted

## Context

<what problem forced a decision; what was tried or considered>

## Decision

<what was decided, stated plainly>

## Consequences

<what this buys, and what it costs — both, not just the upside>
```

Exactly these four H2 sections, in this order: `Status`, `Context`, `Decision`, `Consequences`. No
other section.

## Numbering

1. Resolve `MKR_ADR_DIR` via `config.sh get MKR_ADR_DIR` (CLI mode; default `docs/adr/`).
2. List existing `NNNN-*.md` files there; find the highest `NNNN`; the new ADR is that plus one,
   zero-padded to 4 digits.
3. **This is a courtesy, not an enforced guarantee.** `id-collision-guard.sh` (M3) is what actually
   refuses a reused number; until then, picking the next number correctly is on you. If two ADRs
   are being drafted concurrently in different sessions, check again immediately before writing —
   don't trust a number you resolved more than a few tool calls ago.

## Filename

`<MKR_ADR_DIR>NNNN-<kebab-case-slug-of-the-title>.md`, matching the three existing ADRs.

## When to use this

Triggered by a spec's `## 6. Architecture & key decisions` section naming something as
substantial or hard to reverse (an "AD-N" in that section is a candidate — not every AD needs an
ADR, but a spec's own triage `gates:` line saying `adr ✓` means at least one does), or directly by
`CLAUDE.md`'s cross-cutting rule: "Any substantial or hard-to-reverse decision gets an ADR."
