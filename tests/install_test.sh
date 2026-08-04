#!/usr/bin/env bash
# tests/install_test.sh — specs/M6_Installer_Spec.md §9, TC-M6-01..15, TC-M6-20..24, TC-M6-26;
# specs/M6_InstallCIWorkflow_Spec.md §9, TC-CIW-01..05; specs/M6_InstallBootstrap_Spec.md §9,
# TC-BOOT-01..08 (TC-BOOT-09..11 are direct working-tree/suite checks, not in this file).
# fixture_repo()-style discipline, mirroring tests/hooks_test.sh: each case builds its own
# temp source tree and/or temp git target repo, so no case depends on another's state.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$HERE/.."
INSTALL="$ROOT/install.sh"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# fixture_source — a small representative subset of .claude/+seed/: one hook-lib file (mode
# 755), one skill file (mode 644), and the owned-pair seed files. Prints the path.
fixture_source() {
  local d
  d="$(mktemp -d)"
  mkdir -p "$d/.claude/hooks/lib" "$d/.claude/skills/mkr-loop" "$d/seed"
  printf '#!/usr/bin/env bash\necho config-v1\n' > "$d/.claude/hooks/lib/config.sh"
  chmod 755 "$d/.claude/hooks/lib/config.sh"
  printf '# mkr-loop skill v1\n' > "$d/.claude/skills/mkr-loop/SKILL.md"
  chmod 644 "$d/.claude/skills/mkr-loop/SKILL.md"
  printf '# seed CLAUDE.md\n' > "$d/seed/CLAUDE.md"
  printf '# seed config\n' > "$d/seed/config"
  printf '%s' "$d"
}

# fixture_target — a fresh, empty, git-initialized repo. Prints the path.
fixture_target() {
  local d
  d="$(mktemp -d)"
  ( unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE GIT_COMMON_DIR
    cd "$d" && git init -q && git config user.email t@t.com && git config user.name t ) >/dev/null 2>&1
  printf '%s' "$d"
}

cleanup() { rm -rf "$1" 2>/dev/null; }

run_install() { ( cd "$ROOT" && bash "$INSTALL" "$@" 2>&1 ); }

manifest_of() { printf '%s/.claude/mkr-manifest' "$1"; }

# fixture_source_repo — a fixture_source() tree turned into a local git repo (init + add +
# commit), so it can be `git clone`d for TC-BOOT-01..08 without depending on the real network.
# Prints the path.
fixture_source_repo() {
  local d
  d="$(fixture_source)"
  ( cd "$d" && git init -q && git config user.email t@t.com && git config user.name t \
      && git add -A && git commit -q -m fixture ) >/dev/null 2>&1
  printf '%s' "$d"
}

# bootstrap_tmp_from_output <out> — extracts the temp clone dir path from install.sh's pre-clone
# bootstrap diagnostic line ("install.sh: no --source given — cloning <repo> into <tmp>").
bootstrap_tmp_from_output() {
  printf '%s\n' "$1" | sed -n 's/.*cloning .* into \(.*\)$/\1/p' | tail -1
}

# add_github_workflow <src> — adds a fixture .github/workflows/mkr-gate.yml (mode 644) to a
# fixture_source() tree, for TC-CIW-01..03/05 (specs/M6_InstallCIWorkflow_Spec.md §9).
add_github_workflow() {
  mkdir -p "$1/.github/workflows"
  printf 'name: mkr-gate\n# fixture CI workflow v1\n' > "$1/.github/workflows/mkr-gate.yml"
  chmod 644 "$1/.github/workflows/mkr-gate.yml"
}

# add_git_hook_script <src> — adds a fixture .claude/hooks/scripts/pre-push-review-guard.sh (mode
# 755) to a fixture_source() tree, for the git pre-push hook install cases (issue #5).
add_git_hook_script() {
  mkdir -p "$1/.claude/hooks/scripts"
  printf '#!/usr/bin/env bash\necho fixture pre-push-review-guard v1\n' > "$1/.claude/hooks/scripts/pre-push-review-guard.sh"
  chmod 755 "$1/.claude/hooks/scripts/pre-push-review-guard.sh"
}

# add_settings_json <src> — adds a fixture .claude/settings.json (mode 644, a small representative
# "hooks" shape: one PreToolUse/Bash matcher with two hook commands, one Stop matcher) to a
# fixture_source() tree, for the settings.json merge-path cases (issue #1). Prints nothing.
add_settings_json() {
  mkdir -p "$1/.claude"
  cat > "$1/.claude/settings.json" <<'JSONEOF'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/secret-guard.sh" },
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/branch-guard.sh" }
        ]
      }
    ],
    "Stop": [
      { "hooks": [ { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/stop-checks.sh" } ] }
    ]
  }
}
JSONEOF
  chmod 644 "$1/.claude/settings.json"
}

echo
echo "== install.sh: fresh install (TC-M6-01) =="

SRC="$(fixture_source)"; TGT="$(fixture_target)"
out="$(run_install --source "$SRC" --target "$TGT")"
rc1=0
ok1=1
[ -f "$TGT/.claude/hooks/lib/config.sh" ] && cmp -s "$TGT/.claude/hooks/lib/config.sh" "$SRC/.claude/hooks/lib/config.sh" || ok1=0
[ "$(stat -c '%a' "$TGT/.claude/hooks/lib/config.sh" 2>/dev/null)" = 755 ] || ok1=0
[ -f "$TGT/.claude/skills/mkr-loop/SKILL.md" ] && cmp -s "$TGT/.claude/skills/mkr-loop/SKILL.md" "$SRC/.claude/skills/mkr-loop/SKILL.md" || ok1=0
[ "$(stat -c '%a' "$TGT/.claude/skills/mkr-loop/SKILL.md" 2>/dev/null)" = 644 ] || ok1=0
[ -f "$TGT/CLAUDE.md" ] && cmp -s "$TGT/CLAUDE.md" "$SRC/seed/CLAUDE.md" || ok1=0
[ -f "$TGT/.mkr/config" ] && cmp -s "$TGT/.mkr/config" "$SRC/seed/config" || ok1=0
if [ "$ok1" -eq 1 ]; then
  ok "TC-M6-01a every source path present at target with matching bytes/mode; owned pair seeded"
else
  bad "TC-M6-01a every source path present at target with matching bytes/mode; owned pair seeded" "$out"
fi

ok2=1
for p in .claude/hooks/lib/config.sh .claude/skills/mkr-loop/SKILL.md CLAUDE.md .mkr/config; do
  printf '%s\n' "$out" | grep -qF "created	$p" || ok2=0
done
if [ "$ok2" -eq 1 ]; then
  ok "TC-M6-01b owned pair disclosed as created\\t<path>, same as any other created path"
else
  bad "TC-M6-01b owned pair disclosed as created\\t<path>, same as any other created path" "$out"
fi

MAN="$(manifest_of "$TGT")"
ok3=1
[ "$(sed -n '1p' "$MAN")" = "# mkr-manifest v1" ] || ok3=0
grep -qE '^[0-9a-f]{64} 755 \.claude/hooks/lib/config\.sh$' "$MAN" || ok3=0
grep -qE '^[0-9a-f]{64} 644 \.claude/skills/mkr-loop/SKILL\.md$' "$MAN" || ok3=0
grep -q 'CLAUDE\.md$' "$MAN" && ok3=0
grep -q '\.mkr/config$' "$MAN" && ok3=0
if [ "$ok3" -eq 1 ]; then
  ok "TC-M6-01c manifest correctly hashed per path, owned pair excluded"
else
  bad "TC-M6-01c manifest correctly hashed per path, owned pair excluded" "$(cat "$MAN")"
fi
cleanup "$SRC"

echo
echo "== install.sh: idempotent re-run (TC-M6-02) =="

status_before="$(cd "$TGT" && git status --porcelain -uall)"
manifest_before="$(cat "$MAN")"
out2="$(run_install --source "$(mktemp -d)" --target "$TGT" 2>&1; true)"
# rebuild a fresh, byte-identical source for the re-run (fixture_source already cleaned up)
SRC2="$(fixture_source)"
out2="$(run_install --source "$SRC2" --target "$TGT")"
rc2=$?
status_after="$(cd "$TGT" && git status --porcelain -uall)"
manifest_after="$(cat "$MAN")"
ok4=1
[ "$rc2" -eq 0 ] || ok4=0
while IFS= read -r line; do
  case "$line" in
    "unchanged	"*) ;;
    "") ;;
    "--- revert ---") ;;
    "install.sh: add .mkr/audit.jsonl to your .gitignore"*) ;;
    *) ok4=0 ;;
  esac
done <<< "$out2"
[ "$status_before" = "$status_after" ] || ok4=0
[ "$manifest_before" = "$manifest_after" ] || ok4=0
if [ "$ok4" -eq 1 ]; then
  ok "TC-M6-02 re-run is a byte-identical no-op: exit 0, all unchanged, git status and manifest identical"
else
  bad "TC-M6-02 re-run is a byte-identical no-op: exit 0, all unchanged, git status and manifest identical" "$out2"
fi
cleanup "$SRC2"

echo
echo "== install.sh: refuses a hand-edited divergent path (TC-M6-03) =="

