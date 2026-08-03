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
  procwalk_is_registered_worktree "$ROOT" "$DIR" && exit 0
  deny "editing files" "make this change"
fi

if [ "$TOOL" = "Bash" ]; then
  # Every real `git commit` occurrence is checked independently, not just the last one: unlike a
  # branch switch (where only the final state matters), each commit in a chain is independently
  # consequential — `git commit -m x; cd <worktree> && git commit -m y` must still be denied for
  # the first, unsafe commit even though the second, decoy one resolves somewhere safe.
  while IFS= read -r -d '' target; do
    [ -z "$target" ] && target="${CLAUDE_PROJECT_DIR:-$PWD}"
    GITDIR="$(git -C "$target" rev-parse --absolute-git-dir 2>/dev/null)"
    [ -z "$GITDIR" ] && continue
    procwalk_is_registered_worktree "$ROOT" "$target" && continue
    deny "committing" "commit"
  done < <(procwalk_resolve_target_dirs "$IN" 'commit')
fi

exit 0
