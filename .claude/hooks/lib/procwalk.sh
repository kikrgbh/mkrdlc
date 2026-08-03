#!/usr/bin/env bash
# mkr-aidlc — /proc-walk collision check and cd/-C-aware target-directory resolver.
# Sourced only, never executed, matching hookio.sh's/
# config.sh's own convention.
#
# Rebuilt in pure bash from a sibling private repo's lib/foreign-cwd.mjs and
# lib/resolve-target-dir.mjs (§6 AD-2/AD-3) — /proc is plain files, directly walkable without
# Node, per CLAUDE.md's Stack line.
#
# Requires bash 4.0+ (associative arrays), matching config.sh's own baseline.

procwalk_foreign_cwd() {              # procwalk_foreign_cwd <dir>
  # Prints "  pid <N>: <cmdline>" (one line per hit) and returns 1 if any live process outside
  # this session's own process tree has <dir> as its cwd right now; prints nothing and returns 0
  # if the directory is idle, unreadable, or /proc doesn't exist.
  local dir="$1" proc="${PROCWALK_PROC_ROOT:-/proc}"
  [ -d "$proc" ] || return 0            # AD-4 path 1: /proc unavailable — fail open, no error

  local target
  target="$(cd -- "$dir" 2>/dev/null && pwd -P)"
  [ -z "$target" ] && return 0

  # Single pass over /proc: collect every live pid's PPid and comm.
  local pids=() pid_dir pid ppid comm
  local -A ppid_of=() comm_of=()
  for pid_dir in "$proc"/[0-9]*; do
    [ -d "$pid_dir" ] || continue
    pid="${pid_dir##*/}"
    ppid="$(sed -n 's/^PPid:[[:space:]]*//p' "$pid_dir/status" 2>/dev/null)"
    comm="$(cat "$pid_dir/comm" 2>/dev/null)"
    pids+=("$pid")
    ppid_of["$pid"]="$ppid"
    comm_of["$pid"]="$comm"
  done

  # This process's own real identity: $BASHPID, not $$ — $$ is stale inside a command-substitution
  # subshell (bash preserves $$ from the top-level shell, e.g. this very function's own caller,
  # `hits="$(procwalk_foreign_cwd ...)"`, across every nested subshell), so it can silently name a
  # process other than the one actually running right now.
  local self_pid="${BASHPID:-$$}"

  # This session's own root: nearest ancestor of $self_pid whose comm matches "claude" (AD-5/§7.2).
  # Every ancestor visited on the way up is unconditionally self too, marked individually — never
  # expanding into any of *their* other children/siblings (AD-1). This matters: an ancestor several
  # levels up may itself be a shared subreaper (e.g. a container's own init, or `systemd --user`
  # locally) that has *unrelated* orphaned processes reparented to it too — a genuinely foreign
  # collision, from a different fixture or session entirely, that happens to share that same distant
  # ancestor. Only the exact chain from $self_pid up to root is self; a real foreign process
  # reparented elsewhere under that same ancestor is never swept in by association.
  local -A is_self=()
  local p="$self_pid" root="" matched=0
  while [ -n "$p" ] && [ "$p" != "1" ]; do
    is_self["$p"]=1
    if [ -z "${PROCWALK_SELF_TEST_FORCE_NO_CLAUDE-}" ] \
      && printf '%s' "${comm_of[$p]-}" | grep -qi 'claude'; then
      root="$p"; matched=1; break
    fi
    p="${ppid_of[$p]-}"
  done
  # No claude ancestor (a direct/CI invocation, AD-5): self-root falls back to $self_pid itself for
  # the *descendant* side of the self set below (things this exact process spawns) — $self_pid's
  # own ancestors are already included above unconditionally (AD-1), without expanding into any of
  # those ancestors' other, unrelated descendants.
  [ "$matched" -eq 0 ] && root="$self_pid"

  # Self set: every ancestor of $self_pid (already marked above), plus root and every descendant of
  # root — a plain BFS over a children map (built in one pass below), each pid visited exactly once.
  # An append-only array with a read index (rather than `unset`-ing a consumed slot) avoids negative
  # array-index syntax, which needs bash 4.3+ and would violate this project's own stated 4.0+ floor.
  local -A children=()
  for pid in "${pids[@]}"; do
    p="${ppid_of[$pid]-}"
    [ -n "$p" ] && children["$p"]+="$pid "
  done

  is_self["$root"]=1
  local -a queue=("$root")
  local qi=0 cur c
  while [ "$qi" -lt "${#queue[@]}" ]; do
    cur="${queue[$qi]}"
    qi=$((qi + 1))
    for c in ${children[$cur]-}; do
      if [ -z "${is_self[$c]-}" ]; then
        is_self["$c"]=1
        queue+=("$c")
      fi
    done
  done

  local hits="" cwd cmdline
  for pid in "${pids[@]}"; do
    [ -n "${is_self[$pid]-}" ] && continue
    cwd="$(readlink "$proc/$pid/cwd" 2>/dev/null)"
    [ -z "$cwd" ] && continue
    [ "$cwd" != "$target" ] && continue
    cmdline="$(tr '\0' ' ' < "$proc/$pid/cmdline" 2>/dev/null)"
    cmdline="${cmdline% }"
    [ -z "$cmdline" ] && cmdline="(unknown command)"
    hits+="  pid $pid: $cmdline"$'\n'
  done

  if [ -n "$hits" ]; then
    printf '%s' "$hits"
    return 1
  fi
  return 0
}

