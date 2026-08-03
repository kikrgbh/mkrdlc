#!/usr/bin/env bash
# PreToolUse/Bash guard (specs/M3_Guardrails_Spec.md §7.2). BLOCK tier (docs/DESIGN.md §4).
#
# Denies a `git add`/`git commit` whose about-to-be-staged-or-committed content matches a
# fixed, documented credential pattern set. Not configurable in v1 (spec §3) — growing the
# config contract on a hypothetical false negative would be speculative abstraction.
set -uo pipefail

ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
if [ -z "$ROOT" ]; then exit 0; fi   # not inside a git work tree — nothing to scan, fail open

# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/config.sh"
# shellcheck source=/dev/null
. "$ROOT/.claude/hooks/lib/hookio.sh"

IN="$(hookio_stdin)"
CMD="$(hookio_field "$IN" tool_input.command)"

# Fast path: most Bash calls aren't git at all. Unanchored, not `^...` — a Claude Code Bash
# tool call is often a multi-statement script (`cmd1; cmd2 && cmd3`), so `git add`/`git commit`
# is frequently NOT the first token. Missing that here would mean this guard silently never
# fires on the exact shape of command it exists to catch (found live during this milestone's
# own dogfooding). Loose on purpose — the precise
# per-segment check below is what actually decides; this only skips the common case fast.
if ! printf '%s' "$CMD" | grep -Eq '\bgit\b.*\b(add|commit)\b'; then
  exit 0
fi

PATTERNS=(
  'AKIA[0-9A-Z]{16}'
  'ASIA[0-9A-Z]{16}'
  '\-\-\-\-\-BEGIN (RSA |EC |OPENSSH |DSA |)?PRIVATE KEY\-\-\-\-\-'
  'gh[pousr]_[A-Za-z0-9]{36}'
  'xox[baprs]-[A-Za-z0-9-]{10,}'
)
LABELS=(
  'AWS access key ID'
  'AWS access key ID'
  'PEM private key header'
  'GitHub token'
  'Slack token'
)

scan() {                             # scan <content> — prints the matched label, or nothing
  local content="$1" i
  for i in "${!PATTERNS[@]}"; do
    if printf '%s' "$content" | grep -Eq -- "${PATTERNS[$i]}"; then
      printf '%s' "${LABELS[$i]}"
      return 0
    fi
  done
  return 1
}

# A compound command means "git add"/"git commit" can appear anywhere, and more than once, and
# with global flags between "git" and the subcommand (e.g. `git -C <dir> add ...`) — split into
# top-level statements first (hookio_split_statements — quote-aware, so a literal `;`/`&`/`|`
# inside a quoted commit message doesn't truncate a statement early and hide a trailing flag;
# an earlier, naive `[^;&|]*`-based extraction did exactly that and was an adversarial-review-
# caught bypass in itself), then classify each statement that mentions git add/commit.
#
# Two content-gathering modes, chosen per statement: a *wildcard* add/commit (`-A`, `.`, `--all`,
# `-a`, or `git add` with no path arguments at all) stages everything the working tree currently
# has to offer, so it is scanned broadly (staged + unstaged-tracked + untracked). A *targeted*
# add (explicit filenames) is scanned narrowly — just those paths — so an unrelated stray
# untracked scratch file elsewhere in the tree never becomes a false positive on someone else's
# commit (tests/hooks_test.sh's own TC-M3-02 caught that overcorrection during this milestone's
# self-review). Getting this split wrong in the *narrow* direction is the security-reviewer-found
# defect this rewrite fixes: `git add -A && git commit -m x` — a single, entirely ordinary
# one-liner, not a contrived bypass — used to add zero content to the scan at all, because `-A`
# was skipped as "just a flag" and `git commit`'s pre-existing-`git diff --cached` read ran
# before `-A`'s own effect had happened (PreToolUse fires before the real command executes).
wildcard=0
content=""
while IFS= read -r -d '' statement; do
  [ -z "$statement" ] && continue
  if ! printf '%s' "$statement" | grep -Eq '\bgit\b.*\b(add|commit)\b'; then continue; fi
  segment="$statement"
  if printf '%s' "$segment" | grep -Eq '\bcommit\b'; then
    content="$content
$(cd "$ROOT" && git diff --cached -U0 2>/dev/null)"
    # `-a`/`--all` alone, or bundled into a short-flag cluster like `-am`/`-ma` (git's normal
    # bundled-short-option syntax — arguably more common in practice than `-a -m` separately).
    # An earlier revision only matched a standalone `-a` token and missed `-am`, a real
    # adversarial-review-caught bypass.
    if printf '%s' "$segment" | grep -Eq '(^|[[:space:]])(-[a-zA-Z]*a[a-zA-Z]*|--all)([[:space:]]|$)'; then
      wildcard=1
    fi
  elif printf '%s' "$segment" | grep -Eq '\badd\b'; then
    # `git [flags] add <paths...>` — strip through the last "add" word (flags like `-C <dir>`
    # may precede it); the paths aren't staged yet at hook time, so read them directly.
    paths="$(printf '%s' "$segment" | sed -E 's/^.*\badd\b[[:space:]]*//')"
    saw_path=0
    for p in $paths; do
      # A single matching pair of quotes survives hookio_field's JSON-unescape as literal
      # characters (word-splitting an already-expanded variable does not strip them the way
      # real shell syntax would) — strip one pair so a defensively-quoted plain filename
      # (no spaces, no variable) still resolves to a real path instead of silently matching
      # nothing (another adversarial-review-caught bypass). A filename
      # containing a space, or a variable-indirected path, remains a disclosed residual limit
      # (§7.2) — this only recovers the common "just quoted for habit" case.
      p="${p#\"}"; p="${p%\"}"; p="${p#\'}"; p="${p%\'}"
      case "$p" in
        -A|--all|-a|.) wildcard=1 ;;
        -*) continue ;;              # other flags (-f, -v, -n, ...) — neither path nor wildcard
        *)
          saw_path=1
          if [ -f "$ROOT/$p" ]; then
            content="$content
$(cat "$ROOT/$p" 2>/dev/null)"
          elif [ -f "$p" ]; then
            content="$content
$(cat "$p" 2>/dev/null)"
          fi
          ;;
      esac
    done
    [ "$saw_path" -eq 0 ] && wildcard=1   # `git add` with no path/flag args at all also means "everything"
  fi
done < <(hookio_split_statements "$CMD")

if [ "$wildcard" -eq 1 ]; then
  content="$content
$(cd "$ROOT" && git diff --cached -U0 2>/dev/null)
$(cd "$ROOT" && git diff -U0 2>/dev/null)"
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    p="${line#???}"
    [ -f "$ROOT/$p" ] && content="$content
$(cat "$ROOT/$p" 2>/dev/null)"
  done < <(cd "$ROOT" && git status --porcelain --untracked-files=all 2>/dev/null | grep '^??')
fi

label="$(scan "$content")" || exit 0
hookio_pretooluse_decision deny "staged content matches a $label pattern — remove it before committing (secret-guard.sh, docs/DESIGN.md §4)"
exit 0
