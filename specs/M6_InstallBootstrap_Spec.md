# `install.sh` bootstraps itself when `--source` is omitted

## Intent

`install.sh` gains a bootstrap mode: when invoked with no `--source` (the piped
`curl -fsSL .../install.sh | bash` form), it clones itself into a temp directory instead of
erroring immediately, so the one-liner `README.md`/`docs/DESIGN.md` document actually works.

## Scope

**In scope**
- `--source` omitted, `git` available → clone `--repo` (default
  `https://github.com/kikrgbh/mkr-aidlc.git`) with `git clone --depth 1` into a `mktemp -d`, use
  that directory as `--source`, remove it via a cleanup trap on `EXIT`.
- `--source` given → behavior identical to before; `--repo` is ignored, nothing is cloned.
- `--repo URL` — new, optional, documented flag (shown in `usage()`).
- `stage_and_move`'s own single-purpose cleanup trap is replaced by a shared `CLEANUP_DIRS` array
  and one trap installed once in `main()`.
- `README.md`'s "Build status" sentence claiming no network fetch exists is corrected.

**Out of scope**
- Any change to `install.sh`'s enumerated shipped surface (what ships to an adopter's repo).
- Any change to `.github/workflows/mkr-gate.yml`.
- Pinned-release / tagged-version installs — still an open decision, untouched here.

## Architecture & key decisions

- Bootstrap via clone-and-reinvoke, not a docs rewrite — keeps the advertised `curl | bash`
  one-liner literally true; adds no new trust boundary beyond what piping a script into `bash`
  already implies, since the clone targets the same named repo the script itself came from.
- The clone tracks the same ref (`main`) the running script was fetched from, not a pinned release
  tag — keeps both halves of the one-liner at the same revision by construction. Pinned-release
  installs remain a separate, unresolved decision.
- `--repo` is a documented CLI flag, not an env var — matches `install.sh`'s existing all-flag
  surface (`--source`, `--target`, `--force`, `--dry-run`), and doubles as the seam tests use to
  point the bootstrap at a local fixture repo instead of the network.
- A single consolidated `CLEANUP_DIRS` trap replaces `stage_and_move`'s own — bash's `trap ... EXIT`
  does not stack (only the last handler registered wins); two independent traps would silently
  clobber each other and leak a temp directory.
- The clone restricts `git`'s transport to a fixed protocol allowlist
  (`GIT_ALLOW_PROTOCOL='https:http:git:ssh:file'`) — an adopter-controlled `--repo` value using
  `git`'s `ext::` remote-helper transport would otherwise achieve arbitrary command execution, not
  a clone; the allowlist still permits a plain local-path clone (fixtures, local mirrors).

## Interfaces / contracts

- `parse_args` — the unconditional "`--source` is required" die is removed. A new `--repo` flag is
  parsed the same way `--target` already is (`--repo` / `MKR_REPO`, requires a value, defaults to
  `https://github.com/kikrgbh/mkr-aidlc.git`).
- New `maybe_bootstrap_source()`, called from `main()` right after `parse_args` and before
  `resolve_source`. No-op if `--source` was given (`--repo` silently unused; explicit `--source`
  always wins). Otherwise: requires `git` on `PATH`; `mktemp -d`; registers that path into
  `CLEANUP_DIRS`; clones under the protocol allowlist above; on failure, dies naming the repo URL;
  on success, sets `MKR_SOURCE` to the clone. `resolve_source`'s existing `.claude`/`seed`
  validation then runs unchanged against it.
- New `CLEANUP_DIRS` array + `cleanup_all()`, trap installed once in `main()`. `stage_and_move`
  appends its own staging directory to `CLEANUP_DIRS` instead of installing its own trap; its
  staging/move logic is otherwise unchanged.
- `usage()` gains one line documenting `--repo URL`.
- No change to `install.sh`'s exit codes, `.claude/mkr-manifest`'s format, `resolve_source`'s
  validation, `resolve_target`'s logic, the classify/stage/move pipeline, or `/mkr-update`'s
  contract — `/mkr-update` always calls `install.sh` with an explicit `--source`, so
  `maybe_bootstrap_source` is a no-op for every `/mkr-update` invocation.

## Data model

No change. `.claude/mkr-manifest`'s format and content are unaffected — the bootstrap step only
changes where `--source` points before the existing manifest logic runs.