before_content="content-edited-by-hand"
printf '%s\n' "$before_content" > "$TGT/.claude/skills/mkr-loop/SKILL.md"
SRC3="$(fixture_source)"
out3="$(run_install --source "$SRC3" --target "$TGT")"
rc3=$?
after_content="$(cat "$TGT/.claude/skills/mkr-loop/SKILL.md")"
ok5=1
[ "$rc3" -eq 1 ] || ok5=0
printf '%s\n' "$out3" | grep -qF "refused	.claude/skills/mkr-loop/SKILL.md" || ok5=0
[ "$after_content" = "$before_content" ] || ok5=0
if [ "$ok5" -eq 1 ]; then
  ok "TC-M6-03 divergent path refused without --force, exit 1, file left untouched"
else
  bad "TC-M6-03 divergent path refused without --force, exit 1, file left untouched" "$out3"
fi

echo
echo "== install.sh: --force overwrites a divergent path, with backup (TC-M6-04) =="

out4="$(run_install --source "$SRC3" --target "$TGT" --force)"
rc4=$?
ok6=1
[ "$rc4" -eq 0 ] || ok6=0
printf '%s\n' "$out4" | grep -qF "forced-update	.claude/skills/mkr-loop/SKILL.md" || ok6=0
[ "$(cat "$TGT/.claude/skills/mkr-loop/SKILL.md.mkr-backup" 2>/dev/null)" = "$before_content" ] || ok6=0
cmp -s "$TGT/.claude/skills/mkr-loop/SKILL.md" "$SRC3/.claude/skills/mkr-loop/SKILL.md" || ok6=0
if [ "$ok6" -eq 1 ]; then
  ok "TC-M6-04 --force overwrites, backs up pre-overwrite bytes exactly, target matches source"
else
  bad "TC-M6-04 --force overwrites, backs up pre-overwrite bytes exactly, target matches source" "$out4"
fi
cleanup "$SRC3"
rm -f "$TGT/.claude/skills/mkr-loop/SKILL.md.mkr-backup"

echo
echo "== install.sh: restores a deleted path (TC-M6-05) =="

rm -f "$TGT/.claude/hooks/lib/config.sh"
SRC5="$(fixture_source)"
out5="$(run_install --source "$SRC5" --target "$TGT")"
rc5=$?
ok7=1
[ "$rc5" -eq 0 ] || ok7=0
printf '%s\n' "$out5" | grep -qF "restored	.claude/hooks/lib/config.sh" || ok7=0
cmp -s "$TGT/.claude/hooks/lib/config.sh" "$SRC5/.claude/hooks/lib/config.sh" || ok7=0
grep -qE '\.claude/hooks/lib/config\.sh$' "$MAN" || ok7=0
if [ "$ok7" -eq 1 ]; then
  ok "TC-M6-05 deleted path restored, disclosed, manifest entry present"
else
  bad "TC-M6-05 deleted path restored, disclosed, manifest entry present" "$out5"
fi
cleanup "$SRC5"
cleanup "$TGT"

echo
echo "== install.sh: source upgrade — updated + orphaned (TC-M6-06) =="

SRC6A="$(fixture_source)"; TGT6="$(fixture_target)"
run_install --source "$SRC6A" --target "$TGT6" >/dev/null
v1_content="$(cat "$SRC6A/.claude/skills/mkr-loop/SKILL.md")"
SRC6B="$(fixture_source)"
printf '# mkr-loop skill v2 — changed\n' > "$SRC6B/.claude/skills/mkr-loop/SKILL.md"
rm -rf "$SRC6B/.claude/hooks"
out6="$(run_install --source "$SRC6B" --target "$TGT6")"
rc6=$?
ok8=1
[ "$rc6" -eq 0 ] || ok8=0
printf '%s\n' "$out6" | grep -qF "updated	.claude/skills/mkr-loop/SKILL.md" || ok8=0
[ "$(cat "$TGT6/.claude/skills/mkr-loop/SKILL.md.mkr-backup" 2>/dev/null)" = "$v1_content" ] || ok8=0
cmp -s "$TGT6/.claude/skills/mkr-loop/SKILL.md" "$SRC6B/.claude/skills/mkr-loop/SKILL.md" || ok8=0
printf '%s\n' "$out6" | grep -qF "orphaned	.claude/hooks/lib/config.sh" || ok8=0
[ -f "$TGT6/.claude/hooks/lib/config.sh" ] || ok8=0
grep -q 'hooks/lib/config\.sh$' "$(manifest_of "$TGT6")" && ok8=0
if [ "$ok8" -eq 1 ]; then
  ok "TC-M6-06 changed path updated+backed up; removed path orphaned, left on disk, dropped from manifest"
else
  bad "TC-M6-06 changed path updated+backed up; removed path orphaned, left on disk, dropped from manifest" "$out6"
fi
cleanup "$SRC6A"; cleanup "$SRC6B"; cleanup "$TGT6"

echo
echo "== install.sh: revert command (TC-M6-07) =="

SRC7="$(fixture_source)"; TGT7="$(fixture_target)"
out7="$(run_install --source "$SRC7" --target "$TGT7")"
revert_line="$(printf '%s\n' "$out7" | sed -n '/^--- revert ---$/,$p' | sed -n '2p')"
ok9=1
[[ "$revert_line" == rm\ -f\ * ]] || ok9=0
[[ "$revert_line" == *".claude/hooks/lib/config.sh"* ]] || ok9=0
[[ "$revert_line" == *"CLAUDE.md"* ]] || ok9=0
eval "$revert_line"
[ -e "$TGT7/.claude/hooks/lib/config.sh" ] && ok9=0
[ -e "$TGT7/CLAUDE.md" ] && ok9=0
if [ "$ok9" -eq 1 ]; then
  ok "TC-M6-07a revert command names exactly the created paths, rm -f, and removes them"
else
  bad "TC-M6-07a revert command names exactly the created paths, rm -f, and removes them" "$out7"
fi
cleanup "$SRC7"; cleanup "$TGT7"

SRC7B="$(fixture_source)"; TGT7B="$(fixture_target)"
run_install --source "$SRC7B" --target "$TGT7B" >/dev/null
out7b="$(run_install --source "$SRC7B" --target "$TGT7B")"
marker_line_no="$(printf '%s\n' "$out7b" | grep -n '^--- revert ---$' | cut -d: -f1)"
after_marker="$(printf '%s\n' "$out7b" | sed -n "$((marker_line_no+1)){p};$((marker_line_no+1))q" 2>/dev/null)"
ok10=1
[ -n "$marker_line_no" ] || ok10=0
[ -z "${after_marker:-}" ] || ok10=0
if [ "$ok10" -eq 1 ]; then
  ok "TC-M6-07b no created paths → marker present, empty command after it"
else
  bad "TC-M6-07b no created paths → marker present, empty command after it" "$out7b"
fi
cleanup "$SRC7B"; cleanup "$TGT7B"

echo
echo "== install.sh: unrecorded foreign file at a template path (TC-M6-08) =="

SRC8="$(fixture_source)"; TGT8="$(fixture_target)"
mkdir -p "$TGT8/.claude/skills/mkr-loop"
adopter_content="adopter's own unrelated content"
printf '%s\n' "$adopter_content" > "$TGT8/.claude/skills/mkr-loop/SKILL.md"
out8="$(run_install --source "$SRC8" --target "$TGT8")"
rc8=$?
ok11=1
[ "$rc8" -eq 1 ] || ok11=0
printf '%s\n' "$out8" | grep -qF "refused	.claude/skills/mkr-loop/SKILL.md" || ok11=0
[ "$(cat "$TGT8/.claude/skills/mkr-loop/SKILL.md")" = "$adopter_content" ] || ok11=0
if [ "$ok11" -eq 1 ]; then
  ok "TC-M6-08a unrecorded foreign file refused without --force, not overwritten"
else
  bad "TC-M6-08a unrecorded foreign file refused without --force, not overwritten" "$out8"
fi

out8b="$(run_install --source "$SRC8" --target "$TGT8" --force)"
rc8b=$?
ok12=1
[ "$rc8b" -eq 0 ] || ok12=0
printf '%s\n' "$out8b" | grep -qF "forced-update	.claude/skills/mkr-loop/SKILL.md" || ok12=0
[ "$(cat "$TGT8/.claude/skills/mkr-loop/SKILL.md.mkr-backup" 2>/dev/null)" = "$adopter_content" ] || ok12=0
cmp -s "$TGT8/.claude/skills/mkr-loop/SKILL.md" "$SRC8/.claude/skills/mkr-loop/SKILL.md" || ok12=0
grep -qE '\.claude/skills/mkr-loop/SKILL\.md$' "$(manifest_of "$TGT8")" || ok12=0
if [ "$ok12" -eq 1 ]; then
  ok "TC-M6-08b --force overwrites, backs up adopter's bytes, records a new manifest entry"
else
  bad "TC-M6-08b --force overwrites, backs up adopter's bytes, records a new manifest entry" "$out8b"
fi
cleanup "$SRC8"; cleanup "$TGT8"

echo
echo "== install.sh: --target resolution (TC-M6-09) =="

SRC9="$(fixture_source)"; TGT9="$(fixture_target)"
mkdir -p "$TGT9/sub/dir"
out9="$(run_install --source "$SRC9" --target "$TGT9/sub/dir")"
rc9=$?
ok13=1
[ "$rc9" -eq 0 ] || ok13=0
[ -f "$TGT9/.claude/hooks/lib/config.sh" ] || ok13=0
[ -f "$TGT9/sub/dir/.claude/hooks/lib/config.sh" ] && ok13=0
if [ "$ok13" -eq 1 ]; then
  ok "TC-M6-09a --target subdirectory resolves to the true repo root, succeeds"
else
  bad "TC-M6-09a --target subdirectory resolves to the true repo root, succeeds" "$out9"
fi
cleanup "$TGT9"

