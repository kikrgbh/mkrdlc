---
name: mkr-update
description: Runs install.sh --dry-run against a source checkout, renders a human-readable drift report (created/restored/updated/orphaned/refused), then asks before running install.sh for real. Never applies an update unprompted. Use to upgrade an already-installed repo's template-owned files without touching CLAUDE.md or .mkr/config.
---

# mkr-update — the update seam's ASK-gated front end

`mkr-update` does not reimplement `install.sh`'s classify/stage/move core — it runs the same
`install.sh` twice (specs/M6_Installer_Spec.md §6 AD-4, §7.3): once to see what would happen, once
to actually do it, after a human says yes. Upgrading an adopter's tree is consequential enough to
deserve the same gather-evidence-then-ask shape `mkr-merge` uses before touching `main`.

**Tool scope.** This skill only ever shells out via `Bash` — it never edits a file directly, the
same least-privilege framing `mkr-merge` uses.

## 1. Resolve the source and target

Take the source path from the argument given, or ask for it if none was given — no baked default
exists yet (no release has been cut; a real default lands once the repo goes public). Resolve
`--target` the same way `install.sh` does: the current repo's root.

## 2. Dry run

Run `bash <resolved-source>/install.sh --source <resolved-source> --target <target-root> --dry-run`
— the `install.sh` inside the resolved source checkout itself, not a copy assumed to already exist
at the target. Capture its stdout, stderr, and exit code.

## 3. If this dry-run exits nonzero, stop here

A nonzero exit here means a precondition failed (bad `--source`, the target mid-merge/mid-rebase,
no hashing tool found, a symlink at an enumerated path) before classification ever produced any
labeled rows — there is nothing to report and nothing to ask permission for, since the real run
would fail identically. Report the captured error verbatim and stop. Do not proceed to step 4.

## 4. Render the drift report

Only when step 2's dry-run exited `0`. Group the captured stdout by label and render counts and
paths for each of `created`, `restored`, `updated`, `orphaned`, `refused` — a human-readable summary
of what the real run would do, not just install.sh's own raw `<label>\t<path>` lines.

## 5. Name what `--force` would change

If anything is `refused`: name those paths explicitly and state that they will be skipped unless the
human asks for `--force` on this run. `--force` is whole-run, not per-path — one edited file can
block every other path's routine update in the same run, a real trade-off worth stating plainly
rather than hiding.

## 6. **Ask.**

State the drift report plainly, then ask — never proceed unprompted — for the human's explicit
go-ahead before step 7, including whether to pass `--force` if step 5 found anything `refused`. The
same before-you-touch-anything-consequential shape `mkr-merge` uses before touching `main`.

## 7. **Apply.**

Only after explicit confirmation: run the same `<resolved-source>/install.sh` again, without
`--dry-run` (with `--force` only if the human said yes to that in step 6). Report the resulting
disclosure output and the revert-command block install.sh printed.
