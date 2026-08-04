#!/usr/bin/env bash
# mkr-aidlc installer/updater — specs/M6_Installer_Spec.md, specs/M6_InstallBootstrap_Spec.md.
#
# Classifies every template-owned path under --source against .claude/mkr-manifest at --target,
# stages the result, and moves it into place, all-or-nothing per run. Only ever deletes via the
# separate, confirmation-gated --uninstall path (docs/adr/0005-install-uninstall-narrow-delete.md
# narrows §6 AD-2's original "never deletes anything" to that one, explicit case). Bash-only by
# design (§6 AD-1) — not POSIX-sh. When --source is omitted, clones --repo into a temp dir and
# uses that.
set -uo pipefail

MKR_SOURCE=""
MKR_TARGET=""
MKR_FORCE=0
MKR_DRY_RUN=0
MKR_UNINSTALL=0
MKR_CONFIRM=0
MKR_REPO="https://github.com/kikrgbh/mkrdlc.git"
HASH_TOOL=""
SAW_SOURCE=0
CLEANUP_DIRS=()

usage() {
  cat <<'EOF'
Usage: install.sh [--source PATH] [--repo URL] [--target DIR] [--force] [--dry-run]
       install.sh --uninstall [--target DIR] [--confirm]
       install.sh --help

  --source PATH   Directory containing .claude/ and seed/ (a checked-out copy of this template).
                   Default: none — if omitted, install.sh clones --repo into a temp dir and uses
                   that (requires git).
  --repo URL      Repo to clone when --source is omitted. Ignored if --source is given.
                   Default: https://github.com/kikrgbh/mkrdlc.git
  --target DIR    Target repo root. Default: the git work tree containing the current directory.
  --force         Allow overwriting a path that diverges from both the manifest and the source,
                   or an unrecorded path at a template-owned location.
  --dry-run       Classify and report, but write nothing.
  --uninstall     Remove every path recorded in .claude/mkr-manifest at --target, then the
                   manifest itself. Never touches CLAUDE.md/.mkr/config. Report-only unless
                   --confirm is also given — --uninstall alone deletes nothing.
  --confirm       Required alongside --uninstall to actually delete; ignored otherwise.
  --help          Show this message.
EOF
}

die() {
  printf 'install.sh: %s\n' "$1" >&2
  exit 1
}

parse_args() {
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --source)
        [ "$#" -ge 2 ] || die "--source requires a value"
        MKR_SOURCE="$2"; SAW_SOURCE=1; shift 2 ;;
      --repo)
        [ "$#" -ge 2 ] || die "--repo requires a value"
        MKR_REPO="$2"; shift 2 ;;
      --target)
        [ "$#" -ge 2 ] || die "--target requires a value"
        MKR_TARGET="$2"; shift 2 ;;
      --force)
        MKR_FORCE=1; shift ;;
      --dry-run)
        MKR_DRY_RUN=1; shift ;;
      --uninstall)
        MKR_UNINSTALL=1; shift ;;
      --confirm)
        MKR_CONFIRM=1; shift ;;
      --help)
        usage; exit 0 ;;
      --*)
        die "unrecognized flag: $1" ;;
      *)
        die "unexpected argument: $1" ;;
    esac
  done
}

cleanup_all() {
  local d
  for d in "${CLEANUP_DIRS[@]}"; do
    [ -n "$d" ] && rm -rf -- "$d"
  done
}

# maybe_bootstrap_source — when --source was not given, clones MKR_REPO into a temp dir and uses
# that as MKR_SOURCE (specs/M6_InstallBootstrap_Spec.md §7). No-op if
# --source was given; --repo is then silently unused, explicit --source always wins.
maybe_bootstrap_source() {
  [ "$SAW_SOURCE" -eq 1 ] && return 0
  command -v git >/dev/null 2>&1 \
    || die "no --source given and git is not available to bootstrap one from --repo — pass --source instead, or install git"
  local tmp
  tmp="$(mktemp -d)" || die "mktemp failed"
  CLEANUP_DIRS+=("$tmp")
  printf 'install.sh: no --source given — cloning %s into %s\n' "$MKR_REPO" "$tmp" >&2
  # GIT_ALLOW_PROTOCOL restricts the transport git will use for this clone to a fixed allowlist —
  # --repo is adopter-controlled (and, per --help, meant to be), and without this, a value like
  # 'ext::sh -c ...' would use git's ext:: remote-helper transport to run an arbitrary command
  # instead of cloning anything. "file" stays allowed for local-path/fixture sources (tests, and
  # any adopter cloning from a local mirror).
  GIT_ALLOW_PROTOCOL='https:http:git:ssh:file' \
    git clone --depth 1 --quiet -- "$MKR_REPO" "$tmp" >&2 \
    || die "bootstrap clone of $MKR_REPO failed"
  MKR_SOURCE="$tmp"
}