procwalk_strip_comment() {            # procwalk_strip_comment <statement>
  # Truncates at the first unquoted '#' that starts a real shell comment (preceded by
  # whitespace, or at the very start of the statement) — an ordinary quoted '#' (e.g. a commit
  # message "issue #123") is never a comment and is left untouched. hookio_split_statements'
  # own quote-aware walk splits on `;`/`&`/`|`/newline but never strips comments, so a bare regex
  # or token match against a raw statement — as every keyword/exclude match in this file does —
  # can be fooled by comment text sitting in the same statement as a real command: a genuine,
  # live `git switch other-branch # note: checkout details -- fyi` statement contains the
  # literal substrings "checkout" and "-- " only inside its own trailing comment, which would
  # otherwise satisfy a naive exclude check and silently defeat the whole gate — found on G4
  # re-review. Callers apply this to each statement
  # before any keyword/exclude matching, never before hookio_split_statements' own splitting (a
  # `#` must not be treated as a statement separator itself, only as truncating the one statement
  # it appears in).
  local s="$1"
  local i=0 n=${#s} c in_squote=0 in_dquote=0 prev=' '
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$in_squote" -eq 1 ]; then
      [ "$c" = "'" ] && in_squote=0
    elif [ "$in_dquote" -eq 1 ]; then
      if [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
        i=$((i + 1))
      elif [ "$c" = '"' ]; then
        in_dquote=0
      fi
    elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
      i=$((i + 1))
    else
      case "$c" in
        "'") in_squote=1 ;;
        '"') in_dquote=1 ;;
        '#')
          case "$prev" in
            ' ' | $'\t') printf '%s' "${s:0:$i}"; return 0 ;;
          esac
          ;;
      esac
    fi
    prev="$c"
    i=$((i + 1))
  done
  printf '%s' "$s"
}