NOTREPO="$(mktemp -d)"
out9b="$(run_install --source "$SRC9" --target "$NOTREPO")"
rc9b=$?
if [ "$rc9b" -eq 1 ]; then
  ok "TC-M6-09b --target outside any git work tree → exit 1"
else
  bad "TC-M6-09b --target outside any git work tree → exit 1" "$out9b"
fi
cleanup "$NOTREPO"

BAREREPO="$(mktemp -d)"
git init -q --bare "$BAREREPO" >/dev/null 2>&1
out9c="$(run_install --source "$SRC9" --target "$BAREREPO")"
rc9c=$?
if [ "$rc9c" -eq 1 ]; then
  ok "TC-M6-09c --target inside a bare repo → exit 1"
else
  bad "TC-M6-09c --target inside a bare repo → exit 1" "$out9c"
fi
cleanup "$BAREREPO"
cleanup "$SRC9"
echo "  (dubious-ownership case skipped — not reliably reproducible without root/UID changes)"

echo
echo "== install.sh: symlink at an enumerated path refuses the whole run (TC-M6-10) =="

SRC10="$(fixture_source)"; TGT10="$(fixture_target)"
mkdir -p "$TGT10/.claude/hooks/lib"
ln -s "/nonexistent-target" "$TGT10/.claude/hooks/lib/config.sh"
out10="$(run_install --source "$SRC10" --target "$TGT10")"
rc10=$?
ok14=1
[ "$rc10" -eq 1 ] || ok14=0
[ -e "$TGT10/.claude/skills/mkr-loop/SKILL.md" ] && ok14=0
if [ "$ok14" -eq 1 ]; then
  ok "TC-M6-10a broken symlink at an enumerated path → whole run refuses, nothing else written"
else
  bad "TC-M6-10a broken symlink at an enumerated path → whole run refuses, nothing else written" "$out10"
fi
cleanup "$TGT10"

SRC10B="$(fixture_source)"; TGT10B="$(fixture_target)"
mkdir -p "$TGT10B/.claude/skills/mkr-loop"
cp "$SRC10B/.claude/skills/mkr-loop/SKILL.md" "$TGT10B/.claude/skills/mkr-loop/SKILL.md.real"
ln -s "$TGT10B/.claude/skills/mkr-loop/SKILL.md.real" "$TGT10B/.claude/skills/mkr-loop/SKILL.md"
out10b="$(run_install --source "$SRC10B" --target "$TGT10B")"
rc10b=$?
if [ "$rc10b" -eq 1 ]; then
  ok "TC-M6-10b symlink at a would-be-unchanged path still refuses (checked pre-classification)"
else
  bad "TC-M6-10b symlink at a would-be-unchanged path still refuses (checked pre-classification)" "$out10b"
fi
cleanup "$SRC10"; cleanup "$SRC10B"; cleanup "$TGT10B"

echo
echo "== install.sh: flag/precondition refusals (TC-M6-11) =="

SRC11="$(fixture_source)"; TGT11="$(fixture_target)"
n11=0

out="$(run_install --bogus --source "$SRC11" --target "$TGT11")"; [ $? -eq 1 ] && n11=$((n11+1)) || bad "TC-M6-11 unrecognized flag" "$out"
out="$(run_install --source)"; [ $? -eq 1 ] && n11=$((n11+1)) || bad "TC-M6-11 --source no value" "$out"

for gitfile in MERGE_HEAD rebase-merge rebase-apply; do
  T="$(fixture_target)"
  touch "$T/.git/$gitfile"
  out="$(run_install --source "$SRC11" --target "$T")"
  [ $? -eq 1 ] && n11=$((n11+1)) || bad "TC-M6-11 mid-$gitfile" "$out"
  cleanup "$T"
done

BINDIR_ALL="$(mktemp -d)"
for c in bash git find sort awk stat cp mv mkdir chmod rm mktemp sed dirname cat env grep; do
  p="$(type -P "$c" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$BINDIR_ALL/$(basename "$p")" 2>/dev/null
done
BINDIR_SHASUM="$(mktemp -d)"
cp -r "$BINDIR_ALL"/. "$BINDIR_SHASUM"/
p="$(type -P shasum 2>/dev/null)"; [ -n "$p" ] && ln -sf "$p" "$BINDIR_SHASUM/shasum"

T11S="$(fixture_target)"
out="$(cd "$ROOT" && PATH="$BINDIR_SHASUM" bash "$INSTALL" --source "$SRC11" --target "$T11S" 2>&1)"
[ $? -eq 0 ] && n11=$((n11+1)) || bad "TC-M6-11 shasum-only fallback succeeds" "$out"
cleanup "$T11S"

T11N="$(fixture_target)"
out="$(cd "$ROOT" && PATH="$BINDIR_ALL" bash "$INSTALL" --source "$SRC11" --target "$T11N" 2>&1)"
[ $? -eq 1 ] && n11=$((n11+1)) || bad "TC-M6-11 no hashing tool → refuses" "$out"
cleanup "$T11N"

if [ "$n11" -eq 7 ]; then
  ok "TC-M6-11 all seven scenarios behave as specified"
else
  bad "TC-M6-11 all seven scenarios behave as specified" "only $n11/7 passed"
fi
rm -rf "$BINDIR_ALL" "$BINDIR_SHASUM"
cleanup "$SRC11"; cleanup "$TGT11"

echo
echo "== install.sh: --dry-run never writes, exit-code parity (TC-M6-12) =="

SRC12="$(fixture_source)"; TGT12="$(fixture_target)"
printf 'hand-edited\n' > "$TGT12/.mkr-placeholder-not-real" 2>/dev/null || true
mkdir -p "$TGT12/.claude/skills/mkr-loop"
printf 'divergent\n' > "$TGT12/.claude/skills/mkr-loop/SKILL.md"
status_pre="$(cd "$TGT12" && git status --porcelain -uall)"
out12="$(run_install --source "$SRC12" --target "$TGT12" --dry-run)"
rc12=$?
status_post="$(cd "$TGT12" && git status --porcelain -uall)"
ok15=1
[ "$rc12" -eq 1 ] || ok15=0
[ "$status_pre" = "$status_post" ] || ok15=0
[ -e "$(manifest_of "$TGT12")" ] && ok15=0
printf '%s\n' "$out12" | grep -qF "refused	.claude/skills/mkr-loop/SKILL.md" || ok15=0
printf '%s\n' "$out12" | grep -qF "created	CLAUDE.md" || ok15=0
if [ "$ok15" -eq 1 ]; then
  ok "TC-M6-12a --dry-run with a refusal: exit 1, shows real labels, writes nothing"
else
  bad "TC-M6-12a --dry-run with a refusal: exit 1, shows real labels, writes nothing" "$out12"
fi
cleanup "$TGT12"

SRC12B="$(fixture_source)"; TGT12B="$(fixture_target)"
out12b="$(run_install --source "$SRC12B" --target "$TGT12B" --dry-run)"
if [ $? -eq 0 ]; then
  ok "TC-M6-12b --dry-run against an all-clean fixture → exit 0"
else
  bad "TC-M6-12b --dry-run against an all-clean fixture → exit 0" "$out12b"
fi
cleanup "$SRC12"; cleanup "$SRC12B"; cleanup "$TGT12B"

echo
echo "== install.sh: gitignored path still written, WARN on stderr (TC-M6-13) =="

SRC13="$(fixture_source)"; TGT13="$(fixture_target)"
printf '.claude/skills/mkr-loop/SKILL.md\n' > "$TGT13/.gitignore"
( cd "$TGT13" && git add .gitignore && git commit -qm gitignore )
out13="$(run_install --source "$SRC13" --target "$TGT13")"
ok16=1
[ -f "$TGT13/.claude/skills/mkr-loop/SKILL.md" ] || ok16=0
printf '%s\n' "$out13" | grep -qi 'mkr-loop/SKILL\.md' || ok16=0
printf '%s\n' "$out13" | grep -qi 'git status' || ok16=0
if [ "$ok16" -eq 1 ]; then
  ok "TC-M6-13 gitignored path is still written, and a warning names it + git-status visibility"
else
  bad "TC-M6-13 gitignored path is still written, and a warning names it + git-status visibility" "$out13"
fi
cleanup "$SRC13"; cleanup "$TGT13"

echo
echo "== install.sh: advises adding .mkr/audit.jsonl to .gitignore, never edits it (issue #11) =="

SRCG1="$(fixture_source)"; TGTG1="$(fixture_target)"
outg1="$(run_install --source "$SRCG1" --target "$TGTG1")"
okg1=1
printf '%s\n' "$outg1" | grep -qF 'install.sh: add .mkr/audit.jsonl to your .gitignore' || okg1=0
[ -e "$TGTG1/.gitignore" ] && okg1=0
if [ "$okg1" -eq 1 ]; then
  ok "G11a fresh install with no .gitignore entry for .mkr/audit.jsonl prints the advisory, writes no .gitignore"
else
  bad "G11a fresh install with no .gitignore entry for .mkr/audit.jsonl prints the advisory, writes no .gitignore" "$outg1"
fi
cleanup "$SRCG1"; cleanup "$TGTG1"

SRCG2="$(fixture_source)"; TGTG2="$(fixture_target)"
printf '.mkr/audit.jsonl\n' > "$TGTG2/.gitignore"
( cd "$TGTG2" && git add .gitignore && git commit -qm gitignore )
outg2="$(run_install --source "$SRCG2" --target "$TGTG2")"
okg2=1
printf '%s\n' "$outg2" | grep -qF 'install.sh: add .mkr/audit.jsonl to your .gitignore' && okg2=0
if [ "$okg2" -eq 1 ]; then
  ok "G11b already-ignored .mkr/audit.jsonl: advisory is suppressed"
