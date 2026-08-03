#!/usr/bin/env bash
# mkr-aidlc installer/updater — specs/M6_Installer_Spec.md, specs/M6_InstallBootstrap_Spec.md.
#
# Classifies every template-owned path under --source against .claude/mkr-manifest at --target,
# stages the result, and moves it into place, all-or-nothing per run. Never deletes anything (§6
# AD-2). Bash-only by design (§6 AD-1) — not POSIX-sh. When --source
# is omitted, clones --repo into a temp dir and uses that.
set -uo pipefail

MKR_SOURCE=""
MKR_TARGET=""
MKR_FORCE=0
MKR_DRY_RUN=0
MKR_REPO="https://github.com/kikrgbh/mkrdlc.git"
HASH_TOOL=""
SAW_SOURCE=0
CLEANUP_DIRS=()

usage() {
  cat <<'EOF'
Usage: install.sh [--source PATH] [--repo URL] [--target DIR] [--force] [--dry-run]
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
# created restored updated unchanged refused forced-update orphaned mode-repair
declare -A ACTION NEW_HASH NEW_MODE
REFUSED_ANY=0

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
      created|restored|updated|forced-update|mode-repair) ;;
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

CREATED_PATHS=()

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
      *) continue ;;
    esac
    mkdir -p -- "$(dirname -- "$stage/$rel")" || exit 2
    cp -p -- "$MKR_SOURCE/$rel" "$stage/$rel" || exit 2
    chmod "${SRC_MODE[$rel]}" -- "$stage/$rel" || exit 2
  done

  for rel in "${ENUM_PATHS[@]}"; do
    case "${ACTION[$rel]}" in
      created|restored) ;;
      updated|forced-update) backup_before_overwrite "$rel" ;;
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

main() {
  trap cleanup_all EXIT
  parse_args "$@"
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
  check_gitignore

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
  print_disclosure
  print_revert
}

main "$@"
