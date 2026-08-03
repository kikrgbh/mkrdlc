# Installer and update seam: `install.sh`, `.claude/mkr-manifest`, `mkr-update`

## Intent

`install.sh` seeds this template into an adopter's repo and later updates it in place, without
ever touching `CLAUDE.md` or `.mkr/config`. `.claude/mkr-manifest` is the state that lets a rerun
tell "unedited since the last install" from "the adopter changed this on purpose." `/mkr-update` is
a thin, ASK-gated skill that runs `install.sh` twice — a dry-run drift report, then the real run
only after explicit confirmation.

## Scope

**In scope**
- `install.sh` (repo root, executable bash) — classifies every template-owned path under
  `--source` against `.claude/mkr-manifest` at `--target`, stages the result, and moves it into
  place, all-or-nothing per run. Never deletes anything.
- `.claude/mkr-manifest` — the generated state file the classifier reads and rewrites.
- `mkr-update` (skill + command) — runs `install.sh` twice (dry-run drift report, then for real)
  against a source the human names, asking before the real run.
- `tests/install_test.sh` — fixture-repo test suite.

**Out of scope**
- `mkr-detect` (repo profiling feeding `/mkr-init`) — separate spec.
- The vendor-name denylist and the README gate-tier table — separate spec.
- Network fetch, a pinned-release default, and the `curl | bash` one-liner — separate spec
  (`specs/M6_InstallBootstrap_Spec.md`). `--source` here is always an explicit local directory
  path.
- Recording an executable mode for arbitrary future template files not yet part of `.claude/` —
  handled by construction: the manifest records whatever mode the source file actually has.

## Architecture & key decisions

- `install.sh` requires bash, not POSIX `sh` — matches the rest of this template's shell dialect.
- `install.sh` never deletes anything. A template file dropped from a later version is left on disk
  untouched; only its manifest entry is removed, disclosed as `orphaned`.
- `install.sh` backs up any template-owned path it overwrites, before writing, in every case — not
  only divergent ones — to `<path>.mkr-backup` (overwriting any prior backup at that sibling path),
  disclosed on stderr alongside the stdout overwrite line. Backups are never deleted and
  `install.sh` never edits an adopter's `.gitignore`.
- `/mkr-update` invokes the `install.sh` inside the source checkout it's given
  (`bash <source>/install.sh --source <source> --target <root>`), not a persisted copy in the
  adopter's own tree — one classify/stage/move implementation, not two.
- No network fetch and no pinned-release default here — `--source` is always an explicit local
  directory path (extended by `specs/M6_InstallBootstrap_Spec.md`).
- Manifest hashing is raw-byte `sha256` (`sha256sum`/`shasum -a 256`), never `git hash-object` —
  avoids hashes that vary with a repo's own clean-filter (`text=auto`) configuration.

**Classification**, per template-owned path `P` found under `--source`:

| disk state at `P` | manifest state for `P` | action | disclosed as |
|---|---|---|---|
| absent | no entry | write `P`, record hash+mode | `created` |
| absent | entry present | write `P`, record hash+mode | `restored` |
| present, hash == new source's hash | any | update recorded hash if stale; if mode differs from source, stage+move `P`'s existing content under the corrected mode (no backup, content unchanged); else no write | `unchanged` |
| present, hash == manifest's recorded hash, hash != new source's hash | present | overwrite (back up first), update recorded hash+mode | `updated` |
| present, hash != manifest's recorded hash, hash != new source's hash | present | refuse without `--force`; with `--force`, back up and overwrite, update recorded hash+mode | `refused` / `forced-update` |
| present, no manifest entry (disk non-empty) | no entry | refuse without `--force`; with `--force`, back up, overwrite, record as new entry | `refused` / `forced-update` |

A path present in the old manifest but not among the new source's template-owned paths is never
written or deleted; its manifest entry is dropped and disclosed as `orphaned`. `CLAUDE.md` and
`.mkr/config` (the owned pair) are never classified by this table — they are seeded once, only
when absent at the target, and never appear in the manifest.

**Short-circuit.** The "hash == new source's hash" check runs before consulting the manifest at
all, so a file that already matches the new content is never refused or reported as an edit. This
also repairs a mode-only divergence (content matches, permissions don't) — staged and moved
through the same all-or-nothing pipeline as any other write, not an in-place `chmod`.

**All-or-nothing.** Every path's action is decided first (a mode-only repair is a decision made
here, not a mutation). Every write is then staged into a temp directory created via
`mktemp -d "<target>/.mkr-install-tmp.XXXXXX"` — a hidden sibling inside `--target` itself,
guaranteeing the same filesystem so the final move is a same-filesystem `mv`. Only after every
staged file is ready does `install.sh` move each into place and write `.claude/mkr-manifest` last,
atomically (temp file, then `mv`). A `trap ... EXIT` removes the staging directory whether the run
finished, failed, or was interrupted. The manifest write never happens under `--dry-run`, and
never happens if an earlier step exited early.

