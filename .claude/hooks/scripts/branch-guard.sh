#!/usr/bin/env bash
# PreToolUse/Bash guard (specs/M3_Guardrails_Spec.md §7.3). BLOCK tier (docs/DESIGN.md §4).
#
# Denies a `git push` whose target branch resolves to an entry in MKR_PROTECTED_BRANCHES.
# Exotic refspecs and flags the parser can't confidently resolve to a branch name are allowed,
# not denied — this is a backstop, not the only check (CLAUDE.md's own MUST-ASK-FIRST rule and
# human judgment remain in force regardless). This is a whitespace-tokenizing heuristic, not a
# shell parser, and it looks for the literal token "push" as the signal of a real push — several
# gaps that follow from those two limits are disclosed, accepted, G4-reviewed, and NOT fixed here:
# a real `git push` hidden
# entirely inside `$(...)` behind other text (AD-8); a real push whose subcommand is never
# literally the token "push" at all, reached via git's own inline alias mechanism (AD-10, e.g.
# `git -c alias.pu=push pu origin main`); a spurious deny of an ordinary, non-push command when an
# unrecognized global flag makes the statement "ambiguous" and the word "push" happens to appear
# elsewhere in it (AD-11, e.g. `git log --grep push` on a protected branch); and unbounded work in
# a single crafted statement containing many decoy "push" tokens (AD-12). All four were confirmed,
# not merely theorized, at G4 review; the gate owner (CLAUDE.md's `MKR_GATE_MERGE`) accepted them
# as documented limitations rather than routing back to implement — see the spec's AD list and
# `.mkr/reviews/581dd25.md` for the review record and disposition.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"

IN="$(hookio_stdin)"
CMD="$(hookio_field "$IN" tool_input.command)"

# The broad, unanchored net: does this statement mention "git" then "push" anywhere, in that
# order, as whole words? This is deliberately the SAME broad match the original version of this
# file used for its whole detection gate — the net a BLOCK-tier guard must never narrow, because
# any statement that doesn't match it is skipped entirely and a real push inside it would slip
# through undetected. `resolve_git_subcommand` below is a *refinement* layered on top, used only
# to confidently EXCLUDE a statement this broad net catches but that provably isn't a real push
# (`git stash push`, a branch name or commit message containing the word "push") — it never
# widens what counts as "could be a push," only narrows false positives, and whenever it can't
# resolve confidently it falls back to treating the statement as a potential push rather than
# silently clearing it (revised at G4 review after finding this exact class of narrowing
# regression).
looks_like_push() {
  printf '%s' "$1" | grep -Eq '\bgit\b.*\bpush\b'
}

if ! looks_like_push "$CMD"; then
  exit 0
fi

# Global git flags that can appear between "git" and the real subcommand, taking a following
# value token. Recognizing one lets the walk below correctly see past it to the real subcommand
# (`git -C <dir> stash push` should resolve to `stash`, not get stuck on `-C`'s own value) — but
# this list is deliberately NOT trusted to be exhaustive: hitting a flag NOT on it makes the walk
# stop and report "ambiguous" (AD-4), never guesses that flag's own value is the subcommand.
GLOBAL_VALUE_FLAGS=(-C -c --git-dir --work-tree --namespace --exec-path --html-path --man-path --info-path)

# Set by resolve_git_subcommand — never invoked via `$(...)` (a command substitution runs a
# function in a subshell; any variable it sets there is invisible to the caller once the subshell
# exits, a real bug caught while implementing this file's own AD-5) — always called directly so
# these land in the running script's own environment.
#
# RESOLVED_SUBCOMMAND is exactly one of:
#   push       - a bare "git" token is followed (after skipping only recognized global flags) by
#                the literal word "push": this is confidently a real git push. CONFIRMED_INDEX is
#                set to that token's own, exact position.
#   other      - the same walk instead lands confidently on some other word: this is confidently
#                NOT a push, no matter where else the word "push" appears in this statement (a
#                stash sub-action, a branch name, a commit message).
#   ambiguous  - no bare "git" token was found, or the walk hit a flag-shaped token not on
#                GLOBAL_VALUE_FLAGS before reaching a subcommand candidate — including because
#                that flag might itself consume a following value token, which this walk has no
#                way to confirm one way or the other (a G4 finding — recording *that flag's own
#                index* as a safe search-from position
#                was still wrong, since the flag's own unconfirmed value could itself be the
#                literal word "push", stealing the match). This statement already matched the
#                broad `looks_like_push` net, so "can't confidently resolve" must never be treated
#                the same as "confidently not a push" (AD-4).
RESOLVED_SUBCOMMAND=""
CONFIRMED_INDEX=0

