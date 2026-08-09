#!/usr/bin/env bash
# Spike harness for .claude/hooks/lib/config.sh
# Every case runs in a fresh bash with every MKR_* / _mkr_cfg_* and
# CLAUDE_PROJECT_DIR / GIT_DIR / GIT_WORK_TREE scrubbed, and with cwd outside any
# git work tree unless the case needs one.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LIB="$HERE/../.claude/hooks/lib/config.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want [$3] got [$2]"; fi; }

# The 28 §8 variable names, in table order — typed from the spec, not read from
# config.sh, so this list cannot silently agree with whatever the library ships.
# MKR_GATE_REVIEW added by specs/M2_CodeReview_Spec.md §8 (G4's owner).
# MKR_DESIGN_DIR/MKR_DEPLOY/MKR_EVALS_DIR/MKR_CAPTURE_LOG added by
# specs/M5_Gates_Spec.md §8. MKR_STOP_TEST_MODE/MKR_TEST_FAST added by
# specs/StopHookToggle_Spec.md §8. MKR_BOUNDARIES added by
# specs/M2_CodeReview_Spec.md's Data model (mkr-code-reviewer's Boundaries/Seams check).
# MKR_ID_DIRS added by specs/M3_Guardrails_Spec.md's Data model (id-collision-guard.sh's
# extensible ID-namespace coverage beyond MKR_ADR_DIR). MKR_REVIEW_VERDICT_STRING added by
# specs/M2_CodeReview_Spec.md's Data model (reviewrecord.sh's configurable VERDICT literal).
# MKR_SETUP added by specs/M3_Guardrails_Spec.md's Data model (mkr-gate.yml's repo-bootstrap seam).
MKR_NAMES_SPEC=(
  MKR_CONFIG_SCHEMA MKR_TEST MKR_STOP_TEST_MODE MKR_TEST_FAST MKR_COVERAGE MKR_TYPECHECK MKR_LINT MKR_BUILD MKR_SETUP
  MKR_SPECS_DIR MKR_ADR_DIR MKR_REVIEWS_DIR MKR_AUDITS_DIR
  MKR_DESIGN_DIR MKR_DEPLOY MKR_EVALS_DIR
  MKR_PROTECTED_BRANCHES MKR_WORKTREE_POLICY MKR_COVERAGE_MIN MKR_RISKY_PATHS MKR_BOUNDARIES MKR_ID_DIRS
  MKR_GATE_SPEC MKR_GATE_DESIGN MKR_GATE_MERGE MKR_GATE_DEPLOY MKR_GATE_REVIEW MKR_CAPTURE_LOG MKR_SELF_APPROVE
  MKR_PLAN_MANDATORY MKR_PLAN_OPTIONAL MKR_REVIEW_VERDICT_STRING MKR_SPEC_EXTRA_SECTIONS
)
# The literal §8 defaults — typed from the spec table, not derived from
# _mkr_default(). Comparing mkr_get against config.sh's own function proves
# nothing; comparing against these does.
declare -A MKR_DEFAULT_SPEC=(
  [MKR_CONFIG_SCHEMA]='1'
  [MKR_TEST]=''
  [MKR_STOP_TEST_MODE]=''
  [MKR_TEST_FAST]=''
  [MKR_COVERAGE]=''
  [MKR_TYPECHECK]=''
  [MKR_LINT]=''
  [MKR_BUILD]=''
  [MKR_SETUP]=''
  [MKR_SPECS_DIR]='specs/'
  [MKR_ADR_DIR]='docs/adr/'
  [MKR_REVIEWS_DIR]='.mkr/reviews/'
  [MKR_AUDITS_DIR]='.mkr/audits/'
  [MKR_DESIGN_DIR]='.mkr/designs/'
  [MKR_DEPLOY]=''
  [MKR_EVALS_DIR]='.mkr/evals/'
  [MKR_PROTECTED_BRANCHES]='main'
  [MKR_WORKTREE_POLICY]='off'
  [MKR_COVERAGE_MIN]='80'
  [MKR_RISKY_PATHS]=''
  [MKR_BOUNDARIES]=''
  [MKR_ID_DIRS]=''
  [MKR_GATE_SPEC]=''
  [MKR_GATE_DESIGN]=''
  [MKR_GATE_MERGE]=''
  [MKR_GATE_DEPLOY]=''
  [MKR_GATE_REVIEW]=''
  [MKR_CAPTURE_LOG]='.mkr/captures.jsonl'
  [MKR_SELF_APPROVE]='spec design'
  [MKR_PLAN_MANDATORY]='spec-first reuse-check test-first self-review verify code-review'
  [MKR_PLAN_OPTIONAL]='contract-first coverage-gate adr-for-risky design-before-tests auth-every-surface isolation-every-table api-parity ui-feedback-per-wave build-directive-conformance'
  [MKR_REVIEW_VERDICT_STRING]='VERDICT: READY'
  [MKR_SPEC_EXTRA_SECTIONS]=''
)

