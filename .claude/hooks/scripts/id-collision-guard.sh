#!/usr/bin/env bash
# PreToolUse/Write guard (specs/M3_Guardrails_Spec.md §7.4). BLOCK tier (docs/DESIGN.md §4).
#
# Denies creating a new <dir>NNNN-* whose NNNN collides with an existing file in that same
# ID-namespaced directory — MKR_ADR_DIR always, plus any directory a project lists in
# MKR_ID_DIRS (e.g. a migrations directory that also numbers its files NNNN-*). Checks both the
# local working tree and, best-effort, origin/main — a number only free locally can already be
# taken on a branch someone else pushed and merged; origin/main-awareness catches that earlier
# than mkr-gate.yml's own CI-time, push-time re-check would.
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

# The set of ID-namespaced directories this guard covers: MKR_ADR_DIR always (backward
# compatible with every existing config), plus MKR_ID_DIRS — a project-declared list of
# additional directories that share the same NNNN-* numbering convention but aren't ADRs (a
# migrations/ directory, say). Extension point, not a new architecture: same pattern, more dirs.
ID_DIRS=()
adr_dir="$(mkr_get MKR_ADR_DIR)"
[ -n "$adr_dir" ] && ID_DIRS+=("${adr_dir%/}")
while IFS= read -r extra; do
  [ -n "$extra" ] && ID_DIRS+=("${extra%/}")
done < <(mkr_list MKR_ID_DIRS)

MATCHED_DIR=""
for dir in "${ID_DIRS[@]}"; do
  case "$FILE_PATH" in
    */"$dir"/[0-9][0-9][0-9][0-9]-*) MATCHED_DIR="$dir"; break ;;
    "$dir"/[0-9][0-9][0-9][0-9]-*) MATCHED_DIR="$dir"; break ;;
  esac
done
[ -z "$MATCHED_DIR" ] && exit 0

base="$(basename -- "$FILE_PATH")"
num="${base%%-*}"

# 1. Local working tree — the original, always-available check.
abs_dir="$ROOT/$MATCHED_DIR"
if [ -d "$abs_dir" ]; then
  for existing in "$abs_dir"/"$num"-*; do
    [ -e "$existing" ] || continue
    if [ "$(basename -- "$existing")" != "$base" ]; then
      hookio_pretooluse_decision deny "ID number $num in $MATCHED_DIR already used by $(basename -- "$existing") (id-collision-guard.sh)"
      exit 0
    fi
  done
fi

# 2. origin/<default-branch> — best-effort. <default-branch> is the first entry of
# MKR_PROTECTED_BRANCHES (this codebase's own source of truth for the primary integration branch
# elsewhere, e.g. mkr-merge's own resolution) rather than a hardcoded "main" — an adopter whose
# protected branch isn't literally "main" still gets real coverage, not a silent no-op.
# GIT_TERMINAL_PROMPT=0 so a missing credential never hangs waiting on a prompt. The live fetch
# itself only ever runs when `timeout` is on PATH — without it, there is no portable way to bound
# a `git fetch` against a slow or adversarial remote, and this hook runs synchronously in the
# PreToolUse path, so an unbounded fetch could hang every subsequent Write for the rest of the
# session (found at this PR's own G4 security review; a stock macOS install ships no `timeout`).
# Skipping the live fetch in that case still checks whatever origin/<default-branch> ref already
# exists locally (e.g. from a previous, unrelated fetch) — never worse than doing nothing, never a
# reason to attempt an unbounded network call from here. Any failure — no `origin` remote, no
# network, a timeout, no `timeout` binary — falls back to the local-only result above rather than
# denying: this check can only ever catch MORE collisions than before, never fewer, and a hook
# that started blocking every Write whenever the network is down would be a worse regression than
# the gap it closes. mkr-gate.yml's own CI-time check (fetch-depth: 0) remains the authoritative
# backstop.
default_branch="$(mkr_list MKR_PROTECTED_BRANCHES | head -n1)"
[ -z "$default_branch" ] && default_branch=main
if git -C "$ROOT" remote get-url origin >/dev/null 2>&1; then
  if command -v timeout >/dev/null 2>&1; then
    GIT_TERMINAL_PROMPT=0 timeout 5 git -C "$ROOT" fetch --quiet --no-tags origin "$default_branch" >/dev/null 2>&1
  fi
  if git -C "$ROOT" rev-parse --verify -q "origin/$default_branch" >/dev/null 2>&1; then
    while IFS= read -r remote_path; do
      [ -z "$remote_path" ] && continue
      remote_base="$(basename -- "$remote_path")"
      remote_num="${remote_base%%-*}"
      if [ "$remote_num" = "$num" ] && [ "$remote_base" != "$base" ]; then
        hookio_pretooluse_decision deny "ID number $num in $MATCHED_DIR already used by $remote_base on origin/$default_branch (id-collision-guard.sh)"
        exit 0
      fi
    done < <(git -C "$ROOT" ls-tree -r --name-only "origin/$default_branch" -- "$MATCHED_DIR" 2>/dev/null)
  fi
fi

exit 0