else
  bad "G11b already-ignored .mkr/audit.jsonl: advisory is suppressed" "$outg2"
fi
cleanup "$SRCG2"; cleanup "$TGTG2"

SRCG3="$(fixture_source)"; TGTG3="$(fixture_target)"
outg3="$(run_install --source "$SRCG3" --target "$TGTG3" --dry-run)"
okg3=1
printf '%s\n' "$outg3" | grep -qF 'install.sh: add .mkr/audit.jsonl to your .gitignore' && okg3=0
if [ "$okg3" -eq 1 ]; then
  ok "G11c --dry-run never prints the advisory (nothing was actually installed)"
else
  bad "G11c --dry-run never prints the advisory (nothing was actually installed)" "$outg3"
fi
cleanup "$SRCG3"; cleanup "$TGTG3"

echo
echo "== install.sh: writes confined to the enumerated set (TC-M6-14) =="

ok17=1
grep -q 'git commit' "$INSTALL" && ok17=0
grep -q 'git push' "$INSTALL" && ok17=0
grep -qF 'claude' "$INSTALL" && grep -qE '\bclaude\s' "$INSTALL" && ok17=0
grep -qE '\.claude/hooks/scripts/' "$INSTALL" && ok17=0
if [ "$ok17" -eq 1 ]; then
  ok "TC-M6-14a static check: no git commit/push/claude/hooks-script invocation in install.sh"
else
  bad "TC-M6-14a static check: no git commit/push/claude/hooks-script invocation in install.sh" "found a forbidden call"
fi

SRC14="$(fixture_source)"; TGT14="$(fixture_target)"
printf 'stray top-level file\n' > "$SRC14/stray.txt"
run_install --source "$SRC14" --target "$TGT14" >/dev/null
if [ ! -e "$TGT14/stray.txt" ]; then
  ok "TC-M6-14b a stray file outside .claude/+seed/ is never copied to target"
else
  bad "TC-M6-14b a stray file outside .claude/+seed/ is never copied to target" "stray.txt was copied"
fi
cleanup "$SRC14"; cleanup "$TGT14"

echo
echo "== install.sh: a self-referential .claude/mkr-manifest in --source is never enumerated (G4 fix) =="

SRC14B="$(fixture_source)"
printf '# mkr-manifest v1\nleftover from a prior chained install\n' > "$SRC14B/.claude/mkr-manifest"
TGT14B="$(fixture_target)"
out14b="$(run_install --source "$SRC14B" --target "$TGT14B")"
ok25=1
[ $? -eq 0 ] || true
[ -f "$TGT14B/.claude/mkr-manifest" ] || ok25=0
grep -q 'mkr-manifest$' "$(manifest_of "$TGT14B")" && ok25=0
printf '%s\n' "$out14b" | grep -q 'mkr-manifest' && ok25=0
if [ "$ok25" -eq 1 ]; then
  ok "G4 fix: a leftover .claude/mkr-manifest inside --source is excluded from enumeration"
else
  bad "G4 fix: a leftover .claude/mkr-manifest inside --source is excluded from enumeration" "$out14b"
fi
cleanup "$SRC14B"; cleanup "$TGT14B"

echo
echo "== install.sh: end-to-end (TC-M6-15) =="

SRC15A="$(fixture_source)"; TGT15="$(fixture_target)"
run_install --source "$SRC15A" --target "$TGT15" >/dev/null
run_install --source "$SRC15A" --target "$TGT15" >/dev/null
claude_md_v1="$(cat "$TGT15/CLAUDE.md")"
mkr_config_v1="$(cat "$TGT15/.mkr/config")"
SRC15B="$(fixture_source)"
printf '# mkr-loop skill v2\n' > "$SRC15B/.claude/skills/mkr-loop/SKILL.md"
run_install --source "$SRC15B" --target "$TGT15" >/dev/null
ok18=1
cmp -s "$TGT15/.claude/skills/mkr-loop/SKILL.md" "$SRC15B/.claude/skills/mkr-loop/SKILL.md" || ok18=0
[ "$(cat "$TGT15/CLAUDE.md")" = "$claude_md_v1" ] || ok18=0
[ "$(cat "$TGT15/.mkr/config")" = "$mkr_config_v1" ] || ok18=0
if [ "$ok18" -eq 1 ]; then
  ok "TC-M6-15 end-to-end: install, no-op re-run, upgrade — CLAUDE.md/.mkr/config never touched"
else
  bad "TC-M6-15 end-to-end: install, no-op re-run, upgrade — CLAUDE.md/.mkr/config never touched" "diff"
fi
cleanup "$SRC15A"; cleanup "$SRC15B"; cleanup "$TGT15"

echo
echo "== install.sh: bare positional arg / repeated flag (TC-M6-20) =="

SRC20="$(fixture_source)"; TGT20="$(fixture_target)"
out20="$(run_install --source "$SRC20" extra-arg --target "$TGT20")"
if [ $? -eq 1 ]; then
  ok "TC-M6-20a bare positional argument → exit 1"
else
  bad "TC-M6-20a bare positional argument → exit 1" "$out20"
fi
cleanup "$TGT20"

TGT20A="$(fixture_target)"; TGT20B="$(fixture_target)"
out20b="$(run_install --source "$SRC20" --target "$TGT20A" --target "$TGT20B")"
ok19=1
[ $? -eq 0 ] || ok19=0
[ -f "$TGT20B/CLAUDE.md" ] || ok19=0
[ -f "$TGT20A/CLAUDE.md" ] && ok19=0
if [ "$ok19" -eq 1 ]; then
  ok "TC-M6-20b repeated --target: last occurrence wins, no error"
else
  bad "TC-M6-20b repeated --target: last occurrence wins, no error" "$out20b"
fi
cleanup "$SRC20"; cleanup "$TGT20A"; cleanup "$TGT20B"

echo
echo "== install.sh: --source validation (TC-M6-21, first sub-check modified by TC-BOOT-07) =="

TGT21="$(fixture_target)"
n21=0
BADREPO21="/nonexistent-repo-path-xyz-21"
out21="$(run_install --repo "$BADREPO21" --target "$TGT21")"
[ $? -eq 1 ] && n21=$((n21+1)) || bad "TC-M6-21/TC-BOOT-07 --source omitted, --repo unreachable" "$out21"

out21b="$(run_install --source /nonexistent-source-path-xyz --target "$TGT21")"
[ $? -eq 1 ] && n21=$((n21+1)) || bad "TC-M6-21 --source nonexistent" "$out21b"

BADSRC="$(mktemp -d)"
out21c="$(run_install --source "$BADSRC" --target "$TGT21")"
[ $? -eq 1 ] && n21=$((n21+1)) || bad "TC-M6-21 --source lacking .claude/+seed/" "$out21c"

if [ "$n21" -eq 3 ]; then
  ok "TC-M6-21 all three --source validation scenarios refuse"
else
  bad "TC-M6-21 all three --source validation scenarios refuse" "only $n21/3"
fi
cleanup "$TGT21"; cleanup "$BADSRC"

echo
echo "== install.sh: manifest sorted by path (TC-M6-22) =="

SRC22="$(fixture_source)"
mkdir -p "$SRC22/.claude/zzz-last" "$SRC22/.claude/aaa-first"
printf 'z\n' > "$SRC22/.claude/zzz-last/f.txt"
printf 'a\n' > "$SRC22/.claude/aaa-first/f.txt"
TGT22="$(fixture_target)"
run_install --source "$SRC22" --target "$TGT22" >/dev/null
data_lines="$(sed '1d' "$(manifest_of "$TGT22")" | awk '{print $3}')"
sorted_lines="$(printf '%s\n' "$data_lines" | LC_ALL=C sort)"
if [ "$data_lines" = "$sorted_lines" ]; then
  ok "TC-M6-22 manifest data lines are in strict path-sorted order"
else
  bad "TC-M6-22 manifest data lines are in strict path-sorted order" "$data_lines"
fi
cleanup "$SRC22"; cleanup "$TGT22"

echo
echo "== install.sh: stale manifest hash, content already matches (TC-M6-23) =="

SRC23="$(fixture_source)"; TGT23="$(fixture_target)"
run_install --source "$SRC23" --target "$TGT23" >/dev/null
MAN23="$(manifest_of "$TGT23")"
sed -i 's/^[0-9a-f]\{64\}\( 644 \.claude\/skills\/mkr-loop\/SKILL\.md\)$/deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\1/' "$MAN23"
out23="$(run_install --source "$SRC23" --target "$TGT23")"
rc23=$?
ok20=1
[ "$rc23" -eq 0 ] || ok20=0
printf '%s\n' "$out23" | grep -qF "unchanged	.claude/skills/mkr-loop/SKILL.md" || ok20=0
cmp -s "$TGT23/.claude/skills/mkr-loop/SKILL.md" "$SRC23/.claude/skills/mkr-loop/SKILL.md" || ok20=0
grep -qE '^[0-9a-f]{64} 644 \.claude/skills/mkr-loop/SKILL\.md$' "$MAN23" || ok20=0
grep -q 'deadbeef' "$MAN23" && ok20=0
if [ "$ok20" -eq 1 ]; then
  ok "TC-M6-23 stale manifest hash corrected on the next run, content untouched, disclosed unchanged"
else
  bad "TC-M6-23 stale manifest hash corrected on the next run, content untouched, disclosed unchanged" "$out23"