resolve_source() {
  [ -n "$MKR_SOURCE" ] || die "--source is required"
  [ -d "$MKR_SOURCE" ] || die "--source not found: $MKR_SOURCE"
  MKR_SOURCE="$(cd -- "$MKR_SOURCE" && pwd)"
  [ -d "$MKR_SOURCE/.claude" ] && [ -d "$MKR_SOURCE/seed" ] \
    || die "--source is missing .claude/ or seed/: $MKR_SOURCE"
}

resolve_target() {
  local given="$MKR_TARGET" top
  if [ -n "$given" ]; then
    [ -d "$given" ] || die "--target not found: $given"
  else
    given="$(pwd)"
  fi
  local iw
  iw="$(cd -- "$given" && git rev-parse --is-inside-work-tree 2>&1)"
  if [ "$iw" != "true" ]; then
    die "--target is not inside a usable git work tree: $given ($iw)"
  fi
  top="$(cd -- "$given" && git rev-parse --show-toplevel 2>&1)" \
    || die "--target could not be resolved to a work tree root: $given"
  MKR_TARGET="$top"
}

check_preconditions() {
  local gitdir
  gitdir="$MKR_TARGET/.git"
  if [ -e "$gitdir/MERGE_HEAD" ] || [ -e "$gitdir/rebase-merge" ] || [ -e "$gitdir/rebase-apply" ]; then
    die "$MKR_TARGET is mid-merge or mid-rebase"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    HASH_TOOL=sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    HASH_TOOL=shasum
  else
    die "no hashing tool found (need sha256sum or shasum)"
  fi
}

hash_file() {
  if [ "$HASH_TOOL" = sha256sum ]; then
    sha256sum -- "$1" | awk '{print $1}'
  else
    shasum -a 256 -- "$1" | awk '{print $1}'
  fi
}

mode_of() {
  local f="$1" m
  m="$(stat -c '%a' -- "$f" 2>/dev/null)" || m="$(stat -f '%A' -- "$f" 2>/dev/null)"
  printf '%s' "$m"
}

# Repo-relative enumerated paths, in ENUM_PATHS (sorted), plus the owned pair
# CLAUDE.md / .mkr/config, always checked for symlinks but never classified.
ENUM_PATHS=()
OWNED_PAIR=("CLAUDE.md" ".mkr/config")
declare -A SRC_HASH SRC_MODE

enumerate_source_paths() {
  local f rel
  while IFS= read -r f; do
    rel="${f#"$MKR_SOURCE"/}"
    ENUM_PATHS+=("$rel")
  done < <(find "$MKR_SOURCE/.claude" -type f ! -name mkr-manifest | LC_ALL=C sort)
  # .github/ is walked the same way if present (specs/M6_InstallCIWorkflow_Spec.md AD-1) — absent
  # under --source (e.g. a test fixture covering only .claude/+seed/) is not an error, it just
  # contributes zero paths.
  if [ -d "$MKR_SOURCE/.github" ]; then
    while IFS= read -r f; do
      rel="${f#"$MKR_SOURCE"/}"
      ENUM_PATHS+=("$rel")
    done < <(find "$MKR_SOURCE/.github" -type f | LC_ALL=C sort)
  fi
  for rel in "${ENUM_PATHS[@]}"; do
    SRC_HASH["$rel"]="$(hash_file "$MKR_SOURCE/$rel")"
    SRC_MODE["$rel"]="$(mode_of "$MKR_SOURCE/$rel")"
  done
}

check_symlinks() {
  local rel all=("${ENUM_PATHS[@]}" "${OWNED_PAIR[@]}")
  for rel in "${all[@]}"; do
    if [ -L "$MKR_TARGET/$rel" ]; then
      die "symlink at an enumerated template-owned path: $rel"
    fi
  done
}

declare -A MAN_HASH MAN_MODE
MANIFEST_PATH=""