procwalk_has_command_substitution() { # procwalk_has_command_substitution <statement>
  # True (rc 0) iff <statement> contains `$(`/backtick/`<(`/`>(` anywhere — a real,
  # independently-executing nested command or subprocess, invisible to the flat whitespace
  # tokenizer both `procwalk_checkout_pathspec_form` and the `-C`/`cd` extraction below rely on.
  # `git checkout -- $(git checkout evilbranch)` and `git checkout -- <(git checkout evilbranch)`
  # are both real, ordinary-looking one-liners: bash evaluates the substitution/process
  # substitution *first*, as a genuine `git checkout evilbranch` invocation with its own side
  # effect (a real branch switch, or a live subprocess set up via the substitution's fd), before
  # the outer, harmless-looking `checkout -- <result>` no-op ever runs — and the tokenizer sees
  # only a flat word list, with no concept that inner tokens belong to a separate,
  # already-executing command; found on G4 re-review (`$(`/backtick first, `<(`/`>(` — an
  # ordinary, first-class bash feature, not an exotic one — on the very next round). Correctly
  # parsing nested substitution boundaries needs a real shell parser — squarely the same "full
  # shell parser" scope this project's own guardrail-hook precedent already ruled out for
  # arithmetic expansion and here-documents. The backstop here is not "understand it correctly," it's "never trust a
  # statement enough to exclude or misdirect it once this is present" — both callers below fail
  # toward *more* scrutiny (never excluding, never trusting an embedded `-C`) rather than toward
  # silence.
  case "$1" in
    *'$('*|*'`'*|*'<('*|*'>('*) return 0 ;;
    *) return 1 ;;
  esac
}

procwalk_split_tagged() {             # procwalk_split_tagged <cmd>
  # NUL-terminated pairs, <tag>\0<statement>\0 for each statement — the same statement content
  # and boundaries `hookio_split_statements` would yield, but each one tagged "S" (safe: the
  # separator immediately preceding it is `;`/`&&`/`||`/newline — real, same-shell sequential
  # execution) or "U" (unsafe: a bare, single `&` or `|` — forks a subshell, so whatever a
  # preceding `cd` did never propagates across this specific boundary). The very first statement
  # is always "S" (nothing precedes it to distrust).
  #
  # A faithful, independent re-walk of `hookio_split_statements`' own character-by-character
  # logic (quote tracking, backslash/continuation handling, the `&`-vs-redirect check) — not a
  # wrapper around it — because the boundary *type*, not just the split point, is new
  # information that function doesn't track or expose, and this keeps that shared,
  # already-adversarially-hardened function (also used by secret-guard.sh/branch-guard.sh)
  # completely unchanged. Two deliberate differences from it, both required for correctness here:
  # `&&`/`||` are recognized as doubled, atomic, *safe* separators (consuming both characters,
  # emitting one tag) rather than two independent single-character flushes — a naive
  # whole-command "does any bare `&`/`|` exist anywhere" check (an earlier version of this fix)
  # wrongly distrusted a `cd` that was actually joined by a completely safe `&&`/`||` elsewhere
  # in the same command, purely because an *unrelated* real pipe/background sat somewhere else in
  # it — found on G4 re-review, tracing real bash's own command-grouping rules by hand: `&`/`|`
  # only fork the specific command(s) immediately adjacent to them, never anything connected via
  # a later, different operator.
  #
  # Why per-statement tagging, not per-command: a `cd` statement always updates the tracked
  # directory unconditionally when matched (its own preceding tag is irrelevant to whether *it*
  # runs for real — bash's own grouping already determines that structurally, and empirically
  # tracing several compound cases by hand confirmed this composes correctly); what actually
  # matters is the tag on whatever statement *consumes* that tracked value next. The caller
  # resets its own tracked directory to empty the moment it sees a statement tagged "U" — placing
  # the reset at the boundary itself, not "the whole rest of the command," so a later, genuinely
  # safe `cd` (after the unsafe boundary) can still be trusted again.
  local s="$1"
  local i=0 n=${#s} c buf="" in_squote=0 in_dquote=0 nxt_i buf_last tag="S"
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$in_squote" -eq 1 ]; then
      buf+="$c"
      [ "$c" = "'" ] && in_squote=0
    elif [ "$in_dquote" -eq 1 ]; then
      if [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ] && [ "${s:$((i + 1)):1}" = $'\n' ]; then
        i=$((i + 1))
      elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
        buf+="$c"
        i=$((i + 1))
        buf+="${s:$i:1}"
      else
        buf+="$c"
        [ "$c" = '"' ] && in_dquote=0
      fi
    elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ] && [ "${s:$((i + 1)):1}" = $'\n' ]; then
      i=$((i + 1))
    elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
      buf+="$c"
      i=$((i + 1))
      buf+="${s:$i:1}"
    else
      case "$c" in
        "'") in_squote=1; buf+="$c" ;;
        '"') in_dquote=1; buf+="$c" ;;
        '&')
          nxt_i=$((i + 1))
          while [ "${s:$nxt_i:1}" = '\' ] && [ $((nxt_i + 1)) -lt "$n" ] && [ "${s:$((nxt_i + 1)):1}" = $'\n' ]; do
            nxt_i=$((nxt_i + 2))
          done
          buf_last="${buf:$((${#buf} - 1)):1}"
          if [ "$buf_last" = '>' ] || [ "$buf_last" = '<' ] || [ "${s:$nxt_i:1}" = '>' ]; then
            buf+="$c"
          elif [ "${s:$nxt_i:1}" = '&' ]; then
            printf '%s\0%s\0' "$tag" "$buf"; buf=""; tag="S"
            i="$nxt_i"
          else
            printf '%s\0%s\0' "$tag" "$buf"; buf=""; tag="U"
          fi
          ;;
        '|')
          if [ "${s:$((i + 1)):1}" = '|' ]; then
            printf '%s\0%s\0' "$tag" "$buf"; buf=""; tag="S"
            i=$((i + 1))
          else
            printf '%s\0%s\0' "$tag" "$buf"; buf=""; tag="U"
          fi
          ;;
        ';' | $'\n') printf '%s\0%s\0' "$tag" "$buf"; buf=""; tag="S" ;;
        *) buf+="$c" ;;
      esac
    fi
    i=$((i + 1))
  done
  printf '%s\0%s\0' "$tag" "$buf"
}

