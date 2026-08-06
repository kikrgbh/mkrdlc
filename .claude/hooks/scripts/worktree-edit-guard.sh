#!/usr/bin/env bash
# PreToolUse/Write,Edit,Bash guard (specs/WorktreeGuard_Spec.md §7.4). Active only at
# MKR_WORKTREE_POLICY=enforced (§6 AD-1) — blocks a Write/Edit or a `git commit` made directly
# in a checkout that isn't a real, currently-registered linked worktree of this project's own
# repo (`procwalk_is_registered_worktree`, cross-checked against `git worktree list`'s own
# authoritative registry — a `git -C <dir> rev-parse --absolute-git-dir`-returned *string* is not
# trusted on its own shape, since `git init --separate-git-dir=<anywhere>/.git/worktrees/<name>
# <dir>` fabricates one for a completely unrelated, non-isolated repo in a single command). An
# empty (unresolvable) git-dir always allows, checked before the registration test (§6 AD-4
# path 3) — an empty string is never a registered worktree either way, but checking it first
# keeps the two failure modes ("not a repo at all" vs. "a repo, just not a linked worktree of
# this one") distinct and each independently testable.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/procwalk.sh"

POLICY="$(mkr_get MKR_WORKTREE_POLICY)"
[ "$POLICY" != "enforced" ] && exit 0

IN="$(hookio_stdin)"
TOOL="$(hookio_field "$IN" tool_name)"

deny() {
  hookio_pretooluse_decision deny "$1 directly in the shared checkout is not allowed under MKR_WORKTREE_POLICY=enforced (worktree-edit-guard.sh) — create a worktree first: git worktree add ../<name> <branch>, then $2 there."
  exit 0
}

# is_single_bare_git_commit <cmd> — true (rc 0) iff <cmd> is provably nothing but a plain
# `git commit -m "<message>"` (or single-quoted), with nothing else in the string at all.
# is_bootstrap_policy_commit below decides "safe" by reading the CURRENTLY staged index — a
# snapshot taken before ANY part of this Bash tool call has actually run — so that decision is
# only trustworthy when nothing else in the same tool call can run between this check and the
# commit itself. This started as a blocklist of "dangerous" shell constructs and was rewritten
# to a strict allowlist after four straight G4 review rounds each found one more construct the
# blocklist hadn't thought of — every round closing the exact case just reported while leaving
# the next one open: (a) `git commit -m bootstrap && ... && git add x && git commit -m smuggle`
# (two `commit` occurrences, both checked against the same stale snapshot); (b) `git add x &&
# git commit -m bootstrap` (one occurrence, but `x` lands in the same commit); (c) `git add x &
# git commit -m bootstrap` (bare `&` backgrounds instead of sequencing, same effect); (d)
# `git commit -m bootstrap -F <(git add sneaky.txt)` (process substitution — no `&`/`;`/`|`/`$(`/
# backtick/newline at all, forks a concurrent subprocess anyway); (e), the one that ended the
# blocklist approach: `GIT_EDITOR="sh -c \"git add sneaky.txt\"" git commit -m bootstrap -e` —
# `-e` forces git to invoke the (attacker-controlled) editor even though `-m` already supplies a
# message, and git does not hold the index lock across that invocation, so whatever the editor
# process stages lands in the same commit tree; the identical mechanism works via `-c
# core.editor=...`/`-c gpg.program=...` instead of an env-var prefix. A blocklist has to name
# every one of these (and whatever git/shell feature is next); an allowlist that only accepts the
# one command shape with no room for anything else — no leading env-var/`-c` prefix, no flag but
# `-m`, nothing trailing the closing quote — structurally excludes all five variants above, and
# any future one that isn't yet known, in a single check. A double-quoted message still passes
# through `procwalk_has_command_substitution` below: bash expands `$(...)`/backtick (though not
# `<(...)`/`>(...)`) inside double quotes, so `git commit -m "$(evil)"` would otherwise
# structurally match the allowlist while still being a real command-execution vector — the
# allowlist regex alone is necessary but not sufficient, hence both checks. The cost is rejecting
# some harmless variations too (an unquoted single-word message, `-q`, `cd "$ROOT" &&` in front)
# — an acceptable false-negative for a narrow bootstrapping escape hatch: denied here just falls
# back to the ordinary "create a worktree first" path, never an exploit.
is_single_bare_git_commit() {
  local cmd="$1" pat_dq pat_sq
  pat_dq='^git commit -m "[^"]*"$'
  pat_sq="^git commit -m '[^']*'\$"
  if [[ "$cmd" =~ $pat_dq ]] || [[ "$cmd" =~ $pat_sq ]]; then
    procwalk_has_command_substitution "$cmd" && return 1
    return 0
  fi
  return 1
}