CLEAN=(env -u CLAUDE_PROJECT_DIR -u MKR_CONFIG -u GIT_DIR -u GIT_WORK_TREE -u BASH_ENV -u ENV)
for n in "${MKR_NAMES_SPEC[@]}" MKR_CONFIG_ACTIVE MKR_CONFIG_PATH; do
  CLEAN+=(-u "$n" -u "_mkr_cfg_${n#MKR_}")
done

# run <snippet>            → stdout only, in a scrubbed shell, cwd = non-git tmp
# runenv "V=1 W=2" <snip>  → same, plus those env assignments
NOGIT="$TMP/nogit"; mkdir -p "$NOGIT"
run()    { ( cd "$NOGIT" && "${CLEAN[@]}" bash -c "$1" 2>/dev/null ); }
runerr() { ( cd "$NOGIT" && "${CLEAN[@]}" bash -c "$1" 2>&1 >/dev/null ); }
runrc()  { ( cd "$NOGIT" && "${CLEAN[@]}" bash -c "$1" >/dev/null 2>&1; echo $? ); }
runenv() { local e="$1"; shift; ( cd "$NOGIT" && "${CLEAN[@]}" $e bash -c "$1" 2>/dev/null ); }

cfg() { printf '%s\n' "$2" > "$TMP/$1"; printf '%s' "$TMP/$1"; }

echo "== resolution and defaults =="

is "TC-01 no config → inactive" \
   "$(run ". '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "0"

for n in "${MKR_NAMES_SPEC[@]}"; do
  is "TC-01 default $n matches §8 literally" \
     "$(run ". '$LIB'; mkr_get $n")" "${MKR_DEFAULT_SPEC[$n]}"
done

C_FULL="$(cfg full 'MKR_TEST="make test"
MKR_COVERAGE_MIN=90
MKR_PROTECTED_BRANCHES="main release"')"
is "TC-02 configured value wins" "$(run "MKR_CONFIG='$C_FULL' . '$LIB'; mkr_get MKR_TEST")" "make test"
is "TC-02 active" "$(run "MKR_CONFIG='$C_FULL' . '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "1"
is "TC-02 path absolute" "$(run "MKR_CONFIG='$C_FULL' . '$LIB'; echo \$MKR_CONFIG_PATH")" "$C_FULL"

mkdir -p "$NOGIT/rel"
printf 'MKR_TEST=relhit\n' > "$NOGIT/rel/cfg"
is "TC-02b relative MKR_CONFIG path is absolutised" \
   "$(run "MKR_CONFIG='rel/cfg' . '$LIB'; echo \$MKR_CONFIG_PATH")" "$NOGIT/rel/cfg"
is "TC-02b relative MKR_CONFIG value still resolves" \
   "$(run "MKR_CONFIG='rel/cfg' . '$LIB'; mkr_get MKR_TEST")" "relhit"

C_RESERVED="$(cfg reserved 'MKR_TEST=x
MKR_CONFIG_ACTIVE=99
MKR_CONFIG_PATH=/evil
MKR_CONFIG=/evil2')"
is "TC-02c real ACTIVE/PATH unaffected by a config that sets those names" \
   "$(run "MKR_CONFIG='$C_RESERVED' . '$LIB'; echo \$MKR_CONFIG_ACTIVE:\$MKR_CONFIG_PATH")" "1:$C_RESERVED"
is "TC-02c real value still comes through" \
   "$(run "MKR_CONFIG='$C_RESERVED' . '$LIB'; mkr_get MKR_TEST")" "x"
# The exclusion's actual job: these three names must never reach a _mkr_cfg_*
# slot at all, so looking them up through mkr_get (the only thing that reads
# those slots) must not surface the config's value for them.
is "TC-02c reserved MKR_CONFIG_ACTIVE not importable via mkr_get" \
   "$(run "MKR_CONFIG='$C_RESERVED' . '$LIB'; mkr_get MKR_CONFIG_ACTIVE")" ""
is "TC-02c reserved MKR_CONFIG_PATH not importable via mkr_get" \
   "$(run "MKR_CONFIG='$C_RESERVED' . '$LIB'; mkr_get MKR_CONFIG_PATH")" ""
is "TC-02c reserved MKR_CONFIG not importable via mkr_get" \
   "$(run "MKR_CONFIG='$C_RESERVED' . '$LIB'; mkr_get MKR_CONFIG")" ""

