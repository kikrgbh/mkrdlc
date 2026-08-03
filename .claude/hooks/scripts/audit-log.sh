#!/usr/bin/env bash
# PostToolUse/* guard (specs/M3_Guardrails_Spec.md §7.7). Never blocks (AD-5) — appends one
# JSONL line per completed tool call to .mkr/audit.jsonl. A write failure is swallowed, not
# surfaced: observability must never itself become a new way to block work.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"

IN="$(hookio_stdin)"
TOOL_NAME="$(hookio_field "$IN" tool_name)"
SESSION_ID="$(hookio_field "$IN" session_id)"
SUMMARY="$(hookio_field "$IN" tool_input.command)"
[ -z "$SUMMARY" ] && SUMMARY="$(hookio_field "$IN" tool_input.file_path)"
SUMMARY="${SUMMARY:0:200}"

TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

{
  mkdir -p "$ROOT/.mkr" &&
  printf '{"ts":"%s","session_id":"%s","tool_name":"%s","summary":"%s"}\n' \
    "$(hookio_json_escape "$TS")" \
    "$(hookio_json_escape "$SESSION_ID")" \
    "$(hookio_json_escape "$TOOL_NAME")" \
    "$(hookio_json_escape "$SUMMARY")" \
    >> "$ROOT/.mkr/audit.jsonl"
} 2>/dev/null

exit 0
