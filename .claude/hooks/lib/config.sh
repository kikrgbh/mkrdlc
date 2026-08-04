#!/usr/bin/env bash
# mkr-aidlc — project config reader.
#
# Two ways in:
#   source:  . "$MKR_ROOT/.claude/hooks/lib/config.sh"   then mkr_get / mkr_list   (hooks)
#   execute: config.sh get VAR [fallback] | list VAR | dump                        (skills, CI)
#
# The project config (.mkr/config) is plain shell. It is NEVER sourced into the
# caller: a child process sources it and reports back only its MKR_* assignments.
# That is what makes provenance knowable (an inherited MKR_FOO in the environment
# is not a config value) and what stops a config from reaching the caller's shell
# state at all — `exit`, `set -e`, `cd`, `kill`, `exec`, a BOM, a stray trap:
# every one of them is contained in the child.
#
# Requires bash 4.0+ (`local -`). Never calls `exit` when sourced.

# --- child mode: source the config, report its assignments, and nothing else ----
# Must come first: it runs before any option-juggling the sourced path needs.
# Guarded on BASH_SOURCE[0] = $0, not just $1/$2: a *sourced* file inherits the
# caller's positional parameters, so without this a caller whose own $1/$2 happen
# to be "--mkr-dump"/<path> would run this block — and its `exit 0` — in its own
# shell instead of a child.
#
# Two stages, not one. A config sourced into this process can define a shell
# *function* named after anything this file might call to report values back
# — not only `printf`, but `command` and `builtin` themselves: bash looks up
# functions before builtins for the literal word being invoked, and that
# applies to `command`/`builtin` as the word, not only to what follows them.
# `command printf` is not immune — a config defining `command() { ...; }`
# intercepts it, and a forged whitelist-shaped line emitted from inside that
# function reaches the parent's `eval` with a live payload. So this stage
# never reports anything itself: it only carries the resolved values, under
# an internal name, into a *second*, freshly exec'd bash process that never
# sourced the config and so never saw any function it defined. `env -i`
# starts that process from an empty environment — only PATH and the explicit
# pairs below are visible to it — so a config that tried `export -f` to
# smuggle a function across the exec boundary (the Shellshock vector) carries
# nothing over either.
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "${1-}" = "--mkr-dump" ] && [ -n "${2-}" ]; then
  IFS=$' \t\n'                       # a hostile config can reassign IFS; pin it
                                      # before every compgen-driven loop below
  for _mkr_n in $(compgen -v 2>/dev/null); do
    case "$_mkr_n" in MKR_*) unset "$_mkr_n" ;; esac
  done
  unset _mkr_n

  exec 3>&1 1>&2                     # save the real stdout on fd3; whatever the
                                      # config itself writes to stdout now lands on
                                      # stderr instead of the channel we eval
  # shellcheck source=/dev/null
  . "$2"
  _mkr_rc=$?
  exec 1>&3 3>&-                     # restore stdout for the dump only, close fd3
  if [ "$_mkr_rc" -ne 0 ]; then exit 9; fi

  IFS=$' \t\n'                       # the config may have reassigned IFS; pin it
                                      # again before the loop that depends on it
  _mkr_pairs=()
  for _mkr_n in $(compgen -v 2>/dev/null); do
    case "$_mkr_n" in
      MKR_CONFIG|MKR_CONFIG_ACTIVE|MKR_CONFIG_PATH) : ;;   # reserved: never imported
      MKR_*) _mkr_pairs+=("_mkr_src_${_mkr_n#MKR_}=${!_mkr_n}") ;;
    esac
  done
  unset _mkr_n

  exec env -i PATH="$PATH" "${_mkr_pairs[@]}" \
    "${BASH:-bash}" --noprofile --norc "$0" --mkr-dump-emit
fi

# Stage 2: a clean process that never sourced the config, so nothing it
# defined — function, alias, anything — exists here to intercept this. Same
# BASH_SOURCE[0]=$0 guard as stage 1, for the same reason; reached only by
# stage 1's own `exec` above, into an `env -i` environment stage 1 built
# itself, so nothing outside `_mkr_src_*` can reach in either.
if [ "${BASH_SOURCE[0]}" = "${0}" ] && [ "${1-}" = "--mkr-dump-emit" ]; then
  IFS=$' \t\n'
  for _mkr_n in $(compgen -v 2>/dev/null); do
    case "$_mkr_n" in
      _mkr_src_*) command printf '_mkr_cfg_%s=%q\n' "${_mkr_n#_mkr_src_}" "${!_mkr_n}" ;;
    esac
  done
  unset _mkr_n
  command printf '_mkr_ok=1\n'
  exit 0
fi

