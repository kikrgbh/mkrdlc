#!/usr/bin/env bash
# mkr-aidlc — G4 review-record lookup, with a bounded-chain non-code-commit fallback. Sourced
# only, never executed, matching procwalk.sh's/config.sh's own convention.
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
# <reviews_dir>/<sha's first 7 chars>.md, <sha> provably at-or-behind <expected_prior_tip> (below —
# prints a non-file sentinel instead of a path in this case, docs/adr/0010), a match walking back
# through a bounded chain of <sha>'s ancestors (below — only while each ancestor's own diff touches
# nothing outside <reviews_dir>, <specs_dir>, MKR_ADR_DIR, or MKR_AUDITS_DIR), or — when <sha> is a
# merge commit (`gh pr merge --merge`/`git merge --no-ff`), its first parent exactly equals the
# caller-supplied <expected_prior_tip>, *and* its own
# tree is provably identical to a clean recomputed merge of its two parents (below) — whatever this
# same function resolves for <sha>'s second parent.
# Either match must also pass
# `_reviewrecord_is_ready` (above) — except the at-or-behind case, which needs no review record at
# all (docs/adr/0010). Prints nothing and returns 1 otherwise. Read-only; assumes cwd is
# inside the git work tree <sha> belongs to.
#
# <expected_prior_tip> is required for the merge-commit path to ever succeed (empty/omitted
# unconditionally refuses it, AD-3) — callers must supply a value they independently know to be the
# real, trusted branch tip immediately before this push/merge (`github.event.before` on `push`;
# `pre-push-review-guard.sh`'s own `remote_sha1` from git's pre-push stdin protocol), never derived
# from `<sha>` itself.
#
# A 5th positional argument, `_hops`, carries the non-code-chain fallback's own recursion depth.
# It is internal bookkeeping only, never part of the public contract above — every real caller
# omits it, and it defaults to 0 (`${5:-0}`) when omitted, so no existing call site changes. Only
# this function's own recursive call for that path (below) ever supplies it. The merge-commit
# path's pre-existing recursive call (a few lines down) deliberately keeps omitting it too, so it
# always starts a fresh depth-0 budget for whatever it resolves on the second parent — that path
# is independently bounded by its own tree-equality/`expected_prior_tip` checks and is untouched
# by this bound.
#
# _RRF_MAX_CHAIN_HOPS bounds how many consecutive genuinely non-code (reviews/specs/ADR-only)
# commits the fallback below will walk back through before giving up — a fixed safety ceiling, not
# a per-project setting: a real docs-only chain (an ADR, or more than one, plus the trailing
# review-record commit itself) is on the order of 1-3 commits; 5 gives headroom without being
# unbounded. Deliberately not a config key — see docs/adr for the reasoning.
readonly _RRF_MAX_CHAIN_HOPS=5