read_manifest() {
  MANIFEST_PATH="$MKR_TARGET/.claude/mkr-manifest"
  [ -f "$MANIFEST_PATH" ] || return 0
  local first line hash mode path
  first="$(sed -n '1p' -- "$MANIFEST_PATH")"
  if [ "$first" != "# mkr-manifest v1" ]; then
    printf 'install.sh: .claude/mkr-manifest is unreadable (bad header) — rebuilding\n' >&2
    return 0
  fi
  local ok=1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ "$line" =~ ^([0-9a-f]{64})" "([0-9]{3})" "(.+)$ ]]; then
      hash="${BASH_REMATCH[1]}"; mode="${BASH_REMATCH[2]}"; path="${BASH_REMATCH[3]}"
      MAN_HASH["$path"]="$hash"
      MAN_MODE["$path"]="$mode"
    else
      ok=0
      break
    fi
  done < <(sed '1d' -- "$MANIFEST_PATH")
  if [ "$ok" -eq 0 ]; then
    printf 'install.sh: .claude/mkr-manifest is unreadable (malformed line) — rebuilding\n' >&2
    MAN_HASH=(); MAN_MODE=()
    return 0
  fi
}

# Per-path outcome, keyed by relpath: ACTION[rel] one of
# created restored updated unchanged refused forced-update orphaned mode-repair merged
declare -A ACTION NEW_HASH NEW_MODE MERGED_CONTENT
REFUSED_ANY=0
JQ_CHECKED=0
JQ_TOOL=""

# SETTINGS_JSON_REL — the one path classify() ever attempts a key-level merge on
# (specs/M6_Installer_Spec.md's settings.json merge path). A plain string constant, not a glob
# match against every path, so this never broadens beyond the one file the merge logic below is
# actually written for.
SETTINGS_JSON_REL=".claude/settings.json"

