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
2. List existing `NNNN-*.md` files there in the local working tree; find the highest `NNNN`.
3. Also check `origin/<default-branch>`'s copy of `MKR_ADR_DIR`, not just the local directory —
   `<default-branch>` is the first entry of `MKR_PROTECTED_BRANCHES` (`config.sh list
   MKR_PROTECTED_BRANCHES`, CLI mode; falls back to `main` if that's empty too) — a number only
   free locally can already be taken on a branch someone else has pushed and merged:
   - `git fetch origin -- <default-branch>` (the `--` matters: `<default-branch>` comes from a
     PR-controlled config value, and without it an option-shaped value could be read as a real
     `git fetch` flag instead of a literal branch name) — best-effort: if there's no `origin`
     remote, or the fetch fails, e.g. no network, fall back to the local-only max from step 2 and
     say so in the ADR draft's own handoff, don't block on it).
   - List `NNNN-*.md` under `MKR_ADR_DIR` as it exists at `origin/<default-branch>` (`git ls-tree
     -r --name-only origin/<default-branch> -- <MKR_ADR_DIR>`), find its highest `NNNN`.
4. The new ADR's number is one plus the higher of the two maxima (local, `origin/<default-branch>`),
   zero-padded to 4 digits.
5. **This is still a courtesy, not an enforced guarantee** — checking `origin/<default-branch>`
   catches a number already merged there, but not one another session is drafting concurrently,
   unmerged, right now. `id-collision-guard.sh` (M3) is the local Write-time backstop;
   `mkr-gate.yml`'s CI check is the push-time one. If two ADRs are being drafted concurrently,
   re-check both local and `origin/<default-branch>` immediately before writing — don't trust a
   number resolved more than a few tool calls ago.

## Filename

`<MKR_ADR_DIR>NNNN-<kebab-case-slug-of-the-title>.md`, matching the three existing ADRs.

## When to use this

Triggered by a spec's `## 6. Architecture & key decisions` section naming something as
substantial or hard to reverse (an "AD-N" in that section is a candidate — not every AD needs an
ADR, but a spec's own triage `gates:` line saying `adr ✓` means at least one does), or directly by
`CLAUDE.md`'s cross-cutting rule: "Any substantial or hard-to-reverse decision gets an ADR."