find_review_record() {
  local sha="$1" reviews_dir="${2%/}" specs_dir="${3%/}" expected_prior_tip="${4-}" _hops="${5:-0}" short record

  short="${sha:0:7}"
  record="${reviews_dir}/${short}.md"
  if _reviewrecord_is_ready "$record"; then
    printf '%s\n' "$record"
    return 0
  fi

  # Ancestor-check (docs/adr/0010): a <sha> provably at-or-behind <expected_prior_tip> already
  # existed, immutably, before the current push — nothing reachable from it could have been
  # introduced BY this push, so it terminates the walk immediately (a distinct sentinel, never a
  # `reviews_dir` path, so a caller can never mistake it for a real record file) rather than
  # requiring its own review record or recursing further. `git merge-base --is-ancestor A B`
  # treats A as its own ancestor, so this covers both a <sha> that IS <expected_prior_tip> (the
  # common real-world case — <sha> is literally the branch's real prior tip) and one strictly
  # behind it, in one call. This closes docs/adr/0008's own named, accepted-as-out-of-scope gap: a
  # merge commit reached mid-chain (not the top-level <sha> under lookup) previously always failed
  # here, since `git diff-tree` reports an empty diff for a merge commit by default and the
  # outside-check below reads that as "touches something outside the allowed paths."
  #
  # Runs INSTEAD OF the outside-check below for this <sha>, not in addition to it — the two ask
  # different questions. The outside-check (below) asks "did this commit, newly introduced by the
  # push, touch only safe paths"; this asks "did this commit even originate from the current push
  # at all." Placed before the AD-2/AD-3 merge-commit shortcut purely as an ordering/cost
  # optimization (skips the more expensive `git merge-tree` call when it isn't needed) — the two
  # checks' preconditions never overlap: AD-2/AD-3 only fires when `<sha>^1` equals
  # `expected_prior_tip`, which makes `<sha>` a *child* of `expected_prior_tip` — and by git's own
  # DAG acyclicity a commit can never be `--is-ancestor`-true of its own parent, not just
  # "essentially never" true in practice (confirmed at this fix's own G3 design review).
  #
  # No loophole: `--is-ancestor <sha> <expected_prior_tip>` can only succeed if <sha> is reachable
  # by walking backward from <expected_prior_tip> through real parent links already in the git
  # object database — i.e. <sha> was part of the branch's history BEFORE this push happened, by
  # the same immutable-history guarantee AD-3 (below) already relies on for <expected_prior_tip>
  # itself. A commit newly created BY the current push (a fresh fix commit, a fresh forged commit,
  # or a fresh merge commit) is a descendant of <expected_prior_tip>, never an ancestor of it —
  # `--is-ancestor` returns false for a descendant, so this can never fire for anything the
  # current push actually introduces.
  if [ -n "$expected_prior_tip" ] && git merge-base --is-ancestor -- "$sha" "$expected_prior_tip" 2>/dev/null; then
    printf '(pre-existing, at-or-before %s)\n' "${expected_prior_tip:0:7}"
    return 0
  fi

  # `git diff-tree` shows an empty diff for a merge commit by default (no `-m`/`-c`), which the
  # exact-diff fallback below would otherwise misread as "nothing changed outside reviews/specs" --
  # a false positive for the general case, not applicable here since a merge commit's own diff was
  # never what carried the review; the branch merged in (the second parent) already carries its own
  # already-satisfied record, exact-match or via its own bounded non-code-commit-chain fallback.
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
  #
  # adr_dir/audits_dir are read here, not accepted as positional parameters — matching the
  # precedent already set above by `_reviewrecord_is_ready` reading MKR_REVIEW_VERDICT_STRING
  # directly via mkr_get, which keeps this function's documented 4-argument public signature
  # unchanged. MKR_AUDITS_DIR joins MKR_ADR_DIR here because it is the one other artifact class
  # this repo's own convention commits directly to a protected branch as a standalone trailing
  # commit after merge: `mkr-audit`'s grounding-audit record (`mkr-merge/SKILL.md` step 10 hands
  # off to it explicitly, post-merge). Without this, that trailing commit's diff — confined to
  # MKR_AUDITS_DIR alone — trips the outside-check below on its very first hop, even though the
  # commit immediately behind it resolves cleanly on its own; reported directly from a real
  # adopter repo, where it made `mkr-audit` almost always waste a CI run.
  local changed f outside=0 adr_dir audits_dir
  adr_dir="$(mkr_get MKR_ADR_DIR)"
  adr_dir="${adr_dir%/}"
  audits_dir="$(mkr_get MKR_AUDITS_DIR)"
  audits_dir="${audits_dir%/}"
  changed="$(git diff-tree --no-commit-id --name-only -r "$sha" 2>/dev/null)"
  [ -n "$changed" ] || return 1
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    case "$f" in
      "$reviews_dir"/* | "$specs_dir"/*) continue ;;
    esac
    if [ -n "$adr_dir" ]; then
      case "$f" in
        "$adr_dir"/*) continue ;;
      esac
    fi
    if [ -n "$audits_dir" ]; then
      case "$f" in
        "$audits_dir"/*) continue ;;
      esac
    fi
    outside=1
  done <<<"$changed"
  [ "$outside" -eq 0 ] || return 1

  # This commit's own diff is confined to the allowed non-code paths, but it may not itself be an
  # exact match (the common case — a trailing review-record commit can never name a file after its
  # own not-yet-computed hash). Recurse into the parent, re-running the exact-match check at the
  # top of this same function for free, up to _RRF_MAX_CHAIN_HOPS non-code hops back.
  [ "$_hops" -lt "$_RRF_MAX_CHAIN_HOPS" ] || return 1

  local parent
  parent="$(git rev-parse "${sha}^" 2>/dev/null)" || return 1
  find_review_record "$parent" "$reviews_dir" "$specs_dir" "$expected_prior_tip" "$((_hops + 1))"
}