fi
cleanup "$SRC23"; cleanup "$TGT23"

echo
echo "== install.sh: corrupted manifest fallback (TC-M6-24) =="

SRC24="$(fixture_source)"; TGT24="$(fixture_target)"
run_install --source "$SRC24" --target "$TGT24" >/dev/null
MAN24="$(manifest_of "$TGT24")"
sed -i '2s/.*/deadbeef malformed-line-no-path-field/' "$MAN24"
out24="$(run_install --source "$SRC24" --target "$TGT24")"
rc24=$?
ok21=1
[ "$rc24" -eq 0 ] || ok21=0
printf '%s\n' "$out24" | grep -qi 'unreadable' || ok21=0
printf '%s\n' "$out24" | grep -qF "unchanged	.claude/hooks/lib/config.sh" || ok21=0
printf '%s\n' "$out24" | grep -qF "unchanged	.claude/skills/mkr-loop/SKILL.md" || ok21=0
[ "$(sed -n '1p' "$MAN24")" = "# mkr-manifest v1" ] || ok21=0
grep -qE '^[0-9a-f]{64} 755 \.claude/hooks/lib/config\.sh$' "$MAN24" || ok21=0
if [ "$ok21" -eq 1 ]; then
  ok "TC-M6-24a corrupted manifest → WARN, fallback to unchanged (not spurious refusal), rebuilt well-formed"
else
  bad "TC-M6-24a corrupted manifest → WARN, fallback to unchanged (not spurious refusal), rebuilt well-formed" "$out24"
fi
cleanup "$SRC24"; cleanup "$TGT24"

SRC24B="$(fixture_source)"; TGT24B="$(fixture_target)"
run_install --source "$SRC24B" --target "$TGT24B" >/dev/null
MAN24B="$(manifest_of "$TGT24B")"
sed -i '2s/.*/deadbeef malformed-line-no-path-field/' "$MAN24B"
printf 'also hand-edited\n' > "$TGT24B/.claude/skills/mkr-loop/SKILL.md"
out24b="$(run_install --source "$SRC24B" --target "$TGT24B")"
rc24b=$?
ok22=1
[ "$rc24b" -eq 1 ] || ok22=0
printf '%s\n' "$out24b" | grep -qF "refused	.claude/skills/mkr-loop/SKILL.md" || ok22=0
if [ "$ok22" -eq 1 ]; then
  ok "TC-M6-24b corrupted manifest + a genuinely divergent path → that path still refused"
else
  bad "TC-M6-24b corrupted manifest + a genuinely divergent path → that path still refused" "$out24b"
fi
cleanup "$SRC24B"; cleanup "$TGT24B"

echo
echo "== install.sh: mode-only drift repair (TC-M6-26) =="

SRC26="$(fixture_source)"; TGT26="$(fixture_target)"
run_install --source "$SRC26" --target "$TGT26" >/dev/null
chmod 644 "$TGT26/.claude/hooks/lib/config.sh"
out26="$(run_install --source "$SRC26" --target "$TGT26")"
rc26=$?
ok23=1
[ "$rc26" -eq 0 ] || ok23=0
printf '%s\n' "$out26" | grep -qF "unchanged	.claude/hooks/lib/config.sh" || ok23=0
[ "$(stat -c '%a' "$TGT26/.claude/hooks/lib/config.sh")" = 755 ] || ok23=0
[ -e "$TGT26/.claude/hooks/lib/config.sh.mkr-backup" ] && ok23=0
if [ "$ok23" -eq 1 ]; then
  ok "TC-M6-26a mode-only drift is repaired, disclosed unchanged, no backup"
else
  bad "TC-M6-26a mode-only drift is repaired, disclosed unchanged, no backup" "$out26"
fi

chmod 644 "$TGT26/.claude/hooks/lib/config.sh"
printf 'diverged\n' > "$TGT26/.claude/skills/mkr-loop/SKILL.md"
out26b="$(run_install --source "$SRC26" --target "$TGT26")"
rc26b=$?
ok24=1
[ "$rc26b" -eq 1 ] || ok24=0
[ "$(stat -c '%a' "$TGT26/.claude/hooks/lib/config.sh")" = 644 ] || ok24=0
if [ "$ok24" -eq 1 ]; then
  ok "TC-M6-26b mode repair staged, not in-place: a co-occurring refusal leaves the mode unrepaired"
else
  bad "TC-M6-26b mode repair staged, not in-place: a co-occurring refusal leaves the mode unrepaired" "$out26b"
fi
cleanup "$SRC26"; cleanup "$TGT26"

echo
echo "== install.sh: ships .github/workflows/mkr-gate.yml (TC-CIW-01) =="

SRCC1="$(fixture_source)"; add_github_workflow "$SRCC1"; TGTC1="$(fixture_target)"
outc1="$(run_install --source "$SRCC1" --target "$TGTC1")"
okc1=1
[ -f "$TGTC1/.github/workflows/mkr-gate.yml" ] || okc1=0
diff -q "$SRCC1/.github/workflows/mkr-gate.yml" "$TGTC1/.github/workflows/mkr-gate.yml" >/dev/null 2>&1 || okc1=0
printf '%s\n' "$outc1" | grep -qF "created	.github/workflows/mkr-gate.yml" || okc1=0
MANC1="$(manifest_of "$TGTC1")"
HASHC1="$(sha256sum "$SRCC1/.github/workflows/mkr-gate.yml" | awk '{print $1}')"
grep -qF "$HASHC1 644 .github/workflows/mkr-gate.yml" "$MANC1" || okc1=0
if [ "$okc1" -eq 1 ]; then
  ok "TC-CIW-01 fresh install ships .github/workflows/mkr-gate.yml, disclosed + manifest-recorded"
else
  bad "TC-CIW-01 fresh install ships .github/workflows/mkr-gate.yml, disclosed + manifest-recorded" "$outc1"
fi

echo
echo "== install.sh: re-run is a no-op for .github/ (TC-CIW-02) =="

status_before="$(cd "$TGTC1" && git status --porcelain -uall)"
manifest_before="$(cat "$MANC1")"
outc2="$(run_install --source "$SRCC1" --target "$TGTC1")"
rcc2=$?
okc2=1
[ "$rcc2" -eq 0 ] || okc2=0
printf '%s\n' "$outc2" | grep -qF "unchanged	.github/workflows/mkr-gate.yml" || okc2=0
status_after="$(cd "$TGTC1" && git status --porcelain -uall)"
manifest_after="$(cat "$MANC1")"
[ "$status_before" = "$status_after" ] || okc2=0
[ "$manifest_before" = "$manifest_after" ] || okc2=0
if [ "$okc2" -eq 1 ]; then
  ok "TC-CIW-02 re-run is a byte-identical no-op for .github/workflows/mkr-gate.yml"
else
  bad "TC-CIW-02 re-run is a byte-identical no-op for .github/workflows/mkr-gate.yml" "$outc2"
fi
cleanup "$SRCC1"; cleanup "$TGTC1"

echo
echo "== install.sh: update to .github/workflows/mkr-gate.yml backs up + overwrites (TC-CIW-03) =="

SRCC3="$(fixture_source)"; add_github_workflow "$SRCC3"; TGTC3="$(fixture_target)"
run_install --source "$SRCC3" --target "$TGTC3" >/dev/null
printf 'name: mkr-gate\n# fixture CI workflow v2\n' > "$SRCC3/.github/workflows/mkr-gate.yml"
outc3="$(run_install --source "$SRCC3" --target "$TGTC3")"
okc3=1
printf '%s\n' "$outc3" | grep -qF "updated	.github/workflows/mkr-gate.yml" || okc3=0
diff -q "$SRCC3/.github/workflows/mkr-gate.yml" "$TGTC3/.github/workflows/mkr-gate.yml" >/dev/null 2>&1 || okc3=0
[ -f "$TGTC3/.github/workflows/mkr-gate.yml.mkr-backup" ] || okc3=0
grep -qF 'v1' "$TGTC3/.github/workflows/mkr-gate.yml.mkr-backup" || okc3=0
if [ "$okc3" -eq 1 ]; then
  ok "TC-CIW-03 updated .github/workflows/mkr-gate.yml overwrites target, backs up pre-overwrite bytes"
else
  bad "TC-CIW-03 updated .github/workflows/mkr-gate.yml overwrites target, backs up pre-overwrite bytes" "$outc3"
fi
cleanup "$SRCC3"; cleanup "$TGTC3"

echo
echo "== install.sh: --source with no .github/ at all is not an error (TC-CIW-04) =="

SRCC4="$(fixture_source)"; TGTC4="$(fixture_target)"
outc4="$(run_install --source "$SRCC4" --target "$TGTC4")"
rcc4=$?
okc4=1
[ "$rcc4" -eq 0 ] || okc4=0
printf '%s\n' "$outc4" | grep -q '\.github' && okc4=0
[ -d "$TGTC4/.github" ] && okc4=0
[ -f "$TGTC4/.claude/hooks/lib/config.sh" ] || okc4=0
if [ "$okc4" -eq 1 ]; then
  ok "TC-CIW-04 --source with no .github/ directory installs normally, no .github/ row appears"
else
  bad "TC-CIW-04 --source with no .github/ directory installs normally, no .github/ row appears" "$outc4"
fi
cleanup "$SRCC4"; cleanup "$TGTC4"

echo
echo "== install.sh: symlink at target .github/workflows/mkr-gate.yml refuses the run (TC-CIW-05) =="