resolve_git_subcommand() {
  local statement="$1" n i tok gf
  local -a stoks
  read -r -a stoks <<< "$statement"
  n="${#stoks[@]}"
  i=0
  while [ "$i" -lt "$n" ]; do
    if [ "${stoks[$i]}" = "git" ]; then break; fi
    i=$((i + 1))
  done
  if [ "$i" -ge "$n" ]; then
    RESOLVED_SUBCOMMAND="ambiguous"
    return 0
  fi
  i=$((i + 1))
  while [ "$i" -lt "$n" ]; do
    tok="${stoks[$i]}"
    case "$tok" in
      -*)
        local skip=0
        for gf in "${GLOBAL_VALUE_FLAGS[@]}"; do
          if [ "$tok" = "$gf" ]; then skip=1; i=$((i + 1)); break; fi
        done
        if [ "$skip" -eq 0 ]; then
          RESOLVED_SUBCOMMAND="ambiguous"    # unrecognized flag — don't guess past it
          return 0
        fi
        ;;
      push)
        RESOLVED_SUBCOMMAND="push"
        CONFIRMED_INDEX="$i"
        return 0
        ;;
      *) RESOLVED_SUBCOMMAND="other"; return 0 ;;
    esac
    i=$((i + 1))
  done
  RESOLVED_SUBCOMMAND="ambiguous"             # ran out of tokens with no subcommand candidate
}

# is_protected_branch <branch> — true if <branch> is a literal entry in MKR_PROTECTED_BRANCHES.
is_protected_branch() {
  local candidate="$1" protected
  while IFS= read -r protected; do
    [ -z "$protected" ] && continue
    if [ "$candidate" = "$protected" ]; then
      return 0
    fi
  done < <(mkr_list MKR_PROTECTED_BRANCHES)
  return 1
}

# deny_protected <branch> — emits the deny decision for <branch> and returns 0.
deny_protected() {
  hookio_pretooluse_decision deny "push to protected branch '$1' is blocked (branch-guard.sh, docs/DESIGN.md §4) — open a PR instead, per CLAUDE.md's MUST-ASK-FIRST rule"
  return 0
}

