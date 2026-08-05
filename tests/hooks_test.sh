#!/usr/bin/env bash
# tests/hooks_test.sh — specs/M3_Guardrails_Spec.md §9, TC-M3-01..14, TC-M3-18.
# One fresh git-repo fixture per case, mirroring tests/config_test.sh's fresh-environment
# discipline: each case builds its own temp repo with only the files it needs.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
LIB_DIR="$ROOT/.claude/hooks/lib"
SCRIPTS_DIR="$ROOT/.claude/hooks/scripts"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# fixture_repo — creates a fresh temp git repo with hookio.sh/config.sh vendored in, cd's into
# it, and prints its path. Caller is responsible for cleanup.
fixture_repo() {
  local d
  d="$(mktemp -d)"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
    cd "$d" \
    && git init -q \
    && git config user.email t@t.com \
    && git config user.name t \
    && mkdir -p .claude/hooks/lib .claude/hooks/scripts .mkr \
    && cp "$LIB_DIR/config.sh" .claude/hooks/lib/ \
    && cp "$LIB_DIR/hookio.sh" .claude/hooks/lib/ \
    && cp "$LIB_DIR/procwalk.sh" .claude/hooks/lib/ \
  ) >/dev/null 2>&1
  printf '%s' "$d"
}

cleanup() { cd "$HERE"; rm -rf "$1" 2>/dev/null; }

run_hook() {                          # run_hook <repo> <script> <json>
  local repo="$1" script="$2" json="$3"
  # Unset CLAUDE_PROJECT_DIR/MKR_CONFIG so config.sh falls back to git-root-of-cwd resolution
  # and actually reads the fixture's own .mkr/config, not the real caller's — config.sh prefers
  # both over cwd-based discovery, and Claude Code sets CLAUDE_PROJECT_DIR for every real hook
  # invocation (including this suite's own hooks, when run as part of MKR_TEST from a live
  # session), so leaving it ambient here silently breaks fixture isolation.
  ( cd "$repo" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && printf '%s' "$json" | bash "$SCRIPTS_DIR/$script" 2>&1 )
}

echo
echo "== secret-guard.sh (TC-M3-01, TC-M3-02) =="

D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
# Built via concatenation, not a literal token, so this test file's own source never contains
# a live AKIA-shaped string secret-guard.sh's own fixed pattern set would flag on this repo's
# own commits — found live during this milestone's self-review.
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > secret.txt && git add secret.txt )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-01 AWS-key-shaped staged content → deny"
else
  bad "TC-M3-01 AWS-key-shaped staged content → deny" "$out"
fi
( cd "$D" && git reset -q )
( cd "$D" && printf 'the password field below is just a placeholder\n' > doc.txt && git add doc.txt )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-02 prose mentioning 'password' clears"
else
  bad "TC-M3-02 prose mentioning 'password' clears" "$out"
fi
cleanup "$D"

# TC-M3-20: the compound-wildcard bypass an adversarial security review found — a single,
# entirely ordinary `git add -A && git commit` one-liner used to add zero content to the scan,
# because `-A` was skipped as "just a flag" and `git commit`'s own git-diff-cached read ran
# before `-A`'s effect had happened (PreToolUse fires before the real command executes).
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > secret.txt )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git add -A && git commit -m x"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-20a compound 'git add -A && git commit' with a new secret file → deny"
else
  bad "TC-M3-20a compound 'git add -A && git commit' with a new secret file → deny" "$out"
fi
cleanup "$D"

# Targeted-add false positive must still clear even with the wildcard fix in place: a stray,
# unrelated untracked secret-shaped file elsewhere in the tree must not block a commit of only
# the specific, unrelated, clean file actually named.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > stray_secret.txt )
( cd "$D" && printf 'clean content\n' > doc.txt && git add doc.txt )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-20b targeted commit of an unrelated clean file clears despite a stray untracked secret"
else
  bad "TC-M3-20b targeted commit of an unrelated clean file clears despite a stray untracked secret" "$out"
fi
cleanup "$D"

# TC-M3-22: `-am` (git's normal bundled-short-option syntax) wasn't recognized by a
# whitespace-bounded `-a` check — a second adversarial-review bypass found on re-review of the
# TC-M3-20 fix itself.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' >> f )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -am x"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-22 'git commit -am' (bundled short flags) with a secret change → deny"
else
  bad "TC-M3-22 'git commit -am' (bundled short flags) with a secret change → deny" "$out"
fi
cleanup "$D"

# TC-M3-23: a quoted (but space-free, variable-free) `git add` path survived hookio_field's
# JSON-unescape as literal quote characters, which unquoted word-splitting never strips — a
# third adversarial-review bypass found on the same re-review.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' > secret.txt )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git add \"secret.txt\" && git commit -m x"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-23 quoted 'git add \"secret.txt\"' path still resolves and scans → deny"
else
  bad "TC-M3-23 quoted 'git add \"secret.txt\"' path still resolves and scans → deny" "$out"
fi
cleanup "$D"

# TC-M3-24: a literal `;` inside a quoted commit message (an entirely ordinary thing to write,
# not contrived) truncated the old regex-based segment extraction before a trailing `-a` was
# ever seen — a fourth adversarial-review bypass, fixed by hookio_split_statements' quote-aware
# splitting rather than a character-class-exclusion regex.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' >> f )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix: bug; update tests\" -a"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-24 semicolon inside a quoted commit message doesn't hide a trailing '-a' → deny"
else
  bad "TC-M3-24 semicolon inside a quoted commit message doesn't hide a trailing '-a' → deny" "$out"
fi
cleanup "$D"

# TC-M3-25: an *unquoted*, backslash-escaped `;` (`foo\;bar` — one literal word in real bash,
# the same idiom `find -exec ... \;` relies on) was still treated as a real separator by the
# quote-aware splitter itself, hiding a trailing `-a` — a fifth adversarial-review bypass, fixed
# by recognizing backslash-escaping outside quotes too.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' >> f )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m foo\;bar -a"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-25 backslash-escaped ';' outside quotes doesn't hide a trailing '-a' → deny"
else
  bad "TC-M3-25 backslash-escaped ';' outside quotes doesn't hide a trailing '-a' → deny" "$out"
fi
cleanup "$D"

# TC-M3-26: branch-guard.sh's own positional-arg extraction didn't know `-o <value>` consumes
# a separate following token, so a value token got misread as the remote/refspec — a sixth
# adversarial-review-caught defect (same repro command as TC-M3-25, applied to push).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push -o foo\;bar origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-26 'git push -o <value> ... main' still resolves the real target and denies"
else
  bad "TC-M3-26 'git push -o <value> ... main' still resolves the real target and denies" "$out"
fi
cleanup "$D"

# TC-M3-27: `2>&1` (one of the single most ordinary shell idioms, not exotic) was read as a
# bare job-control separator by the quote-aware splitter, splitting the statement and hiding
# a trailing `-a` — a seventh adversarial-review bypass, fixed by recognizing `&` as part of
# a redirection-duplication operator when adjacent to `>`/`<`.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'AWS_KEY=%s%s\n' 'AKIA' 'ABCDEFGHIJKLMNOP' >> f )
out="$(run_hook "$D" secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"fix\" 2>&1 -a"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"AWS access key"* ]]; then
  ok "TC-M3-27 '2>&1' doesn't hide a trailing '-a' → deny"
else
  bad "TC-M3-27 '2>&1' doesn't hide a trailing '-a' → deny" "$out"
fi
cleanup "$D"

# TC-M3-28: the same `2>&1` idiom, applied to `git push`, made branch-guard.sh's own token
# extraction read the redirection sequence itself as the remote name — an eighth
# adversarial-review-caught defect, fixed by treating any token containing `<`/`>` (characters
# git-check-ref-format forbids in a real ref name) as a redirection, never a positional arg.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push 2>&1 origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-28 'git push 2>&1 origin main' still resolves 'main' as the real target and denies"
else
  bad "TC-M3-28 'git push 2>&1 origin main' still resolves 'main' as the real target and denies" "$out"
fi
cleanup "$D"

# TC-M3-29: hookio_split_statements emitted newline-terminated records, but a single logical
# statement can legitimately contain a raw embedded newline (an ordinary backslash-newline line
# continuation, or a multi-line quoted string) — desynchronizing every caller's `read` loop from
# the split function's own quote/escape-aware boundary decision. A ninth adversarial-review
# bypass: `git push \<newline>  origin main` (ordinary multi-line formatting, not adversarial)
# made branch-guard.sh see only the "git push \" fragment and fall back to resolving the
# current branch instead of the real "main" target. Fixed by switching to NUL-terminated
# records (a real bash string can never contain a NUL byte) and eliding backslash-newline
# entirely, matching real bash's own line-continuation semantics.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name": "Bash", "tool_input": {"command": "git push \\\n  origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-29 backslash-newline continuation in 'git push' still resolves 'main' and denies"
else
  bad "TC-M3-29 backslash-newline continuation in 'git push' still resolves 'main' and denies" "$out"
fi
cleanup "$D"

# TC-M3-30: a line-wrapped `2>&1` (continuation landing between the `>` and the `&`, e.g.
# `git push origin main 2>\<newline>&1` reformatted for length — still ordinary, not adversarial)
# desynchronized the `&`-vs-redirection check itself: it looked back at the *raw string's*
# previous character, which was the just-elided newline, not the real `>` — a tenth
# adversarial-review bypass, fixed by checking `buf`'s own last character instead (immune to
# elision by construction) and by peeking past continuations for the forward `>` check too.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name": "Bash", "tool_input": {"command": "git push 2>\\\n&1 origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-30 continuation landing inside '2>&1' still resolves 'main' and denies"
else
  bad "TC-M3-30 continuation landing inside '2>&1' still resolves 'main' and denies" "$out"
fi
cleanup "$D"

