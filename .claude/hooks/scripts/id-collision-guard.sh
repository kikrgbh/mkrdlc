#!/usr/bin/env bash
# PreToolUse/Write guard (specs/M3_Guardrails_Spec.md §7.4). BLOCK tier (docs/DESIGN.md §4).
#
# Denies creating a new <MKR_ADR_DIR>NNNN-*.md whose NNNN collides with an existing ADR.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"

IN="$(hookio_stdin)"
FILE_PATH="$(hookio_field "$IN" tool_input.file_path)"
[ -z "$FILE_PATH" ] && exit 0

ADR_DIR="$(mkr_get MKR_ADR_DIR)"
ADR_DIR="${ADR_DIR%/}"

case "$FILE_PATH" in
  */"$ADR_DIR"/[0-9][0-9][0-9][0-9]-*.md) : ;;
  "$ADR_DIR"/[0-9][0-9][0-9][0-9]-*.md) : ;;
  *) exit 0 ;;
esac

base="$(basename -- "$FILE_PATH")"
num="${base%%-*}"

abs_adr_dir="$ROOT/$ADR_DIR"
if [ -d "$abs_adr_dir" ]; then
  for existing in "$abs_adr_dir"/"$num"-*.md; do
    [ -e "$existing" ] || continue
    if [ "$(basename -- "$existing")" != "$base" ]; then
      hookio_pretooluse_decision deny "ADR number $num already used by $(basename -- "$existing") (id-collision-guard.sh)"
      exit 0
    fi
  done
fi

exit 0
