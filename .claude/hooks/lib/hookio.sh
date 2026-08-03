#!/usr/bin/env bash
# mkr-aidlc — shared I/O for Claude-Code settings.json tool-hooks (specs/M3_Guardrails_Spec.md §7.1).
#
# Distinct from config.sh (the config-reading library): this one reads the hook stdin JSON
# contract and emits the hook decision JSON contract. Sourced only, never executed — every
# hook script under .claude/hooks/scripts/ sources it, matching config.sh's own convention.
#
# Deliberately jq/python/node-free (CLAUDE.md's Stack: "no runtime dependency, no interpreter
# beyond what ships with a Claude Code checkout") — grep/sed/printf/bash builtins only, the
# same tool set config.sh already relies on. hookio_field reads exactly the known, shallow
# fields these hooks need via an anchored grep -E pattern; it is not a general JSON parser and
# does not handle nested objects, arrays, or a field name colliding with another field's own
# string value (AD-1, M3 spec §6).
#
# Requires bash 4.0+ (parameter-expansion substitution), matching config.sh's own baseline.

hookio_stdin() {                     # reads all of stdin once; callers pass the result around
  cat
}

hookio_field() {                     # hookio_field <json> <tool_name|tool_input.command|tool_input.file_path|session_id>
  local json="$1" key="$2" name value
  case "$key" in
    tool_name)             name="tool_name" ;;
    tool_input.command)    name="command" ;;
    tool_input.file_path)  name="file_path" ;;
    session_id)            name="session_id" ;;
    cwd)                   name="cwd" ;;
    *) return 1 ;;
  esac

  value="$(printf '%s' "$json" \
    | grep -E -o "\"${name}\"[[:space:]]*:[[:space:]]*\"(\\\\.|[^\"\\\\])*\"" \
    | head -n1)"
  if [ -z "$value" ]; then printf ''; return 0; fi

  value="${value#*:}"
  value="${value#"${value%%[![:space:]]*}"}"   # ltrim whitespace between ':' and the opening quote
  value="${value#\"}"; value="${value%\"}"

  # Unescape in the order that keeps a literal backslash from being mistaken for an escape
  # introduced by the previous substitution: quotes and newlines first, then bare backslashes.
  value="${value//\\\"/\"}"
  value="${value//\\n/$'\n'}"
  value="${value//\\\\/\\}"
  printf '%s' "$value"
}

hookio_json_escape() {               # hookio_json_escape <string> — backslash, quote, newline only
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}

hookio_pretooluse_decision() {       # hookio_pretooluse_decision allow|deny|ask [reason]
  local decision="$1" reason="${2-}"
  case "$decision" in
    allow) return 0 ;;               # no output; caller exits 0 and the tool call proceeds
    deny|ask)
      printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"%s","permissionDecisionReason":"%s"}}\n' \
        "$decision" "$(hookio_json_escape "$reason")"
      ;;
    *) return 1 ;;
  esac
}

hookio_stop_block() {                # hookio_stop_block <reason> — caller exits 0 after printing
  local reason="$1"
  printf '{"decision":"block","reason":"%s"}\n' "$(hookio_json_escape "$reason")"
}