SRCC5="$(fixture_source)"; add_github_workflow "$SRCC5"; TGTC5="$(fixture_target)"
mkdir -p "$TGTC5/.github/workflows"
ln -s /nonexistent "$TGTC5/.github/workflows/mkr-gate.yml"
outc5="$(run_install --source "$SRCC5" --target "$TGTC5")"
rcc5=$?
okc5=1
[ "$rcc5" -eq 1 ] || okc5=0
printf '%s\n' "$outc5" | grep -qF '.github/workflows/mkr-gate.yml' || okc5=0
[ -e "$TGTC5/.claude/hooks/lib/config.sh" ] && okc5=0
if [ "$okc5" -eq 1 ]; then
  ok "TC-CIW-05 target-side symlink at .github/workflows/mkr-gate.yml refuses the whole run, naming it"
else
  bad "TC-CIW-05 target-side symlink at .github/workflows/mkr-gate.yml refuses the whole run, naming it" "$outc5"
fi
cleanup "$SRCC5"; cleanup "$TGTC5"

echo
echo "== install.sh: bootstrap clones --repo when --source omitted (TC-BOOT-01) =="

SRCREPO1="$(fixture_source_repo)"; TGT1B="$(fixture_target)"
out1b="$(run_install --repo "$SRCREPO1" --target "$TGT1B")"
rc1b=$?
ok1b=1
[ "$rc1b" -eq 0 ] || ok1b=0
[ -f "$TGT1B/.claude/hooks/lib/config.sh" ] && cmp -s "$TGT1B/.claude/hooks/lib/config.sh" "$SRCREPO1/.claude/hooks/lib/config.sh" || ok1b=0
[ "$(stat -c '%a' "$TGT1B/.claude/hooks/lib/config.sh" 2>/dev/null)" = 755 ] || ok1b=0
[ -f "$TGT1B/.claude/skills/mkr-loop/SKILL.md" ] && cmp -s "$TGT1B/.claude/skills/mkr-loop/SKILL.md" "$SRCREPO1/.claude/skills/mkr-loop/SKILL.md" || ok1b=0
[ -f "$TGT1B/CLAUDE.md" ] && cmp -s "$TGT1B/CLAUDE.md" "$SRCREPO1/seed/CLAUDE.md" || ok1b=0
[ -f "$TGT1B/.mkr/config" ] && cmp -s "$TGT1B/.mkr/config" "$SRCREPO1/seed/config" || ok1b=0
if [ "$ok1b" -eq 1 ]; then
  ok "TC-BOOT-01 no --source: bootstraps from --repo, installs exactly as --source would"
else
  bad "TC-BOOT-01 no --source: bootstraps from --repo, installs exactly as --source would" "$out1b"
fi

echo
echo "== install.sh: bootstrap + staging temp dirs both cleaned up (TC-BOOT-02) =="

tmp1b="$(bootstrap_tmp_from_output "$out1b")"
ok2b=1
[ -n "$tmp1b" ] || ok2b=0
[ -d "$tmp1b" ] && ok2b=0
stagecount1b="$(find "$TGT1B" -maxdepth 1 -name '.mkr-install-tmp.*' 2>/dev/null | wc -l)"
[ "$stagecount1b" -eq 0 ] || ok2b=0
if [ "$ok2b" -eq 1 ]; then
  ok "TC-BOOT-02 bootstrap clone dir and stage_and_move's staging dir both gone after the run"
else
  bad "TC-BOOT-02 bootstrap clone dir and stage_and_move's staging dir both gone after the run" "tmp=$tmp1b stagecount=$stagecount1b"
fi
cleanup "$SRCREPO1"; cleanup "$TGT1B"

echo
echo "== install.sh: bootstrap + --dry-run installs nothing but reports correctly (TC-BOOT-03) =="

SRCREPO3="$(fixture_source_repo)"; TGT3B="$(fixture_target)"
out3b="$(run_install --repo "$SRCREPO3" --target "$TGT3B" --dry-run)"
rc3b=$?
ok3b=1
[ "$rc3b" -eq 0 ] || ok3b=0
for p in .claude/hooks/lib/config.sh .claude/skills/mkr-loop/SKILL.md CLAUDE.md .mkr/config; do
  printf '%s\n' "$out3b" | grep -qF "created	$p" || ok3b=0
done
[ -e "$TGT3B/.claude" ] && ok3b=0
[ -e "$TGT3B/CLAUDE.md" ] && ok3b=0
tmp3b="$(bootstrap_tmp_from_output "$out3b")"
[ -n "$tmp3b" ] || ok3b=0
[ -d "$tmp3b" ] && ok3b=0
if [ "$ok3b" -eq 1 ]; then
  ok "TC-BOOT-03 --dry-run bootstrap: reports created\\t<path>, writes nothing, clone dir cleaned up"
else
  bad "TC-BOOT-03 --dry-run bootstrap: reports created\\t<path>, writes nothing, clone dir cleaned up" "$out3b"
fi
cleanup "$SRCREPO3"; cleanup "$TGT3B"

echo
echo "== install.sh: unreachable --repo fails cleanly, cleans up (TC-BOOT-04) =="

BADREPO4="/nonexistent-repo-path-xyz-04"
TGT4B="$(fixture_target)"
out4b="$(run_install --repo "$BADREPO4" --target "$TGT4B")"
rc4b=$?
ok4b=1
[ "$rc4b" -eq 1 ] || ok4b=0
printf '%s\n' "$out4b" | grep -qF "$BADREPO4" || ok4b=0
[ -e "$TGT4B/.claude" ] && ok4b=0
tmp4b="$(bootstrap_tmp_from_output "$out4b")"
[ -n "$tmp4b" ] || ok4b=0
[ -d "$tmp4b" ] && ok4b=0
if [ "$ok4b" -eq 1 ]; then
  ok "TC-BOOT-04 unreachable --repo: exit 1, names the URL, nothing written, temp dir cleaned up"
else
  bad "TC-BOOT-04 unreachable --repo: exit 1, names the URL, nothing written, temp dir cleaned up" "$out4b"
fi
cleanup "$TGT4B"

echo
echo "== install.sh: --repo ignored when --source given (TC-BOOT-06) =="

SRC6="$(fixture_source)"; TGT6B="$(fixture_target)"
BADREPO6="/nonexistent-repo-path-xyz-06"
out6b="$(run_install --source "$SRC6" --repo "$BADREPO6" --target "$TGT6B")"
rc6b=$?
ok6b=1
[ "$rc6b" -eq 0 ] || ok6b=0
[ -f "$TGT6B/.claude/hooks/lib/config.sh" ] && cmp -s "$TGT6B/.claude/hooks/lib/config.sh" "$SRC6/.claude/hooks/lib/config.sh" || ok6b=0
if [ "$ok6b" -eq 1 ]; then
  ok "TC-BOOT-06 --repo has no effect when --source is also given"
else
  bad "TC-BOOT-06 --repo has no effect when --source is also given" "$out6b"
fi
cleanup "$SRC6"; cleanup "$TGT6B"

echo
echo "== install.sh: no test call site depends on real network (TC-BOOT-08) =="

noncompliant="$(grep -n 'run_install ' "${BASH_SOURCE[0]}" \
  | grep -v 'run_install() {' \
  | grep -v "grep -n 'run_install" \
  | grep -v -- '--source' \
  | grep -v -- '--repo' \
  | grep -v -- '--help' \
  | grep -v -- '--uninstall')"
ok8b=1
[ -z "$noncompliant" ] || ok8b=0
if [ "$ok8b" -eq 1 ]; then
  ok "TC-BOOT-08 every run_install call site passes --source or --repo (none relies on the real default URL)"
else
  bad "TC-BOOT-08 every run_install call site passes --source or --repo (none relies on the real default URL)" "$noncompliant"
fi

echo
echo "== install.sh: --repo cannot use git's ext:: transport to run arbitrary commands (TC-BOOT-12) =="

MARKER12="$(mktemp -u)-boot12-marker"
TGT12B="$(fixture_target)"
out12b="$(run_install --repo "ext::sh -c \"touch $MARKER12\"" --target "$TGT12B")"
rc12b=$?
ok12b=1
[ "$rc12b" -eq 1 ] || ok12b=0
[ -e "$MARKER12" ] && ok12b=0
[ -e "$TGT12B/.claude" ] && ok12b=0
if [ "$ok12b" -eq 1 ]; then
  ok "TC-BOOT-12 ext:: --repo scheme is blocked (GIT_ALLOW_PROTOCOL), no command execution"
else
  bad "TC-BOOT-12 ext:: --repo scheme is blocked (GIT_ALLOW_PROTOCOL), no command execution" "$out12b"
fi
rm -f "$MARKER12"
cleanup "$TGT12B"

echo
echo "== install.sh: pre-push-review-guard.sh installed as a real git hook (issue #5) =="

SRCG5="$(fixture_source)"; add_git_hook_script "$SRCG5"; TGTG5="$(fixture_target)"
outg5="$(run_install --source "$SRCG5" --target "$TGTG5")"
okg5a=1
[ -L "$TGTG5/.git/hooks/pre-push" ] || okg5a=0
[ "$(readlink -- "$TGTG5/.git/hooks/pre-push")" = "../../.claude/hooks/scripts/pre-push-review-guard.sh" ] || okg5a=0
printf '%s\n' "$outg5" | grep -qF "created	.git/hooks/pre-push" || okg5a=0
[ "$(cd "$TGTG5" && bash .git/hooks/pre-push)" = "fixture pre-push-review-guard v1" ] || okg5a=0
if [ "$okg5a" -eq 1 ]; then
  ok "G5a fresh install symlinks .git/hooks/pre-push to the shipped script, disclosed, actually runs it"