MERGE_SETTINGS_JQ_FILTER='
def union_by_command(a; b):
  (a // []) + (b // []) | unique_by(.command // .);
def merge_matcher_array($srcArr; $tgtArr):
  ($tgtArr // []) as $tgt
  | reduce ($srcArr // [])[] as $s (
      $tgt;
      (map(.matcher) | index($s.matcher)) as $idx
      | if $idx == null then . + [$s]
        else .[$idx].hooks = union_by_command(.[$idx].hooks; $s.hooks)
        end
    );
def merge_hooks($srcHooks; $tgtHooks):
  ($tgtHooks // {}) as $tgt
  | reduce (($srcHooks // {}) | keys[]) as $k (
      $tgt; .[$k] = merge_matcher_array($srcHooks[$k]; .[$k])
    );
. as $tgt
| ($src + $tgt)
| .hooks = merge_hooks($src.hooks; $tgt.hooks)
'

# try_merge_settings_json <rel> <target_file> — union-merges the shipped $rel (always
# SETTINGS_JSON_REL) into a divergent adopter copy at <target_file>: every hook entry the template
# ships ends up present (added if missing, matched by "command"); nothing the adopter already has
# — an added hook, an added matcher, an unrelated top-level key like "permissions" — is ever
# removed (specs/M6_Installer_Spec.md's settings.json merge path). Sets ACTION[$rel]=merged,
# NEW_HASH[$rel], and MERGED_CONTENT[$rel] on success; leaves ACTION[$rel] untouched (never sets
# it) on any failure — no jq on PATH, either file fails to parse as JSON, or the filter itself
# errors — so the caller's own fall-through to the exact original refuse/--force logic is what
# actually runs; this function never contributes a REFUSED_ANY itself.
try_merge_settings_json() {
  local rel="$1" target_file="$2" merged
  if [ "$JQ_CHECKED" -eq 0 ]; then
    JQ_CHECKED=1
    command -v jq >/dev/null 2>&1 && JQ_TOOL=jq
  fi
  [ -n "$JQ_TOOL" ] || return 0
  jq empty -- "$MKR_SOURCE/$rel" >/dev/null 2>&1 || return 0
  jq empty -- "$target_file" >/dev/null 2>&1 || return 0
  merged="$(jq --argjson src "$(cat -- "$MKR_SOURCE/$rel")" "$MERGE_SETTINGS_JQ_FILTER" -- "$target_file" 2>/dev/null)" || return 0
  [ -n "$merged" ] || return 0
  ACTION["$rel"]=merged
  MERGED_CONTENT["$rel"]="$merged"
  # Hashed with the exact trailing newline stage_and_move's own printf '%s\n' writes to disk —
  # a hash computed over different bytes than what actually lands on disk would make classify()
  # misjudge a byte-identical idempotent re-run as still-refused next time.
  NEW_HASH["$rel"]="$(printf '%s\n' "$merged" | { [ "$HASH_TOOL" = sha256sum ] && sha256sum || shasum -a 256; } | awk '{print $1}')"
}

classify() {
  local rel target_file th tm
  for rel in "${ENUM_PATHS[@]}"; do
    target_file="$MKR_TARGET/$rel"
    NEW_HASH["$rel"]="${SRC_HASH[$rel]}"
    NEW_MODE["$rel"]="${SRC_MODE[$rel]}"
    if [ ! -e "$target_file" ]; then
      if [ -n "${MAN_HASH[$rel]:-}" ]; then
        ACTION["$rel"]=restored
      else
        ACTION["$rel"]=created
      fi
      continue
    fi
    th="$(hash_file "$target_file")"
    if [ "$th" = "${SRC_HASH[$rel]}" ]; then
      tm="$(mode_of "$target_file")"
      if [ "$tm" != "${SRC_MODE[$rel]}" ]; then
        ACTION["$rel"]=mode-repair
      else
        ACTION["$rel"]=unchanged
      fi
      continue
    fi

    # settings.json: always re-attempt the merge before falling back to the generic
    # updated/refused logic below — not just when this path would otherwise be refused. A
    # previously-merged target's hash will never again equal SRC_HASH (it legitimately, forever,
    # differs from pure source), so without this a manifest-matching merged file would fall into
    # the ordinary "updated" branch on every later run and get overwritten with pure source,
    # silently discarding whatever was merged in. Re-merging a target that already contains
    # everything the current source ships is idempotent (the same union-by-command produces the
    # same bytes again) — caught below by comparing the fresh merge output's hash to $th.
    if [ "$rel" = "$SETTINGS_JSON_REL" ]; then
      try_merge_settings_json "$rel" "$target_file"
      if [ "${ACTION[$rel]-}" = merged ]; then
        if [ "${NEW_HASH[$rel]}" = "$th" ]; then
          tm="$(mode_of "$target_file")"
          if [ "$tm" != "${SRC_MODE[$rel]}" ]; then
            ACTION["$rel"]=mode-repair
          else
            ACTION["$rel"]=unchanged
          fi
        fi
        continue
      fi
      # Merge unavailable or failed (no jq, malformed JSON on either side): fall through to the
      # exact same updated/refused logic every other path gets, unchanged.
    fi

    if [ -n "${MAN_HASH[$rel]:-}" ]; then
      if [ "$th" = "${MAN_HASH[$rel]}" ]; then
        ACTION["$rel"]=updated
      else
        ACTION["$rel"]=refused
      fi
    else
      ACTION["$rel"]=refused
    fi
    if [ "${ACTION[$rel]}" = refused ]; then
      if [ "$MKR_FORCE" -eq 1 ]; then
        ACTION["$rel"]=forced-update
      else
        REFUSED_ANY=1
      fi
    fi
  done
}

ORPHANED=()

classify_orphans() {
  local p found rel
  for p in "${!MAN_HASH[@]}"; do
    found=0
    for rel in "${ENUM_PATHS[@]}"; do
      if [ "$rel" = "$p" ]; then found=1; break; fi
    done
    [ "$found" -eq 0 ] && ORPHANED+=("$p")
  done
}

CREATED_PAIR=()

classify_owned_pair() {
  local rel
  for rel in "${OWNED_PAIR[@]}"; do
    if [ ! -e "$MKR_TARGET/$rel" ]; then
      CREATED_PAIR+=("$rel")
    fi
  done
}

check_gitignore() {
  local rel
  for rel in "${ENUM_PATHS[@]}"; do
    case "${ACTION[$rel]:-}" in
      created|restored|updated|forced-update|mode-repair|merged) ;;
      *) continue ;;
    esac
    if git -C "$MKR_TARGET" check-ignore -q -- "$rel" 2>/dev/null; then
      printf 'install.sh: WARN %s is gitignored — it will not appear in `git status`\n' "$rel" >&2
    fi
  done
  for rel in "${CREATED_PAIR[@]}"; do
    if git -C "$MKR_TARGET" check-ignore -q -- "$rel" 2>/dev/null; then
      printf 'install.sh: WARN %s is gitignored — it will not appear in `git status`\n' "$rel" >&2
    fi
  done
}

# git pre-push hook install — specs/M2_CodeReview_Spec.md's own "out of scope: an install step,
# not a script" deferred this here. Found by basename among the enumerated .claude/ paths, never
# by a hardcoded full directory path to the hooks/scripts subtree (tests/install_test.sh's
# TC-M6-14a static check forbids install.sh from referencing that path directly) — a project that
# renamed or dropped the script from --source simply has nothing to find, and this whole feature
# is a no-op.
GIT_HOOK_SOURCE_REL=""
GIT_HOOK_ACTION=""

find_git_hook_source() {
  local rel
  for rel in "${ENUM_PATHS[@]}"; do
    case "$rel" in
      */pre-push-review-guard.sh) GIT_HOOK_SOURCE_REL="$rel"; return 0 ;;
    esac
  done
  return 1
}

classify_git_hook() {
  find_git_hook_source || return 0
  # An adopter who already routes hooks elsewhere (core.hooksPath) is left alone entirely — this
  # only ever touches the conventional .git/hooks/ location, the same way the rest of install.sh
  # only ever touches its own enumerated set.
  [ -n "$(git -C "$MKR_TARGET" config --get core.hooksPath 2>/dev/null)" ] && return 0

  local hook_path="$MKR_TARGET/.git/hooks/pre-push" want_target="../../$GIT_HOOK_SOURCE_REL"
  if [ -L "$hook_path" ]; then
    if [ "$(readlink -- "$hook_path")" = "$want_target" ]; then
      GIT_HOOK_ACTION=unchanged
    else
      GIT_HOOK_ACTION=refused
    fi
  elif [ -e "$hook_path" ]; then
    GIT_HOOK_ACTION=refused
  else
    GIT_HOOK_ACTION=created
  fi

  if [ "$GIT_HOOK_ACTION" = refused ]; then
    if [ "$MKR_FORCE" -eq 1 ]; then
      GIT_HOOK_ACTION=forced-update
    else
      REFUSED_ANY=1
    fi
  fi
}

install_git_hook() {
  case "$GIT_HOOK_ACTION" in
    created) ;;
    forced-update)
      local hook_path="$MKR_TARGET/.git/hooks/pre-push"
      cp -p -- "$hook_path" "$hook_path.mkr-backup" || exit 2
      printf 'install.sh: backed up .git/hooks/pre-push to .git/hooks/pre-push.mkr-backup\n' >&2
      rm -f -- "$hook_path" || exit 2
      ;;
    *) return 0 ;;
  esac
  mkdir -p -- "$MKR_TARGET/.git/hooks" || exit 2
  ln -s -- "../../$GIT_HOOK_SOURCE_REL" "$MKR_TARGET/.git/hooks/pre-push" || exit 2
}

