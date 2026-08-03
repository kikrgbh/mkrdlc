#!/usr/bin/env bash
# G4's local half (specs/M2_CodeReview_Spec.md §7.4, AD-3): a genuine git
# `pre-push` hook, not a Claude-Code settings.json tool-hook (that's a
# different mechanism, wiring the *other* guards at M3). WARNs only, never
# blocks — the hard stop is CI checking the record exists, added at M3.
#
# Installed by symlinking this file into <repo-root>/.git/hooks/pre-push;
# distributing that install step to an adopter's repo is install.sh's job
# (M6), not this script's.
#
# Reads git's own pre-push stdin protocol, one line per ref being pushed:
#   <local ref> SP <local sha1> SP <remote ref> SP <remote sha1> LF
set -uo pipefail

# Git sets these for every hook invocation (its own hook-invocation contract). Left unguarded,
# the git rev-parse call right below — and, transitively, config.sh's own _mkr_resolve_path()
# fallback, sourced later in this same process — would resolve against a leaked GIT_DIR instead
# of the actual repo this hook is running in (reproduced empirically against a decoy repo
# during this fix's own drafting).
unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then
  printf 'WARN: pre-push-review-guard.sh: not inside a git work tree; skipping\n' >&2
  exit 0
fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/reviewrecord.sh"

REVIEWS_DIR="$(mkr_get MKR_REVIEWS_DIR)"
SPECS_DIR="$(mkr_get MKR_SPECS_DIR)"
ZERO_SHA='0000000000000000000000000000000000000000'

while read -r _local_ref local_sha1 _remote_ref remote_sha1; do
  [ -z "${local_sha1:-}" ] && continue
  [ "$local_sha1" = "$ZERO_SHA" ] && continue   # deleting a ref — nothing to review

  # Fixed 7-char prefix, not git's own variable-length --short abbreviation
  # (spec §7.1) — matches mkr-code-review's own filename computation with no
  # shared state, and this repo's pre-existing .mkr/reviews/ precedent. A record committed as a
  # separate trailing commit (this repo's own convention) can never name its own sha — checked
  # via find_review_record's one-level parent fallback before warning. A
  # merge commit resolves via its second parent only once its first parent is confirmed to equal
  # the real remote tip before this push (git's own pre-push protocol value, `remote_sha1` —
  # never derived from `local_sha1` itself; the all-zero sentinel means no prior remote tip
  # exists, so the merge-commit path is correctly unreachable for a brand-new ref).
  short="${local_sha1:0:7}"
  expected_prior_tip="$remote_sha1"
  [ "$expected_prior_tip" = "$ZERO_SHA" ] && expected_prior_tip=""
  if ! record="$(find_review_record "$local_sha1" "$REVIEWS_DIR" "$SPECS_DIR" "$expected_prior_tip")"; then
    printf 'WARN: no review record for %s (checked %s/%s.md and, if applicable, its parent) — run /mkr-code-review before pushing (docs/DESIGN.md §2 phase 7)\n' \
      "$short" "${REVIEWS_DIR%/}" "$short" >&2
  fi
done

exit 0