_MKR_SELF="${BASH_SOURCE[0]}"

# --- defaults: the single source of truth (a seed config ships these empty) -----
_mkr_default() {
  case "$1" in
    MKR_CONFIG_SCHEMA)      printf '1' ;;
    MKR_SPECS_DIR)          printf 'specs/' ;;
    MKR_ADR_DIR)            printf 'docs/adr/' ;;
    MKR_REVIEWS_DIR)        printf '.mkr/reviews/' ;;
    MKR_AUDITS_DIR)         printf '.mkr/audits/' ;;
    MKR_DESIGN_DIR)         printf '.mkr/designs/' ;;
    MKR_EVALS_DIR)          printf '.mkr/evals/' ;;
    MKR_CAPTURE_LOG)        printf '.mkr/captures.jsonl' ;;
    MKR_PROTECTED_BRANCHES) printf 'main' ;;
    MKR_WORKTREE_POLICY)    printf 'off' ;;
    MKR_COVERAGE_MIN)       printf '80' ;;
    MKR_SELF_APPROVE)       printf 'spec design' ;;
    MKR_PLAN_MANDATORY)     printf 'spec-first reuse-check test-first self-review verify code-review' ;;
    MKR_PLAN_OPTIONAL)      printf 'contract-first coverage-gate adr-for-risky design-before-tests auth-every-surface isolation-every-table api-parity ui-feedback-per-wave build-directive-conformance' ;;
    MKR_REVIEW_VERDICT_STRING) printf 'VERDICT: READY' ;;
    *)                      printf '' ;;
  esac
}

# Every variable the contract publishes, in table order. `dump` walks this.
_mkr_names() {
  printf '%s\n' \
    MKR_CONFIG_SCHEMA MKR_TEST MKR_STOP_TEST_MODE MKR_TEST_FAST MKR_COVERAGE MKR_TYPECHECK MKR_LINT MKR_BUILD MKR_SETUP \
    MKR_SPECS_DIR MKR_ADR_DIR MKR_REVIEWS_DIR MKR_AUDITS_DIR \
    MKR_DESIGN_DIR MKR_DEPLOY MKR_EVALS_DIR \
    MKR_PROTECTED_BRANCHES MKR_WORKTREE_POLICY MKR_COVERAGE_MIN MKR_RISKY_PATHS MKR_BOUNDARIES MKR_ID_DIRS \
    MKR_GATE_SPEC MKR_GATE_DESIGN MKR_GATE_MERGE MKR_GATE_DEPLOY MKR_GATE_REVIEW MKR_CAPTURE_LOG MKR_SELF_APPROVE \
    MKR_PLAN_MANDATORY MKR_PLAN_OPTIONAL MKR_REVIEW_VERDICT_STRING MKR_SPEC_EXTRA_SECTIONS
}

_mkr_warn() { printf 'mkr: %s\n' "$1" >&2; }

_mkr_valid_name() {
  # Anchored, so `MKR_X};id;a={` is rejected. A `case` glob cannot anchor its
  # tail — `MKR_[A-Z0-9_]*` accepts any suffix — and grep costs two forks a call.
  [[ "$1" =~ ^MKR_[A-Z0-9_]*$ ]]
}

_mkr_value() {                       # configured value, empty if none
  local slot="_mkr_cfg_${1#MKR_}"
  printf '%s' "${!slot-}"
}

# --- loading -------------------------------------------------------------------
_mkr_resolve_path() {                # prints a candidate path, or nothing
  if [ -n "${MKR_CONFIG-}" ]; then
    printf '%s' "$MKR_CONFIG"        # explicit: terminal, never falls through
  elif [ -n "${CLAUDE_PROJECT_DIR-}" ]; then
    printf '%s' "$CLAUDE_PROJECT_DIR/.mkr/config"
  else
    local root
    root="$(git rev-parse --show-toplevel 2>/dev/null)"
    if [ -n "$root" ]; then printf '%s' "$root/.mkr/config"; fi
  fi
}

_mkr_reject_bytes() {                # things `bash -n` accepts and shouldn't
  local first
  first="$(head -c 3 "$1" 2>/dev/null)"
  if [ "$first" = $'\xef\xbb\xbf' ]; then printf 'has a UTF-8 BOM'; return 0; fi
  if LC_ALL=C grep -q $'\r' "$1" 2>/dev/null; then printf 'has CRLF line endings'; return 0; fi
  printf ''
}