CREATED_PATHS=()

# print_gitignore_hint — advisory only: install.sh never edits an adopter's .gitignore
# (specs/M6_Installer_Spec.md:39, an intentional non-goal), but .mkr/audit.jsonl (the
# passive tool-call log audit-log.sh writes) will get committed by accident unless an
# adopter thinks to ignore it themselves. Silent once they have.
print_gitignore_hint() {
  git -C "$MKR_TARGET" check-ignore -q -- .mkr/audit.jsonl 2>/dev/null && return 0
  printf 'install.sh: add .mkr/audit.jsonl to your .gitignore — this project never edits it for you\n' >&2
}

print_disclosure() {
  local rel
  for rel in "${ENUM_PATHS[@]}"; do
    printf '%s\t%s\n' "${ACTION[$rel]/mode-repair/unchanged}" "$rel"
    if [ "${ACTION[$rel]}" = created ]; then CREATED_PATHS+=("$rel"); fi
  done
  for rel in "${CREATED_PAIR[@]}"; do
    printf 'created\t%s\n' "$rel"
    CREATED_PATHS+=("$rel")
  done
  for rel in "${ORPHANED[@]}"; do
    printf 'orphaned\t%s\n' "$rel"
  done
  if [ -n "$GIT_HOOK_ACTION" ]; then
    printf '%s\t%s\n' "$GIT_HOOK_ACTION" ".git/hooks/pre-push"
    if [ "$GIT_HOOK_ACTION" = created ]; then CREATED_PATHS+=(".git/hooks/pre-push"); fi
  fi
}