# check_candidate_tokens <token>... — given the tokens found after ONE candidate subcommand
# position, strips flags/redirections, resolves the target(s), and denies if any resolves to a
# protected branch. Returns 0 (and has emitted the deny decision) or 1. Factored out of
# deny_if_protected_push so the "ambiguous" path below can try it against more than one candidate
# position without duplicating this logic.
check_candidate_tokens() {
  local tok vf target refspec i
  local -a tokens=("$@") args

  # Strip flags, keep positional args (remote, refspec...). A handful of git-push flags take a
  # separate following value token (`-o value`, not `-ovalue`) — skipping only the flag itself
  # and not its value would misalign the positional args that follow (e.g. `-o foo origin main`
  # would wrongly read "foo" as the remote and "origin" as a refspec), an adversarial-review-
  # caught defect. Anything not on this short, explicit list still falls
  # through to "unresolved → allow" below, per this script's own disclosed fail-open posture —
  # this is not a full git-CLI arg parser.
  local -a VALUE_FLAGS=(-o --push-option --repo --receive-pack --exec)
  args=()
  i=0
  while [ "$i" -lt "${#tokens[@]}" ]; do
    tok="${tokens[$i]}"
    case "$tok" in
      -*)
        for vf in "${VALUE_FLAGS[@]}"; do
          if [ "$tok" = "$vf" ]; then i=$((i + 1)); break; fi
        done
        ;;
      *'<'* | *'>'*)
        # A redirection token (`2>&1`, `>&2`, `&>out`, `2>/dev/null`, ...) never starts with `-`,
        # so the flag check above misses it — but `<`/`>` are characters `git-check-ref-format`
        # forbids in any real ref name, so any token containing either is unambiguously a
        # redirection, never a real remote/refspec. Treating it as a positional arg misaligned
        # which token is the real target branch — an adversarial-review-caught defect.
        # Not appended to `args` — the shared `i` increment below still runs.
        ;;
      *) args+=("$tok") ;;
    esac
    i=$((i + 1))
  done

  if [ "${#args[@]}" -ge 2 ]; then
    # git push <remote> <refspec>... — one or more refspecs, each possibly <local>:<remote> or a
    # bare branch name. A real `git push` accepts more than one refspec in a single invocation
    # (`git push origin decoy-branch main:main` updates both `decoy-branch` and `main`) —
    # checking only the first left every later, real refspec's own target unexamined, a live,
    # pre-existing (not introduced by this fix), G4-review-caught defect (AD-6). Every refspec is
    # checked; the first one that resolves to a protected branch denies immediately.
    for ((i = 1; i < ${#args[@]}; i++)); do
      refspec="${args[$i]}"
      if [[ "$refspec" == *:* ]]; then
        target="${refspec#*:}"
      else
        target="$refspec"
      fi
      [ -n "$target" ] && is_protected_branch "$target" && { deny_protected "$target"; return 0; }
    done
    return 1
  elif [ "${#args[@]}" -eq 0 ] || [ "${#args[@]}" -eq 1 ]; then
    # bare `git push` or `git push <remote>` — pushes the current branch by name.
    target="$(cd "$ROOT" && git symbolic-ref --short HEAD 2>/dev/null)"
    [ -z "$target" ] && return 1        # unresolved — fail open, per §7.3
    is_protected_branch "$target" && { deny_protected "$target"; return 0; }
    return 1
  fi

  return 1
}

# deny_if_protected_push <statement> <confirmed|ambiguous> — if any of this push's target(s)
# resolve to an entry in MKR_PROTECTED_BRANCHES, emits the deny decision and returns 0 (caller
# stops scanning — one confirmed denial is enough); otherwise returns 1 (caller continues to the
# next statement — a real-but-unprotected push
# earlier in a compound command must not mask a later, real, protected one).
deny_if_protected_push() {
  local segment="$1" kind="$2" n i
  local -a stoks

  read -r -a stoks <<< "$segment"
  n="${#stoks[@]}"
  if [ "$kind" = "confirmed" ]; then
    # resolve_git_subcommand already found the real subcommand's own, exact position — use it
    # directly, no search of any kind (AD-7: a search, even a careful one, is a weaker guarantee
    # than a position the structural walk itself already verified).
    check_candidate_tokens "${stoks[@]:$((CONFIRMED_INDEX + 1))}"
    return $?
  fi

  # "ambiguous": no confirmed position exists. Try EVERY exact `push` token in the statement as a
  # candidate subcommand position — not just the rightmost one. A flag this walk couldn't
  # recognize may itself have a value that happens to literally be "push" (AD-7), but a decoy can
  # also sit AFTER the real subcommand, as an ordinary trailing refspec of a real, syntactically
  # valid multi-refspec push (AD-9, a G4 finding: `git --no-pager push origin main push` is a real
  # push of both `main` and `push`; a rightmost-only search landed on the trailing `push` refspec
  # instead of the real subcommand two tokens earlier, collapsed the arg list to empty, and
  # silently discarded the real, protected `main` refspec). No single position — leftmost,
  # rightmost, or otherwise — is structurally guaranteed safe here, so every exact "push" token is
  # tried, and this statement denies if ANY candidate's resolved target is protected (AD-4: an
  # unresolvable choice between candidates must fail toward checking all of them, never toward
  # picking just one and hoping). Never a substring match against raw text (AD-5): a real push's
  # own refspec or branch name can itself contain the word "push" (`push-notifications:main`), and
  # that is never the same array element as `push`.
  for ((i = 0; i < n; i++)); do
    [ "${stoks[$i]}" = "push" ] || continue
    if check_candidate_tokens "${stoks[@]:$((i + 1))}"; then
      return 0
    fi
  done
  return 1
}

# Walk every statement in order: a statement
# resolve_git_subcommand confidently identifies as NOT a push ("other") is skipped; anything else
# ("push" or "ambiguous", AD-4) is treated as a potential real push and checked immediately —
# denying and stopping on an actual match, but never stopping merely because a statement was
# treated as a potential push, since a later statement could still be a real push to a protected
# branch (a first draft of this fix stopped at the first push-shaped statement and masked exactly
# that case — G1 review caught it before this landed).
while IFS= read -r -d '' statement; do
  looks_like_push "$statement" || continue
  resolve_git_subcommand "$statement"         # called directly, never via $(...) — see above
  [ "$RESOLVED_SUBCOMMAND" = "other" ] && continue
  kind="ambiguous"
  [ "$RESOLVED_SUBCOMMAND" = "push" ] && kind="confirmed"
  if deny_if_protected_push "$statement" "$kind"; then
    exit 0
  fi
done < <(hookio_split_statements "$CMD")

exit 0
