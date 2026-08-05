#!/usr/bin/env bash
# mkr-aidlc — G4 review-record lookup, with a one-level parent fallback. Sourced only, never
# executed, matching procwalk.sh's/config.sh's own convention.
#
# Requires bash 4.0+, matching config.sh's own baseline.

# _reviewrecord_is_ready (below) reads MKR_REVIEW_VERDICT_STRING via mkr_get. Every real caller
# (pre-push-review-guard.sh) already sources config.sh first, but this file makes that a
# guarantee rather than an assumption a caller could get wrong — sourcing config.sh a second time
# is a documented no-op (config.sh's own TC-12), so this is never harmful when it's redundant.
if ! declare -F mkr_get >/dev/null 2>&1; then
  # shellcheck source=./config.sh
  . "$(dirname -- "${BASH_SOURCE[0]}")/config.sh"
fi

# _reviewrecord_is_ready <file> — true only if <file> exists and contains a line starting
# "VERDICT: READY" (the literal closing line specs/M2_CodeReview_Spec.md §7.3's format and
# mkr-code-review's own skill always write for a passing review). Existence alone was never a
# meaningful check even before this fallback existed — the fallback is what makes it newly
# reachable via self-fabrication (found by mkr-security-reviewer at this spec's own G4, §13):
# before, no commit could ever satisfy the exact-match check by construction (a commit cannot
# name a file after its own not-yet-computed hash), so a fabricated record had nowhere to land;
# the fallback's parent-lookup breaks that structural accident, since a trailing commit *can*
# know its parent's sha in advance. This check does not authenticate who wrote the record or
# prove a real review actually ran — it only rejects the trivial, accidental case (a stray or
# placeholder file) and requires deliberate, informed forgery of the established format, which is
# the same residual-risk shape this repo already accepts elsewhere.
_reviewrecord_is_ready() {
  local file="$1" pattern
  [ -e "$file" ] || return 1
  # MKR_REVIEW_VERDICT_STRING (default "VERDICT: READY") lets a project customize the record's
  # own passing-verdict literal without patching this file. Matched as an anchored line-prefix via
  # awk substr, not grep -E/-F against a config value: a config value is project data, not a
  # regex a caller should have to escape, and this avoids a customized string containing "^$.*[]"
  # ever being misread as a pattern instead of literal text.
  pattern="$(mkr_get MKR_REVIEW_VERDICT_STRING)"
  awk -v p="$pattern" 'substr($0, 1, length(p)) == p { found=1; exit } END { exit !found }' "$file" 2>/dev/null
}

