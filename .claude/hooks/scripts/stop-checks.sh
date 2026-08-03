#!/usr/bin/env bash
# Stop guard (specs/M3_Guardrails_Spec.md §7.6, specs/StopHookToggle_Spec.md §7). Blocks the
# session from stopping (forces continuation) when this session's uncommitted changes touch a
# test-relevant path and the effective test command fails. Never blocks an un-configured project,
# and never blocks when nothing test-relevant changed. MKR_STOP_TEST_MODE selects which command:
# full (default/unset) = MKR_TEST, fast = MKR_TEST_FAST, off = never blocks.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"

MODE="$(mkr_get MKR_STOP_TEST_MODE)"
case "$MODE" in
  off)
    exit 0 ;;
  fast)
    LABEL="MKR_TEST_FAST"
    MKR_TEST_CMD="$(mkr_get MKR_TEST_FAST)"
    ;;
  ''|full)
    LABEL="MKR_TEST"
    MKR_TEST_CMD="$(mkr_get MKR_TEST)"
    ;;
  *)
    printf 'mkr: MKR_STOP_TEST_MODE=%s not recognized (full|fast|off) — falling back to full\n' "$MODE" >&2
    LABEL="MKR_TEST"
    MKR_TEST_CMD="$(mkr_get MKR_TEST)"
    ;;
esac
[ -z "$MKR_TEST_CMD" ] && exit 0

changed="$(cd "$ROOT" && git status --porcelain 2>/dev/null)"
[ -z "$changed" ] && exit 0

paths="$(printf '%s\n' "$changed" | sed -E 's/^...//')"
relevant=0
while IFS= read -r p; do
  case "$p" in
    tests/*|.claude/hooks/*|.claude/agents/*|.claude/skills/*|.claude/commands/*|specs/*)
      relevant=1; break ;;
  esac
done <<< "$paths"

[ "$relevant" -eq 0 ] && exit 0

out="$(cd "$ROOT" && bash -c "$MKR_TEST_CMD" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ]; then
  tail_out="$(printf '%s' "$out" | tail -n 20)"
  hookio_stop_block "$LABEL ('$MKR_TEST_CMD') failed (exit $rc) — fix before stopping (stop-checks.sh, docs/DESIGN.md §2 phase 6):
$tail_out"
fi

exit 0