print_revert() {
  printf -- '--- revert ---\n'
  if [ "${#CREATED_PATHS[@]}" -eq 0 ]; then
    return 0
  fi
  local rel quoted=()
  for rel in "${CREATED_PATHS[@]}"; do
    quoted+=("$(printf '%q' "$MKR_TARGET/$rel")")
  done
  printf 'rm -f %s\n' "${quoted[*]}"
}

backup_before_overwrite() {
  local rel="$1" f="$MKR_TARGET/$rel"
  [ -e "$f" ] || return 0
  cp -p -- "$f" "$f.mkr-backup" || exit 2
  printf 'install.sh: backed up %s to %s\n' "$rel" "$rel.mkr-backup" >&2
}

stage_and_move() {
  local rel stage
  stage="$(mktemp -d "$MKR_TARGET/.mkr-install-tmp.XXXXXX")" || exit 2
  CLEANUP_DIRS+=("$stage")

  for rel in "${ENUM_PATHS[@]}"; do
    case "${ACTION[$rel]}" in
      created|restored|updated|forced-update|mode-repair) ;;
      merged)
        mkdir -p -- "$(dirname -- "$stage/$rel")" || exit 2
        printf '%s\n' "${MERGED_CONTENT[$rel]}" > "$stage/$rel" || exit 2
        chmod "${SRC_MODE[$rel]}" -- "$stage/$rel" || exit 2
        continue
        ;;
      *) continue ;;
    esac
    mkdir -p -- "$(dirname -- "$stage/$rel")" || exit 2
    cp -p -- "$MKR_SOURCE/$rel" "$stage/$rel" || exit 2
    chmod "${SRC_MODE[$rel]}" -- "$stage/$rel" || exit 2
  done

  for rel in "${ENUM_PATHS[@]}"; do
    case "${ACTION[$rel]}" in
      created|restored) ;;
      updated|forced-update|merged) backup_before_overwrite "$rel" ;;
      mode-repair) ;;
      *) continue ;;
    esac
    mkdir -p -- "$(dirname -- "$MKR_TARGET/$rel")" || exit 2
    mv -f -- "$stage/$rel" "$MKR_TARGET/$rel" || exit 2
  done

  local rel2
  for rel2 in "${CREATED_PAIR[@]}"; do
    mkdir -p -- "$(dirname -- "$MKR_TARGET/$rel2")" || exit 2
    if [ "$rel2" = "CLAUDE.md" ]; then
      cp -p -- "$MKR_SOURCE/seed/CLAUDE.md" "$MKR_TARGET/CLAUDE.md" || exit 2
    else
      cp -p -- "$MKR_SOURCE/seed/config" "$MKR_TARGET/.mkr/config" || exit 2
    fi
  done
}

write_manifest() {
  local tmp rel
  tmp="$(mktemp "$MKR_TARGET/.claude/.mkr-manifest.tmp.XXXXXX")" || exit 2
  {
    printf '# mkr-manifest v1\n'
    for rel in "${ENUM_PATHS[@]}"; do
      printf '%s %s %s\n' "${NEW_HASH[$rel]}" "${NEW_MODE[$rel]}" "$rel"
    done | LC_ALL=C sort -k3
  } > "$tmp" || exit 2
  mv -f -- "$tmp" "$MANIFEST_PATH" || exit 2
}

# report_foreign_files — advisory only (docs/adr/0005-install-uninstall-narrow-delete.md): a file
# under .claude/skills|commands|agents that this run neither ships (ENUM_PATHS) nor has ever owned
# (a prior manifest entry, MAN_HASH) is content install.sh has never touched — possibly left over
# from a different, unrelated toolkit. Never removed, never refused; purely a heads-up. Runs
# whether or not the rest of this run writes anything, so a --dry-run surfaces it too.
report_foreign_files() {
  local dir f rel p found
  for dir in .claude/skills .claude/commands .claude/agents; do
    [ -d "$MKR_TARGET/$dir" ] || continue
    while IFS= read -r f; do
      rel="${f#"$MKR_TARGET"/}"
      found=0
      for p in "${ENUM_PATHS[@]}"; do
        if [ "$p" = "$rel" ]; then found=1; break; fi
      done
      if [ "$found" -eq 0 ] && [ -z "${MAN_HASH[$rel]:-}" ]; then
        printf 'install.sh: WARN unrecognized file at a template-owned location, possibly from a different toolkit (never removed automatically): %s\n' "$rel" >&2
      fi
    done < <(find "$MKR_TARGET/$dir" -type f 2>/dev/null | LC_ALL=C sort)
  done
}