else
  bad "G5a fresh install symlinks .git/hooks/pre-push to the shipped script, disclosed, actually runs it" "$outg5"
fi

status_before5="$(cd "$TGTG5" && git status --porcelain -uall)"
SRCG5B="$(fixture_source)"; add_git_hook_script "$SRCG5B"
outg5b="$(run_install --source "$SRCG5B" --target "$TGTG5")"
rcg5b=$?
status_after5="$(cd "$TGTG5" && git status --porcelain -uall)"
okg5b=1
[ "$rcg5b" -eq 0 ] || okg5b=0
printf '%s\n' "$outg5b" | grep -qF "unchanged	.git/hooks/pre-push" || okg5b=0
[ "$status_before5" = "$status_after5" ] || okg5b=0
if [ "$okg5b" -eq 1 ]; then
  ok "G5b re-run is a byte-identical no-op for .git/hooks/pre-push too"
else
  bad "G5b re-run is a byte-identical no-op for .git/hooks/pre-push too" "$outg5b"
fi
cleanup "$SRCG5"; cleanup "$SRCG5B"; cleanup "$TGTG5"

# An adopter's own pre-existing, different pre-push hook is refused like any other divergent path.
SRCG5C="$(fixture_source)"; add_git_hook_script "$SRCG5C"; TGTG5C="$(fixture_target)"
mkdir -p "$TGTG5C/.git/hooks"
printf '#!/usr/bin/env bash\necho adopter-own-hook\n' > "$TGTG5C/.git/hooks/pre-push"
chmod 755 "$TGTG5C/.git/hooks/pre-push"
outg5c="$(run_install --source "$SRCG5C" --target "$TGTG5C")"
rcg5c=$?
okg5c=1
[ "$rcg5c" -eq 1 ] || okg5c=0
printf '%s\n' "$outg5c" | grep -qF "refused	.git/hooks/pre-push" || okg5c=0
[ "$(cd "$TGTG5C" && bash .git/hooks/pre-push)" = "adopter-own-hook" ] || okg5c=0
if [ "$okg5c" -eq 1 ]; then
  ok "G5c an adopter's own different pre-push hook refuses the whole run without --force, left untouched"
else
  bad "G5c an adopter's own different pre-push hook refuses the whole run without --force, left untouched" "$outg5c"
fi

outg5d="$(run_install --source "$SRCG5C" --target "$TGTG5C" --force)"
rcg5d=$?
okg5d=1
[ "$rcg5d" -eq 0 ] || okg5d=0
printf '%s\n' "$outg5d" | grep -qF "forced-update	.git/hooks/pre-push" || okg5d=0
[ -f "$TGTG5C/.git/hooks/pre-push.mkr-backup" ] || okg5d=0
[ "$(cat "$TGTG5C/.git/hooks/pre-push.mkr-backup" 2>/dev/null)" = "$(printf '#!/usr/bin/env bash\necho adopter-own-hook')" ] || okg5d=0
[ -L "$TGTG5C/.git/hooks/pre-push" ] || okg5d=0
if [ "$okg5d" -eq 1 ]; then
  ok "G5d --force overwrites the adopter's hook with our symlink, backing up their bytes first"
else
  bad "G5d --force overwrites the adopter's hook with our symlink, backing up their bytes first" "$outg5d"
fi
cleanup "$SRCG5C"; cleanup "$TGTG5C"

# core.hooksPath customization is left alone entirely — no row, no write, nothing refused.
SRCG5E="$(fixture_source)"; add_git_hook_script "$SRCG5E"; TGTG5E="$(fixture_target)"
mkdir -p "$TGTG5E/custom-hooks"
( cd "$TGTG5E" && git config core.hooksPath custom-hooks )
outg5e="$(run_install --source "$SRCG5E" --target "$TGTG5E")"
rcg5e=$?
okg5e=1
[ "$rcg5e" -eq 0 ] || okg5e=0
printf '%s\n' "$outg5e" | grep -q '\.git/hooks/pre-push' && okg5e=0
[ -e "$TGTG5E/.git/hooks/pre-push" ] && okg5e=0
if [ "$okg5e" -eq 1 ]; then
  ok "G5e a configured core.hooksPath is left alone: no row, no write, install still succeeds"
else
  bad "G5e a configured core.hooksPath is left alone: no row, no write, install still succeeds" "$outg5e"
fi
cleanup "$SRCG5E"; cleanup "$TGTG5E"

# --source with no pre-push-review-guard.sh at all: no row, no error — matches TC-CIW-04's shape
# for a --source with no .github/ at all.
SRCG5F="$(fixture_source)"; TGTG5F="$(fixture_target)"
outg5f="$(run_install --source "$SRCG5F" --target "$TGTG5F")"
rcg5f=$?
okg5f=1
[ "$rcg5f" -eq 0 ] || okg5f=0
printf '%s\n' "$outg5f" | grep -q '\.git/hooks/pre-push' && okg5f=0
[ -e "$TGTG5F/.git/hooks/pre-push" ] && okg5f=0
if [ "$okg5f" -eq 1 ]; then
  ok "G5f --source with no pre-push-review-guard.sh installs normally, no .git/hooks/pre-push row"
else
  bad "G5f --source with no pre-push-review-guard.sh installs normally, no .git/hooks/pre-push row" "$outg5f"
fi
cleanup "$SRCG5F"; cleanup "$TGTG5F"

echo
echo "== install.sh: --uninstall is report-only without --confirm (issue #3, docs/adr/0005) =="

SRCG3="$(fixture_source)"; add_git_hook_script "$SRCG3"; TGTG3="$(fixture_target)"
run_install --source "$SRCG3" --target "$TGTG3" >/dev/null
status_before_g3="$(cd "$TGTG3" && git status --porcelain -uall)"
outg3a="$(run_install --uninstall --target "$TGTG3")"
rcg3a=$?
status_after_g3="$(cd "$TGTG3" && git status --porcelain -uall)"
okg3a=1
[ "$rcg3a" -eq 0 ] || okg3a=0
printf '%s
' "$outg3a" | grep -qF "would-remove	.claude/hooks/lib/config.sh" || okg3a=0
printf '%s
' "$outg3a" | grep -qF "would-remove	.claude/mkr-manifest" || okg3a=0
printf '%s
' "$outg3a" | grep -qF "would-remove	.git/hooks/pre-push" || okg3a=0
[ -f "$TGTG3/.claude/hooks/lib/config.sh" ] || okg3a=0
[ -f "$TGTG3/.claude/mkr-manifest" ] || okg3a=0
[ -L "$TGTG3/.git/hooks/pre-push" ] || okg3a=0
[ "$status_before_g3" = "$status_after_g3" ] || okg3a=0
if [ "$okg3a" -eq 1 ]; then
  ok "G3a --uninstall without --confirm reports every owned path, deletes nothing"
else
  bad "G3a --uninstall without --confirm reports every owned path, deletes nothing" "$outg3a"
fi

echo
echo "== install.sh: --uninstall --confirm actually removes what it owns (issue #3) =="

outg3b="$(run_install --uninstall --target "$TGTG3" --confirm)"
rcg3b=$?
okg3b=1
[ "$rcg3b" -eq 0 ] || okg3b=0
printf '%s
' "$outg3b" | grep -qF "removed	.claude/hooks/lib/config.sh" || okg3b=0
printf '%s
' "$outg3b" | grep -qF "removed	.claude/mkr-manifest" || okg3b=0
printf '%s
' "$outg3b" | grep -qF "removed	.git/hooks/pre-push" || okg3b=0
[ -e "$TGTG3/.claude/hooks/lib/config.sh" ] && okg3b=0
[ -e "$TGTG3/.claude/skills/mkr-loop/SKILL.md" ] && okg3b=0
[ -e "$TGTG3/.claude/mkr-manifest" ] && okg3b=0
[ -e "$TGTG3/.git/hooks/pre-push" ] && okg3b=0
[ -f "$TGTG3/CLAUDE.md" ] || okg3b=0
[ -f "$TGTG3/.mkr/config" ] || okg3b=0
if [ "$okg3b" -eq 1 ]; then
  ok "G3b --uninstall --confirm removes every owned path and the manifest, CLAUDE.md/.mkr/config survive"
else
  bad "G3b --uninstall --confirm removes every owned path and the manifest, CLAUDE.md/.mkr/config survive" "$outg3b"
fi
cleanup "$SRCG3"; cleanup "$TGTG3"

echo
echo "== install.sh: --uninstall on a never-installed target is a clean no-op (issue #3) =="

TGTG3C="$(fixture_target)"
outg3c="$(run_install --uninstall --target "$TGTG3C" --confirm)"
rcg3c=$?
if [ "$rcg3c" -eq 0 ] && printf '%s
' "$outg3c" | grep -qi 'nothing to uninstall'; then
  ok "G3c --uninstall on a target with no manifest: clean no-op, exit 0"
else
  bad "G3c --uninstall on a target with no manifest: clean no-op, exit 0" "$outg3c"
fi
cleanup "$TGTG3C"

echo
echo "== install.sh: foreign-toolkit file advisory (issue #3, docs/adr/0005) =="