procwalk_checkout_pathspec_form() {   # procwalk_checkout_pathspec_form <statement>
  # True (rc 0) iff <statement>'s real git subcommand — the token immediately after `git`
  # (skipping an optional `-C <dir>` pair), found by whitespace tokenizing, not a regex
  # word-boundary test — is literally `checkout`, AND a standalone `--` token appears anywhere
  # after it (`checkout`'s own file-path/pathspec-restore mode). `switch` never returns true
  # here — it has no such mode at all, so a `--` anywhere in a `switch` invocation is always
  # just the ordinary end-of-options marker, never a reason to exclude it.
  #
  # Deliberately whitespace-tokenized (`read -ra`), not `\bcheckout\b`/`\b--\b`-style regex
  # matching against the raw string: a regex word boundary fires on *any* transition between a
  # word character and a non-word one, including a bare hyphen — so `\bcheckout\b` matches
  # "checkout" as a substring of an entirely ordinary, real branch name like
  # `run-checkout-now` or `fix-checkout-crash`, even though that name is one single token to
  # bash, never three. `git switch -c run-checkout-now -- other-branch` — a real, valid,
  # executing branch switch, using `--` only as `switch`'s own ordinary start-point
  # disambiguator — would satisfy a bare substring/word-boundary exclude check and bypass every
  # caller of this predicate entirely; found on G4 re-review. Whitespace tokenizing treats
  # `run-checkout-now` as one token that can never equal bare `checkout`, closing this off
  # structurally rather than adding another special case. Quoting is not reconstructed (a
  # quoted `--` keeps its quote characters and so never equals bare `--`, and a quoted
  # `checkout` never equals the bare subcommand token either) — both directions fail toward
  # treating the statement as a real, gated switch/checkout rather than silently excluding it,
  # the safe direction for a security-relevant guard.
  local statement="$1"
  procwalk_has_command_substitution "$statement" && return 1
  local -a tokens=()
  local i=0 n j subcmd_idx=-1 k
  read -ra tokens <<< "$statement"
  n="${#tokens[@]}"
  while [ "$i" -lt "$n" ]; do
    if [ "${tokens[$i]}" = "git" ]; then
      j=$((i + 1))
      if [ "${tokens[$j]-}" = "-C" ]; then j=$((j + 2)); fi
      case "${tokens[$j]-}" in
        checkout) subcmd_idx="$j" ;;
        switch) return 1 ;;
      esac
      i="$j"
      continue
    fi
    i=$((i + 1))
  done
  [ "$subcmd_idx" -lt 0 ] && return 1
  for ((k = subcmd_idx + 1; k < n; k++)); do
    [ "${tokens[$k]}" = "--" ] && return 0
  done
  return 1
}

