#!/usr/bin/env bash
# PreToolUse/Bash guard (specs/WorktreeGuard_Spec.md §7.3). Gates a branch-switching
# `git checkout`/`git switch` against a real, live collision — another process that genuinely
# has the target directory open as its cwd right now — per MKR_WORKTREE_POLICY's tier (§6 AD-1).
# A file-path checkout (`git checkout -- <path>`) is never gated, at any tier. `git switch` has
# no such file-path/pathspec-restore mode at all — its own `--` is only the ordinary
# end-of-options marker (disambiguating a branch name, or a new-branch/start-point pair for
# `-c`, that looks like a flag), so it is never excluded. Exclusion is decided by
# `procwalk_checkout_pathspec_form` (procwalk.sh) — a real, whitespace-tokenized check, not a
# `\bcheckout\b`/`--`-shaped regex against the raw statement text, which a real, valid branch
# name like `run-checkout-now` (one token to bash, but three "words" to a regex, since a hyphen
# is a word boundary) or a trailing shell comment could otherwise satisfy without any real
# checkout-with-pathspec invocation ever occurring.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/procwalk.sh"

IN="$(hookio_stdin)"
CMD="$(hookio_field "$IN" tool_input.command)"

# Isolate the LAST statement containing a real (non-file-path) branch-switching checkout/switch
# (quote-aware split, same discipline branch-guard.sh already uses) — the *last* match, not the
# first, so a trailing real switch is never shadowed by an earlier `git checkout -- <path>` file
# form in the same multi-statement command; a file-path form is never gated, at any tier, and is
# skipped here entirely rather than short-circuiting the whole scan, so it can't hide a real
# switch later in the same command.
# The keyword test is procwalk_statement_has_git_keyword (procwalk.sh) — shared with
# procwalk_resolve_target_dir/_dirs rather than a third independent copy of the same pattern
# (an earlier version of this file kept its own inline duplicate, which drifted out of sync with
# the other two and reopened a `git -c name=value checkout ...`-shaped bypass a fix to the other
# two didn't reach — found on G4 re-review). Still never a loose `\bgit\b.*\b(checkout|switch)\b`
# wildcard, which matches "checkout"/"switch" appearing anywhere later in the statement,
# including as ordinary English inside an unrelated quoted commit message (`git commit -m
# "checkout fix"`) — misclassifying a plain commit as a branch-switch candidate and
# false-positive-gating it on a real, unrelated collision at the invoking directory — that
# specific widening was tried and reverted while fixing the `-c` gap above; see
# procwalk_statement_has_git_keyword's own comment for why it stays adjacency-anchored except for
# the one narrow, unavoidable ambiguity (an unrecognized flag sitting directly after `git`).

segment=""
while IFS= read -r -d '' statement; do
  statement="$(procwalk_strip_comment "$statement")"
  if procwalk_statement_has_git_keyword "$statement" 'checkout|switch' \
      && ! procwalk_checkout_pathspec_form "$statement"; then
    segment="$statement"
  fi
done < <(hookio_split_statements "$CMD")
[ -z "$segment" ] && exit 0

POLICY="$(mkr_get MKR_WORKTREE_POLICY)"
[ "$POLICY" = "off" ] && exit 0

# Resolution skips the same excluded statements as the scan above — a trailing decoy
# `git checkout -- <path>` (possibly preceded by its own unrelated `cd`) must never redirect
# which directory gets checked away from the real switch's own context. Only the LAST real
# checkout/switch matters here, unlike a `git commit` chain: a branch switch's only observable
# effect is where the session ends up, so an earlier, transient checkout in the same command
# (immediately superseded by a later one) has nothing left to collide over by the time the
# command would actually run.
DIR="$(procwalk_resolve_target_dir "$IN" 'checkout|switch' procwalk_checkout_pathspec_form)"
[ -z "$DIR" ] && DIR="${CLAUDE_PROJECT_DIR:-$PWD}"

hits="$(procwalk_foreign_cwd "$DIR")"
rc=$?

if [ "$rc" -ne 0 ]; then
  if [ "$POLICY" = "enforced" ]; then
    hookio_pretooluse_decision deny "another live process has this worktree open (worktree-collision-guard.sh), switching branches here can pull it out from under that session:
$hits"
  else
    printf 'WARNING (worktree-collision-guard.sh): another live process has this worktree open — switching branches here can pull it out from under that session:\n%s\n' "$hits" >&2
  fi
fi

exit 0