SRCG3D="$(fixture_source)"; TGTG3D="$(fixture_target)"
mkdir -p "$TGTG3D/.claude/skills/some-other-toolkit"
printf '# unrelated skill from a different toolkit
' > "$TGTG3D/.claude/skills/some-other-toolkit/SKILL.md"
outg3d="$(run_install --source "$SRCG3D" --target "$TGTG3D")"
okg3d=1
printf '%s
' "$outg3d" | grep -qi 'unrecognized file' || okg3d=0
printf '%s
' "$outg3d" | grep -qF '.claude/skills/some-other-toolkit/SKILL.md' || okg3d=0
[ -f "$TGTG3D/.claude/skills/some-other-toolkit/SKILL.md" ] || okg3d=0
if [ "$okg3d" -eq 1 ]; then
  ok "G3d a foreign file at a template-owned location is reported, never touched"
else
  bad "G3d a foreign file at a template-owned location is reported, never touched" "$outg3d"
fi

outg3e="$(run_install --source "$SRCG3D" --target "$TGTG3D" --dry-run)"
if printf '%s
' "$outg3e" | grep -qF '.claude/skills/some-other-toolkit/SKILL.md'; then
  ok "G3e the foreign-file advisory also surfaces under --dry-run"
else
  bad "G3e the foreign-file advisory also surfaces under --dry-run" "$outg3e"
fi
cleanup "$SRCG3D"; cleanup "$TGTG3D"

SRCG3F="$(fixture_source)"; TGTG3F="$(fixture_target)"
outg3f="$(run_install --source "$SRCG3F" --target "$TGTG3F")"
if ! printf '%s
' "$outg3f" | grep -qi 'unrecognized file'; then
  ok "G3f a clean fixture (nothing foreign) never triggers the advisory"
else
  bad "G3f a clean fixture (nothing foreign) never triggers the advisory" "$outg3f"
fi
cleanup "$SRCG3F"; cleanup "$TGTG3F"

echo
echo "== install.sh: settings.json key-level merge, jq available (issue #1) =="

if command -v jq >/dev/null 2>&1; then
  SRCG1="$(fixture_source)"; add_settings_json "$SRCG1"; TGTG1="$(fixture_target)"
  mkdir -p "$TGTG1/.claude"
  cat > "$TGTG1/.claude/settings.json" <<'JSONEOF'
{
  "permissions": { "allow": ["Bash(npm test:*)"] },
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/secret-guard.sh" },
          { "type": "command", "command": "${CLAUDE_PROJECT_DIR}/.claude/hooks/scripts/adopter-own-guard.sh" }
        ]
      }
    ]
  }
}
JSONEOF
  chmod 644 "$TGTG1/.claude/settings.json"
  outg1="$(run_install --source "$SRCG1" --target "$TGTG1")"
  rcg1=$?
  okg1a=1
  [ "$rcg1" -eq 0 ] || okg1a=0
  printf '%s
' "$outg1" | grep -qF "merged	.claude/settings.json" || okg1a=0
  [ -f "$TGTG1/.claude/settings.json.mkr-backup" ] || okg1a=0
  command -v python3 >/dev/null 2>&1 && {
    python3 -c "
import json, sys
d = json.load(open('$TGTG1/.claude/settings.json'))
cmds = [h['command'] for m in d['hooks']['PreToolUse'] for h in m['hooks']]
assert any('adopter-own-guard.sh' in c for c in cmds), 'adopter hook missing'
assert any('branch-guard.sh' in c for c in cmds), 'template hook missing'
assert d.get('permissions', {}).get('allow') == ['Bash(npm test:*)'], 'adopter top-level key missing'
stop_cmds = [h['command'] for m in d['hooks']['Stop'] for h in m['hooks']]
assert any('stop-checks.sh' in c for c in stop_cmds), 'template Stop hook missing'
" || okg1a=0
  }
  if [ "$okg1a" -eq 1 ]; then
    ok "G1a divergent settings.json merges instead of refusing: adopter's hook and template's hooks both survive"
  else
    bad "G1a divergent settings.json merges instead of refusing: adopter's hook and template's hooks both survive" "$outg1"
  fi

  echo
  echo "== install.sh: settings.json merge is idempotent (issue #1) =="

  status_before_g1="$(cd "$TGTG1" && git status --porcelain -uall)"
  SRCG1B="$(fixture_source)"; add_settings_json "$SRCG1B"
  outg1b="$(run_install --source "$SRCG1B" --target "$TGTG1")"
  rcg1b=$?
  status_after_g1="$(cd "$TGTG1" && git status --porcelain -uall)"
  okg1b=1
  [ "$rcg1b" -eq 0 ] || okg1b=0
  printf '%s
' "$outg1b" | grep -qF "unchanged	.claude/settings.json" || okg1b=0
  [ "$status_before_g1" = "$status_after_g1" ] || okg1b=0
  if [ "$okg1b" -eq 1 ]; then
    ok "G1b re-merging an already-merged settings.json is a byte-identical no-op, not a re-overwrite"
  else
    bad "G1b re-merging an already-merged settings.json is a byte-identical no-op, not a re-overwrite" "$outg1b"
  fi
  cleanup "$SRCG1"; cleanup "$SRCG1B"; cleanup "$TGTG1"
else
  echo "  (jq not on PATH in this environment — G1a/G1b skipped, jq-present behavior untestable here)"
fi

echo
echo "== install.sh: settings.json falls back to refuse/--force when jq is unavailable (issue #1) =="

BINDIR_NOJQ="$(mktemp -d)"
for c in bash git find sort awk stat cp mv mkdir chmod rm mktemp sed dirname cat env grep sha256sum shasum printf; do
  p="$(type -P "$c" 2>/dev/null)"
  [ -n "$p" ] && ln -sf "$p" "$BINDIR_NOJQ/$(basename "$p")" 2>/dev/null
done
SRCG1C="$(fixture_source)"; add_settings_json "$SRCG1C"; TGTG1C="$(fixture_target)"
mkdir -p "$TGTG1C/.claude"
printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"adopter-only.sh"}]}]}}
' > "$TGTG1C/.claude/settings.json"
outg1c="$(cd "$ROOT" && PATH="$BINDIR_NOJQ" bash "$INSTALL" --source "$SRCG1C" --target "$TGTG1C" 2>&1)"
rcg1c=$?
okg1c=1
[ "$rcg1c" -eq 1 ] || okg1c=0
printf '%s
' "$outg1c" | grep -qF "refused	.claude/settings.json" || okg1c=0
[ "$(cat "$TGTG1C/.claude/settings.json")" = '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"adopter-only.sh"}]}]}}' ] || okg1c=0
if [ "$okg1c" -eq 1 ]; then
  ok "G1c no jq on PATH: settings.json refuses exactly as before merge support existed, file untouched"
else
  bad "G1c no jq on PATH: settings.json refuses exactly as before merge support existed, file untouched" "$outg1c"
fi

outg1d="$(cd "$ROOT" && PATH="$BINDIR_NOJQ" bash "$INSTALL" --source "$SRCG1C" --target "$TGTG1C" --force 2>&1)"
rcg1d=$?
okg1d=1
[ "$rcg1d" -eq 0 ] || okg1d=0
printf '%s
' "$outg1d" | grep -qF "forced-update	.claude/settings.json" || okg1d=0
cmp -s "$TGTG1C/.claude/settings.json" "$SRCG1C/.claude/settings.json" || okg1d=0
if [ "$okg1d" -eq 1 ]; then
  ok "G1d no jq on PATH, --force: full raw overwrite still works exactly as before merge support existed"
else
  bad "G1d no jq on PATH, --force: full raw overwrite still works exactly as before merge support existed" "$outg1d"
fi
rm -rf "$BINDIR_NOJQ"
cleanup "$SRCG1C"; cleanup "$TGTG1C"

echo
echo "== install.sh: malformed adopter settings.json falls back to refuse, never crashes (issue #1) =="

SRCG1E="$(fixture_source)"; add_settings_json "$SRCG1E"; TGTG1E="$(fixture_target)"
mkdir -p "$TGTG1E/.claude"
printf '{ this is not valid json' > "$TGTG1E/.claude/settings.json"
outg1e="$(run_install --source "$SRCG1E" --target "$TGTG1E")"
rcg1e=$?
okg1e=1
[ "$rcg1e" -eq 1 ] || okg1e=0
printf '%s
' "$outg1e" | grep -qF "refused	.claude/settings.json" || okg1e=0
[ "$(cat "$TGTG1E/.claude/settings.json")" = '{ this is not valid json' ] || okg1e=0
if [ "$okg1e" -eq 1 ]; then
  ok "G1e malformed adopter JSON: merge is skipped, falls back to refuse, file left untouched"
else
  bad "G1e malformed adopter JSON: merge is skipped, falls back to refuse, file left untouched" "$outg1e"
fi
cleanup "$SRCG1E"; cleanup "$TGTG1E"

echo
echo "== fixture_target(): hardened against a leaked GIT_DIR (specs/CIGateHardening_Spec.md TC-CGH-09) =="

DECOY_CGH="$(mktemp -d)"; ( cd "$DECOY_CGH" && git init -q ) >/dev/null 2>&1
FT_CGH="$( (export GIT_DIR="$DECOY_CGH/.git"; fixture_target) )"
resolved_cgh="$(git -C "$FT_CGH" rev-parse --show-toplevel 2>&1)"
if [ "$resolved_cgh" = "$FT_CGH" ]; then
  ok "TC-CGH-09 fixture_target() resolves its own real .git even with GIT_DIR leaked"
else
  bad "TC-CGH-09 fixture_target() resolves its own real .git even with GIT_DIR leaked" "want=$FT_CGH got=$resolved_cgh"
fi
cleanup "$DECOY_CGH"; cleanup "$FT_CGH"

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
