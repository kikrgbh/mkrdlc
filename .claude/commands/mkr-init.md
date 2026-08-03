---
description: Interview this repo and seed its CLAUDE.md and .mkr/config from seed/CLAUDE.md and seed/config. Refuses to run against mkr-aidlc's own root, and refuses to silently overwrite an already-filled owned pair.
---

# /mkr-init

No matching skill exists for this command (per `docs/DESIGN.md` §5.1's layout, `mkr-init` has a
command but no separate skill) — this file *is* the whole procedure. Follow it in order.

## 1. Resolve the project root

- `$CLAUDE_PROJECT_DIR` if set and non-empty.
- else `git rev-parse --show-toplevel`.
- else **stop**: "no project root found — not inside a git repo and `CLAUDE_PROJECT_DIR` is unset."

This is its own algorithm, not `.claude/hooks/lib/config.sh` §7.1's config-*file* resolution (that
one also considers `$MKR_CONFIG`, which finding a project *root* has no equivalent of — don't
conflate the two).

## 2. Refuse to run against this repo's own root

Check `<root>/docs/DESIGN.md`. If it exists **and** its first line is exactly:

```
# mkr-aidlc — an open-source AIDLC template for Claude Code
```

**stop**: "refusing to run — this is mkr-aidlc's own root, not an adopter repo. `/mkr-init` seeds a
*caller's* `CLAUDE.md`/`.mkr/config`; this repo's are already filled by hand (M0)."

This is a content check, not a path or remote-URL check, on purpose — it survives a fork, rename, or
different checkout location of this repo, and per `docs/DESIGN.md` §5.2, an adopter's repo never
receives `docs/DESIGN.md` (that's the template's own design note, not part of what an adopter gets),
so this check can never produce a false refusal against a real target.

## 3. Refuse to silently overwrite an already-initialized repo

Check `<root>/CLAUDE.md` and `<root>/.mkr/config`. For each that exists: read it, and check whether
it still contains a seed placeholder — for `CLAUDE.md`, any line matching `^\s*<.+>\s*$`; for
`.mkr/config`, any `MKR_*=""` line still empty in a way that suggests it was never filled (use
judgment — a deliberately-left-empty variable after a real init is fine; a file that is *entirely*
still `seed/config`'s literal empty-with-comment shape is not).

- Neither file exists → proceed, this is a first init.
- Both exist and both still look like unfilled seed copies → proceed (finishing an interrupted
  init).
- Either exists and looks genuinely filled in (non-placeholder content) → **stop and ask** the user
  to confirm before overwriting anything. `docs/DESIGN.md` §5.2 promises these two files are never
  touched by an *update* — `/mkr-init` re-running on an already-initialized repo has to hold itself
  to at least that same bar.

## 4. Interview

Free-form, not a fixed script — the sample `CLAUDE.md` in `docs/DESIGN.md` §6 is the target shape
to fill, not a question list to read verbatim. At minimum, gather enough to fill:

- **`CLAUDE.md`**: what the project is (one paragraph) · stack (languages, frameworks, package
  manager, database, layout) · commands (install/test/coverage/typecheck/lint/build/run) · gate
  owners (five: spec approval, design, pre-merge, pre-deploy, incident/kill switch) ·
  non-negotiables (3–7 project-specific invariants) · conventions (code style, commit/branch
  conventions, when a decision needs an ADR). `How we build` and `Allowed actions` are **not**
  interviewed — copy them from `seed/CLAUDE.md` verbatim, adapting only `MUST ASK FIRST`/`MUST
  NEVER` if the project has genuinely different guardrails; the loop itself doesn't change per
  project.
- **`.mkr/config`**: for each `MKR_*` variable in `seed/config` (each has a one-line comment above
  it explaining what it's for), ask whether this project wants to override `config.sh`'s shipped
  default. Leave any the user doesn't have an opinion on empty — empty means "use the default,"
  not "broken."

Invoke `mkr-detect` against the target root for systematic detection. If it returns one or more
ecosystem blocks, present each to the human as a proposal — confirm them, don't assume them
silently. If it returns zero blocks ("no recognized ecosystem detected"), state that to the human
plainly before continuing — the interview still proceeds from a blank starting point in that case,
but the human is told detection ran and found nothing, not left to wonder whether it ran at all.

## 5. Write

- `<root>/CLAUDE.md` from `seed/CLAUDE.md`'s structure, all eight `## ` headings present, every
  placeholder replaced, `How we build`/`Allowed actions` carried over per step 4.
- `<root>/.mkr/config` from `seed/config`'s structure — same variables, same comments, values filled
  per the interview, everything else left as `""`.

Never touch `mkr-aidlc`'s own `CLAUDE.md`/`.mkr/config` (step 2 already refuses this outright) and
never write partial output — if the interview is abandoned partway, don't write either file rather
than writing an inconsistent one.