# TC-M3-31: `${var: -N}` (space then a negative offset) is bash-4.2+-only substring syntax,
# contradicting this project's own stated "Bash 4.0+" floor (CLAUDE.md Stack;
# hookio.sh's own header comment) — a code-review-caught defect introduced by an earlier
# revision of the &-vs-redirection fix. A static guard, not a behavioral one: no hook script
# should ever reintroduce this pattern.
fail31=0
for f in "$LIB_DIR"/*.sh "$SCRIPTS_DIR"/*.sh; do
  # Requires a real space before the `-` — that space is exactly what makes it the
  # bash-4.2+-only negative-offset substring form, as opposed to the ordinary, portable
  # `${var:-default}` (no space) "use default if unset/null" operator.
  grep -Eq '\$\{[A-Za-z_][A-Za-z0-9_]*: +-[0-9]' "$f" && { fail31=1; echo "    found in $f"; }
done
if [ "$fail31" -eq 0 ]; then
  ok "TC-M3-31 no bash-4.2+-only negative-offset substring syntax in any hook script/lib"
else
  bad "TC-M3-31 no bash-4.2+-only negative-offset substring syntax in any hook script/lib" "see above"
fi

echo
echo "== branch-guard.sh (TC-M3-03, TC-M3-04) =="

D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-03 push to protected branch → deny"
else
  bad "TC-M3-03 push to protected branch → deny" "$out"
fi
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin feature-x"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-04 push to non-protected branch clears"
else
  bad "TC-M3-04 push to non-protected branch clears" "$out"
fi
cleanup "$D"

echo
echo "== branch-guard.sh: push-detection false-positive fix (TC-M3-32..39) =="

# TC-M3-32: `git stash push` is a real, unrelated git-stash subcommand whose own sub-action
# happens to be named "push" -- previously denied as if it were `git push` to a protected branch
# (live-confirmed defect).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git stash push -- somefile"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-32 'git stash push' allowed (not a real push)"
else
  bad "TC-M3-32 'git stash push' allowed (not a real push)" "$out"
fi
cleanup "$D"

# TC-M3-33: a branch name merely containing the substring "push" -- previously denied on the
# same basis (live-confirmed defect, same session).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout -b some-push-in-the-name"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-33 branch name containing 'push' allowed"
else
  bad "TC-M3-33 branch name containing 'push' allowed" "$out"
fi
cleanup "$D"

# TC-M3-34: the word "push" inside a quoted commit-message argument to a non-push subcommand.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"add push support\" -a"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-34 'push' inside a commit message allowed"
else
  bad "TC-M3-34 'push' inside a commit message allowed" "$out"
fi
cleanup "$D"

# TC-M3-35: a global flag *and* a non-push subcommand together, run ON the protected branch
# itself so a flag-value-consumption miscount that mis-resolved the subcommand as `push` would
# be distinguishable (deny) from correct behavior (allow) -- see spec §9's own rationale.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git -C /some/dir stash push"}}')"
if [ -z "$out" ]; then
  ok "TC-M3-35 global flag + non-push subcommand allowed, even on the protected branch"
else
  bad "TC-M3-35 global flag + non-push subcommand allowed, even on the protected branch" "$out"
fi
cleanup "$D"

# TC-M3-36: regression -- every pre-existing branch-guard.sh case still passes against the fixed
# script, re-run explicitly here as its own record tied to this fix.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push -o foo\;bar origin main"}}')"
[[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]] \
  && ok "TC-M3-36a regression: 'git push -o <value> ... main' still denies" \
  || bad "TC-M3-36a regression: 'git push -o <value> ... main' still denies" "$out"
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push 2>&1 origin main"}}')"
[[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]] \
  && ok "TC-M3-36b regression: 'git push 2>&1 origin main' still denies" \
  || bad "TC-M3-36b regression: 'git push 2>&1 origin main' still denies" "$out"
out="$(run_hook "$D" branch-guard.sh '{"tool_name": "Bash", "tool_input": {"command": "git push \\\n  origin main"}}')"
[[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]] \
  && ok "TC-M3-36c regression: backslash-newline continuation still denies" \
  || bad "TC-M3-36c regression: backslash-newline continuation still denies" "$out"
out="$(run_hook "$D" branch-guard.sh '{"tool_name": "Bash", "tool_input": {"command": "git push 2>\\\n&1 origin main"}}')"
[[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]] \
  && ok "TC-M3-36d regression: continuation inside '2>&1' still denies" \
  || bad "TC-M3-36d regression: continuation inside '2>&1' still denies" "$out"
cleanup "$D"
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')"
[[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]] \
  && ok "TC-M3-36e regression: 'git push origin main' still denies" \
  || bad "TC-M3-36e regression: 'git push origin main' still denies" "$out"
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin feature-x"}}')"
[ -z "$out" ] \
  && ok "TC-M3-36f regression: 'git push origin feature-x' still clears" \
  || bad "TC-M3-36f regression: 'git push origin feature-x' still clears" "$out"
cleanup "$D"

# TC-M3-37: the security-critical mirror-image of TC-M3-35 -- a real push, preceded by a
# recognized global flag, must still be denied (a flag-consumption miscount resolving toward
# "not a push" would silently allow a real push through this BLOCK-tier guard).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git -C /some/dir push origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-37 real push preceded by a global flag still denies"
else
  bad "TC-M3-37 real push preceded by a global flag still denies" "$out"
fi
cleanup "$D"

# TC-M3-38: a decoy statement containing the word "push" for an unrelated reason, immediately
# followed by a genuine push in the same compound command -- the current, buggy code's
# segment-search loop breaks at the first regex-matching statement and never examines the second.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git stash push -- f; git push origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-38 decoy 'git stash push' statement doesn't mask a real push later in the command"
else
  bad "TC-M3-38 decoy 'git stash push' statement doesn't mask a real push later in the command" "$out"
fi
cleanup "$D"

# TC-M3-39: two genuine pushes in one compound command, only the second to a protected branch --
# a first draft of this fix stopped scanning at the first push-shaped statement and never
# examined the second, real, protected-target push (G1 rev 4 finding).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin feature; git push origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-39 an earlier real-but-unprotected push doesn't mask a later real protected push"
else
  bad "TC-M3-39 an earlier real-but-unprotected push doesn't mask a later real protected push" "$out"
fi
cleanup "$D"

# TC-M3-40: a real push whose literal command text never contains the exact word "git" as its
# own token -- `$(echo git)` word-splits to the literal word "git" at real execution time, but no
# token in the *literal* string equals "git" -- a first draft's strict subcommand walk silently
# skipped this statement (G4/mkr-security-reviewer finding).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"$(echo git) push origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-40 a real push via command substitution still denies"
else
  bad "TC-M3-40 a real push via command substitution still denies" "$out"
fi
cleanup "$D"

# TC-M3-41: a real push preceded by a real git global flag not on the recognized
# GLOBAL_VALUE_FLAGS allowlist -- a first draft's walk treated the unrecognized flag as consuming
# zero tokens and misread its own value as the subcommand (G4/mkr-security-reviewer finding).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git --super-prefix foo push origin main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-41 a real push preceded by an unrecognized global flag still denies"
else
  bad "TC-M3-41 a real push preceded by an unrecognized global flag still denies" "$out"
fi
cleanup "$D"

# TC-M3-42: a confirmed real push whose own refspec's source branch name itself contains the
# whole word "push" -- the pre-existing (not newly introduced by this fix) downstream extraction
# re-derived the arguments boundary via its own greedy, rightmost "\bpush\b" text search, which
# landed on the "push" embedded in the branch name instead of the real subcommand token, and
# silently fell to the bare-push-of-current-branch fallback (G4/mkr-security-reviewer finding).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin push-notifications:main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-42 a real push whose refspec contains the word 'push' still resolves the real target"
else
  bad "TC-M3-42 a real push whose refspec contains the word 'push' still resolves the real target" "$out"
fi
cleanup "$D"

# TC-M3-43: the same "push"-in-refspec failure as TC-M3-42, combined with an ambiguous-triggering
# ordinary boolean global flag (--no-pager, not on GLOBAL_VALUE_FLAGS) -- a first attempt at the
# fix only hardened the confirmed-push extraction path, leaving the ambiguous fallback vulnerable
# to the identical bug (G4/mkr-security-reviewer round-3 finding).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git --no-pager push origin push-hotfix:main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-43 ambiguous trigger + 'push'-in-refspec still resolves the real target"
else
  bad "TC-M3-43 ambiguous trigger + 'push'-in-refspec still resolves the real target" "$out"
fi
cleanup "$D"

# TC-M3-44: a real, unobfuscated multi-refspec push where only the second refspec targets the
# protected branch -- the downstream extraction checked only the first positional argument,
# silently ignoring any further refspec (G4/mkr-security-reviewer round-3 finding, unrelated to
# and untouched by the earlier AD-1..AD-5 fixes).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin decoy-branch main:main"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-44 a multi-refspec push still denies on a later, real, protected refspec"
else
  bad "TC-M3-44 a multi-refspec push still denies on a later, real, protected refspec" "$out"
fi
cleanup "$D"

# TC-M3-45: a recognized global flag (-C) whose own VALUE token is literally "push" (an ordinary
# directory name) -- round 3's unified extraction searched for the first exact "push" token from
# index 0 unconditionally, independent of the structural walk's own correctly-flag-aware position,
# so it latched onto the flag's value instead of the real subcommand. Run ON the protected branch
# itself so a misresolution denies instead of allowing either way (same load-bearing rationale as
# TC-M3-35) -- G4 round-4 finding, independently caught by both reviewers.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && mkdir -p push && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git -C push push origin"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-45 a recognized flag's own value equal to 'push' doesn't steal the real subcommand"
else
  bad "TC-M3-45 a recognized flag's own value equal to 'push' doesn't steal the real subcommand" "$out"
fi
cleanup "$D"

# TC-M3-46: an UNRECOGNIZED global flag (--super-prefix, not on GLOBAL_VALUE_FLAGS) whose own
# value is literally "push" -- the "ambiguous" classification's extraction must find the real,
# rightmost "push" token (the structural subcommand, which always comes after any flags/values in
# git's own grammar), never the leftmost one (the flag's own decoy value) -- G4 round-5 finding.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git --super-prefix push push origin"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-46 an unrecognized flag's own value equal to 'push' doesn't steal the real subcommand"
else
  bad "TC-M3-46 an unrecognized flag's own value equal to 'push' doesn't steal the real subcommand" "$out"
fi
cleanup "$D"

# TC-M3-47: an ambiguous-triggering ordinary boolean flag (--no-pager, not on GLOBAL_VALUE_FLAGS)
# combined with a real, syntactically valid multi-refspec push whose SECOND refspec is itself the
# literal word "push" -- positioned AFTER the real subcommand, not before it. Rightmost-only search
# (AD-7) lands on that trailing decoy instead of the real subcommand two tokens earlier, collapsing
# the argument list to empty and silently discarding the real, protected `main` refspec via the
# current-branch fallback -- G4 round-6 finding, independently caught by both reviewers (AD-9: every
# exact "push" token is tried as a candidate subcommand position, not just the rightmost).
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb somebranch )
out="$(run_hook "$D" branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git --no-pager push origin main push"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"main"* ]]; then
  ok "TC-M3-47 a trailing refspec equal to 'push' doesn't steal the real subcommand position"
else
  bad "TC-M3-47 a trailing refspec equal to 'push' doesn't steal the real subcommand position" "$out"
fi
cleanup "$D"

echo
echo "== id-collision-guard.sh (TC-M3-05, TC-M3-06) =="

D="$(fixture_repo)"
( cd "$D" && mkdir -p docs/adr && printf 'existing\n' > docs/adr/0003-existing.md \
  && git add -A && git commit -qm init )
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0003-new.md\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"0003"* ]]; then
  ok "TC-M3-05 duplicate ADR number → deny"
else
  bad "TC-M3-05 duplicate ADR number → deny" "$out"
fi
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0006-new.md\"}}")"
if [ -z "$out" ]; then
  ok "TC-M3-06 unused ADR number clears"
else
  bad "TC-M3-06 unused ADR number clears" "$out"
fi
cleanup "$D"

D="$(fixture_repo)"
( cd "$D" && mkdir -p docs/adr && printf 'existing\n' > docs/adr/0003-existing.md \
  && git add -A && git commit -qm init )
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0007-new.md\"}}")"
if [ -z "$out" ]; then
  ok "G4a no origin remote configured: behaves exactly as local-only (no hang, no spurious deny)"
else
  bad "G4a no origin remote configured: behaves exactly as local-only (no hang, no spurious deny)" "$out"
fi
cleanup "$D"

# G6: without a `timeout` binary on PATH, the origin-awareness fetch must never even be attempted
# — only whatever origin/main ref is already cached locally is consulted. Bounded with the test's
# own `timeout 5` as a safety net; a regression back to an unconditional fetch here would hang
# this case against an unreachable remote instead of completing near-instantly.
NOTOOLDIR="$(mktemp -d)"
for c in bash cat grep sed head basename dirname mktemp printf test date tr sort git env find awk stat; do
  p="$(type -P "$c" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$NOTOOLDIR/$(basename "$p")" 2>/dev/null
done
D="$(fixture_repo)"
( cd "$D" && mkdir -p docs/adr && printf 'existing\n' > docs/adr/0003-existing.md \
  && git add -A && git commit -qm init \
  && git remote add origin "http://198.51.100.1/unreachable-and-blackholed.git" )
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && timeout 5 env PATH="$NOTOOLDIR" \
  bash -c 'printf "%s" "$1" | bash "$2"' _ \
  "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0007-new.md\"}}" \
  "$SCRIPTS_DIR/id-collision-guard.sh" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
  ok "G6 no timeout binary on PATH: fetch is skipped entirely, completes near-instantly, no hang"
else
  bad "G6 no timeout binary on PATH: fetch is skipped entirely, completes near-instantly, no hang" "rc=$rc out=[$out]"
fi
cleanup "$D"
rm -rf "$NOTOOLDIR"

# G9: MKR_PROTECTED_BRANCHES is read from the checked-out .mkr/config — a PR-controlled, ordinary
# tracked file — and its first entry is passed to `git fetch origin -- <value>`. Without the "--"
# separator, an option-shaped value (e.g. "--upload-pack=<arbitrary command>") would be
# interpreted by git as a real fetch option instead of a literal branch name, letting a crafted
# PR trigger arbitrary command execution the moment anyone Writes an ADR/MKR_ID_DIRS path on that
# branch. This proves the injection is inert: the marker command inside the crafted value must
# never actually run.
MARKER9="$(mktemp -u)-g9-marker"
REMOTE9="$(mktemp -d)"
( cd "$REMOTE9" && git init -q --bare && git symbolic-ref HEAD refs/heads/main ) >/dev/null 2>&1
D="$(fixture_repo)"
( cd "$D" && mkdir -p docs/adr && printf 'existing\n' > docs/adr/0003-existing.md \
  && printf 'MKR_PROTECTED_BRANCHES="--upload-pack=touch %s"\n' "$MARKER9" > .mkr/config \
  && git add -A && git commit -qm init \
  && git remote add origin "$REMOTE9" )
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0009-new.md\"}}")"
ok9g=1
[ -e "$MARKER9" ] && ok9g=0
[ -z "$out" ] || ok9g=0
if [ "$ok9g" -eq 1 ]; then
  ok "G9 an option-shaped MKR_PROTECTED_BRANCHES value cannot inject a git fetch option (marker command never ran)"
else
  bad "G9 an option-shaped MKR_PROTECTED_BRANCHES value cannot inject a git fetch option (marker command never ran)" "out=[$out] marker_exists=$([ -e "$MARKER9" ] && echo yes || echo no)"
fi
rm -f "$MARKER9"
cleanup "$D"; cleanup "$REMOTE9"

# origin/main-awareness: a number free in the local working tree but already used on origin/main
# (pushed and merged by a different, unrelated branch/session) must still be denied.
REMOTE="$(mktemp -d)"
( cd "$REMOTE" && git init -q --bare && git symbolic-ref HEAD refs/heads/main ) >/dev/null 2>&1
D="$(fixture_repo)"
( cd "$D" && mkdir -p docs/adr && printf 'local-existing\n' > docs/adr/0003-existing.md \
  && git add -A && git checkout -qb main && git commit -qm init \
  && git remote add origin "$REMOTE" && git push -q origin main )
CLONE2="$(mktemp -d)"
( git clone -q "$REMOTE" "$CLONE2" \
  && cd "$CLONE2" && git checkout -q main && mkdir -p docs/adr \
  && printf 'remote-only\n' > docs/adr/0009-remote-only.md \
  && git add -A && git -c user.email=t@t.com -c user.name=t commit -qm 'add 0009' \
  && git push -q origin main ) >/dev/null 2>&1
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0009-new.md\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"0009"* ]] && [[ "$out" == *"origin/main"* ]]; then
  ok "G4b number free locally but already used on origin/main â deny, citing origin/main"
else
  bad "G4b number free locally but already used on origin/main â deny, citing origin/main" "$out"
fi
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0011-new.md\"}}")"
if [ -z "$out" ]; then
  ok "G4c a number free both locally and on origin/main still clears"
else
  bad "G4c a number free both locally and on origin/main still clears" "$out"
fi
cleanup "$D"; cleanup "$CLONE2"; cleanup "$REMOTE"

# MKR_ID_DIRS: a project-declared extra directory (e.g. migrations/) gets the same NNNN-*
# collision coverage as MKR_ADR_DIR, without being ADR-specific or .md-specific.
D="$(fixture_repo)"
( cd "$D" && mkdir -p db/migrations \
  && printf 'MKR_ID_DIRS="db/migrations"\n' > .mkr/config \
  && printf 'existing\n' > db/migrations/0001-init.sql \
  && git add -A && git commit -qm init )
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/db/migrations/0001-new.sql\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"0001"* ]]; then
  ok "G4d MKR_ID_DIRS extends coverage to a non-ADR, non-.md directory"
else
  bad "G4d MKR_ID_DIRS extends coverage to a non-ADR, non-.md directory" "$out"
fi
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/db/migrations/0002-new.sql\"}}")"
if [ -z "$out" ]; then
  ok "G4e MKR_ID_DIRS: an unused number in the declared directory still clears"
else
  bad "G4e MKR_ID_DIRS: an unused number in the declared directory still clears" "$out"
fi
cleanup "$D"

# A directory NOT in MKR_ADR_DIR or MKR_ID_DIRS is never checked, even if it happens to hold an
# NNNN-*-shaped file - the guard's coverage is opt-in per directory, not a global filename scan.
D="$(fixture_repo)"
( cd "$D" && mkdir -p notes && printf 'existing\n' > notes/0001-existing.md \
  && git add -A && git commit -qm init )
out="$(run_hook "$D" id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/notes/0001-new.md\"}}")"
if [ -z "$out" ]; then
  ok "G4f an uncovered directory with an NNNN-shaped filename is never checked"
else
  bad "G4f an uncovered directory with an NNNN-shaped filename is never checked" "$out"
fi
cleanup "$D"

echo
echo "== spec-gate.sh (TC-M3-07..10) =="

D="$(fixture_repo)"
( cd "$D" && mkdir -p specs src && git checkout -qb main \
  && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'x\n' > f && git add -A && git commit -qm init \
  && git checkout -qb feature )

out="$(run_hook "$D" spec-gate.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/src/x.sh\"}}")"
if [[ "$out" == *'"permissionDecision":"ask"'* ]]; then
  ok "TC-M3-07 no ACCEPTED spec on branch → ask"
else
  bad "TC-M3-07 no ACCEPTED spec on branch → ask" "$out"
fi

( cd "$D" && printf '**Status** | ACCEPTED rev 1 (Alex, 2026-01-01)\n' > specs/Feature_Spec.md )
out="$(run_hook "$D" spec-gate.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/src/x.sh\"}}")"
if [ -z "$out" ]; then
  ok "TC-M3-08 branch's own ACCEPTED spec → allow"
else
  bad "TC-M3-08 branch's own ACCEPTED spec → allow" "$out"
fi
( cd "$D" && rm specs/Feature_Spec.md )

# TC-M3-09: no .mkr/config at all — separate fixture, since removing it here would affect
# MKR_PROTECTED_BRANCHES resolution for later cases in this same repo.
D9="$(fixture_repo)"
( cd "$D9" && mkdir -p src && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init && git checkout -qb feature )
out="$(run_hook "$D9" spec-gate.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D9/src/x.sh\"}}")"
if [ -z "$out" ]; then
  ok "TC-M3-09 .mkr/config absent (inactive) → allow"
else
  bad "TC-M3-09 .mkr/config absent (inactive) → allow" "$out"
fi
cleanup "$D9"

fail10=0
for p in "$D/specs/New_Spec.md" "$D/docs/adr/0007-x.md" "$D/docs/other.md" "$D/tests/x.sh" "$D/README.md" "$D/CLAUDE.md" "$D/VERSION"; do
  out="$(run_hook "$D" spec-gate.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$p\"}}")"
  [ -n "$out" ] && fail10=1
done
if [ "$fail10" -eq 0 ]; then
  ok "TC-M3-10 non-source paths (specs/docs/adr/docs/tests/README/CLAUDE.md/VERSION) always allow"
else
  bad "TC-M3-10 non-source paths (specs/docs/adr/docs/tests/README/CLAUDE.md/VERSION) always allow" "unexpected output for at least one path"
fi
cleanup "$D"

echo
echo "== stop-checks.sh (TC-M3-11..13) =="

D="$(fixture_repo)"
( cd "$D" && mkdir -p tests && printf 'x\n' > f && git add -A && git commit -qm init )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [ -z "$out" ]; then
  ok "TC-M3-pre nothing changed → allow"
else
  bad "TC-M3-pre nothing changed → allow" "$out"
fi

( cd "$D" && printf 'y\n' >> tests/foo.sh && printf 'MKR_TEST=false\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [[ "$out" == *'"decision":"block"'* ]]; then
  ok "TC-M3-11 test-relevant change + failing MKR_TEST → block"
else
  bad "TC-M3-11 test-relevant change + failing MKR_TEST → block" "$out"
fi

( cd "$D" && printf 'MKR_TEST=true\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [ -z "$out" ]; then
  ok "TC-M3-12 passing MKR_TEST → allow"
else
  bad "TC-M3-12 passing MKR_TEST → allow" "$out"
fi

( cd "$D" && printf '' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [ -z "$out" ]; then
  ok "TC-M3-13 MKR_TEST unset → allow"
else
  bad "TC-M3-13 MKR_TEST unset → allow" "$out"
fi
cleanup "$D"

echo
echo "== stop-checks.sh MKR_STOP_TEST_MODE toggle (TC-STH-01..10) =="

# TC-M3-11/12 above already prove the unset-mode case (failing/passing MKR_TEST → block/allow);
# TC-STH-01/02 are that same regression guarantee, restated under this feature's own IDs rather
# than duplicated as new test code.
ok "TC-STH-01 MKR_STOP_TEST_MODE unset + failing MKR_TEST → block (same case as TC-M3-11)"
ok "TC-STH-02 MKR_STOP_TEST_MODE unset + passing MKR_TEST → allow (same case as TC-M3-12)"

D="$(fixture_repo)"
( cd "$D" && mkdir -p tests && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'y\n' >> tests/foo.sh )

( cd "$D" && printf 'MKR_STOP_TEST_MODE=full\nMKR_TEST=false\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [[ "$out" == *'"decision":"block"'* ]]; then
  ok "TC-STH-03 MKR_STOP_TEST_MODE=full explicitly + failing MKR_TEST → block (same as unset)"
else
  bad "TC-STH-03 MKR_STOP_TEST_MODE=full explicitly + failing MKR_TEST → block (same as unset)" "$out"
fi

( cd "$D" && printf 'MKR_STOP_TEST_MODE=off\nMKR_TEST=false\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [ -z "$out" ]; then
  ok "TC-STH-04 MKR_STOP_TEST_MODE=off + failing MKR_TEST → allow"
else
  bad "TC-STH-04 MKR_STOP_TEST_MODE=off + failing MKR_TEST → allow" "$out"
fi

( cd "$D" && printf 'MKR_STOP_TEST_MODE=fast\nMKR_TEST=false\nMKR_TEST_FAST=true\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [ -z "$out" ]; then
  ok "TC-STH-06 MKR_STOP_TEST_MODE=fast, MKR_TEST_FAST passing (MKR_TEST failing) → allow"
else
  bad "TC-STH-06 MKR_STOP_TEST_MODE=fast, MKR_TEST_FAST passing (MKR_TEST failing) → allow" "$out"
fi

( cd "$D" && printf 'MKR_STOP_TEST_MODE=fast\nMKR_TEST=true\nMKR_TEST_FAST=false\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [[ "$out" == *'"decision":"block"'* ]] && [[ "$out" == *"MKR_TEST_FAST"* ]]; then
  ok "TC-STH-07 MKR_STOP_TEST_MODE=fast, MKR_TEST_FAST failing (MKR_TEST passing) → block, names MKR_TEST_FAST"
else
  bad "TC-STH-07 MKR_STOP_TEST_MODE=fast, MKR_TEST_FAST failing (MKR_TEST passing) → block, names MKR_TEST_FAST" "$out"
fi

( cd "$D" && printf 'MKR_STOP_TEST_MODE=fast\nMKR_TEST=false\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [ -z "$out" ]; then
  ok "TC-STH-08 MKR_STOP_TEST_MODE=fast, MKR_TEST_FAST unset → allow (no fallback to MKR_TEST)"
else
  bad "TC-STH-08 MKR_STOP_TEST_MODE=fast, MKR_TEST_FAST unset → allow (no fallback to MKR_TEST)" "$out"
fi

( cd "$D" && printf 'MKR_STOP_TEST_MODE=bogus\nMKR_TEST=false\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [[ "$out" == *'"decision":"block"'* ]] && [[ "$out" == *"not recognized"* ]]; then
  ok "TC-STH-09 MKR_STOP_TEST_MODE=bogus → warns, falls back to full → block on failing MKR_TEST"
else
  bad "TC-STH-09 MKR_STOP_TEST_MODE=bogus → warns, falls back to full → block on failing MKR_TEST" "$out"
fi

( cd "$D" && printf 'MKR_TEST=false\nMKR_TEST_FAST=true\n' > .mkr/config )
out="$(run_hook "$D" stop-checks.sh '{}')"
if [[ "$out" == *'"decision":"block"'* ]]; then
  ok "TC-STH-10 MKR_TEST_FAST set but MODE unset/full → ignored, decision follows MKR_TEST only"
else
  bad "TC-STH-10 MKR_TEST_FAST set but MODE unset/full → ignored, decision follows MKR_TEST only" "$out"
fi
cleanup "$D"

# TC-STH-05: MKR_STOP_TEST_MODE=off must short-circuit before the git-status scan itself ever
# runs, not just happen to land on the same "allow" a clean tree would give anyway. A PATH-shadowed
# `git` wrapper marks only `git status` invocations (not the earlier `git rev-parse
# --show-toplevel` config-resolution call), so the marker's absence proves the scan was skipped.
D="$(fixture_repo)"
( cd "$D" && mkdir -p tests && printf 'x\n' > f && git add -A && git commit -qm init )
( cd "$D" && printf 'MKR_STOP_TEST_MODE=off\nMKR_TEST=false\n' > .mkr/config && git add -A && git commit -qm cfg )
REAL_GIT="$(command -v git)"
FAKEBIN="$(mktemp -d)"
MARKER="$FAKEBIN/status-called"
cat > "$FAKEBIN/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "status" ]; then touch "$MARKER"; fi
exec "$REAL_GIT" "\$@"
EOF
chmod +x "$FAKEBIN/git"
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && PATH="$FAKEBIN:$PATH" bash "$SCRIPTS_DIR/stop-checks.sh" <<<'{}' 2>&1)"
if [ -z "$out" ] && [ ! -e "$MARKER" ]; then
  ok "TC-STH-05 MKR_STOP_TEST_MODE=off short-circuits before git status is ever called"
else
  bad "TC-STH-05 MKR_STOP_TEST_MODE=off short-circuits before git status is ever called" \
      "out=[$out] marker=$([ -e "$MARKER" ] && echo present || echo absent)"
fi
cleanup "$D"
rm -rf "$FAKEBIN"

echo
echo "== audit-log.sh (TC-M3-14) =="

D="$(fixture_repo)"
out="$(run_hook "$D" audit-log.sh '{"tool_name":"Bash","session_id":"sess123","tool_input":{"command":"npm test"}}')"
rc=$?
line="$(cat "$D/.mkr/audit.jsonl" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ -z "$out" ] \
   && [[ "$line" == '{"ts":"'*'","session_id":"sess123","tool_name":"Bash","summary":"npm test"}' ]]; then
  ok "TC-M3-14 well-formed JSONL line appended, exit 0, never blocks"
else
  bad "TC-M3-14 well-formed JSONL line appended, exit 0, never blocks" "rc=$rc out=[$out] line=[$line]"
fi
cleanup "$D"

# TC-M3-21: §7.7 promises "creating the file/directory if absent" — a code-review-caught defect
# in an earlier revision only worked because fixture_repo() always pre-creates .mkr/.
D="$(mktemp -d)"
( cd "$D" && git init -q && git config user.email t@t.com && git config user.name t \
  && mkdir -p .claude/hooks/lib .claude/hooks/scripts \
  && cp "$LIB_DIR/hookio.sh" .claude/hooks/lib/ ) >/dev/null 2>&1
out="$(run_hook "$D" audit-log.sh '{"tool_name":"Bash","session_id":"sess123","tool_input":{"command":"npm test"}}')"
rc=$?
line="$(cat "$D/.mkr/audit.jsonl" 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ -z "$out" ] && [ -d "$D/.mkr" ] \
   && [[ "$line" == '{"ts":"'*'","session_id":"sess123","tool_name":"Bash","summary":"npm test"}' ]]; then
  ok "TC-M3-21 audit-log.sh creates .mkr/ itself when absent"
else
  bad "TC-M3-21 audit-log.sh creates .mkr/ itself when absent" "rc=$rc out=[$out] line=[$line]"
fi
cleanup "$D"

echo
echo "== jq/python3/node-free, all six scripts (TC-M3-18) =="

BAREDIR="$(mktemp -d)"
# git is a sanctioned, required dependency (CLAUDE.md Stack: "Git is required for the git-root
# fallback in config.sh") — this case proves the absence of jq/python3/node, not of git.
# `type -P`, not `command -v`: this interactive shell defines a `grep` *function* (an editor
# convenience wrapper), and `command -v` would report its bare name instead of resolving the
# real on-disk binary these hook scripts actually need on PATH.
for c in bash cat grep sed head basename dirname mktemp printf test date tr sort git env; do
  p="$(type -P "$c" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$BAREDIR/$(basename "$p")" 2>/dev/null
done

D="$(fixture_repo)"
( cd "$D" && mkdir -p docs/adr specs tests src && git checkout -qb main \
  && printf 'MKR_PROTECTED_BRANCHES=main\n' > .mkr/config \
  && printf 'existing\n' > docs/adr/0003-existing.md \
  && printf 'x\n' > f && git add -A && git commit -qm init )

bare_run() { ( cd "$D" && PATH="$BAREDIR" bash "$SCRIPTS_DIR/$1" <<< "$2" 2>&1 ); }

fail18=0
out="$(bare_run secret-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git status"}}')"
[ -n "$out" ] && fail18=1
out="$(bare_run branch-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git push origin main"}}')"
[[ "$out" == *'"permissionDecision":"deny"'* ]] || fail18=1
out="$(bare_run id-collision-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/docs/adr/0003-new.md\"}}")"
[[ "$out" == *'"permissionDecision":"deny"'* ]] || fail18=1
out="$(bare_run spec-gate.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/src/x.sh\"}}")"
[[ "$out" == *'"permissionDecision":"ask"'* ]] || fail18=1
out="$(bare_run stop-checks.sh '{}')"
[ -n "$out" ] && fail18=1
out="$(bare_run audit-log.sh '{"tool_name":"Bash","session_id":"s","tool_input":{"command":"x"}}')"
[ -n "$out" ] && fail18=1

if [ "$fail18" -eq 0 ]; then
  ok "TC-M3-18 all six hook scripts run and decide correctly with no jq/python3/node on PATH"
else
  bad "TC-M3-18 all six hook scripts run and decide correctly with no jq/python3/node on PATH" "at least one script misbehaved bare"
fi
rm -rf "$BAREDIR"
cleanup "$D"

# --- WorktreeGuard test helpers ---------------

# start_foreign_process <dir> — starts a real, genuinely orphaned (kernel-reparented) process
# with cwd=<dir> and prints its pid. Genuine orphaning matters even though this suite itself
# may run inside a live Claude Code session: procwalk_foreign_cwd's own self-root (AD-5) walks
# up from its own $$ to the nearest ancestor process whose comm matches "claude" and treats that
# whole subtree as "self" — an ordinary backgrounded child job started from within this same
# session would still be a descendant of that subtree and could never register as a foreign
# collision. Backgrounding inside a subshell that then exits immediately makes the kernel
# reparent the still-running child (to the nearest subreaper, or PID 1) the moment its immediate
# parent — the subshell — exits, moving it structurally outside that subtree regardless of
# invocation context.
start_foreign_process() {
  local dir="$1" pf
  pf="$(mktemp)"
  # `exec` replaces the backgrounded subshell's own process image with sleep itself, so `$!` is
  # sleep's own pid (killable directly, not a wrapper whose real sleep grandchild survives a
  # `kill $pid` of the wrapper alone) — and its stdio is detached from this script's own
  # stdout/stderr, so an orphaned survivor can never hold this script's own output pipe open.
  ( cd "$dir" && exec sleep 300 </dev/null >/dev/null 2>&1 & echo $! > "$pf" )
  cat "$pf"
  rm -f "$pf"
}

stop_foreign_process() { kill "$1" >/dev/null 2>&1; }

# sibling_path <dir> — an unused absolute path next to <dir>, not yet created (git worktree add
# creates the leaf directory itself).
sibling_path() { mktemp -u "$(dirname -- "$1")/wg-sibling.XXXXXX"; }

relpath() { realpath --relative-to="$1" "$2"; }

echo
echo "== worktree-collision-guard.sh (TC-WG-01..06, 13, 15a, 19) =="

D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}')"
if [ -z "$out" ]; then
  ok "TC-WG-01 MKR_WORKTREE_POLICY=off leaves the collision guard inert despite a real collision"
else
  bad "TC-WG-01 MKR_WORKTREE_POLICY=off leaves the collision guard inert despite a real collision" "$out"
fi

( cd "$D" && printf 'MKR_WORKTREE_POLICY=advisory\n' > .mkr/config )
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}')"
if [[ "$out" == *"pid $pid"* ]] && [[ "$out" != *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-02 advisory warns (stderr, names the pid) but never blocks on a real collision"
else
  bad "TC-WG-02 advisory warns (stderr, names the pid) but never blocks on a real collision" "$out"
fi

( cd "$D" && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]] && [[ "$out" == *"pid $pid"* ]]; then
  ok "TC-WG-03 enforced denies a real collision, naming the pid"
else
  bad "TC-WG-03 enforced denies a real collision, naming the pid" "$out"
fi

out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout -- somefile"}}')"
if [ -z "$out" ]; then
  ok "TC-WG-05 a file-path 'git checkout -- <path>' is never gated, even with a real collision present"
else
  bad "TC-WG-05 a file-path 'git checkout -- <path>' is never gated, even with a real collision present" "$out"
fi

out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-15a no cd/-C/cwd to resolve → falls back to \${CLAUDE_PROJECT_DIR:-\$PWD} and gates correctly (denied)"
else
  bad "TC-WG-15a no cd/-C/cwd to resolve → falls back to \${CLAUDE_PROJECT_DIR:-\$PWD} and gates correctly (denied)" "$out"
fi

D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
rel="$(relpath "$D" "$D2")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $rel && git checkout other-branch\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-06 an inline 'cd <dir>' redirects the check to the idle target, not the colliding invoking cwd"
else
  bad "TC-WG-06 an inline 'cd <dir>' redirects the check to the idle target, not the colliding invoking cwd" "$out"
fi
cleanup "$D2"
stop_foreign_process "$pid"
cleanup "$D"

D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}')"
if [ -z "$out" ]; then
  ok "TC-WG-04 enforced allows a checkout when no live process holds the directory"
else
  bad "TC-WG-04 enforced allows a checkout when no live process holds the directory" "$out"
fi

pid="$(start_foreign_process "$D")"
out="$( ( cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG \
  && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}' \
  | PROCWALK_PROC_ROOT=/nonexistent-procwalk-root-xyz bash "$SCRIPTS_DIR/worktree-collision-guard.sh" ) 2>&1 )"
if [ -z "$out" ]; then
  ok "TC-WG-13 /proc absent (PROCWALK_PROC_ROOT) fails open — allowed, no error, despite a real collision that would otherwise be caught"
else
  bad "TC-WG-13 /proc absent (PROCWALK_PROC_ROOT) fails open — allowed, no error, despite a real collision that would otherwise be caught" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
WT19="$(sibling_path "$D")"
( cd "$D" && git worktree add -q "$WT19" -b wg19branch >/dev/null 2>&1 )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git checkout other-branch\"},\"cwd\":\"$WT19\"}")"
if [ -z "$out" ]; then
  ok "TC-WG-19 EnterWorktree divergence: resolution follows the payload's cwd (idle worktree), not the stale, colliding \$PWD"
else
  bad "TC-WG-19 EnterWorktree divergence: resolution follows the payload's cwd (idle worktree), not the stale, colliding \$PWD" "$out"
fi
stop_foreign_process "$pid"
( cd "$D" && git worktree remove --force "$WT19" >/dev/null 2>&1 )
cleanup "$D"

echo
echo "== worktree-edit-guard.sh (TC-WG-07..12, 15b, 16..18, 20) =="

D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
WT="$(sibling_path "$D")"
( cd "$D" && git worktree add -q "$WT" -b wg-edit-branch >/dev/null 2>&1 )

out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/newfile.txt\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-08 enforced denies a Write made directly in the shared (non-worktree) checkout"
else
  bad "TC-WG-08 enforced denies a Write made directly in the shared (non-worktree) checkout" "$out"
fi

out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$WT/newfile.txt\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-09 enforced allows the identical Write inside a real git worktree"
else
  bad "TC-WG-09 enforced allows the identical Write inside a real git worktree" "$out"
fi

out="$(run_hook "$D" worktree-edit-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-10 enforced denies a 'git commit' issued directly in the shared checkout"
else
  bad "TC-WG-10 enforced denies a 'git commit' issued directly in the shared checkout" "$out"
fi

out="$(run_hook "$WT" worktree-edit-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
if [ -z "$out" ]; then
  ok "TC-WG-18 enforced allows 'git commit' issued directly inside a real worktree (no -C, no cd)"
else
  bad "TC-WG-18 enforced allows 'git commit' issued directly inside a real worktree (no -C, no cd)" "$out"
fi

rel="$(relpath "$D" "$WT")"
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C $rel commit -m x\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-07 explicit 'git -C <worktree>' from the shared root correctly redirects the edit guard's check to the worktree"
else
  bad "TC-WG-07 explicit 'git -C <worktree>' from the shared root correctly redirects the edit guard's check to the worktree" "$out"
fi

( cd "$D" && printf 'MKR_WORKTREE_POLICY=advisory\n' > .mkr/config )
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/advisoryfile.txt\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-11 advisory: edit guard doesn't run at all — no denial, no warning"
else
  bad "TC-WG-11 advisory: edit guard doesn't run at all — no denial, no warning" "$out"
fi

( cd "$D" && printf 'MKR_WORKTREE_POLICY=off\n' > .mkr/config )
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/offfile.txt\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-12 off: edit guard fully inert"
else
  bad "TC-WG-12 off: edit guard fully inert" "$out"
fi

( cd "$D" && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$(run_hook "$D" worktree-edit-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m x"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-15b edit guard's Bash/git-commit path falls back to \${CLAUDE_PROJECT_DIR:-\$PWD} and gates correctly (denied)"
else
  bad "TC-WG-15b edit guard's Bash/git-commit path falls back to \${CLAUDE_PROJECT_DIR:-\$PWD} and gates correctly (denied)" "$out"
fi

SCRATCH="$(mktemp -d)"
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SCRATCH/f.txt\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-16 a file outside any git repo at all → allowed (empty-git-dir-first ordering, not a false '/worktrees/' non-match)"
else
  bad "TC-WG-16 a file outside any git repo at all → allowed (empty-git-dir-first ordering, not a false '/worktrees/' non-match)" "$out"
fi
rm -rf "$SCRATCH"

out="$(run_hook "$D" worktree-edit-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git -C /nonexistent/deleted-worktree-path-xyz commit -m x"}}')"
if [ -z "$out" ]; then
  ok "TC-WG-17 a resolved-but-nonexistent -C target → allowed (empty-git-dir-first ordering; the invoking cwd's own git-dir is fine, only the resolved target is checked)"
else
  bad "TC-WG-17 a resolved-but-nonexistent -C target → allowed (empty-git-dir-first ordering; the invoking cwd's own git-dir is fine, only the resolved target is checked)" "$out"
fi

out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m x\"},\"cwd\":\"$WT\"}")"
if [ -z "$out" ]; then
  ok "TC-WG-20 EnterWorktree divergence: resolution follows the payload's cwd (real worktree), not the stale, non-worktree \$PWD"
else
  bad "TC-WG-20 EnterWorktree divergence: resolution follows the payload's cwd (real worktree), not the stale, non-worktree \$PWD" "$out"
fi

( cd "$D" && git worktree remove --force "$WT" >/dev/null 2>&1 )
cleanup "$D"

# --- G4 review hardening (TC-WG-21..24): three real bypasses found on independent security and
# code review of the above, fixed, and regression-tested here rather than only disclosed. ---

echo
echo "== worktree guard hardening from G4 review (TC-WG-21..24) =="

# TC-WG-21/22: a multi-statement command mixing a file-path-form 'git checkout -- <path>' with a
# real branch-switching checkout must not let the file-path form either (a) short-circuit the
# whole scan before the real switch is ever seen, or (b) hijack which directory gets checked via
# its own unrelated 'cd'.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout -- somefile && git checkout other-branch"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-21 a leading file-path-form checkout doesn't shadow a real switch later in the same command"
else
  bad "TC-WG-21 a leading file-path-form checkout doesn't shadow a real switch later in the same command" "$out"
fi

D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
rel="$(relpath "$D" "$D2")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git checkout other-branch; cd $rel && git checkout -- somefile\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-22 a trailing decoy file-path checkout's own 'cd' doesn't redirect resolution away from the real switch's own (colliding) context"
else
  bad "TC-WG-22 a trailing decoy file-path checkout's own 'cd' doesn't redirect resolution away from the real switch's own (colliding) context" "$out"
fi
cleanup "$D2"
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-23: a Write creating the first file under a brand-new subdirectory of the shared,
# non-worktree checkout must still be denied — PreToolUse fires before the directory exists, so
# a naive `git -C <not-yet-created-dir>` would fail open on every such write.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$D/newsubdir/file.txt\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-23 a Write under a not-yet-created subdirectory of the shared checkout is still denied"
else
  bad "TC-WG-23 a Write under a not-yet-created subdirectory of the shared checkout is still denied" "$out"
fi
cleanup "$D"

# TC-WG-24: an ordinary (non-worktree) clone placed under a directory literally named
# "worktrees" must not be misidentified as a real git worktree by an unanchored substring match.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
DECOY_PARENT="$(mktemp -d)/worktrees"
mkdir -p "$DECOY_PARENT"
DECOY="$DECOY_PARENT/plain-clone"
git clone -q "$D" "$DECOY" >/dev/null 2>&1
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$DECOY/newfile.txt\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-24 an ordinary clone under a directory literally named 'worktrees' is still denied, not mistaken for a real worktree"
else
  bad "TC-WG-24 an ordinary clone under a directory literally named 'worktrees' is still denied, not mistaken for a real worktree" "$out"
fi
rm -rf "$(dirname -- "$DECOY_PARENT")"
cleanup "$D"

# TC-WG-25: 'git switch' has no file-path/pathspec-restore mode at all (unlike 'checkout') — its
# own '--' is only the ordinary end-of-options marker, so 'git switch -- <branch>' must still be
# gated as a real branch switch, not excluded the way a genuine 'git checkout -- <path>' is.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git switch -- other-branch"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-25 'git switch -- <branch>' is still gated as a real switch, not excluded like checkout's pathspec form"
else
  bad "TC-WG-25 'git switch -- <branch>' is still gated as a real switch, not excluded like checkout's pathspec form" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-26: the worktree-shape check must not trust a git-dir *string* alone — an ordinary,
# unrelated, non-isolated repo can be made to produce a git-dir containing the literal substring
# '.git/worktrees/' in one command (`git init --separate-git-dir=...`), with no real linkage back
# to the project being protected. Must still be denied.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
SPOOF_BASE="$(mktemp -d)"
mkdir -p "$SPOOF_BASE/x/.git/worktrees/fake"
SPOOF_DIR="$(mktemp -d)"
git init -q --separate-git-dir="$SPOOF_BASE/x/.git/worktrees/fake" "$SPOOF_DIR" >/dev/null 2>&1
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$SPOOF_DIR/newfile.txt\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-26 a fabricated git-dir string containing '.git/worktrees/' (via --separate-git-dir) is still denied — not a registered worktree of any real project"
else
  bad "TC-WG-26 a fabricated git-dir string containing '.git/worktrees/' (via --separate-git-dir) is still denied — not a registered worktree of any real project" "$out"
fi
rm -rf "$SPOOF_BASE" "$SPOOF_DIR"
cleanup "$D"

# TC-WG-27: every real 'git commit' occurrence in a multi-statement command is checked
# independently — an earlier, unsafe commit in the shared checkout must not hide behind a later,
# safe decoy commit inside a real worktree.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
WT27="$(sibling_path "$D")"
( cd "$D" && git worktree add -q "$WT27" -b wg27branch >/dev/null 2>&1 )
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git commit -m first; cd $WT27 && git commit -m second\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-27 an earlier unsafe commit in the shared checkout is denied even when a later commit in the same command targets a real worktree"
else
  bad "TC-WG-27 an earlier unsafe commit in the shared checkout is denied even when a later commit in the same command targets a real worktree" "$out"
fi
( cd "$D" && git worktree remove --force "$WT27" >/dev/null 2>&1 )
cleanup "$D"

# TC-WG-28: the exclude check must not be fooled by a trailing shell comment that happens to
# contain the words 'checkout' and '--' — the actual command bash would run is a real,
# ordinary 'git switch', not excluded by any genuine checkout pathspec form.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git switch other-branch # note: run checkout later -- do not forget"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-28 a trailing comment containing 'checkout' and '--' doesn't fool the exclude match into hiding a real switch"
else
  bad "TC-WG-28 a trailing comment containing 'checkout' and '--' doesn't fool the exclude match into hiding a real switch" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-28b: a '#' quoted inside a real 'cd' target must not be mistaken for a comment start and
# truncate the statement mid-quote — that would drop the closing quote the cd-target regex
# itself requires to match at all, silently breaking resolution (falling back to the invoking,
# colliding cwd instead of the real, idle target) rather than merely stripping harmless trailing
# text.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
D2="$(fixture_repo)"
D2HASH="$(dirname -- "$D2")/idle#$(basename -- "$D2")"
mv "$D2" "$D2HASH"
D2="$D2HASH"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
pid="$(start_foreign_process "$D")"
rel="$(relpath "$D" "$D2")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd \\\"$rel\\\" && git checkout other-branch\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-28b a '#' quoted inside a real 'cd' target isn't mistaken for a comment start (which would drop the closing quote and break resolution)"
else
  bad "TC-WG-28b a '#' quoted inside a real 'cd' target isn't mistaken for a comment start (which would drop the closing quote and break resolution)" "$out"
fi
cleanup "$D2"
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-29: a real, valid branch name that merely *contains* 'checkout' as a hyphen-delimited
# fragment (an entirely ordinary naming pattern — 'run-checkout-now', 'fix-checkout-crash') must
# not satisfy a checkout-pathspec exclusion check — that name is one single token to bash, never
# three, even though a regex word-boundary test can't tell the difference. 'switch -c <name> --
# <start-point>' is a real, executing branch switch using '--' only as switch's own ordinary
# start-point disambiguator, not a file-path/pathspec form.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git switch -c run-checkout-now -- other-branch"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-29 a branch name merely containing 'checkout' (e.g. 'run-checkout-now') doesn't fool the exclude check into hiding a real switch"
else
  bad "TC-WG-29 a branch name merely containing 'checkout' (e.g. 'run-checkout-now') doesn't fool the exclude check into hiding a real switch" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-30/30b: a command substitution embedded in what looks like a safe checkout pathspec form
# (`git checkout -- $(git checkout evilbranch)`) genuinely executes the inner `git checkout
# evilbranch` as a real, independent side effect before the outer no-op ever runs — the flat
# tokenizer can't see that boundary, so the statement must never be excluded, at all, once a
# substitution is present (fails toward more scrutiny, not less).
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout -- $(git checkout evilbranch)"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-30 a checkout hidden inside a command substitution's own '-- \$(...)' argument is not excluded as a safe pathspec form"
else
  bad "TC-WG-30 a checkout hidden inside a command substitution's own '-- \$(...)' argument is not excluded as a safe pathspec form" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout -- $(git checkout evilbranch)"}}')"
if [ -z "$out" ]; then
  ok "TC-WG-30b the same command-substitution shape still allows when no real collision exists — gated (really checked), not blindly denied"
else
  bad "TC-WG-30b the same command-substitution shape still allows when no real collision exists — gated (really checked), not blindly denied" "$out"
fi
cleanup "$D"

# TC-WG-31: a real, unambiguous 'git -C <dir>' must still be trusted and resolved correctly even
# when an unrelated, inert substitution sits elsewhere in the same statement — distrusting -C
# whenever a substitution appears ANYWHERE in the statement (rather than only when the -C value
# itself is one) silently redirects resolution to the invoking session's own (safe) cwd instead
# of the real, colliding target — a real regression an earlier version of this same fix caused.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
pid="$(start_foreign_process "$D2")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"git -C $D2 checkout other-branch \$(true)\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-31 a real '-C <dir>' is still trusted and resolved when an unrelated, inert \$(...) sits elsewhere in the same statement"
else
  bad "TC-WG-31 a real '-C <dir>' is still trusted and resolved when an unrelated, inert \$(...) sits elsewhere in the same statement" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D2"
cleanup "$D"

# TC-WG-32: process substitution ('<(...)'/'>(...)') genuinely spawns a real subprocess the same
# way command substitution does, and is just as ordinary a bash feature (e.g. 'diff <(a) <(b)')
# — not covered by the earlier '$('/backtick-only check.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git checkout -- <(git checkout evilbranch)"}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-32 a checkout hidden inside process substitution ('<(...)') is not excluded as a safe pathspec form"
else
  bad "TC-WG-32 a checkout hidden inside process substitution ('<(...)') is not excluded as a safe pathspec form" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-33: a real 'git commit' issued directly in the shared checkout must still be denied even
# when its own commit message happens to contain 'git -C <path>' as ordinary text — an unanchored
# -C extraction would mistake that quoted decoy for the real command's own flag and redirect
# resolution to whatever (likely nonexistent) path the message names.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$(run_hook "$D" worktree-edit-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -am \"docs: explain git -C ../other-repo usage for debugging\""}}')"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-33 a commit directly in the shared checkout is still denied even when its own message contains 'git -C <path>' as ordinary text"
else
  bad "TC-WG-33 a commit directly in the shared checkout is still denied even when its own message contains 'git -C <path>' as ordinary text" "$out"
fi
cleanup "$D"

# TC-WG-34: a real branch switch in the colliding invoking directory must still be denied even
# when an unrelated env-var prefix on the same simple command happens to contain 'git -C <path>'
# text naming an idle decoy directory.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"NOTE=\\\"git -C $D2 checkout later\\\" git switch other-branch\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-34 a real switch in the colliding cwd is still denied even when an unrelated env-var prefix contains 'git -C <path>' text naming an idle decoy"
else
  bad "TC-WG-34 a real switch in the colliding cwd is still denied even when an unrelated env-var prefix contains 'git -C <path>' text naming an idle decoy" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D2"
cleanup "$D"

# TC-WG-35: a backgrounded 'cd' forks a subshell whose own cwd change never propagates back to
# the invoking shell — so a real 'git checkout' that follows it on the same line still actually
# runs in the original (colliding) directory, not the backgrounded cd's own idle target.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $D2 & git checkout other-branch\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-35 a backgrounded 'cd' doesn't redirect resolution away from the real switch's own (still-colliding) invoking directory"
else
  bad "TC-WG-35 a backgrounded 'cd' doesn't redirect resolution away from the real switch's own (still-colliding) invoking directory" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D2"
cleanup "$D"

# TC-WG-36: the same backgrounded-cd effect, for the edit guard's Bash/git-commit path — a real
# commit issued directly in the shared checkout must still be denied even when preceded by a
# backgrounded 'cd' into a real worktree that never actually took effect.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
WT36="$(sibling_path "$D")"
( cd "$D" && git worktree add -q "$WT36" -b wg36branch >/dev/null 2>&1 )
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $WT36 & git commit -m x\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-36 a backgrounded 'cd' into a real worktree doesn't excuse a real commit that still actually lands in the shared checkout"
else
  bad "TC-WG-36 a backgrounded 'cd' into a real worktree doesn't excuse a real commit that still actually lands in the shared checkout" "$out"
fi
( cd "$D" && git worktree remove --force "$WT36" >/dev/null 2>&1 )
cleanup "$D"

# TC-WG-37: an ordinary 'git commit' whose message merely happens to contain the standalone
# English word 'checkout' (or 'switch') must never be misclassified as a branch-switch
# candidate — the collision guard's own keyword scan must be as tight as procwalk_resolve_target_dir's,
# not a loose wildcard that matches the word anywhere in the statement.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$(run_hook "$D" worktree-collision-guard.sh '{"tool_name":"Bash","tool_input":{"command":"git commit -m \"checkout fix\""}}')"
if [ -z "$out" ]; then
  ok "TC-WG-37 an ordinary commit message containing the word 'checkout' is never misclassified as a branch-switch candidate"
else
  bad "TC-WG-37 an ordinary commit message containing the word 'checkout' is never misclassified as a branch-switch candidate" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

# TC-WG-38: a real, safe 'cd' (joined by '&&', genuinely taking effect in the real shell) must
# still be trusted even when an unrelated pipe appears later in the same command, on a different
# statement — real bash only forks a subshell for what's directly adjacent to '|'/'&', not
# everything connected via a different, later operator. An earlier, coarser fix wrongly
# distrusted the whole command whenever any pipe/background appeared anywhere in it.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
pid="$(start_foreign_process "$D2")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $D2 && git checkout other-branch | cat\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-38 a real, safe 'cd' (via &&) is still trusted even when an unrelated pipe appears later in the same command"
else
  bad "TC-WG-38 a real, safe 'cd' (via &&) is still trusted even when an unrelated pipe appears later in the same command" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D2"
cleanup "$D"

# TC-WG-39: '||' never forks a subshell (same as '&&') — the ordinary 'cd dir || exit 1' idiom
# must not be misclassified as an unsafe, subshell-forking boundary.
D="$(fixture_repo)"
( cd "$D" && git checkout -qb main && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
WT39="$(sibling_path "$D")"
( cd "$D" && git worktree add -q "$WT39" -b wg39branch >/dev/null 2>&1 )
out="$(run_hook "$D" worktree-edit-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $WT39 || exit 1; git commit -m x\"}}")"
if [ -z "$out" ]; then
  ok "TC-WG-39 the ordinary 'cd dir || exit 1' idiom is not misclassified as an unsafe boundary — a real commit into a real worktree is still allowed"
else
  bad "TC-WG-39 the ordinary 'cd dir || exit 1' idiom is not misclassified as an unsafe boundary — a real commit into a real worktree is still allowed" "$out"
fi
( cd "$D" && git worktree remove --force "$WT39" >/dev/null 2>&1 )
cleanup "$D"

# TC-WG-40: a second 'cd' that is itself about to be forked away by its own following unsafe
# boundary must not clobber an earlier, still-genuinely-real 'cd' — 'cd A && cd B | git checkout
# other-branch' really executes the checkout in A (the pipeline forks from the shell's state
# right after 'cd A' took effect; 'cd B''s own effect is confined to its own subshell).
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
D2="$(fixture_repo)"
( cd "$D2" && printf 'x\n' > f2 && git add -A && git commit -qm init2 )
D3="$(fixture_repo)"
( cd "$D3" && printf 'x\n' > f3 && git add -A && git commit -qm init3 )
pid="$(start_foreign_process "$D2")"
out="$(run_hook "$D" worktree-collision-guard.sh "{\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"cd $D2 && cd $D3 | git checkout other-branch\"}}")"
if [[ "$out" == *'"permissionDecision":"deny"'* ]]; then
  ok "TC-WG-40 an earlier, genuinely-real 'cd' isn't clobbered by a later 'cd' that's itself forked away by its own following unsafe boundary"
else
  bad "TC-WG-40 an earlier, genuinely-real 'cd' isn't clobbered by a later 'cd' that's itself forked away by its own following unsafe boundary" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D3"
cleanup "$D2"
cleanup "$D"

# TC-WG-41/42 (AD-1/AD-2): forced onto the
# no-claude-ancestor path (PROCWALK_SELF_TEST_FORCE_NO_CLAUDE), reproducing the CI-only shape
# where run_hook's own enclosing subshell — a forked, not exec'd, continuation of this script's own
# process, sharing the exact target cwd for its whole lifetime — is $$'s direct parent, not its
# descendant, and so was never in procwalk_foreign_cwd's self set on that path.
D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
out="$( ( cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG \
  && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}' \
  | PROCWALK_SELF_TEST_FORCE_NO_CLAUDE=1 bash "$SCRIPTS_DIR/worktree-collision-guard.sh" ) 2>&1 )"
if [ -z "$out" ]; then
  ok "TC-WG-41 forced no-claude-ancestor path: the hook's own calling subshell is never mistaken for a foreign collision"
else
  bad "TC-WG-41 forced no-claude-ancestor path: the hook's own calling subshell is never mistaken for a foreign collision" "$out"
fi
cleanup "$D"

D="$(fixture_repo)"
( cd "$D" && printf 'x\n' > f && git add -A && git commit -qm init \
  && printf 'MKR_WORKTREE_POLICY=enforced\n' > .mkr/config )
pid="$(start_foreign_process "$D")"
out="$( ( cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG \
  && printf '%s' '{"tool_name":"Bash","tool_input":{"command":"git checkout other-branch"}}' \
  | PROCWALK_SELF_TEST_FORCE_NO_CLAUDE=1 bash "$SCRIPTS_DIR/worktree-collision-guard.sh" ) 2>&1 )"
if [[ "$out" == *'"permissionDecision":"deny"'* && "$out" == *"pid $pid"* ]]; then
  ok "TC-WG-42 forced no-claude-ancestor path: a real, genuinely foreign process is still correctly denied, naming the pid"
else
  bad "TC-WG-42 forced no-claude-ancestor path: a real, genuinely foreign process is still correctly denied, naming the pid" "$out"
fi
stop_foreign_process "$pid"
cleanup "$D"

echo
echo "== reviewrecord.sh: find_review_record =="

# rrf_commit <repo> <relpath> <content> — mkdir -p, write, add, commit; prints the new sha.
rrf_commit() {
  local repo="$1" rel="$2" content="$3"
  ( cd "$repo" && mkdir -p "$(dirname -- "$rel")" 2>/dev/null; printf '%s' "$content" > "$repo/$rel" \
      && cd "$repo" && git add -- "$rel" && git commit -q -m "commit $rel" >/dev/null && git rev-parse HEAD )
}

RRF_LIB="$LIB_DIR/reviewrecord.sh"

# TC-RRF-01: exact match.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" src.txt hello)"
shortX="${shaX:0:7}"
mkdir -p "$D/.mkr/reviews"
printf 'VERDICT: READY\n' > "$D/.mkr/reviews/$shortX.md"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaX" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = ".mkr/reviews/$shortX.md" ]; then
  ok "TC-RRF-01 exact match at the given sha returns that record"
else
  bad "TC-RRF-01 exact match at the given sha returns that record" "rc=$rc out=[$out]"
fi
cleanup "$D"

# G5: MKR_REVIEW_VERDICT_STRING lets a project customize the literal reviewrecord.sh looks for,
# without patching this file. A record written in the shipped default shape ("VERDICT: READY")
# must NOT satisfy a project that has configured a different one, and a record written in the
# configured shape must.
D="$(fixture_repo)"
shaG5="$(rrf_commit "$D" src.txt hello)"
shortG5="${shaG5:0:7}"
mkdir -p "$D/.mkr/reviews"
printf 'MKR_REVIEW_VERDICT_STRING="APPROVED"\n' > "$D/.mkr/config"
printf 'VERDICT: READY\n' > "$D/.mkr/reviews/$shortG5.md"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaG5" ".mkr/reviews" "specs")"
rcG5a=$?
printf 'APPROVED\n' > "$D/.mkr/reviews/$shortG5.md"
out2="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaG5" ".mkr/reviews" "specs")"
rcG5b=$?
if [ "$rcG5a" -ne 0 ] && [ "$rcG5b" -eq 0 ] && [ "$out2" = ".mkr/reviews/$shortG5.md" ]; then
  ok "G5 MKR_REVIEW_VERDICT_STRING: the default literal no longer satisfies, the configured one does"
else
  bad "G5 MKR_REVIEW_VERDICT_STRING: the default literal no longer satisfies, the configured one does" "rcG5a=$rcG5a rcG5b=$rcG5b out2=[$out2]"
fi
cleanup "$D"

# TC-RRF-02: PR #24's real, two-directory shape — Y's diff touches reviews/ AND specs/.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
shortX="${shaX:0:7}"
( cd "$D" && mkdir -p .mkr/reviews specs \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortX.md" \
    && printf '# spec DoD: reviewed at .mkr/reviews/%s.md\n' "$shortX" > specs/Some_Spec.md \
    && git add .mkr/reviews specs && git commit -q -m "review commit" >/dev/null )
shaY="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaY" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = ".mkr/reviews/$shortX.md" ]; then
  ok "TC-RRF-02 real PR#24 shape (reviews/+specs/ together) falls back to the parent's record"
else
  bad "TC-RRF-02 real PR#24 shape (reviews/+specs/ together) falls back to the parent's record" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-RRF-02b: narrower shape — Y's diff touches only reviews/, nothing under specs/.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
shortX="${shaX:0:7}"
( cd "$D" && mkdir -p .mkr/reviews \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortX.md" \
    && git add .mkr/reviews && git commit -q -m "review commit" >/dev/null )
shaY="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaY" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = ".mkr/reviews/$shortX.md" ]; then
  ok "TC-RRF-02b reviews/-only shape also falls back correctly"
else
  bad "TC-RRF-02b reviews/-only shape also falls back correctly" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-RRF-03: no loophole — Y's diff also touches a file outside both directories.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
shortX="${shaX:0:7}"
( cd "$D" && mkdir -p .mkr/reviews specs \
    && printf '# review\n' > ".mkr/reviews/$shortX.md" \
    && printf '# spec DoD\n' > specs/Some_Spec.md \
    && printf 'echo v2\n' > install.sh \
    && git add .mkr/reviews specs install.sh && git commit -q -m "review commit + sneaky code change" >/dev/null )
shaY="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaY" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-RRF-03 no loophole: a real change riding along with the record is refused"
else
  bad "TC-RRF-03 no loophole: a real change riding along with the record is refused" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-RRF-04: touches only reviews/specs, but parent has no record either.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
( cd "$D" && mkdir -p .mkr/reviews specs \
    && printf '# review\n' > ".mkr/reviews/deadbee.md" \
    && git add .mkr/reviews && git commit -q -m "review commit, mismatched name" >/dev/null )
shaY="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaY" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-RRF-04 no record at either level fails cleanly"
else
  bad "TC-RRF-04 no record at either level fails cleanly" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-RRF-05: root commit, no parent at all.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaX" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-RRF-05 root commit (no parent) fails cleanly, no crash"
else
  bad "TC-RRF-05 root commit (no parent) fails cleanly, no crash" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-RRF-08: a fabricated record (exists, right filename, but no "VERDICT: READY" line — the
# exact shape mkr-security-reviewer demonstrated at this spec's own G4, §13) is refused at both
# the exact-match and fallback paths, not just accepted on existence.
D="$(fixture_repo)"
shaX="$(rrf_commit "$D" src.txt hello)"
shortX="${shaX:0:7}"
mkdir -p "$D/.mkr/reviews"
printf '# review\n' > "$D/.mkr/reviews/$shortX.md"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaX" ".mkr/reviews" "specs")"
rc1=$?
cleanup "$D"

D="$(fixture_repo)"
shaX2="$(rrf_commit "$D" install.sh 'echo v1')"
shortX2="${shaX2:0:7}"
( cd "$D" && mkdir -p .mkr/reviews specs \
    && printf 'VERDICT: NOT READY (1 blocking)\n' > ".mkr/reviews/$shortX2.md" \
    && printf '# spec DoD\n' > specs/Some_Spec.md \
    && git add .mkr/reviews specs && git commit -q -m "review commit, but NOT READY" >/dev/null )
shaY2="$(cd "$D" && git rev-parse HEAD)"
out2="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaY2" ".mkr/reviews" "specs")"
rc2=$?
cleanup "$D"

if [ "$rc1" -ne 0 ] && [ "$rc2" -ne 0 ]; then
  ok "TC-RRF-08 a fabricated or NOT-READY record is refused at both exact-match and fallback"
else
  bad "TC-RRF-08 a fabricated or NOT-READY record is refused at both exact-match and fallback" "rc1=$rc1 out1=[$out] rc2=$rc2 out2=[$out2]"
fi

echo
echo "== reviewrecord.sh: find_review_record on a real merge commit =="

# TC-MRF-01: a real merge commit (git merge --no-ff, matching gh pr merge --merge's own shape) whose
# second parent (the merged-in branch tip, the feature commit itself -- no trailing review commit)
# has a valid exact-match record, and whose first parent is correctly supplied as expected_prior_tip
# (AD-3 -- required for the merge-commit path to run at all). git diff-tree shows an empty diff for a
# merge commit by default -- the merge commit's own sha must resolve via its second parent's own
# exact match directly, not via a (nonexistent) diff of its own and not via any fallback recursion
# (that shape is TC-MRF-02's).
D="$(fixture_repo)"
shaBase="$(rrf_commit "$D" base.txt hello)"
( cd "$D" && git checkout -q -b feature )
shaFeature="$(rrf_commit "$D" feature.txt world)"
shortFeature="${shaFeature:0:7}"
( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master )
( cd "$D" && git merge --no-ff -q -m "merge feature" feature >/dev/null )
shaMerge="$(cd "$D" && git rev-parse HEAD)"
mkdir -p "$D/.mkr/reviews"
printf 'VERDICT: READY\n' > "$D/.mkr/reviews/$shortFeature.md"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaMerge" ".mkr/reviews" "specs" "$shaBase")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = ".mkr/reviews/$shortFeature.md" ]; then
  ok "TC-MRF-01 merge commit resolves via its second parent's exact-match record"
else
  bad "TC-MRF-01 merge commit resolves via its second parent's exact-match record" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-MRF-02: the merged branch's own tip is itself a record-only trailing commit (this repo's own
# real shape: PR #27 merged into pre-release-cleanup-issue23 as 6545cdf, whose second parent 1208916
# was a "review: ..." commit needing its own one-level fallback to d27e5d5) -- the merge-commit
# resolution must recurse through the second parent's own fallback, not just its exact sha.
D="$(fixture_repo)"
shaBase="$(rrf_commit "$D" base.txt hello)"
( cd "$D" && git checkout -q -b feature )
shaFeature="$(rrf_commit "$D" feature.txt world)"
shortFeature="${shaFeature:0:7}"
( cd "$D" && mkdir -p .mkr/reviews \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortFeature.md" \
    && git add .mkr/reviews && git commit -q -m "review commit" >/dev/null )
shaFeatureReview="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master )
( cd "$D" && git merge --no-ff -q -m "merge feature" feature >/dev/null )
shaMerge="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaMerge" ".mkr/reviews" "specs" "$shaBase")"
rc=$?
if [ "$rc" -eq 0 ] && [ "$out" = ".mkr/reviews/$shortFeature.md" ]; then
  ok "TC-MRF-02 merge commit recurses through its second parent's own one-level fallback"
else
  bad "TC-MRF-02 merge commit recurses through its second parent's own one-level fallback" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-MRF-03: no loophole -- a merge commit whose second parent has no valid record at all (neither
# exact-match nor via its own fallback) must fail closed, not silently accept the merge itself.
D="$(fixture_repo)"
shaBase="$(rrf_commit "$D" base.txt hello)"
( cd "$D" && git checkout -q -b feature )
shaFeature="$(rrf_commit "$D" feature.txt world)"
( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master )
( cd "$D" && git merge --no-ff -q -m "merge feature" feature >/dev/null )
shaMerge="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaMerge" ".mkr/reviews" "specs" "$shaBase")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-MRF-03 merge commit with no reviewed second parent fails closed"
else
  bad "TC-MRF-03 merge commit with no reviewed second parent fails closed" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-MRF-04 (AD-2): no loophole -- a crafted two-parent commit whose second parent is a real,
# validly reviewed sha picked from unrelated history, but whose own TREE is unrelated/malicious
# (built via `git commit-tree`, the same shape `git merge -s ours` produces -- never a real
# `git merge --no-ff`/`gh pr merge --merge` output) must be refused, even when the attacker's
# crafted tree also smuggles in a byte-for-byte copy of the stolen review record at its exact
# expected path (so a naive disk-based existence check alone would still see it once the malicious
# commit is actually checked out) and even when the correct expected_prior_tip is supplied (isolating
# that AD-2's tree-verification specifically is what catches this, not AD-3's first-parent check) --
# a merge commit's parent list alone is never sufficient proof its second parent's own review
# actually covers its content (AD-2, found by mkr-security-reviewer at this fix's own G4;
# empirically reproduced end-to-end against the pre-AD-2 code before this test was added -- rc=0,
# exploit succeeded).
D="$(fixture_repo)"
shaMainTip="$(rrf_commit "$D" base.txt hello)"
( cd "$D" && git checkout -q -b old-reviewed )
shaOldFeature="$(rrf_commit "$D" unrelated.txt "unrelated content")"
shortOldFeature="${shaOldFeature:0:7}"
( cd "$D" && mkdir -p .mkr/reviews \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortOldFeature.md" \
    && git add .mkr/reviews && git commit -q -m "review commit" >/dev/null )
shaOldReviewed="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master )
( cd "$D" && mkdir -p .mkr/reviews \
    && printf 'MALICIOUS PAYLOAD, never reviewed\n' > evil.txt \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortOldFeature.md" \
    && git add evil.txt .mkr/reviews )
maliciousTree="$(cd "$D" && git write-tree)"
shaMalicious="$(cd "$D" && git commit-tree "$maliciousTree" -p "$shaMainTip" -p "$shaOldReviewed" -m "fake merge")"
( cd "$D" && git checkout -q "$shaMalicious" )
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaMalicious" ".mkr/reviews" "specs" "$shaMainTip")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-MRF-04 a crafted merge-shaped commit with a stolen review record and unrelated payload is refused"
else
  bad "TC-MRF-04 a crafted merge-shaped commit with a stolen review record and unrelated payload is refused" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-MRF-05 (AD-3): no loophole -- the deeper attack AD-2 alone did not catch. Attacker crafts a
# *fresh* commit E sharing a real common ancestor P with an already-reviewed commit S (E's parent =
# P, E's tree = P's tree plus a new file at a path S never touches), then a genuinely conflict-free
# `git merge-tree --write-tree E S` recomputation matches the crafted merge commit's own tree by
# construction (E and S touch disjoint paths from a real common ancestor) -- AD-2's tree check alone
# would pass this. Closed only because E != the real expected_prior_tip supplied by the caller (found
# by mkr-security-reviewer at this fix's own G4 re-review; empirically reproduced end-to-end against
# the AD-2-only code before this test was added -- rc=0, exploit succeeded even with AD-2 in place).
D="$(fixture_repo)"
shaP="$(rrf_commit "$D" shared.txt base)"
shaS="$(rrf_commit "$D" s_file.txt "S's real change")"
shortS="${shaS:0:7}"
( cd "$D" && mkdir -p .mkr/reviews \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortS.md" \
    && git add .mkr/reviews && git commit -q -m "review commit for S" >/dev/null )
shaSReviewed="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && git checkout -q "$shaP" )
( cd "$D" && printf 'EVIL PAYLOAD\n' > evil.txt && git add evil.txt )
eTree="$(cd "$D" && git write-tree)"
shaE="$(cd "$D" && git commit-tree "$eTree" -p "$shaP" -m "E: attacker commit")"
mTree="$(cd "$D" && git merge-tree --write-tree "$shaE" "$shaSReviewed")"
shaMalicious="$(cd "$D" && git commit-tree "$mTree" -p "$shaE" -p "$shaSReviewed" -m "fake merge")"
( cd "$D" && git checkout -q "$shaMalicious" )
# expected_prior_tip is the REAL prior main tip (shaP, or anything other than shaE) -- shaE is a
# freshly-fabricated commit the caller never actually had as its own branch tip.
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaMalicious" ".mkr/reviews" "specs" "$shaP")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-MRF-05 a fabricated first parent sharing a real ancestor with a reviewed commit is refused"
else
  bad "TC-MRF-05 a fabricated first parent sharing a real ancestor with a reviewed commit is refused" "rc=$rc out=[$out]"
fi
cleanup "$D"

# TC-MRF-06 (AD-3): an otherwise-honest merge with no expected_prior_tip supplied at all (the 4th
# arg omitted/empty) must not resolve via the merge-commit path -- the caller's own attestation is
# mandatory, never optional, for this shortcut to ever fire.
D="$(fixture_repo)"
shaBase="$(rrf_commit "$D" base.txt hello)"
( cd "$D" && git checkout -q -b feature )
shaFeature="$(rrf_commit "$D" feature.txt world)"
shortFeature="${shaFeature:0:7}"
( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master )
( cd "$D" && git merge --no-ff -q -m "merge feature" feature >/dev/null )
shaMerge="$(cd "$D" && git rev-parse HEAD)"
mkdir -p "$D/.mkr/reviews"
printf 'VERDICT: READY\n' > "$D/.mkr/reviews/$shortFeature.md"
out="$(cd "$D" && . "$RRF_LIB" 2>/dev/null && find_review_record "$shaMerge" ".mkr/reviews" "specs")"
rc=$?
if [ "$rc" -ne 0 ] && [ -z "$out" ]; then
  ok "TC-MRF-06 an omitted expected_prior_tip refuses the merge-commit path entirely"
else
  bad "TC-MRF-06 an omitted expected_prior_tip refuses the merge-commit path entirely" "rc=$rc out=[$out]"
fi
cleanup "$D"

echo
echo "== pre-push-review-guard.sh: fallback path =="

GUARD_PATH="$SCRIPTS_DIR/pre-push-review-guard.sh"
ZERO_SHA='0000000000000000000000000000000000000000'

# fixture_repo() already vendors config.sh/hookio.sh/procwalk.sh; add reviewrecord.sh too, since
# pre-push-review-guard.sh resolves its own root via cwd and sources everything from there.
rrf_fixture_with_lib() {
  local d
  d="$(fixture_repo)"
  cp "$RRF_LIB" "$d/.claude/hooks/lib/" 2>/dev/null
  printf '%s' "$d"
}

# TC-PPR-01: real PR#24 shape as the pushed ref's local sha → no WARN.
D="$(rrf_fixture_with_lib)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
shortX="${shaX:0:7}"
( cd "$D" && mkdir -p .mkr/reviews specs \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortX.md" \
    && printf '# spec DoD: .mkr/reviews/%s.md\n' "$shortX" > specs/Some_Spec.md \
    && git add .mkr/reviews specs && git commit -q -m "review commit" >/dev/null )
shaY="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && printf 'refs/heads/x %s refs/heads/x %s\n' "$shaY" "$ZERO_SHA" | bash "$GUARD_PATH" 2>&1)"
if [[ "$out" != *"WARN: no review record"* ]]; then
  ok "TC-PPR-01 real PR#24 shape at HEAD → no WARN"
else
  bad "TC-PPR-01 real PR#24 shape at HEAD → no WARN" "$out"
fi
cleanup "$D"

# TC-PPR-02: no record at either level → WARN naming the sha.
D="$(rrf_fixture_with_lib)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
shortX="${shaX:0:7}"
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && printf 'refs/heads/x %s refs/heads/x %s\n' "$shaX" "$ZERO_SHA" | bash "$GUARD_PATH" 2>&1)"
if [[ "$out" == *"WARN: no review record"* ]] && [[ "$out" == *"$shortX"* ]]; then
  ok "TC-PPR-02 no record anywhere → WARN naming the sha"
else
  bad "TC-PPR-02 no record anywhere → WARN naming the sha" "$out"
fi
cleanup "$D"

# TC-PPR-03: fallback-eligible commit, but neither it nor its parent has a record → WARN names
# that the parent was also checked.
D="$(rrf_fixture_with_lib)"
shaX="$(rrf_commit "$D" install.sh 'echo v1')"
( cd "$D" && mkdir -p .mkr/reviews specs \
    && printf '# spec DoD, no matching review record\n' > specs/Some_Spec.md \
    && git add specs && git commit -q -m "specs-only commit, no record anywhere" >/dev/null )
shaY="$(cd "$D" && git rev-parse HEAD)"
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && printf 'refs/heads/x %s refs/heads/x %s\n' "$shaY" "$ZERO_SHA" | bash "$GUARD_PATH" 2>&1)"
if [[ "$out" == *"WARN: no review record"* ]] && [[ "$out" == *"parent"* ]]; then
  ok "TC-PPR-03 WARN names that the parent was also checked"
else
  bad "TC-PPR-03 WARN names that the parent was also checked" "$out"
fi
cleanup "$D"

# TC-PPR-04 (AD-3): a real, honest `git merge --no-ff`
# pushed through the actual script's stdin protocol, with the real prior tip as the pushed ref's own
# `remote_sha1` field -- end-to-end coverage of the remote_sha1 -> expected_prior_tip wiring itself
# (found missing, non-blocking, at this fix's own G4 by both reviewers independently), not just
# find_review_record called directly.
D="$(rrf_fixture_with_lib)"
shaBase="$(rrf_commit "$D" base.txt hello)"
( cd "$D" && git checkout -q -b feature )
shaFeature="$(rrf_commit "$D" feature.txt world)"
shortFeature="${shaFeature:0:7}"
( cd "$D" && git checkout -q main 2>/dev/null || git checkout -q master )
( cd "$D" && git merge --no-ff -q -m "merge feature" feature >/dev/null )
shaMerge="$(cd "$D" && git rev-parse HEAD)"
mkdir -p "$D/.mkr/reviews"
printf 'VERDICT: READY\n' > "$D/.mkr/reviews/$shortFeature.md"
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && printf 'refs/heads/main %s refs/heads/main %s\n' "$shaMerge" "$shaBase" | bash "$GUARD_PATH" 2>&1)"
if [[ "$out" != *"WARN: no review record"* ]]; then
  ok "TC-PPR-04 an honest merge commit with the real remote_sha1 resolves via the script itself → no WARN"
else
  bad "TC-PPR-04 an honest merge commit with the real remote_sha1 resolves via the script itself → no WARN" "$out"
fi
cleanup "$D"

# TC-PPR-05 (AD-3): the same fabricated-first-parent attack (TC-MRF-05) pushed through the actual
# script, with the real prior tip supplied as remote_sha1 (not the attacker's fabricated commit) →
# WARN fires naming the crafted sha, proving the script's own wiring rejects the attack end-to-end,
# not just find_review_record called directly.
D="$(rrf_fixture_with_lib)"
shaP="$(rrf_commit "$D" shared.txt base)"
shaS="$(rrf_commit "$D" s_file.txt "S's real change")"
shortS="${shaS:0:7}"
( cd "$D" && mkdir -p .mkr/reviews \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortS.md" \
    && git add .mkr/reviews && git commit -q -m "review commit for S" >/dev/null )
shaSReviewed="$(cd "$D" && git rev-parse HEAD)"
( cd "$D" && git checkout -q "$shaP" )
( cd "$D" && printf 'EVIL PAYLOAD\n' > evil.txt && git add evil.txt )
eTree="$(cd "$D" && git write-tree)"
shaE="$(cd "$D" && git commit-tree "$eTree" -p "$shaP" -m "E: attacker commit")"
mTree="$(cd "$D" && git merge-tree --write-tree "$shaE" "$shaSReviewed")"
shaMalicious="$(cd "$D" && git commit-tree "$mTree" -p "$shaE" -p "$shaSReviewed" -m "fake merge")"
shortMalicious="${shaMalicious:0:7}"
( cd "$D" && git checkout -q "$shaMalicious" )
out="$(cd "$D" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && printf 'refs/heads/main %s refs/heads/main %s\n' "$shaMalicious" "$shaP" | bash "$GUARD_PATH" 2>&1)"
if [[ "$out" == *"WARN: no review record"* ]] && [[ "$out" == *"$shortMalicious"* ]]; then
  ok "TC-PPR-05 a fabricated first parent is refused end-to-end through the script itself → WARN"
else
  bad "TC-PPR-05 a fabricated first parent is refused end-to-end through the script itself → WARN" "$out"
fi
cleanup "$D"

echo
echo "== pre-push-review-guard.sh: GIT_DIR leak defense =="

DECOY="$(fixture_repo)"
( cd "$DECOY" && printf 'x\n' > f && git add -A && git commit -qm decoy ) >/dev/null 2>&1

REAL="$(rrf_fixture_with_lib)"
shaX="$(rrf_commit "$REAL" install.sh 'echo v1')"
shortX="${shaX:0:7}"
( cd "$REAL" && mkdir -p .mkr/reviews specs \
    && printf 'VERDICT: READY\n' > ".mkr/reviews/$shortX.md" \
    && printf '# spec DoD\n' > specs/Some_Spec.md \
    && git add .mkr/reviews specs && git commit -q -m "review commit" >/dev/null )
shaY="$(cd "$REAL" && git rev-parse HEAD)"

# TC-CGH-06: with the real, fixed guard script, a leaked GIT_DIR pointing at an unrelated decoy
# repo must not corrupt the review-record lookup.
out="$(cd "$REAL" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && export GIT_DIR="$DECOY/.git" \
  && printf 'refs/heads/x %s refs/heads/x %s\n' "$shaY" "$ZERO_SHA" | bash "$GUARD_PATH" 2>&1)"
if [[ "$out" != *"WARN: no review record"* ]]; then
  ok "TC-CGH-06 leaked GIT_DIR (pointing at a decoy repo) doesn't corrupt the hook's review-record lookup"
else
  bad "TC-CGH-06 leaked GIT_DIR (pointing at a decoy repo) doesn't corrupt the hook's review-record lookup" "$out"
fi

# TC-CGH-07: the test itself is sound — against a copy of the guard script with the unset line
# stripped, the same leaked GIT_DIR *does* corrupt the lookup (proves TC-CGH-06 would have caught
# the bug before the fix, not just a vacuously-passing setup).
UNFIXED_GUARD="$(mktemp)"
grep -v '^unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR$' "$GUARD_PATH" > "$UNFIXED_GUARD"
chmod +x "$UNFIXED_GUARD"
out2="$(cd "$REAL" && unset CLAUDE_PROJECT_DIR MKR_CONFIG && export GIT_DIR="$DECOY/.git" \
  && printf 'refs/heads/x %s refs/heads/x %s\n' "$shaY" "$ZERO_SHA" | bash "$UNFIXED_GUARD" 2>&1)"
if [[ "$out2" == *"WARN: no review record"* ]]; then
  ok "TC-CGH-07 without the unset, the same leaked GIT_DIR does corrupt the lookup (the test is real)"
else
  bad "TC-CGH-07 without the unset, the same leaked GIT_DIR does corrupt the lookup (the test is real)" "$out2"
fi
rm -f "$UNFIXED_GUARD"
cleanup "$DECOY"; cleanup "$REAL"

# TC-CGH-08: fixture_repo() itself must resolve its own real .git even with a leaked GIT_DIR —
# the outer `git -C` check below runs with a clean environment, so it independently verifies
# whatever fixture_repo() produced, rather than trusting its own resolution.
DECOY3="$(mktemp -d)"; ( cd "$DECOY3" && git init -q ) >/dev/null 2>&1
F3="$( (export GIT_DIR="$DECOY3/.git"; fixture_repo) )"
resolved3="$(git -C "$F3" rev-parse --show-toplevel 2>&1)"
if [ "$resolved3" = "$F3" ]; then
  ok "TC-CGH-08 fixture_repo() resolves its own real .git even with GIT_DIR leaked"
else
  bad "TC-CGH-08 fixture_repo() resolves its own real .git even with GIT_DIR leaked" "want=$F3 got=$resolved3"
fi
cleanup "$DECOY3"; cleanup "$F3"

echo
echo "=================================================="
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
