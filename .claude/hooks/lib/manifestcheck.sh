#!/usr/bin/env bash
# mkr-aidlc — .claude/mkr-manifest integrity verification (specs/M3_Guardrails_Spec.md §7,
# mkr-gate.yml step 4). Sourced only, never executed, matching config.sh's/reviewrecord.sh's own
# convention.
#
# Requires bash 4.0+, matching config.sh's own baseline.

# manifestcheck_verify <repo-root> — recomputes every .claude/mkr-manifest entry's SHA-256 and
# mode bits against the real file at <repo-root> and reports any divergence. mkr-code-reviewer and
# mkr-security-reviewer are deliberately Read/Grep/Glob-only (no Bash) — neither can compute a
# hash or stat a mode bit, so neither can ever itself catch a manifest that has drifted from the
# files it describes (accidental, or a PR quietly editing a hook's bytes without updating its
# recorded hash). This is the Bash-capable check that can. Prints one line per problem to stdout;
# returns 0 if the manifest is absent (nothing to verify — this repo's own checkout included,
# since mkr-aidlc is the template source, never installed against itself) or every entry matches,
# 1 otherwise.
manifestcheck_verify() {
  local root="$1" man
  man="$root/.claude/mkr-manifest"
  if [ ! -f "$man" ]; then
    return 0
  fi
  if [ "$(sed -n '1p' -- "$man")" != "# mkr-manifest v1" ]; then
    printf '%s: unreadable (bad header) — cannot verify, failing closed\n' "$man"
    return 1
  fi

  local fail=0 line hash mode path real_hash real_mode target
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [[ "$line" =~ ^([0-9a-f]{64})\ ([0-9]{3})\ (.+)$ ]]; then
      hash="${BASH_REMATCH[1]}"; mode="${BASH_REMATCH[2]}"; path="${BASH_REMATCH[3]}"
    else
      printf '%s: malformed line: %s\n' "$man" "$line"
      fail=1
      continue
    fi
    # Same shape install.sh's own is_safe_owned_relpath enforces on --uninstall: rooted at
    # .claude/ or .github/ (the only two directories install.sh ever enumerates), no ".."
    # segment, never absolute — a manifest entry is an ordinary tracked file with no write-gate
    # of its own, so a crafted line must never be trusted to name a path outside install.sh's own
    # owned domain, even for a read-only hash check.
    case "$path" in
      /*) printf '%s: unsafe entry, not under .claude/ or .github/: %s\n' "$man" "$path"; fail=1; continue ;;
      .claude/*|.github/*) ;;
      *) printf '%s: unsafe entry, not under .claude/ or .github/: %s\n' "$man" "$path"; fail=1; continue ;;
    esac
    case "/$path/" in
      */../*|*/./*) printf "%s: unsafe entry, contains a '..' or '.' segment: %s\n" "$man" "$path"; fail=1; continue ;;
    esac
    target="$root/$path"
    # A symlink at a manifest-recorded path is checked BEFORE anything that would dereference it
    # (`-f`, `sha256sum`, `stat`) — the same protection install.sh's own check_symlinks() applies
    # to every enumerated path, here against a path string this function only trusts by shape, not
    # by proof it's the ordinary regular file it claims to be. Skipping this check would let a
    # PR-committed symlink at a nominally-safe path (e.g. `.claude/evil` -> `../../../../etc/
    # passwd`) be transparently followed: `-f`/`sha256sum`/`stat` all dereference symlinks by
    # default, so the *target's* existence and content hash would leak into this check's own
    # output — which lands in a CI log a fork-PR attacker can read.
    if [ -L "$target" ]; then
      printf 'manifest entry is a symlink on disk, refusing to follow it: %s\n' "$path"
      fail=1
      continue
    fi
    if [ ! -f "$target" ]; then
      printf 'manifest entry missing on disk: %s\n' "$path"
      fail=1
      continue
    fi
    real_hash="$(sha256sum -- "$target" 2>/dev/null | awk '{print $1}')"
    [ -n "$real_hash" ] || real_hash="$(shasum -a 256 -- "$target" 2>/dev/null | awk '{print $1}')"
    real_mode="$(stat -c '%a' -- "$target" 2>/dev/null)"
    [ -n "$real_mode" ] || real_mode="$(stat -f '%A' -- "$target" 2>/dev/null)"
    if [ "$real_hash" != "$hash" ]; then
      printf 'manifest hash mismatch: %s (manifest %s, actual %s)\n' "$path" "$hash" "$real_hash"
      fail=1
    fi
    if [ "$real_mode" != "$mode" ]; then
      printf 'manifest mode mismatch: %s (manifest %s, actual %s)\n' "$path" "$mode" "$real_mode"
      fail=1
    fi
  done < <(sed '1d' -- "$man")

  [ "$fail" -eq 0 ]
}