**Disclosure contract.** One line per acted-on path on stdout: `<label>\t<repo-relative-path>`,
`label` one of `created restored updated unchanged refused forced-update orphaned`. Diagnostics
(each overwrite's backup path, a `git check-ignore` WARN) go to stderr. After a fixed stdout marker
line, `--- revert ---`, the exact revert command for paths this run *created* follows, shell-quoted,
using `rm -f`; the marker and an empty command list both still appear when a run created nothing.

## Interfaces / contracts

### `install.sh` (repo root, executable bash)

**Flags:**
- `--source PATH` (required) — a directory containing `.claude/` and `seed/`. Missing or
  nonexistent → exit 1.
- `--target DIR` (optional) — default: `git rev-parse --show-toplevel` from `cwd`. Nonexistent
  path, outside any git work tree, a bare repo, or a dubious-ownership error → exit 1, naming the
  reason.
- `--force` — allow overwriting a `refused` row (a path diverging from both the manifest's and the
  new source's hash, or present with no manifest entry). Discloses as `forced-update`.
- `--dry-run` — runs the full classification and prints the same disclosure output, but skips
  every write and the manifest update. Exit 0 if nothing would be `refused`; exit 1 if anything
  would be — matching the real run's exit code.
- `--help` — prints usage, exits 0.
- Any other flag, a flag missing its required value, or a positional argument → exit 1. Repeated
  flags: last occurrence wins, no error.

**Preconditions**, checked before any classification: `--target`'s work tree is not mid-merge or
mid-rebase; at least one of `sha256sum` or `shasum -a 256` is available; no symlink (broken or
not) sits at any enumerated template-owned path at `--target` — checked over the full enumerated
set from `--source`, not just the subset a given run would actually classify. Source-side symlinks
are not checked (`--source` is this template's own trusted checkout).

**Exit codes:** `0` success (or a `--dry-run` that found nothing to refuse); `1` a refusal — bad
flags, an unmet precondition, a `refused` classification without `--force` — always with no
writes; `2` an unexpected I/O failure mid-run. The cleanup trap still fires on `2`, and no
partially-moved file reaches `--target`, since staged files are moved into place only after every
staged file succeeded.

**Steps:** enumerate every template-owned path under `--source` (`.claude/`, `.github/` if
present, plus the owned pair `seed/CLAUDE.md` → `CLAUDE.md` and `seed/config` → `.mkr/config`,
seeded only when absent at target, never classified); classify each against
`.claude/mkr-manifest`; for each path about to be written, run `git check-ignore` and, if ignored,
still write it but emit a stderr WARN naming the path. Under `--dry-run`, stop here — print the
disclosure output and the revert-command block, touch nothing under `--target`. Otherwise: stage
all writes, move them into place, write the manifest, print the disclosure output and the
revert-command block.

### `.claude/mkr-manifest` format

Plain text, LF-terminated, generated — never hand-edited, never itself a classified path:

```
# mkr-manifest v1
<sha256-hex> <mode-3-digit> <repo-relative-path>
```

One line per template-owned path, sorted by path. `mode` is the file's permission bits as three
octal digits, read from the source file when written and restored via `chmod` on write. A
manifest that fails to parse (missing header, a malformed data line) is treated as absent for the
run — every path falls back to the "no entry" row — and a stderr WARN discloses that it's being
rebuilt.

### `mkr-update` (skill + command)

Tool scope: only `Bash`, to invoke `install.sh` — no broader `Read`/`Write`/`Edit` grant.

Input: a source path (positional, or asked for if omitted). Steps:

1. Resolve `--target` the same way `install.sh` does (current repo's root).
2. Run `bash <resolved>/install.sh --source <resolved> --target <root> --dry-run` — the
   `install.sh` inside the resolved source checkout itself, not a copy assumed to already exist at
   `<root>`; capture its stdout/stderr and exit code.
3. If this dry-run exits nonzero (a precondition failure before classification produced any
   labeled rows), stop: report the captured error verbatim, render no drift report, do not ask.
4. Otherwise render a human-readable drift report grouped by label: counts and paths for `created`,
   `restored`, `updated`, `orphaned`, `refused` (refused paths named explicitly).
5. If anything is `refused`: state which paths, and that they'll be skipped unless the human asks
   for `--force` on this run (`--force` is whole-run, not per-path).
6. Ask — state the drift report plainly and require explicit human go-ahead before step 7. Never
   runs the real update unprompted.
7. Only after confirmation: run the same `<resolved>/install.sh` again without `--dry-run` (with
   `--force` only if confirmed), report the resulting disclosure output and revert-command block.

## Data model

No new `config.sh` variable. `install.sh`'s own location (repo root) and `.claude/mkr-manifest`'s
location are fixed template conventions, not `.mkr/config`-driven.

One new generated artifact: `.claude/mkr-manifest` — a state file `install.sh` reads and rewrites,
never hand-authored, never itself a classified template-owned path.