# run_uninstall — docs/adr/0005-install-uninstall-narrow-delete.md. Removes exactly what
# .claude/mkr-manifest at --target records, plus a .git/hooks/pre-push symlink this install.sh
# itself created (found the same way classify_git_hook finds it — by basename, never a hardcoded
# hooks/scripts path) — nothing else, ever. CLAUDE.md/.mkr/config are never in the manifest to
# begin with, so they are never a candidate here. Report-only unless --confirm is also given.
run_uninstall() {
  resolve_target
  check_preconditions
  read_manifest

  # Note: an indexed array's count ("${#sorted[@]}") is used for every emptiness check below, not
  # "${#MAN_HASH[@]}" directly — an associative array that was declared but never assigned a key
  # (read_manifest's own early-return path, no manifest file present) trips "unbound variable"
  # under this script's set -u the moment its element count is read, even though iterating
  # "${!MAN_HASH[@]}" over it is fine either way.
  local rel sorted=() hook_path="$MKR_TARGET/.git/hooks/pre-push" hook_is_ours=0
  if [ -L "$hook_path" ]; then
    case "$(readlink -- "$hook_path")" in
      ../../*/pre-push-review-guard.sh) hook_is_ours=1 ;;
    esac
  fi

  while IFS= read -r rel; do sorted+=("$rel"); done < <(printf '%s\n' "${!MAN_HASH[@]}" | LC_ALL=C sort)
  # A truly empty MAN_HASH still yields one blank line from the printf above; drop it.
  if [ "${#sorted[@]}" -eq 1 ] && [ -z "${sorted[0]}" ]; then sorted=(); fi

  if [ "${#sorted[@]}" -eq 0 ] && [ "$hook_is_ours" -eq 0 ]; then
    printf 'install.sh: nothing to uninstall at %s (no .claude/mkr-manifest, no owned git hook)\n' "$MKR_TARGET" >&2
    exit 0
  fi

  for rel in "${sorted[@]}"; do
    printf 'would-remove	%s
' "$rel"
  done
  [ "${#sorted[@]}" -gt 0 ] && printf 'would-remove	.claude/mkr-manifest
'
  [ "$hook_is_ours" -eq 1 ] && printf 'would-remove	.git/hooks/pre-push
'

  if [ "$MKR_CONFIRM" -ne 1 ]; then
    printf 'install.sh: --uninstall is report-only without --confirm — nothing removed\n' >&2
    exit 0
  fi

  for rel in "${sorted[@]}"; do
    rm -f -- "$MKR_TARGET/$rel"
    printf 'removed	%s
' "$rel"
  done
  if [ "${#sorted[@]}" -gt 0 ]; then
    rm -f -- "$MANIFEST_PATH"
    printf 'removed	.claude/mkr-manifest
'
  fi
  if [ "$hook_is_ours" -eq 1 ]; then
    rm -f -- "$hook_path"
    printf 'removed	.git/hooks/pre-push
'
  fi
  exit 0
}

main() {
  trap cleanup_all EXIT
  parse_args "$@"

  if [ "$MKR_UNINSTALL" -eq 1 ]; then
    run_uninstall
  fi

  maybe_bootstrap_source
  resolve_source
  resolve_target
  check_preconditions
  enumerate_source_paths
  check_symlinks
  read_manifest
  classify
  classify_orphans
  classify_owned_pair
  classify_git_hook
  check_gitignore
  report_foreign_files

  if [ "$MKR_DRY_RUN" -eq 1 ]; then
    print_disclosure
    print_revert
    if [ "$REFUSED_ANY" -eq 1 ]; then exit 1; else exit 0; fi
  fi

  if [ "$REFUSED_ANY" -eq 1 ]; then
    print_disclosure
    print_revert
    exit 1
  fi

  stage_and_move
  write_manifest
  install_git_hook
  print_gitignore_hint
  print_disclosure
  print_revert
}

main "$@"
