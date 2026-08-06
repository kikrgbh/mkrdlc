# 0007 — `.github/CODEOWNERS` is never installed

## Status

Accepted

## Context

`install.sh` walks `.github/` the same generic way it walks `.claude/` — every file present gets
enumerated, hashed, shipped, and manifest-tracked, refused on divergence, all the same mechanics
(specs/M6_InstallCIWorkflow_Spec.md's `mkr-gate.yml` shipping already established the pattern; it
has since broadened to the whole directory). That generic treatment is correct for every other file
under `.github/` here — `workflows/mkr-gate.yml`, `ISSUE_TEMPLATE/*.md`, `PULL_REQUEST_TEMPLATE.md`
— because their content is genuinely template content: the same bytes are correct for every
adopter.

`.github/CODEOWNERS` is not that. Its one line of real content, `* @kikrgbh`, names this template's
own maintainer. Shipped verbatim to every adopter (an installation issue reported after a real
adopt), that is at best meaningless (a username with no relationship to the adopting repo) and at
worst a genuine, silent review-ownership collision (a different real GitHub user or org happening
to collide with `@kikrgbh`, silently granted review authority they never asked for). Unlike
`CLAUDE.md`/`.mkr/config` — also adopter-specific, and already handled as the "owned pair,"
created once from a `seed/` template and never overwritten again — `install.sh` has no interview
step for `.github/CODEOWNERS` and no adopter identity to fill it in with at install time.

## Decision

`.github/CODEOWNERS` is excluded, by exact path, from `install.sh`'s `.github/` enumeration —
never shipped, never manifest-tracked, never refused on divergence, exactly as if it didn't exist
under `--source` at all. A `--source` that ships one (this repo's own checkout always does) prints
a one-line, once-per-run advisory instead: `.github/CODEOWNERS was not installed... create your
own if you want required-reviewer routing` — naming the gap instead of leaving it silent.

This repo's own `.github/CODEOWNERS` (`* @kikrgbh`) is untouched by this change: it still exists,
still governs *this* repo's own review ownership (docs/DESIGN.md §4's gate-owner table), and is
simply no longer one of the paths `install.sh` walks when shipping the template to somewhere else.

Rejected alternative: ship a placeholder (`* @REPLACE_ME`) as `OWNED_PAIR`-style seeded content,
paired with a new `/mkr-init` interview question. Correct in principle, but a materially bigger
change for this fix — a third owned-file class, a new `seed/CODEOWNERS`, and a new interview
question — for a file whose only defensible default, absent an actual adopter identity to seed it
with, is "don't silently grant it to the wrong person." Never shipping it reaches that same
guarantee directly, and does not preclude adding the seeded-placeholder path later if `/mkr-init`
grows a general "seed adopter-identity files" step that would also serve other future cases.

## Consequences

- No adopter installing this template ever receives a CODEOWNERS entry naming someone else's
  GitHub identity, silently or otherwise.
- An adopter who wants required-reviewer routing must create `.github/CODEOWNERS` themselves; the
  advisory names that as the next step rather than leaving a first-time reader to notice the file
  is simply absent.
- An adopter who already has their own `.github/CODEOWNERS` (common — many repos start with one)
  is completely unaffected: this file was never in `install.sh`'s enumeration to refuse or diverge
  against in the first place.
- A prior installation whose manifest recorded `.github/CODEOWNERS` from before this change reports
  it as `orphaned` on the next run — the same, already-existing signal `install.sh` gives any
  path a newer template version stops shipping — never auto-removed.