procwalk_resolve_target_dir() {       # procwalk_resolve_target_dir <json> <keyword-regex> [<exclude-fn>]
  # Prints the best-guess absolute/relative directory the last command segment matching
  # <keyword-regex> (and for which the optional <exclude-fn> — a predicate function name, called
  # as `"$exclude_fn" "$statement"` — does NOT return true; e.g. a bare `checkout -- <path>`
  # file-path form the caller has already decided never counts as a real match —
  # worktree-collision-guard.sh passes `procwalk_checkout_pathspec_form` here so a decoy
  # `git checkout -- <path>` segment is skipped for resolution exactly as it is for the caller's
  # own gating decision, not just excluded from the count while still able to hijack which
  # directory gets resolved) actually targets: an explicit
  # `git -C <dir>` on that segment, else the most recent preceding `cd <dir>` in the same command,
  # else the JSON payload's own `cwd` field, else nothing (caller supplies its own final
  # fallback). Segments come from procwalk_split_tagged, a boundary-aware variant of
  # hookio_split_statements (§6 AD-2/§11 finding (15)).
  local json="$1" keyword_re="$2" exclude_fn="${3-}" cmd cwd_field tag statement current_dir="" resolved=""
  local pending_dir="" pending_is_cd=0
  cmd="$(hookio_field "$json" tool_input.command)"
  cwd_field="$(hookio_field "$json" cwd)"

  while IFS= read -r -d '' tag && IFS= read -r -d '' statement; do
    # A `cd`'s own update is never committed to `current_dir` (the trusted value later statements
    # may use) immediately — it sits in `pending_dir` until the *next* statement's own tag proves
    # the boundary right after that `cd` was safe. Committing immediately and unconditionally (an
    # earlier version of this fix) clobbered a still-valid, already-committed `current_dir` when a
    # SECOND `cd` — itself about to be forked away by ITS OWN following unsafe boundary — appeared
    # in between: `cd A && cd B | git checkout other-branch` really executes the checkout in `A`
    # (the pipeline forks from the shell's state right after `cd A`, and `cd B`'s own effect is
    # confined to its own subshell), but immediate-unconditional-overwrite left `current_dir=B`
    # and then blanked it entirely on the following unsafe `|` tag, losing `A` too; found on G4
    # re-review, hand-traced against several compound bash-grouping cases (including this one,
    # and the earlier `cd A & cd C | someCommand; git checkout D` case, which correctly still
    # resolves to nothing/fallback either way). A safe ("S") tag promotes whatever the *previous*
    # statement's own `cd` set into `current_dir`; an unsafe ("U") tag discards it instead,
    # leaving `current_dir` — and therefore anything committed *before* that pending value —
    # untouched.
    if [ "$pending_is_cd" -eq 1 ]; then
      [ "$tag" = "S" ] && current_dir="$pending_dir"
      pending_is_cd=0
    fi
    statement="$(procwalk_strip_comment "$statement")"
    if [[ "$statement" =~ ^[[:space:]]*cd[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+) ]]; then
      pending_dir="${BASH_REMATCH[1]}"
      pending_dir="${pending_dir%\"}"; pending_dir="${pending_dir#\"}"
      pending_dir="${pending_dir%\'}"; pending_dir="${pending_dir#\'}"
      pending_is_cd=1
      continue
    fi
    if ! printf '%s' "$statement" \
        | grep -Eq "(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(${keyword_re})([[:space:]]|\$)"; then
      continue
    fi
    if [ -n "$exclude_fn" ] && "$exclude_fn" "$statement"; then
      continue
    fi
    # `-C` is extracted only from the *start* of the statement (after optional leading
    # whitespace) — `git` immediately followed by `-C`, mirroring the `cd` extraction's own
    # anchor above — never from anywhere later in the raw text. An unanchored match would happily
    # pick up a "git -C <dir>" substring sitting inside unrelated quoted data (e.g. a commit
    # message: `git commit -m "see also: git -C /real-worktree status"`), extracting a
    # fabricated target from message *content*, not the real command's own flag — found on G4
    # re-review, the same "text that's inert to real execution misread as a real token" failure
    # class this file has now closed for a comment (`procwalk_strip_comment`), a hyphenated
    # branch name (`procwalk_checkout_pathspec_form`), and a substitution
    # (`procwalk_has_command_substitution`) — closed here at its root the same way `cd`'s own
    # extraction always was, by anchoring to the statement's actual start.
    #
    # An extracted `-C <dir>` value is additionally trusted only if the captured value ITSELF
    # contains no embedded substitution — not "the whole statement contains one anywhere," which
    # would distrust a real, unambiguous `-C /real/dir` merely because an unrelated, inert
    # `$(...)`/`<(...)` sits elsewhere in the same statement — a regression an earlier version of
    # this same guard introduced, found on G4 re-review. A `-C` value that IS itself a
    # substitution (`git -C $(evil) checkout ...`) still falls through to `current_dir` instead.
    if [[ "$statement" =~ ^[[:space:]]*git[[:space:]]+-C[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+) ]] \
        && ! procwalk_has_command_substitution "${BASH_REMATCH[1]}"; then
      resolved="${BASH_REMATCH[1]}"
      resolved="${resolved%\"}"; resolved="${resolved#\"}"
      resolved="${resolved%\'}"; resolved="${resolved#\'}"
    else
      resolved="$current_dir"
    fi
  done < <(procwalk_split_tagged "$cmd")

  if [ -n "$resolved" ]; then
    printf '%s' "$resolved"
  elif [ -n "$cwd_field" ]; then
    printf '%s' "$cwd_field"
  fi
}

