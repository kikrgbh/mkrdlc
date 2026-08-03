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

BASE=""
while IFS= read -r candidate; do
  [ -z "$candidate" ] && continue
  if git -C "$ROOT" rev-parse --verify --quiet "$candidate" >/dev/null 2>&1; then
    BASE="$candidate"; break
  fi
  if git -C "$ROOT" rev-parse --verify --quiet "origin/$candidate" >/dev/null 2>&1; then
    BASE="origin/$candidate"; break
  fi
done < <(mkr_list MKR_PROTECTED_BRANCHES)

[ -z "$BASE" ] && exit 0               # unresolvable — fail open

MERGE_BASE="$(git -C "$ROOT" merge-base HEAD "$BASE" 2>/dev/null)"
[ -z "$MERGE_BASE" ] && exit 0

has_accepted_spec() {
  local f
  while IFS= read -r f; do
    [ -z "$f" ] && continue
    if [ -f "$ROOT/$f" ] && grep -Eq '\*\*Status\*\*.*ACCEPTED' "$ROOT/$f" 2>/dev/null; then
      return 0
    fi
  done < <(
    { git -C "$ROOT" diff --name-only "$MERGE_BASE"...HEAD -- "$SPECS_DIR" 2>/dev/null
      git -C "$ROOT" status --porcelain --untracked-files=all -- "$SPECS_DIR" 2>/dev/null | sed -E 's/^...//'
    } | sort -u
  )
  return 1
}

if has_accepted_spec; then
  exit 0
fi

hookio_pretooluse_decision ask "no spec on this branch has reached ACCEPTED yet — proceeding treats this as Quick-depth; confirm that's intended, or run mkr-loop first (spec-gate.sh, docs/DESIGN.md §4 G1)"
exit 0
