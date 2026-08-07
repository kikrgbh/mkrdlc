#!/usr/bin/env bash
# PreToolUse/Write|Edit guard (specs/M3_Guardrails_Spec.md §7.5). ASK tier (docs/DESIGN.md §4, G1).
#
# Never blocks — asks. Inert (allow, silently) whenever .mkr/config doesn't exist yet (AD-3,
# resolving docs/DESIGN.md §9 item 4): a fresh, un-adopted clone is never surprised by an ASK
# on its very first edit.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/procwalk.sh"

# AD-3: inert until this repo (or an adopter's) has actually run /mkr-init. config.sh (sourced
# above) already set MKR_CONFIG_ACTIVE as a side effect of _mkr_load.
if [ "${MKR_CONFIG_ACTIVE:-0}" != "1" ]; then
  exit 0
fi

IN="$(hookio_stdin)"
FILE_PATH="$(hookio_field "$IN" tool_input.file_path)"
[ -z "$FILE_PATH" ] && exit 0

SPECS_DIR="$(mkr_get MKR_SPECS_DIR)"; SPECS_DIR="${SPECS_DIR%/}"
ADR_DIR="$(mkr_get MKR_ADR_DIR)"; ADR_DIR="${ADR_DIR%/}"

# Never gates non-source paths (AD-4): the spec/ADR itself, docs, tests, or the two owned
# project-fact files and VERSION.
case "$FILE_PATH" in
  */"$SPECS_DIR"/*|"$SPECS_DIR"/*) exit 0 ;;
  */"$ADR_DIR"/*|"$ADR_DIR"/*) exit 0 ;;
  */docs/*|docs/*) exit 0 ;;
  */tests/*|tests/*) exit 0 ;;
  */README.md|README.md) exit 0 ;;
  */CLAUDE.md|CLAUDE.md) exit 0 ;;
  */VERSION|VERSION) exit 0 ;;
esac

# $ROOT above is the hook process's own cwd — this session's fixed primary checkout — but the
# file actually being edited can live in a different worktree, on a different branch, with its
# own spec/ADR state (e.g. the agent editing directly inside a linked worktree while the hook
# subprocess itself still runs from the primary checkout). Every git query below (branch
# resolution, merge-base, spec lookup) should run against THAT checkout, not blindly against
# $ROOT, or the gate silently checks the wrong repo. Walk up to the nearest existing ancestor
# first: PreToolUse fires before the write happens, so a Write creating the first file under a
# brand-new subdirectory commonly has a directory that doesn't exist yet, and `git -C` requires
# it to.
TARGET_DIR="$(dirname -- "$FILE_PATH")"
while [ ! -d "$TARGET_DIR" ] && [ "$TARGET_DIR" != "/" ] && [ "$TARGET_DIR" != "." ]; do
  TARGET_DIR="$(dirname -- "$TARGET_DIR")"
done
TARGET_ROOT="$(git -C "$TARGET_DIR" rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$TARGET_ROOT" ]; then
  # The edited file isn't inside any git working tree at all (e.g. a scratch path outside every
  # repo) — fall back to $ROOT exactly as this hook behaved before TARGET_ROOT existed, rather
  # than silently skipping the gate for want of a repo to check.
  TARGET_ROOT="$ROOT"
elif [ "$TARGET_ROOT" != "$ROOT" ]; then
  # A DIFFERENT root is only trusted when it's a genuine, currently-registered linked worktree of
  # this same project (cross-checked against git's own `worktree list` registry, not a spoofable
  # path string — see procwalk_is_registered_worktree). $SPECS_DIR/$ADR_DIR/MKR_PROTECTED_BRANCHES
  # above were already read from $ROOT's own config, so treating some other, unrelated repository
  # as TARGET_ROOT would check that project's git state using this project's policy — a mismatch
  # that fails open (e.g. its branch names never match MKR_PROTECTED_BRANCHES) rather than closed.
  procwalk_is_registered_worktree "$ROOT" "$TARGET_ROOT" || TARGET_ROOT="$ROOT"
fi

BASE=""
while IFS= read -r candidate; do
  [ -z "$candidate" ] && continue
  if git -C "$TARGET_ROOT" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
    BASE="$candidate"; break
  fi
  if git -C "$TARGET_ROOT" rev-parse --verify --quiet "origin/$candidate" >/dev/null 2>&1; then
    BASE="origin/$candidate"; break
  fi
done < <(mkr_list MKR_PROTECTED_BRANCHES)

[ -z "$BASE" ] && exit 0               # unresolvable — fail open

MERGE_BASE="$(git -C "$TARGET_ROOT" merge-base HEAD "$BASE" 2>/dev/null)"
[ -z "$MERGE_BASE" ] && exit 0

has_accepted_spec() {
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -f "$TARGET_ROOT/$f" ] && grep -Eq '\*\*Status\*\*.*ACCEPTED' "$TARGET_ROOT/$f" 2>/dev/null; then
      return 0
    fi
  done < <(
    { git -C "$TARGET_ROOT" diff --name-only "$MERGE_BASE"...HEAD -- "$SPECS_DIR" 2>/dev/null
      git -C "$TARGET_ROOT" status --porcelain --untracked-files=all -- "$SPECS_DIR" 2>/dev/null | sed -E 's/^...//'
    } | sort -u
  )
  return 1
}

if has_accepted_spec; then
  exit 0
fi

hookio_pretooluse_decision ask "no spec on this branch has reached ACCEPTED yet — proceeding treats this as Quick-depth; confirm that's intended, or run mkr-loop first (spec-gate.sh, docs/DESIGN.md §4 G1)"
exit 0