procwalk_resolve_target_dirs() {      # procwalk_resolve_target_dirs <json> <keyword-regex> [<exclude-fn>]
  # Like procwalk_resolve_target_dir, but prints one resolved directory per matching (and not
  # excluded) statement, NUL-terminated — for a caller that must check every real occurrence in a
  # multi-statement command, not just the last one. Unlike a branch switch (where only the final
  # state matters, so "the last real checkout/switch" is the whole story), each `git commit` in a
  # chain is independently consequential: `git commit -m x; cd <worktree> && git commit -m y`
  # would let an earlier, unsafe commit in the shared checkout hide behind a later, safe decoy if
  # only the last match were checked — the caller must deny the whole command if ANY occurrence
  # resolves somewhere unsafe. Each occurrence still resolves via the same three-tier precedence
  # (explicit `-C` > preceding `cd` > the payload's own `cwd` field); an occurrence with none of
  # the three prints an empty record (caller supplies its own final fallback per occurrence).
  local json="$1" keyword_re="$2" exclude_fn="${3-}" cmd cwd_field tag statement current_dir="" resolved
  local pending_dir="" pending_is_cd=0
  cmd="$(hookio_field "$json" tool_input.command)"
  cwd_field="$(hookio_field "$json" cwd)"

  while IFS= read -r -d '' tag && IFS= read -r -d '' statement; do
    # See procwalk_resolve_target_dir's own comment: a `cd`'s own update is held in `pending_dir`
    # until the next statement's tag confirms the boundary right after it was safe, rather than
    # committed to `current_dir` immediately and unconditionally.
    if [ "$pending_is_cd" -eq 1 ]; then
      [ "$tag" = "S" ] && current_dir="$pending_dir"
      pending_is_cd=0
    fi
    statement="$(procwalk_strip_comment "$statement")"
    if [[ "$statement" =~ ^[[:space:]]*cd[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+) ]]; then
      pending_dir="${BASH_REMATCH[1]}"
      pending_dir="${pending_dir%\"}"; pending_dir="${pending_dir#\"}"
      pending_dir="${pending_dir%\'}"; pending_dir="${pending_dir#\'}"
      pending_is_cd=1
      continue
    fi
    if ! printf '%s' "$statement" \
        | grep -Eq "(^|[[:space:]])git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+(${keyword_re})([[:space:]]|\$)"; then
      continue
    fi
    if [ -n "$exclude_fn" ] && "$exclude_fn" "$statement"; then
      continue
    fi
    # See procwalk_resolve_target_dir's own comment: `-C` is extracted only from the statement's
    # actual start (never from a "git -C ..." substring sitting inside unrelated quoted data,
    # e.g. a commit message), and the captured value is trusted only if it itself contains no
    # embedded substitution.
    if [[ "$statement" =~ ^[[:space:]]*git[[:space:]]+-C[[:space:]]+(\"[^\"]+\"|\'[^\']+\'|[^[:space:]]+) ]] \
        && ! procwalk_has_command_substitution "${BASH_REMATCH[1]}"; then
      resolved="${BASH_REMATCH[1]}"
      resolved="${resolved%\"}"; resolved="${resolved#\"}"
      resolved="${resolved%\'}"; resolved="${resolved#\'}"
    else
      resolved="$current_dir"
    fi
    [ -z "$resolved" ] && resolved="$cwd_field"
    printf '%s\0' "$resolved"
  done < <(procwalk_split_tagged "$cmd")
}

procwalk_is_registered_worktree() {   # procwalk_is_registered_worktree <root> <dir>
  # True (rc 0) iff <dir> is a genuine, currently-registered LINKED worktree of the repo at
  # <root> — never <root>'s own main checkout. Deliberately does NOT trust `git -C <dir>
  # rev-parse --absolute-git-dir`'s own returned *string* (a bare `*/worktrees/*` or even an
  # anchored `*.git/worktrees/*` substring test is spoofable with one ordinary command,
  # `git init --separate-git-dir=<anywhere>/.git/worktrees/<name> <dir>`, which fabricates a
  # git-dir string matching either pattern for a freshly-initialized, completely unrelated repo
  # with no actual linkage back to <root> at all). Cross-references against `git worktree
  # list`'s own authoritative registry instead: the first entry is always <root>'s own main
  # worktree (never eligible), and <dir> must resolve (realpath) to exactly one of the remaining,
  # genuinely-linked entries.
  local root="$1" dir="$2" target line path wtreal first=1
  target="$(cd -- "$dir" 2>/dev/null && pwd -P)"
  [ -z "$target" ] && return 1

  while IFS= read -r line; do
    case "$line" in
      "worktree "*)
        path="${line#worktree }"
        if [ "$first" -eq 1 ]; then first=0; continue; fi
        wtreal="$(cd -- "$path" 2>/dev/null && pwd -P)"
        [ -n "$wtreal" ] && [ "$wtreal" = "$target" ] && return 0
        ;;
    esac
  done < <(git -C "$root" worktree list --porcelain 2>/dev/null)
  return 1
}