# find_review_record <sha> <reviews_dir> <specs_dir> [expected_prior_tip] — prints the resolved
# review-record path and returns 0 if found: either an exact match at
# <reviews_dir>/<sha's first 7 chars>.md, a match at <sha>'s immediate parent (only when <sha>'s own
# diff touches nothing outside <reviews_dir> or <specs_dir>), or — when <sha> is a merge commit
# (`gh pr merge --merge`/`git merge --no-ff`), its first parent exactly equals the caller-supplied
# <expected_prior_tip>, *and* its own tree is provably identical to a clean recomputed merge of its
# two parents (below) — whatever this same function resolves for <sha>'s second parent.
# Either match must also pass
# `_reviewrecord_is_ready` (above). Prints nothing and returns 1 otherwise. Read-only; assumes cwd is
# inside the git work tree <sha> belongs to.
#
# <expected_prior_tip> is required for the merge-commit path to ever succeed (empty/omitted
# unconditionally refuses it, AD-3) — callers must supply a value they independently know to be the
# real, trusted branch tip immediately before this push/merge (`github.event.before` on `push`;
# `pre-push-review-guard.sh`'s own `remote_sha1` from git's pre-push stdin protocol), never derived
# from `<sha>` itself.
find_review_record() {
  local sha="$1" reviews_dir="${2%/}" specs_dir="${3%/}" expected_prior_tip="${4-}" short record

  short="${sha:0:7}"
  record="${reviews_dir}/${short}.md"
  if _reviewrecord_is_ready "$record"; then
    printf '%s\n' "$record"
    return 0
  fi

  # `git diff-tree` shows an empty diff for a merge commit by default (no `-m`/`-c`), which the
  # exact-diff fallback below would otherwise misread as "nothing changed outside reviews/specs" --
  # a false positive for the general case, not applicable here since a merge commit's own diff was
  # never what carried the review; the branch merged in (the second parent) already carries its own
  # already-satisfied record, exact-match or via its own one-level fallback.
  #
  # A merge commit's parent *list* is only metadata, though — git never binds a merge commit's tree
  # to its second parent's history. Two distinct gaps, found in sequence at this fix's own G4 (both
  # by mkr-security-reviewer, both empirically reproduced end-to-end before being accepted as real):
  #
  # AD-2 gap: trusting `<sha>^2` alone let anyone craft a two-parent commit (`git commit-tree
  # <arbitrary-tree> -p <head> -p <any-old-reviewed-sha>`, or `git merge -s ours`) whose real content
  # is unreviewed but whose second parent is any already-reviewed commit picked from anywhere in
  # history. Closed by recomputing what a real, clean, conflict-free merge of `<sha>`'s two parents
  # would produce (`git merge-tree --write-tree`, no working tree/index touched) and requiring
  # `<sha>`'s own tree to match it exactly — true for any honest `git merge --no-ff`/`gh pr merge
  # --merge` output, false for a tampered or hand-conflict-resolved tree.
  #
  # AD-3 gap: AD-2 alone still trusted `<sha>`'s first parent unconditionally — an attacker can craft
  # a *fresh* commit sharing a real common ancestor with any already-reviewed commit `S` (parent =
  # `S`'s own parent, tree = that parent's tree plus an unrelated addition `S` never touches), then a
  # genuinely conflict-free `git merge-tree --write-tree <that-commit> S` recomputation matches by
  # construction, passing AD-2's own check while still shipping unreviewed content. AD-2 only proves
  # `<sha>`'s tree is *consistent with* its two declared parents, never that the first parent is
  # itself the real, expected prior tip. Closed by requiring `<sha>^1` to exactly equal
  # `expected_prior_tip`, a value only the caller (never `<sha>` or anything reachable from it) can
  # supply — an attacker who doesn't already control the trusted branch's real history cannot forge
  # this equality no matter what commit graph they construct.
  #
  # On any failure (`expected_prior_tip` unset, first-parent mismatch, tree mismatch, or a real
  # conflict, which `--write-tree` also reports as failure), the second-parent shortcut is refused
  # entirely; falling through to the diff-based path below is harmless, since `git diff-tree` is
  # blind to merge commits regardless and that path returns 1 immediately for any commit with a
  # second parent.
  local second_parent
  if second_parent="$(git rev-parse "${sha}^2" 2>/dev/null)"; then
    local first_parent actual_tree computed_tree
    first_parent="$(git rev-parse "${sha}^1" 2>/dev/null)"
    if [ -n "$expected_prior_tip" ] && [ "$first_parent" = "$expected_prior_tip" ]; then
      actual_tree="$(git rev-parse "${sha}^{tree}" 2>/dev/null)"
      computed_tree="$(git merge-tree --write-tree "$first_parent" "$second_parent" 2>/dev/null)"
      if [ -n "$actual_tree" ] && [ -n "$computed_tree" ] && [ "$actual_tree" = "$computed_tree" ]; then
        find_review_record "$second_parent" "$reviews_dir" "$specs_dir" "$expected_prior_tip"
        return $?
      fi
    fi
  fi

  # No `--` before <sha> for either git call below: `git diff-tree -- <sha>` mis-parses and dumps
  # its own usage text instead of running, and `git rev-parse -- <sha>^` on an unresolvable sha
  # silently "succeeds" with the literal argument string as garbage output instead of failing —
  # both confirmed empirically during this fix's own drafting. <sha> is always a resolved 40-hex
  # commit hash, never attacker-supplied free text, so `--`'s usual injection defense isn't needed.
  local changed f outside=0
  changed="$(git diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null)"
  [ -n "$changed" ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      "$reviews_dir"/* | "$specs_dir"/*) ;;
      *) outside=1 ;;
    esac
  done <<<"$changed"
  [ "$outside" -eq 0 ] || return 1

  local parent
  parent="$(git rev-parse "${sha}^" 2>/dev/null)" || return 1
  short="${parent:0:7}"
  record="${reviews_dir}/${short}.md"
  _reviewrecord_is_ready "$record" || return 1
  printf '%s\n' "$record"
}
