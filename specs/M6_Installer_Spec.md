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
  place, all-or-nothing per run. Never deletes anything on a plain install/update run — the sole
  exception is the separate, explicit `--uninstall` path below.
- `install.sh` also installs `pre-push-review-guard.sh` (specs/M2_CodeReview_Spec.md) as a real
  git `.git/hooks/pre-push` symlink, when shipped and the default hooks location isn't already
  claimed by something else — the "install step, not a script" that spec deferred here.
- `install.sh --skip-git-hook` — never classifies or installs the `.git/hooks/pre-push` symlink;
  the rest of the file-drop install (`.claude/`, `.github/`) still runs and still succeeds. The
  symlink write has a fundamentally different risk profile than dropping ordinary files — some
  sandboxed/CI environments restrict writes under `.git/hooks/` specifically — and without this
  opt-out a single all-or-nothing run fails entirely rather than let the safe file-drop path
  succeed on its own. Discloses as `skipped\t.git/hooks/pre-push`.
- `install.sh --uninstall` (docs/adr/0005-install-uninstall-narrow-delete.md) — removes exactly
  what `.claude/mkr-manifest` at `--target` records, plus an owned `.git/hooks/pre-push` symlink;
  report-only unless `--confirm` is also given. A narrow, explicit exception to "never deletes
  anything," not a general delete capability.
- A plain install run also reports (never touches) any file under `.claude/skills/`,
  `.claude/commands/`, or `.claude/agents/` at `--target` that this run doesn't ship and no prior
  manifest ever recorded — a possible leftover from a different, unrelated toolkit.
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
- On a plain install/update run, `install.sh` never deletes anything. A template file dropped from
  a later version is left on disk untouched; only its manifest entry is removed, disclosed as
  `orphaned`. `--uninstall` is the one deliberate exception (below), gated behind an explicit
  second flag precisely because it reopens that guarantee.
- The git-hook install is found by basename (`*/pre-push-review-guard.sh`) among the already-
  enumerated `.claude/` paths, never by a hardcoded reference to the hooks/scripts subtree
  (tests/install_test.sh's TC-M6-14a static check forbids install.sh from referencing that path
  directly) — a `--source` without the script simply has nothing to find. It follows the same
  refuse/`--force`/backup/disclosure rules as any other path: absent → `created`; already our own
  symlink → `unchanged`; anything else there (an adopter's own hook) → `refused` without
  `--force`, `forced-update` with it, backing up the adopter's bytes first. A configured
  `core.hooksPath` is left alone entirely — this only ever touches the conventional
  `.git/hooks/` location.
- `install.sh` backs up any template-owned path it overwrites, before writing, in every case — not
  only divergent ones — to `<path>.mkr-backup` (overwriting any prior backup at that sibling path),
  disclosed on stderr alongside the stdout overwrite line. Backups are never deleted and
  `install.sh` never edits an adopter's `.gitignore`.
- `.claude/settings.json` gets one extra classification path, opportunistic on `jq` being on
  `PATH` (issue #1): a divergence that would otherwise `refuse` is first offered to a union-merge
  filter (`jq`, embedded in `install.sh`) — every hook entry the template ships is added if
  missing (matched by its `"command"` string), and nothing the adopter already has (an added hook,
  an added matcher, an unrelated top-level key) is ever removed. Success reclassifies the path as
  `merged`; disclosed, backed up, and staged exactly like `updated`. The merge is re-attempted on
  every run, not only the first — an already-merged target that still contains everything the
  current source ships re-merges to byte-identical content and is correctly reported `unchanged`,
  not silently overwritten with pure source the way `updated`'s ordinary hash-vs-manifest logic
  would otherwise do to it. Any failure — no `jq` on `PATH`, either side fails to parse as JSON, or
  the filter itself errors — falls back to the exact refuse/`--force` behavior this path always
  had; the merge only ever adds a better outcome, never a new failure mode.
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
| present, hash != manifest's recorded hash, hash != new source's hash | present | refuse without `--force`; with `--force`, back up and overwrite, update recorded hash+mode; for `.claude/settings.json` specifically, try a `jq` union-merge first (below) | `refused` / `forced-update` / `merged` |
| present, no manifest entry (disk non-empty) | no entry | refuse without `--force`; with `--force`, back up, overwrite, record as new entry; for `.claude/settings.json` specifically, try a `jq` union-merge first (below) | `refused` / `forced-update` / `merged` |

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
`label` one of `created restored updated unchanged refused forced-update orphaned merged skipped`
(`skipped` only ever for `.git/hooks/pre-push`, under `--skip-git-hook`). Diagnostics
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
- `--skip-git-hook` — never classify or install the `.git/hooks/pre-push` symlink; every other
  enumerated path still installs normally. Discloses as `skipped\t.git/hooks/pre-push`.
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
all writes, move them into place, write the manifest, and — unless `.mkr/audit.jsonl` is already
covered by the target's own `.gitignore` (a `git check-ignore` check, same mechanism as the WARN
above) — print a one-line stderr advisory to add it there; still never edits the file itself.
Then print the disclosure output and the revert-command block.

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
