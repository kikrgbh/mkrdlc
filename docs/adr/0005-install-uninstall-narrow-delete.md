# 0005 — install.sh gains a narrow, confirmation-gated --uninstall

## Status

Accepted

## Context

`install.sh`'s header states plainly "Never deletes anything (§6 AD-2)," and until now nothing in
the script contradicted that: create, restore, update, refuse, orphan-report — never delete. That
was a deliberate safety decision, not an oversight (a template-installer that can delete files in
an adopter's repo is a materially more dangerous tool than one that can only ever add or overwrite
what it's told to).

An adopter repo (Misikiri, reported upstream) hit the gap AD-2 leaves open: `install.sh` has no way
to remove what it previously installed, and no way to detect a differently-named prior AIDLC-style
toolkit already present (e.g. a hypothetical `aidlc-spec` skill from an earlier, unrelated setup).
A repo migrating between toolkits, or wanting to cleanly remove `mkr-aidlc`, is stuck hand-running
`git rm` against the manifest's own file list — the exact kind of manual, error-prone step
`install.sh` exists to replace for every *other* lifecycle action.

Any fix here necessarily reopens AD-2: there is no way to "remove what was installed" without a
delete capability appearing somewhere. The question is how narrowly to scope it so the original
safety reasoning behind AD-2 — install.sh should never be the mechanism that silently destroys an
adopter's data — still holds.

## Decision

`install.sh` gains `--uninstall [--target DIR]`:

- Reads `.claude/mkr-manifest` at `--target` — the same file the rest of `install.sh` already
  treats as the authoritative record of what it owns — and considers exactly those paths, nothing
  else. `CLAUDE.md`/`.mkr/config` (the owned pair) are never touched; they carry adopter facts, not
  template content, and were never in the manifest to begin with.
- **Defaults to report-only**, the same shape `--dry-run` already uses for the rest of the script:
  lists every manifest-tracked path that *would* be removed, deletes nothing, exits 0. This is the
  confirmation gate — translated from `mkr-merge`'s "ask a human before acting" (which needs an
  interactive session) into the CLI equivalent: no destructive action on the first invocation, ever.
- Only actually deletes when the adopter passes the explicit, separate `--confirm` flag alongside
  `--uninstall` — a second, deliberate flag, not a prompt a scripted/non-interactive invocation
  could accidentally satisfy. `--uninstall` alone can never delete anything, no matter what else is
  passed.
- Removes exactly the listed manifest-tracked files, then the manifest file itself. No backup (the
  removed files are ordinary template content, typically already git-tracked in the adopter's own
  repo — `git status`/`git diff` after an uninstall shows exactly what changed, and `git checkout`
  is the real undo here, the same safety net `install.sh`'s own `.mkr-backup` mechanism doesn't
  replace for genuinely tracked files elsewhere in the script either).
- Separately, a plain (non-uninstall) install run gains a foreign-file advisory: any file under
  `.claude/skills/`, `.claude/commands/`, or `.claude/agents/` at `--target` that is neither in the
  current `--source` enumeration nor recorded in the manifest — i.e., content install.sh has never
  owned, from this template or a prior one — is reported (stderr, non-blocking) as a possible
  leftover from a different toolkit. Advisory only, matching this issue's own accepted alternative:
  a hardcoded "known prior-toolkit" denylist would need constant maintenance and still miss
  anything not on it, where a generic "content we don't recognize" check catches any prior toolkit,
  named or not, without ever guessing at its identity or auto-removing it.

## Consequences

- AD-2 is narrowed, not repealed: `install.sh` can now delete, but only files it already owns (per
  its own manifest), only when explicitly asked twice (`--uninstall` *and* `--confirm`), and never
  the two adopter-owned files. Every other path through the script — install, update, `--dry-run` —
  is exactly as unable to delete anything as before.
- An adopter can cleanly remove `mkr-aidlc` in one command instead of hand-`git rm`-ing the
  manifest's file list.
- The foreign-file advisory gives an adopter visibility into toolkit collisions on every plain
  install, not just at uninstall time — closer to catching the problem before it causes confusion,
  the shape the reported incident actually took (found only after the fact, hand-corrected).
- No support for detecting or uninstalling a *specific* named prior toolkit (e.g. cleaning up
  `aidlc-spec`'s own files automatically) — only this template's own manifest-tracked removal and a
  generic "here's what we don't recognize" report. A prior toolkit's own removal is still the
  adopter's own `git rm`, now at least a visible, named list instead of a silent surprise.