# is_bootstrap_policy_commit <target> — true (rc 0) iff <target>'s staged changes are EXACTLY
# the single line in .mkr/config that turns MKR_WORKTREE_POLICY on. Without this, the commit
# that first sets MKR_WORKTREE_POLICY=enforced is itself blocked in the shared checkout: this
# guard reads the just-staged/just-written value from disk (config.sh has no notion of "before
# this commit"), so the policy is already "enforced" by the time the very commit enabling it
# runs — a bootstrapping trap with no escape inside the shared checkout, since creating a
# worktree first doesn't help either (the same just-edited file is what a worktree would carry
# too). Scoped narrowly: only the shared checkout's OWN top-level ($ROOT, not any other repo),
# only a staged diff touching `.mkr/config` and nothing else, and only a one-line change to
# MKR_WORKTREE_POLICY itself, landing on a value of "enforced" — never a blanket bypass for
# unrelated `.mkr/config` edits, and never for a change bundled with edits to any other file. The
# caller only invokes this after is_single_bare_git_commit has already confirmed nothing else in
# the same Bash tool call can run between this check and the commit — see that function's comment.
is_bootstrap_policy_commit() {
  local target="$1"
  [ "$target" = "$ROOT" ] || return 1

  local files
  files="$(git -C "$target" diff --cached --name-only -- .mkr/config 2>/dev/null)"
  [ "$files" = ".mkr/config" ] || return 1
  [ "$(git -C "$target" diff --cached --name-only 2>/dev/null)" = ".mkr/config" ] || return 1

  local numstat adds dels
  numstat="$(git -C "$target" diff --cached --numstat -- .mkr/config 2>/dev/null)"
  adds="$(printf '%s' "$numstat" | awk '{print $1}')"
  dels="$(printf '%s' "$numstat" | awk '{print $2}')"
  [ "$adds" = "1" ] || return 1
  { [ "$dels" = "0" ] || [ "$dels" = "1" ]; } || return 1

  local diff added removed
  diff="$(git -C "$target" diff --cached -- .mkr/config 2>/dev/null)"
  added="$(printf '%s\n' "$diff" | grep -E '^\+MKR_WORKTREE_POLICY=')"
  printf '%s\n' "$added" | grep -Eq '^\+MKR_WORKTREE_POLICY=\"?enforced\"?[[:space:]]*$' || return 1
  if [ "$dels" = "1" ]; then
    removed="$(printf '%s\n' "$diff" | grep -E '^-MKR_WORKTREE_POLICY=')"
    [ -n "$removed" ] || return 1
  fi
  return 0
}

if [ "$TOOL" = "Write" ] || [ "$TOOL" = "Edit" ]; then
  FILE="$(hookio_field "$IN" tool_input.file_path)"
  [ -z "$FILE" ] && exit 0
  DIR="$(dirname -- "$FILE")"
  # PreToolUse fires before the write happens, so DIR itself commonly doesn't exist yet (e.g. a
  # Write creating the first file under a brand-new subdirectory) — `git -C <dir>` requires the
  # directory to already exist, so without this walk every such write would fail open on an
  # empty GITDIR even when it will land inside the shared, non-worktree checkout once created.
  # Walk up to the nearest directory that does exist before asking git; a target genuinely
  # outside any repo anywhere in its ancestry (TC-WG-16) still ends up with an empty GITDIR once
  # the walk reaches an existing, non-repo directory (or "/").
  while [ ! -d "$DIR" ] && [ "$DIR" != "/" ] && [ "$DIR" != "." ]; do
    DIR="$(dirname -- "$DIR")"
  done
  GITDIR="$(git -C "$DIR" rev-parse --absolute-git-dir 2>/dev/null)"
  [ -z "$GITDIR" ] && exit 0
  # `git worktree list`'s own registry only ever names a worktree's TOP-level directory — a
  # Write/Edit at any deeper path (the overwhelmingly common case: almost no file sits directly
  # at a worktree's root) must resolve up to that top level before the registration check below,
  # or every such edit inside an otherwise perfectly valid, registered linked worktree would be
  # denied. `rev-parse --show-toplevel` is safe here precisely because GITDIR above already
  # proved `$DIR` resolves inside a real repo.
  WTDIR="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null)"
  [ -z "$WTDIR" ] && WTDIR="$DIR"
  procwalk_is_registered_worktree "$ROOT" "$WTDIR" && exit 0
  deny "editing files" "make this change"
fi

if [ "$TOOL" = "Bash" ]; then
  RAW_CMD="$(hookio_field "$IN" tool_input.command)"
  # Every real `git commit` occurrence is checked independently, not just the last one: unlike a
  # branch switch (where only the final state matters), each commit in a chain is independently
  # consequential — `git commit -m x; cd <worktree> && git commit -m y` must still be denied for
  # the first, unsafe commit even though the second, decoy one resolves somewhere safe.
  while IFS= read -r -d '' target; do
    [ -z "$target" ] && target="${CLAUDE_PROJECT_DIR:-$PWD}"
    GITDIR="$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null)"
    [ -z "$GITDIR" ] && continue
    # Same top-level resolution as the Write/Edit branch above: a `cd`/`-C` into a subdirectory
    # of a registered worktree (e.g. `cd <worktree>/packages/db && git commit`) must not be
    # compared against the registry's own top-level-only entries as-is.
    WTDIR="$(git -C "$target" rev-parse --show-toplevel 2>/dev/null)"
    [ -z "$WTDIR" ] && WTDIR="$target"
    procwalk_is_registered_worktree "$ROOT" "$WTDIR" && continue
    is_single_bare_git_commit "$RAW_CMD" && is_bootstrap_policy_commit "$WTDIR" && continue
    deny "committing" "commit"
  done < <(procwalk_resolve_target_dirs "$IN" 'commit')
fi

exit 0