hookio_split_statements() {          # hookio_split_statements <command> — NUL-terminated records
  # A regex-based split on `;`/`&`/`|` (character-class exclusion) is quote-unaware: a literal
  # `;` inside an ordinary quoted commit message (`git commit -m "fix: bug; more" -a` — not a
  # contrived case) gets treated as a real statement separator, truncating the segment before
  # a trailing flag like `-a` is ever seen — a real bypass an adversarial security review found
  # in secret-guard.sh. This walks the string one character at a time,
  # tracking single/double-quote state, and only splits on `;`/`&`/`|` outside any quote —
  # still no interpreter beyond bash (AD-1), just a loop instead of a regex.
  #
  # Records are NUL-terminated (`printf '%s\0'`), not newline-terminated: a single logical
  # statement can legitimately *contain* a raw newline (a multi-line quoted commit message, or
  # an ordinary backslash-newline line continuation), and a caller reading with plain
  # `while read -r line` would treat that embedded newline as its own record boundary —
  # desynchronizing the caller's view of "one statement" from this function's own quote/escape-
  # aware one. A bash string can never contain a literal NUL byte, so it is the one separator
  # guaranteed not to collide with real content. Callers must read with
  # `while IFS= read -r -d '' statement; do ... done < <(hookio_split_statements "$CMD")` —
  # an adversarial-review-caught defect found the plain-newline version of this contract still
  # let a multi-line `git push` hide its own remote/refspec from `branch-guard.sh`.
  local s="$1"
  local i=0 n=${#s} c buf="" in_squote=0 in_dquote=0 nxt_i buf_last
  while [ "$i" -lt "$n" ]; do
    c="${s:$i:1}"
    if [ "$in_squote" -eq 1 ]; then
      buf+="$c"
      [ "$c" = "'" ] && in_squote=0
    elif [ "$in_dquote" -eq 1 ]; then
      if [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ] && [ "${s:$((i + 1)):1}" = $'\n' ]; then
        i=$((i + 1))   # backslash-newline is a line *continuation* even inside double quotes —
                        # real bash elides both characters entirely, unlike every other \x escape
      elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
        buf+="$c"
        i=$((i + 1))
        buf+="${s:$i:1}"
      else
        buf+="$c"
        [ "$c" = '"' ] && in_dquote=0
      fi
    elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ] && [ "${s:$((i + 1)):1}" = $'\n' ]; then
      # A backslash-newline outside any quote is a line *continuation*, not an ordinary escape:
      # real bash elides both characters completely (`foo \<newline>bar` is the single word
      # `foobar`, with no separator inserted at all) — unlike `\;`/`\&`/etc., which keep the
      # escaped character as a literal. Treating it like any other escape left a stray literal
      # backslash sitting in the reassembled statement, which downstream per-word tokenizing in
      # branch-guard.sh/secret-guard.sh then misread as a real positional token — an
      # adversarial-review-caught defect.
      i=$((i + 1))
    elif [ "$c" = '\' ] && [ $((i + 1)) -lt "$n" ]; then
      # A bare backslash outside any quote escapes the next character universally in real
      # bash (the same mechanism `find -exec ... \;` relies on) — `foo\;bar` is one literal
      # word, not two statements. Missing this let `git commit -m foo\;bar -a` split into
      # fragments that hid the trailing `-a`, a real bypass found on adversarial re-review.
      buf+="$c"
      i=$((i + 1))
      buf+="${s:$i:1}"
    else
      case "$c" in
        "'") in_squote=1; buf+="$c" ;;
        '"') in_dquote=1; buf+="$c" ;;
        '&')
          # `&` is only a job-control/`&&` separator when it isn't part of an ordinary
          # redirection-duplication operator (`2>&1`, `>&2`) or output-and-error redirection
          # (`&>file`, `&>>file`) — both extremely common, not exotic. Missing this made
          # `git push 2>&1 origin main` hide the real refspec from branch-guard.sh entirely.
          # The *previous* character check reads `buf`'s own last
          # character, not the raw string's `i-1` — a backslash-newline continuation elides two
          # raw characters into zero, so raw-position lookback desyncs the instant a line-wrapped
          # `2>\<newline>&1` puts a continuation right before the `&` (a second, adversarial-
          # review-caught instance of this exact bug). The *next* character check still peeks the
          # raw string, skipping over any continuation first, since `buf` doesn't know the future.
          nxt_i=$((i + 1))
          while [ "${s:$nxt_i:1}" = '\' ] && [ $((nxt_i + 1)) -lt "$n" ] && [ "${s:$((nxt_i + 1)):1}" = $'\n' ]; do
            nxt_i=$((nxt_i + 2))
          done
          buf_last="${buf:$((${#buf} - 1)):1}"
          if [ "$buf_last" = '>' ] || [ "$buf_last" = '<' ] || [ "${s:$nxt_i:1}" = '>' ]; then
            buf+="$c"
          else
            printf '%s\0' "$buf"; buf=""
          fi
          ;;
        ';' | '|' | $'\n') printf '%s\0' "$buf"; buf="" ;;
        *) buf+="$c" ;;
      esac
    fi
    i=$((i + 1))
  done
  [ -n "$buf" ] && printf '%s\0' "$buf"
  return 0
}