_mkr_load() {
  local - ; set +e +u -f            # scoped to this function; caller's $- untouched
  local _mkr_n
  for _mkr_n in $(compgen -v 2>/dev/null); do
    case "$_mkr_n" in _mkr_cfg_*) unset "$_mkr_n" ;; esac
  done
  MKR_CONFIG_ACTIVE=0
  MKR_CONFIG_PATH=""

  local cfg explicit=0 bad out safe
  cfg="$(_mkr_resolve_path)"
  if [ -n "${MKR_CONFIG-}" ]; then explicit=1; fi

  if [ -z "$cfg" ]; then return 0; fi
  if [ ! -e "$cfg" ]; then
    # Absent is the normal state of an un-adopted repo: silent, unless the caller
    # named the path itself, in which case silence would hide a typo.
    if [ "$explicit" = 1 ]; then _mkr_warn "MKR_CONFIG=$cfg does not exist; config inactive"; fi
    return 0
  fi
  if [ ! -r "$cfg" ]; then _mkr_warn "$cfg is not readable; config inactive"; return 0; fi

  bad="$(_mkr_reject_bytes "$cfg")"
  if [ -n "$bad" ]; then _mkr_warn "$cfg $bad; config inactive"; return 0; fi

  out="$(env -u BASH_ENV -u ENV "${BASH:-bash}" --noprofile --norc "$_MKR_SELF" --mkr-dump "$cfg" 2>/dev/null)"

  # Two independent guards on what reaches eval: the child already keeps the
  # config's own stdout out of this channel (see --mkr-dump above); this is the
  # second layer — only lines shaped like a namespaced assignment or the exact
  # sentinel survive, and the sentinel must match as a whole line. The suffix
  # class here must match _mkr_valid_name's own `[A-Z0-9_]*` exactly — a
  # tighter class silently drops a legal MKR_* name whose first character
  # after MKR_ is a digit (e.g. MKR_2FOO), which is otherwise a real bug: a
  # name §7.1 declares readable that the whitelist below never lets through.
  safe="$(printf '%s\n' "$out" | LC_ALL=C grep -E '^(_mkr_cfg_[A-Z0-9_]*=.*|_mkr_ok=1)$')"
  if ! printf '%s\n' "$safe" | LC_ALL=C grep -qx '_mkr_ok=1'; then
    _mkr_warn "$cfg could not be read (syntax error, or it exits/execs); config inactive"
    return 0
  fi

  eval "$safe"
  MKR_CONFIG_ACTIVE=1
  MKR_CONFIG_PATH="$(cd -- "$(dirname -- "$cfg")" 2>/dev/null && pwd)/$(basename -- "$cfg")"
  return 0
}

# --- public API ----------------------------------------------------------------
mkr_get() {                          # mkr_get VAR [fallback]
  local - ; set +e +u -f   # -f: noglob ON — a config value is never a glob to expand
  local name="${1-}" val
  if ! _mkr_valid_name "$name"; then
    _mkr_warn "mkr_get: '$name' is not a MKR_ variable name"
    return 0
  fi
  val="$(_mkr_value "$name")"
  if [ -n "$val" ]; then printf '%s\n' "$val"; return 0; fi
  if [ "$#" -ge 2 ]; then printf '%s\n' "$2"; return 0; fi
  printf '%s\n' "$(_mkr_default "$name")"
  return 0
}

mkr_list() {                         # mkr_list VAR — one item per line
  local - ; set +e +u -f   # -f: noglob ON — a config value is never a glob to expand
  local name="${1-}" val item
  if ! _mkr_valid_name "$name"; then
    _mkr_warn "mkr_list: '$name' is not a MKR_ variable name"
    return 0
  fi
  val="$(mkr_get "$name")"
  if [ -z "$val" ]; then return 0; fi
  local IFS=' '                      # space only: tabs/newlines stay inside items.
                                      # `local`, not save/restore: an IFS that was
                                      # *unset* on entry comes back unset, not "".
  for item in $val; do
    if [ -n "$item" ]; then printf '%s\n' "$item"; fi
  done
  return 0
}

_mkr_load

# --- CLI mode: the interface a skill or a CI step can call ----------------------
# A skill is markdown read by the model; it cannot source a shell library, so the
# same contract is reachable as a command. Reached only when executed, never when
# sourced, so the sourced path never risks `exit`.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  case "${1-}" in
    get)  shift; mkr_get "$@" ;;
    list) shift; mkr_list "$@" ;;
    dump) while IFS= read -r _n; do printf '%s=%s\n' "$_n" "$(mkr_get "$_n")"; done < <(_mkr_names) ;;
    path) printf '%s\n' "$MKR_CONFIG_PATH" ;;
    active) printf '%s\n' "$MKR_CONFIG_ACTIVE" ;;
    *) printf 'usage: config.sh {get VAR [fallback]|list VAR|dump|path|active}\n' >&2; exit 2 ;;
  esac
fi

return 0 2>/dev/null || :