C_EMPTY="$(cfg empty 'MKR_COVERAGE_MIN=""')"
is "TC-03 empty == unset" "$(run "MKR_CONFIG='$C_EMPTY' . '$LIB'; mkr_get MKR_COVERAGE_MIN")" "80"

is "TC-04 fallback beats default" "$(run ". '$LIB'; mkr_get MKR_COVERAGE_MIN 55")" "55"
is "TC-04 value beats fallback"   "$(run "MKR_CONFIG='$C_FULL' . '$LIB'; mkr_get MKR_COVERAGE_MIN 55")" "90"

is "TC-05 list applies defaults" \
   "$(run ". '$LIB'; mkr_list MKR_PLAN_MANDATORY | wc -l")" "6"
is "TC-05 list order preserved" \
   "$(run ". '$LIB'; mkr_list MKR_PLAN_MANDATORY | head -1")" "spec-first"

mkdir -p "$NOGIT/auth" "$NOGIT/infra"; : > "$NOGIT/auth/x"; : > "$NOGIT/infra/y"
C_GLOB="$(cfg glob 'MKR_RISKY_PATHS="**/auth/** **/migrations/** infra/** .github/**"')"
is "TC-06 globs unexpanded" "$(run "MKR_CONFIG='$C_GLOB' . '$LIB'; mkr_list MKR_RISKY_PATHS | wc -l")" "4"
is "TC-06 globstar caller"  "$(run "shopt -s globstar; MKR_CONFIG='$C_GLOB' . '$LIB'; mkr_list MKR_RISKY_PATHS | wc -l")" "4"

C_TAB="$(cfg tab $'MKR_RISKY_PATHS="a\tb c"')"
is "TC-06b mkr_list splits on space only, not the default IFS" \
   "$(run "MKR_CONFIG='$C_TAB' . '$LIB'; mkr_list MKR_RISKY_PATHS | wc -l")" "2"
is "TC-06b tab stays inside an item" \
   "$(run "MKR_CONFIG='$C_TAB' . '$LIB'; mkr_list MKR_RISKY_PATHS | head -1 | cat -A")" 'a^Ib$'

C_UNREAD="$(cfg unreadable 'MKR_TEST=x')"
chmod 000 "$C_UNREAD"
if [ "$(id -u)" = "0" ]; then
  # `chmod 000` never makes a file unreadable to root (DAC override) — this test's own
  # precondition cannot hold while running as root, unrelated to config.sh's real permission
  # handling below, which is untouched and still enforced for every non-root execution
  # (including real CI, which never runs as root). Named skip, not a silent pass: a mutation
  # deleting the permission check entirely would still be caught by this test suite under any
  # normal (non-root) run.
  echo "  SKIP TC-06c unreadable-file checks (running as root — chmod 000 is not enforced)"
else
  is "TC-06c unreadable file → inactive" "$(run "MKR_CONFIG='$C_UNREAD' . '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "0"
  is "TC-06c unreadable file → exactly one warning" "$(runerr "MKR_CONFIG='$C_UNREAD' . '$LIB'" | wc -l)" "1"
  # Without the dedicated check, the child's own failed `.` produces the same
  # ACTIVE=0/one-warning shape — only the warning's wording distinguishes an
  # explicit permission check from falling through to the generic failure path.
  is "TC-06c unreadable file → the permission-specific warning, not the generic one" \
     "$(runerr "MKR_CONFIG='$C_UNREAD' . '$LIB'")" "mkr: $C_UNREAD is not readable; config inactive"
fi
chmod 600 "$C_UNREAD"

echo
echo "== the caller's shell is not collateral =="

is "TC-07 set -eu caller survives" \
   "$(run "set -eu; . '$LIB'; mkr_get MKR_TEST >/dev/null; echo SURVIVED")" "SURVIVED"
is "TC-07 \$- byte-identical (set -eu)" \
   "$(run "set -eu; B=\$-; . '$LIB'; mkr_get MKR_TEST >/dev/null; mkr_list MKR_PLAN_MANDATORY >/dev/null; [ \"\$B\" = \"\$-\" ] && echo SAME || echo \"\$B|\$-\"")" "SAME"
is "TC-07 \$- byte-identical (no flags)" \
   "$(run "set +eu +f; B=\$-; . '$LIB'; mkr_get MKR_TEST >/dev/null; [ \"\$B\" = \"\$-\" ] && echo SAME || echo \"\$B|\$-\"")" "SAME"
is "TC-07 caller's -f preserved" \
   "$(run "set -f; B=\$-; . '$LIB'; mkr_list MKR_PLAN_MANDATORY >/dev/null; [ \"\$B\" = \"\$-\" ] && echo SAME || echo \"\$B|\$-\"")" "SAME"
is "TC-07 IFS restored" \
   "$(run ". '$LIB'; I=\$IFS; mkr_list MKR_PLAN_MANDATORY >/dev/null; [ \"\$I\" = \"\$IFS\" ] && echo SAME || echo DIFF")" "SAME"
is "TC-07b mkr_list leaves an originally-unset IFS unset" \
   "$(run ". '$LIB'; unset IFS; mkr_list MKR_PLAN_MANDATORY >/dev/null; [ -z \"\${IFS+set}\" ] && echo UNSET || echo \"SET=[\$IFS]\"")" "UNSET"
is "N-m mkr_get returns 0 for a normal resolved value" \
   "$(runrc ". '$LIB'; mkr_get MKR_COVERAGE_MIN >/dev/null")" "0"

echo
echo "== hostile and malformed configs are contained =="

C_SYN="$(cfg syn 'MKR_TEST="unterminated')"
is "TC-08 syntax error → survives" "$(run "MKR_CONFIG='$C_SYN' . '$LIB'; echo SURVIVED")" "SURVIVED"
is "TC-08 syntax error → inactive" "$(run "MKR_CONFIG='$C_SYN' . '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "0"
is "TC-08 syntax error → default"  "$(run "MKR_CONFIG='$C_SYN' . '$LIB'; mkr_get MKR_COVERAGE_MIN")" "80"
is "TC-08 exactly one warning"     "$(runerr "MKR_CONFIG='$C_SYN' . '$LIB'; mkr_get MKR_TEST" | wc -l)" "1"

C_EXIT="$(cfg hexit 'MKR_TEST=x
exit 1')"
is "N-a config that exits → survives" "$(run "MKR_CONFIG='$C_EXIT' . '$LIB'; echo SURVIVED")" "SURVIVED"

C_SETE="$(cfg hsete 'set -e
false
MKR_TEST=x')"
is "N-b config with set -e+false → survives" "$(run "MKR_CONFIG='$C_SETE' . '$LIB'; echo SURVIVED")" "SURVIVED"
is "N-b caller keeps its own flags"          "$(run "set +e; B=\$-; MKR_CONFIG='$C_SETE' . '$LIB'; [ \"\$B\" = \"\$-\" ] && echo SAME || echo DIFF")" "SAME"

C_CD="$(cfg hcd 'cd /
MKR_TEST=x')"
is "N-c config that cds → caller cwd intact" "$(run "MKR_CONFIG='$C_CD' . '$LIB'; pwd")" "$NOGIT"

C_KILL="$(cfg hkill 'kill -TERM $$
MKR_TEST=x')"
is "N-d config that kills → survives" "$(run "MKR_CONFIG='$C_KILL' . '$LIB'; echo SURVIVED")" "SURVIVED"

# The internals a config could actually reach are the child's own top-level
# names (_mkr_n, _mkr_rc) — a config is never sourced anywhere near _mkr_load's
# locals, which live in a separate process. Clobbering names that don't exist
# in the implementation (_mkr_dash, _mkr_ifs) cannot fail for any input.
C_CLOB="$(cfg hclob 'MKR_TEST=x
_mkr_n=zzz
_mkr_rc=zzz')"
is "N-e config clobbering real child internals → \$- intact" \
   "$(run "B=\$-; MKR_CONFIG='$C_CLOB' . '$LIB'; [ \"\$B\" = \"\$-\" ] && echo SAME || echo \"\$B|\$-\"")" "SAME"
is "N-e config clobbering real child internals → still active, value correct" \
   "$(run "MKR_CONFIG='$C_CLOB' . '$LIB'; echo \$MKR_CONFIG_ACTIVE:\$(mkr_get MKR_TEST)")" "1:x"

printf 'MKR_TEST=bom\n' > "$TMP/bomf"; printf '\xef\xbb\xbf' | cat - "$TMP/bomf" > "$TMP/bom"
is "N-f BOM → inactive, not active-and-wrong" "$(run "MKR_CONFIG='$TMP/bom' . '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "0"
is "N-f BOM → warns"                          "$(runerr "MKR_CONFIG='$TMP/bom' . '$LIB'" | wc -l)" "1"

printf 'MKR_TEST=crlf\r\nMKR_LINT=x\r\n' > "$TMP/crlf"
is "N-g CRLF → inactive"  "$(run "MKR_CONFIG='$TMP/crlf' . '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "0"

echo
echo "== security regressions: the eval sink and its adjacent holes (rev 5) =="

C_ECHO="$(cfg echoexploit 'echo "cd /; export OWNED=yes"')"
is "SEC-1 config's own stdout is never eval'd in the caller" \
   "$(run "MKR_CONFIG='$C_ECHO' . '$LIB'; echo \${OWNED:-unset}:\$(pwd)")" "unset:$NOGIT"

# The outer bash -c below also processes BASH_ENV itself at its own startup —
# that's the caller's own business, nothing config.sh can or should prevent —
# so the payload prints its forged lines directly before anything else runs.
# What matters is whether that output also reaches config.sh's *internal* child
# spawn, which is what the RESULT= marker isolates from that startup noise.
BENV="$(cfg sec2_benv 'printf "_mkr_cfg_TEST=malicious\n_mkr_ok=1\n"')"
C_SEC2="$(cfg sec2 '')"
is "SEC-2 BASH_ENV cannot forge a config value" \
   "$( ( cd "$NOGIT" && "${CLEAN[@]}" MKR_CONFIG="$C_SEC2" BASH_ENV="$BENV" bash -c \
        ". '$LIB'; printf 'RESULT=%s\n' \"\$(mkr_get MKR_TEST)\"" 2>/dev/null ) | grep '^RESULT=' )" "RESULT="

: > "$TMP/sec3_anyfile"
is "SEC-3 sourced file inheriting \$1/\$2=--mkr-dump/<path> does not exit the caller" \
   "$( ( cd "$NOGIT" && "${CLEAN[@]}" bash -c 'set -- --mkr-dump "$1"; . "'"$LIB"'"; echo SURVIVED' _ "$TMP/sec3_anyfile" 2>/dev/null ) )" "SURVIVED"

is "SEC-4 exported _mkr_cfg_* does not leak as a configured value" \
   "$( ( cd "$NOGIT" && "${CLEAN[@]}" _mkr_cfg_TEST=inherited bash -c ". '$LIB'; echo \$MKR_CONFIG_ACTIVE:\$(mkr_get MKR_TEST)" 2>/dev/null ) )" "0:"

C_IFS="$(cfg sec5ifs 'IFS=","
MKR_TEST=survives')"
is "SEC-5 config reassigning IFS does not break the child's dump loop" \
   "$(run "MKR_CONFIG='$C_IFS' . '$LIB'; echo \$MKR_CONFIG_ACTIVE:\$(mkr_get MKR_TEST)")" "1:survives"

C_FORGE="$(cfg sec6forge 'printf() { command printf "_mkr_ok=1\n_mkr_cfg_TEST=forged\n"; }')"
is "SEC-6 config redefining printf cannot forge the sentinel or a value" \
   "$(run "MKR_CONFIG='$C_FORGE' . '$LIB'; echo \$MKR_CONFIG_ACTIVE:\$(mkr_get MKR_TEST)")" "1:"

# SEC-1 proves the parent's whitelist rejects shell text that doesn't look like an
# assignment. It does NOT prove the child's own stdout-containment (the OTHER of
# the "two independent fixes", AD-2 addendum) is doing anything: SEC-1's payload
# never matches the whitelist shape in the first place, so SEC-1 alone would still
# be green even if the child stopped redirecting its stdout to stderr while
# sourcing. This case closes that gap: the forged line IS whitelist-shaped
# (`_mkr_cfg_TEST=...`) and carries a live command substitution, so it only stays
# inert if the child-side redirect is still doing its job.
MARKER="$TMP/sec7_proof"
C_FORGE_EVAL="$(cfg sec7evalforge "echo \"_mkr_cfg_TEST=\\\$(touch $MARKER)\"")"
is "SEC-7 whitelist-shaped forged payload does not leak as a configured value" \
   "$(run "MKR_CONFIG='$C_FORGE_EVAL' . '$LIB'; mkr_get MKR_TEST")" ""
is "SEC-7 the forged payload's command substitution never executes in the caller" \
   "$([ -e "$MARKER" ] && echo EXISTS || echo ABSENT)" "ABSENT"
rm -f "$MARKER"

# SEC-6 proved a config can't forge the dump by shadowing `printf`, because the
# child calls `command printf`. That is not the whole guarantee: bash looks up
# a shell function before a builtin for the literal word being invoked, and
# that applies to `command` itself, not only to what follows it — a config
# defining `command() { ...; }` intercepts every `command printf` call in the
# child, including the one meant to be unshadowable. A forged line built this
# way is emitted by the trusted code path itself, so it never has to sneak
# past the parent's whitelist — it looks exactly like a real assignment. This
# was a real, confirmed bypass (not a hypothetical): it gave arbitrary command
# execution in the caller's shell via the eval this file's whitelist filter
# feeds. The fix is structural, not another name to protect: the dump now
# happens in a second, freshly exec'd bash process that never sourced the
# config, so no function it defined — this one included — exists there to
# intercept anything.
MARKER="$TMP/sec8_proof"
C_FORGE_COMMAND="$TMP/sec8forgecmd"
cat > "$C_FORGE_COMMAND" <<SEC8EOF
command() {
  if [ "\$1" = printf ]; then
    shift
    builtin printf "\$@"
    builtin printf '_mkr_cfg_LEAKED=\$(touch $MARKER)\n'
  fi
}
MKR_TEST=looks_totally_normal
SEC8EOF
is "SEC-8 config redefining the \`command\` builtin: real value still comes through" \
   "$(run "MKR_CONFIG='$C_FORGE_COMMAND' . '$LIB'; mkr_get MKR_TEST")" "looks_totally_normal"
is "SEC-8 config redefining the \`command\` builtin: forged value does not leak" \
   "$(run "MKR_CONFIG='$C_FORGE_COMMAND' . '$LIB'; mkr_get MKR_LEAKED")" ""
is "SEC-8 config redefining the \`command\` builtin: forged command substitution never executes" \
   "$([ -e "$MARKER" ] && echo EXISTS || echo ABSENT)" "ABSENT"
rm -f "$MARKER"

# The parent's whitelist must accept every name _mkr_valid_name accepts. A
# suffix class stricter than `[A-Z0-9_]*` (e.g. requiring a non-digit first
# character) silently drops a legal MKR_* name whose first character after
# MKR_ is a digit — ACTIVE=1, no warning, the value just never arrives.
C_DIGIT="$(cfg digitname 'MKR_2FOO=hello')"
is "N-n whitelist accepts a legal name starting with a digit after MKR_" \
   "$(run "MKR_CONFIG='$C_DIGIT' . '$LIB'; mkr_get MKR_2FOO")" "hello"

echo
echo "== provenance: the environment is not the config =="

is "N-h exported MKR_* does not win" \
   "$(runenv "MKR_COVERAGE_MIN=5" ". '$LIB'; mkr_get MKR_COVERAGE_MIN")" "80"
is "N-h exported MKR_* does not leak as a value" \
   "$(runenv "MKR_TEST=leaked" ". '$LIB'; mkr_get MKR_TEST")" ""
is "N-h config still wins over env" \
   "$(runenv "MKR_COVERAGE_MIN=5" "MKR_CONFIG='$C_FULL' . '$LIB'; mkr_get MKR_COVERAGE_MIN")" "90"

echo
echo "== resolution branches =="

is "TC-10 MKR_CONFIG missing → inactive"      "$(run "MKR_CONFIG='$TMP/nope' . '$LIB'; echo \$MKR_CONFIG_ACTIVE")" "0"
is "TC-10 MKR_CONFIG missing → warns"         "$(runerr "MKR_CONFIG='$TMP/nope' . '$LIB'" | wc -l)" "1"
is "TC-01 absent config is silent"            "$(runerr ". '$LIB'" | wc -l)" "0"

GITREPO="$TMP/repo"; mkdir -p "$GITREPO/.mkr" "$GITREPO/pkg/.mkr"
git -C "$GITREPO" init -q 2>/dev/null
printf 'MKR_TEST=from_gitroot\n' > "$GITREPO/.mkr/config"
is "TC-11 git root resolution" \
   "$( ( cd "$GITREPO/pkg" && "${CLEAN[@]}" bash -c ". '$LIB'; mkr_get MKR_TEST" 2>/dev/null ) )" "from_gitroot"

is "N-i CLAUDE_PROJECT_DIR is terminal (no upward search)" \
   "$( ( cd "$GITREPO/pkg" && "${CLEAN[@]}" CLAUDE_PROJECT_DIR="$GITREPO/pkg" bash -c ". '$LIB'; echo \$MKR_CONFIG_ACTIVE" 2>/dev/null ) )" "0"

is "N-j MKR_CONFIG beats CLAUDE_PROJECT_DIR" \
   "$( ( cd "$GITREPO" && "${CLEAN[@]}" CLAUDE_PROJECT_DIR="$GITREPO" MKR_CONFIG="$C_FULL" bash -c ". '$LIB'; mkr_get MKR_TEST" 2>/dev/null ) )" "make test"

echo
echo "== hygiene =="

is "TC-12 double source, same config" "$(run "export MKR_CONFIG='$C_FULL'; . '$LIB'; . '$LIB'; mkr_get MKR_TEST")" "make test"

C_RE_A="$(cfg reA 'MKR_TEST=configA
MKR_COVERAGE_MIN=11')"
C_RE_B="$(cfg reB 'MKR_TEST=configB')"
is "TC-12b second source, different config: not short-circuited" \
   "$(run "MKR_CONFIG='$C_RE_A' . '$LIB'; T1=\$(mkr_get MKR_TEST); MKR_CONFIG='$C_RE_B' . '$LIB'; echo \$T1:\$(mkr_get MKR_TEST)")" \
   "configA:configB"
is "TC-12b second source, different config: no config replaces, doesn't merge" \
   "$(run "MKR_CONFIG='$C_RE_A' . '$LIB'; MKR_CONFIG='$C_RE_B' . '$LIB'; mkr_get MKR_COVERAGE_MIN")" "80"
is "TC-12c a rejected second config does not keep serving the first config's values" \
   "$(run "MKR_CONFIG='$C_FULL' . '$LIB'; MKR_CONFIG='$TMP/nope' . '$LIB'; echo \$MKR_CONFIG_ACTIVE:\$(mkr_get MKR_TEST)")" "0:"

is "TC-13 sourcing never exits (behavioural)" \
   "$(run "set -eu; . '$LIB'; . '$LIB'; mkr_get MKR_TEST >/dev/null; mkr_list MKR_RISKY_PATHS >/dev/null; echo SENTINEL")" "SENTINEL"

is "N-k bad name warns, returns 0" "$(runrc ". '$LIB'; mkr_get lowercase")" "0"
is "N-k injection name rejected"   "$(run ". '$LIB'; mkr_get 'MKR_X};id;a={' 2>/dev/null; echo RC=\$?")" "RC=0"

is "N-l public symbols are functions" \
   "$(run ". '$LIB'; declare -F mkr_get mkr_list >/dev/null && echo YES")" "YES"

echo
echo "== CLI mode (the interface a skill can call) =="

is "CLI get default"  "$(run "'$LIB' get MKR_COVERAGE_MIN")" "80"
is "CLI get w/ config" "$(run "MKR_CONFIG='$C_FULL' '$LIB' get MKR_TEST")" "make test"
is "CLI list"         "$(run "'$LIB' list MKR_PLAN_MANDATORY | wc -l")" "6"
is "CLI dump lines"   "$(run "'$LIB' dump | wc -l")" "33"
is "CLI dump plan"    "$(run "'$LIB' dump | grep '^MKR_PLAN_MANDATORY=' | cut -d= -f2-")" \
                      "spec-first reuse-check test-first self-review verify code-review"
is "CLI active"       "$(run "MKR_CONFIG='$C_FULL' '$LIB' active")" "1"
is "CLI usage rc"     "$(runrc "'$LIB' bogus")" "2"

echo
echo "== seed pair and our own owned files (M0 §7.2, §12 tasks 5-6) =="

ROOT="$(cd -- "$HERE/.." && pwd)"
SEED_CONFIG="$ROOT/seed/config"
SEED_CLAUDE="$ROOT/seed/CLAUDE.md"
OUR_CONFIG="$ROOT/.mkr/config"
OUR_CLAUDE="$ROOT/CLAUDE.md"

HEADINGS_SPEC=(
  "What this project is"
  "Stack"
  "Commands"
  "How we build — the AIDLC loop"
  "Allowed actions"
  "Gate owners"
  "Non-negotiables"
  "Conventions"
)
EXPECT_HEADINGS="$(printf '%s\n' "${HEADINGS_SPEC[@]}")"
NONCONTENT_SECTIONS=("What this project is" "Stack" "Commands" "Gate owners" "Non-negotiables" "Conventions")

# TC-M0-19: seed/config sources cleanly; every §8 variable is defined and empty,
# and each assignment has a comment line directly above it.
_tc19_ok=1
for n in "${MKR_NAMES_SPEC[@]}"; do
  v="$(run ". '$SEED_CONFIG'; printf '%s' \"\${$n-__MKR_UNSET__}\"")"
  [ "$v" = "" ] || _tc19_ok=0
done
for n in "${MKR_NAMES_SPEC[@]}"; do
  ln="$(grep -n "^${n}=" "$SEED_CONFIG" | head -1 | cut -d: -f1)"
  if [ -z "$ln" ]; then _tc19_ok=0; continue; fi
  prev="$(sed -n "$((ln-1))p" "$SEED_CONFIG")"
  case "$prev" in \#*) ;; *) _tc19_ok=0 ;; esac
done
is "TC-19 seed/config defines every §8 variable empty, each commented above" "$_tc19_ok" "1"

# TC-M0-20: no non-empty value from our own .mkr/config, and no literal repo
# name, appears anywhere in the generic seed pair — except a config variable's own
# documented-enum comment (the line directly above its empty assignment, per TC-19): an
# enum-typed var (e.g. MKR_WORKTREE_POLICY's "off | advisory | enforced") will always
# coincidentally match whatever one of its own valid values this repo happens to set,
# which is expected vocabulary overlap, not a leaked, repo-specific fact.
_tc20_hits=0
for _n in "${MKR_NAMES_SPEC[@]}"; do
  _val="$(bash -c ". '$OUR_CONFIG' 2>/dev/null; printf '%s' \"\${$_n}\"")"
  [ -n "$_val" ] || continue
  _seed_ln="$(grep -n "^${_n}=" "$SEED_CONFIG" | head -1 | cut -d: -f1)"
  _own_comment_ln=0
  [ -n "$_seed_ln" ] && _own_comment_ln=$((_seed_ln - 1))
  _hit=0
  while IFS=: read -r _hl _rest; do
    [ -n "$_hl" ] || continue
    [ "$_hl" = "$_own_comment_ln" ] || _hit=1
  done < <(grep -nF -- "$_val" "$SEED_CONFIG" 2>/dev/null)
  grep -qF -- "$_val" "$SEED_CLAUDE" 2>/dev/null && _hit=1
  [ "$_hit" -eq 1 ] && _tc20_hits=$((_tc20_hits + 1))
done
grep -qF -- "mkr-aidlc" "$SEED_CONFIG" "$SEED_CLAUDE" 2>/dev/null && _tc20_hits=$((_tc20_hits + 1))
is "TC-20 seed pair carries no fact from our own .mkr/config or the repo name" "$_tc20_hits" "0"

# TC-M0-21: seed/CLAUDE.md has exactly the eight §7.2 headings, in order.
_seed_headings="$(grep '^## ' "$SEED_CLAUDE" | sed 's/^## //')"
is "TC-21 seed/CLAUDE.md has exactly the eight §7.2 headings in order" "$_seed_headings" "$EXPECT_HEADINGS"

# TC-M0-21: its six non-content sections each carry at least one placeholder.
_tc21b_ok=1
for h in "${NONCONTENT_SECTIONS[@]}"; do
  section="$(awk -v h="## $h" '$0==h{f=1;next} /^## /&&f{exit} f{print}' "$SEED_CLAUDE")"
  printf '%s\n' "$section" | grep -Eq '^[[:space:]]*<.+>[[:space:]]*$' || _tc21b_ok=0
done
is "TC-21 seed/CLAUDE.md: each non-content section has a placeholder line" "$_tc21b_ok" "1"

# TC-M0-22: our CLAUDE.md has the same eight headings, in order.
_our_headings="$(grep '^## ' "$OUR_CLAUDE" | sed 's/^## //')"
is "TC-22 our CLAUDE.md has exactly the eight §7.2 headings in order" "$_our_headings" "$EXPECT_HEADINGS"

# TC-M0-22: and no placeholder line remains anywhere in it.
if grep -Eq '^[[:space:]]*<.+>[[:space:]]*$' "$OUR_CLAUDE"; then _tc22b=0; else _tc22b=1; fi
is "TC-22 our CLAUDE.md has no placeholder line remaining" "$_tc22b" "1"

# TC-M0-23: our .mkr/config names a real, resolvable test command.
_our_test_val="$(bash -c ". '$OUR_CONFIG' 2>/dev/null; printf '%s' \"\$MKR_TEST\"")"
_first_word="${_our_test_val%% *}"
if [ -n "$_our_test_val" ] && command -v "$_first_word" >/dev/null 2>&1; then
  _tc23_ok=1
else
  _tc23_ok=0
fi
is "TC-23 our .mkr/config: MKR_TEST is non-empty and its command resolves on PATH" "$_tc23_ok" "1"

# TC-M0-24: VERSION is semver with no leading v.
_version="$(tr -d '\n' < "$ROOT/VERSION" 2>/dev/null)"
if [[ "$_version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then _tc24a=1; else _tc24a=0; fi
is "TC-24 VERSION is semver, no leading v" "$_tc24a" "1"

# TC-M0-24: LICENSE is MIT-0.
if grep -qi "MIT No Attribution" "$ROOT/LICENSE" 2>/dev/null; then _tc24b=1; else _tc24b=0; fi
is "TC-24 LICENSE is MIT-0" "$_tc24b" "1"

# TC-STH-12 (specs/StopHookToggle_Spec.md §9): MKR_STOP_TEST_MODE/MKR_TEST_FAST are consumed only
# by stop-checks.sh — CI and ground stay on the strict, shared MKR_TEST regardless of this repo's
# per-turn Stop-hook setting.
_tc_sth12=1
grep -q "MKR_STOP_TEST_MODE\|MKR_TEST_FAST" "$ROOT/.github/workflows/mkr-gate.yml" 2>/dev/null && _tc_sth12=0
grep -q "MKR_STOP_TEST_MODE\|MKR_TEST_FAST" "$ROOT/.claude/agents/mkr-auditor.md" 2>/dev/null && _tc_sth12=0
is "TC-STH-12 mkr-gate.yml and mkr-auditor unaffected by the new stop-hook variables" "$_tc_sth12" "1"

echo
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
