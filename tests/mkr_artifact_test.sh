#!/usr/bin/env bash
# M1 structural-shape checks (specs/M1_Loop_Spec.md §9, TC-M1-01..14).
#
# Skill/command/agent bodies are prompts, not code, so there is nothing to
# unit-test about their judgment (that's M5's mkr-evals). What this suite
# checks is the *shape* every artifact must have: required sections in
# required order, well-formed Status/verdict/TRIAGE strings, no leftover
# placeholder, no duplicate ADR number. TC-M1-01..09 and TC-M1-12..14 run
# against hand-written fixtures under tests/fixtures/ so the suite doesn't
# depend on any real spec/ADR staying byte-identical. TC-M1-10..11 check the
# real artifacts this milestone adds under .claude/ and docs/adr/ — until
# those are built, expect them red; that is test-first working as intended,
# not a suite bug.
set -uo pipefail

HERE="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd -- "$HERE/.." && pwd)"
FIX="$HERE/fixtures"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n     %s\n' "$1" "$2"; }

# ---------------------------------------------------------------- helpers --

# check_spec_structure <file>
# Verifies the 14 required §7.3 H2 headings are all present and in order.
# Prints MISSING:<heading> or ORDER_VIOLATION:<found> before <expected> on
# failure. Extra, non-required '## ' headings are ignored.
SPEC_REQUIRED=(
  "## 0. Triage" "## 1. Header" "## 2. Intent" "## 3. Scope"
  "## 4. Affected users & journey change" "## 5. Reuse check"
  "## 6. Architecture & key decisions" "## 7. Interfaces / contracts"
  "## 8. Data model" "## 9. Test-case register" "## 10. Acceptance criteria"
  "## 11. Definition of Done" "## 12. Task breakdown" "## 13. Review history"
)

check_spec_structure() {
  local file="$1" a r found i
  local actual=() missing=() filtered=()
  while IFS= read -r a; do actual+=("$a"); done < <(grep '^## ' -- "$file")

  for r in "${SPEC_REQUIRED[@]}"; do
    found=0
    for a in "${actual[@]}"; do [ "$a" = "$r" ] && { found=1; break; }; done
    [ "$found" = 0 ] && missing+=("$r")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'MISSING:%s\n' "${missing[0]}"
    return 1
  fi

  for a in "${actual[@]}"; do
    for r in "${SPEC_REQUIRED[@]}"; do
      [ "$a" = "$r" ] && { filtered+=("$a"); break; }
    done
  done
  for i in "${!SPEC_REQUIRED[@]}"; do
    if [ "${filtered[$i]}" != "${SPEC_REQUIRED[$i]}" ]; then
      printf 'ORDER_VIOLATION:%s before %s\n' "${filtered[$i]}" "${SPEC_REQUIRED[$i]}"
      return 1
    fi
  done
  return 0
}

# check_status_line <file> — the Header's Status row matches one of the
# three literal shapes §7.3 defines.
check_status_line() {
  local file="$1" row
  row="$(grep -m1 -- '\*\*Status\*\*' "$file" || true)"
  if [[ "$row" =~ \*\*Status\*\*\ \|\ (DRAFT\ rev\ [0-9]+|NOT\ READY\ rev\ [0-9]+\ \(.+\)|ACCEPTED\ rev\ [0-9]+\ \(.+\)) ]]; then
    return 0
  fi
  printf 'BAD_STATUS:%s\n' "$row"
  return 1
}

# check_approver <file> <expected> — the Header's Approver field equals
# <expected> (the calling repo's MKR_GATE_SPEC value).
check_approver() {
  local file="$1" expected="$2" row value
  row="$(grep -m1 -- '\*\*Approver\*\*' "$file" || true)"
  value="$(printf '%s' "$row" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
  if [ "$value" = "$expected" ]; then return 0; fi
  printf 'APPROVER_MISMATCH:got [%s] want [%s]\n' "$value" "$expected"
  return 1
}

# check_adr_shape <file> — the four required H2 sections, in order.
ADR_REQUIRED=("## Status" "## Context" "## Decision" "## Consequences")
check_adr_shape() {
  local file="$1" actual=()
  while IFS= read -r a; do actual+=("$a"); done < <(grep '^## ' -- "$file")
  if [ "${#actual[@]}" -ne "${#ADR_REQUIRED[@]}" ]; then
    printf 'WRONG_SECTION_COUNT:got %d want %d\n' "${#actual[@]}" "${#ADR_REQUIRED[@]}"
    return 1
  fi
  for i in "${!ADR_REQUIRED[@]}"; do
    if [ "${actual[$i]}" != "${ADR_REQUIRED[$i]}" ]; then
      printf 'ADR_ORDER_VIOLATION:%s\n' "${actual[$i]}"
      return 1
    fi
  done
  return 0
}

# check_adr_numbering <dir> — no two files share the same NNNN- prefix.
check_adr_numbering() {
  local dir="$1" f base num
  declare -A seen
  for f in "$dir"/*.md; do
    [ -e "$f" ] || continue
    base="$(basename -- "$f")"
    if [[ "$base" =~ ^([0-9]{4})- ]]; then
      num="${BASH_REMATCH[1]}"
      if [ -n "${seen[$num]:-}" ]; then
        printf 'DUP_ADR_NUMBER:%s (%s and %s)\n' "$num" "${seen[$num]}" "$base"
        return 1
      fi
      seen[$num]="$base"
    fi
  done
  return 0
}

# check_claude_md_structure <file> — the 8 required §7.2 H2 headings, in
# order (same subsequence technique as check_spec_structure).
CLAUDE_MD_REQUIRED=(
  "## What this project is" "## Stack" "## Commands"
  "## How we build — the AIDLC loop" "## Allowed actions" "## Gate owners"
  "## Non-negotiables" "## Conventions"
)
check_claude_md_structure() {
  local file="$1" a r found i
  local actual=() missing=() filtered=()
  while IFS= read -r a; do actual+=("$a"); done < <(grep '^## ' -- "$file")
  for r in "${CLAUDE_MD_REQUIRED[@]}"; do
    found=0
    for a in "${actual[@]}"; do [ "$a" = "$r" ] && { found=1; break; }; done
    [ "$found" = 0 ] && missing+=("$r")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'MISSING:%s\n' "${missing[0]}"
    return 1
  fi
  for a in "${actual[@]}"; do
    for r in "${CLAUDE_MD_REQUIRED[@]}"; do
      [ "$a" = "$r" ] && { filtered+=("$a"); break; }
    done
  done
  for i in "${!CLAUDE_MD_REQUIRED[@]}"; do
    if [ "${filtered[$i]}" != "${CLAUDE_MD_REQUIRED[$i]}" ]; then
      printf 'ORDER_VIOLATION:%s\n' "${filtered[$i]}"
      return 1
    fi
  done
  return 0
}

# check_no_placeholder <file> — no line matches ^\s*<.+>\s*$
check_no_placeholder() {
  local file="$1" hit
  hit="$(grep -nE '^[[:space:]]*<.+>[[:space:]]*$' -- "$file" || true)"
  if [ -n "$hit" ]; then
    printf 'PLACEHOLDER:%s\n' "$hit"
    return 1
  fi
  return 0
}

# check_triage_block <file> — the 8 required fields, in order.
TRIAGE_REQUIRED=(depth why scope reuse touches risky gates "done when")
check_triage_block() {
  local file="$1" f found i
  local actual=() missing=() filtered=()
  while IFS= read -r a; do actual+=("$a"); done < <(
    grep -oE '^(depth|why|scope|reuse|touches|risky|gates|done when):' -- "$file" \
      | sed -E 's/:$//'
  )
  for f in "${TRIAGE_REQUIRED[@]}"; do
    found=0
    for a in "${actual[@]}"; do [ "$a" = "$f" ] && { found=1; break; }; done
    [ "$found" = 0 ] && missing+=("$f")
  done
  if [ "${#missing[@]}" -gt 0 ]; then
    printf 'MISSING_FIELD:%s\n' "${missing[0]}"
    return 1
  fi
  for a in "${actual[@]}"; do
    for f in "${TRIAGE_REQUIRED[@]}"; do
      [ "$a" = "$f" ] && { filtered+=("$a"); break; }
    done
  done
  for i in "${!TRIAGE_REQUIRED[@]}"; do
    if [ "${filtered[$i]}" != "${TRIAGE_REQUIRED[$i]}" ]; then
      printf 'ORDER_VIOLATION:%s\n' "${filtered[$i]}"
      return 1
    fi
  done
  return 0
}

# check_plan_verdict <string> — exactly CONFORMANT or BLOCKED(...).
check_plan_verdict() {
  local v="$1"
  [[ "$v" =~ ^CONFORMANT$ ]] && return 0
  [[ "$v" =~ ^BLOCKED\(.*\)$ ]] && return 0
  return 1
}

# check_init_refuse <root_dir> — echoes BLOCK or PROCEED per AD-5.
MKR_TITLE_LINE="# mkr-aidlc — an open-source AIDLC template for Claude Code"
check_init_refuse() {
  local root="$1" f first_line
  f="$root/docs/DESIGN.md"
  if [ -f "$f" ]; then
    first_line="$(head -n1 -- "$f")"
    if [ "$first_line" = "$MKR_TITLE_LINE" ]; then
      echo BLOCK
      return 0
    fi
  fi
  echo PROCEED
  return 0
}

# check_frontmatter <file> <needs_name:0|1> — a leading YAML block with a
# non-empty description:, and a non-empty name: when needs_name=1.
check_frontmatter() {
  local file="$1" needs_name="$2" block desc name
  block="$(sed -n '2,/^---$/p' -- "$file" | sed '$d')"
  if [ "$(sed -n '1p' -- "$file")" != "---" ]; then
    echo 'NO_FRONTMATTER'
    return 1
  fi
  desc="$(printf '%s\n' "$block" | grep -m1 '^description:' | sed -E 's/^description:[[:space:]]*//')"
  if [ -z "$desc" ]; then
    echo 'EMPTY_DESCRIPTION'
    return 1
  fi
  if [ "$needs_name" = 1 ]; then
    name="$(printf '%s\n' "$block" | grep -m1 '^name:' | sed -E 's/^name:[[:space:]]*//')"
    if [ -z "$name" ]; then
      echo 'EMPTY_NAME'
      return 1
    fi
  fi
  return 0
}

# check_review_structure <file> — specs/M2_CodeReview_Spec.md §7.3's required
# markers, in order: **Reviewers.** and **Scope.** (bold paragraph markers,
# matching .mkr/reviews/4e507dd.md's own precedent), then zero or more
# `## Finding N` sections, then the three fixed H2s: Findings not pursued
# further, Verification discipline, Verdict.
check_review_structure() {
  local file="$1" reviewers scope fnp verif verdict
  reviewers="$(grep -n -m1 '^\*\*Reviewers\.\*\*' -- "$file" | cut -d: -f1)"
  scope="$(grep -n -m1 '^\*\*Scope\.\*\*' -- "$file" | cut -d: -f1)"
  fnp="$(grep -n -m1 '^## Findings not pursued further$' -- "$file" | cut -d: -f1)"
  verif="$(grep -n -m1 '^## Verification discipline$' -- "$file" | cut -d: -f1)"
  verdict="$(grep -n -m1 '^## Verdict$' -- "$file" | cut -d: -f1)"

  if [ -z "$reviewers" ]; then printf 'MISSING:Reviewers\n'; return 1; fi
  if [ -z "$scope" ]; then printf 'MISSING:Scope\n'; return 1; fi
  if [ -z "$fnp" ]; then printf 'MISSING:Findings not pursued further\n'; return 1; fi
  if [ -z "$verif" ]; then printf 'MISSING:Verification discipline\n'; return 1; fi
  if [ -z "$verdict" ]; then printf 'MISSING:Verdict\n'; return 1; fi

  if ! [ "$reviewers" -lt "$scope" ] || ! [ "$scope" -lt "$fnp" ] \
     || ! [ "$fnp" -lt "$verif" ] || ! [ "$verif" -lt "$verdict" ]; then
    printf 'ORDER_VIOLATION\n'
    return 1
  fi

  # Any ## Finding N headings, if present, must sit strictly between Scope
  # and Findings-not-pursued-further — not before Scope, not after it.
  local finding_lines
  finding_lines="$(grep -n -E '^## Finding [0-9]' -- "$file" | cut -d: -f1)"
  local fl
  for fl in $finding_lines; do
    if ! [ "$scope" -lt "$fl" ] || ! [ "$fl" -lt "$fnp" ]; then
      printf 'FINDING_OUT_OF_PLACE:line %s\n' "$fl"
      return 1
    fi
  done
  return 0
}

# check_review_verdict_line <file> — the closing Verdict section's line
# matches exactly VERDICT: READY or VERDICT: NOT READY (<n> blocking).
check_review_verdict_line() {
  local file="$1" line
  line="$(grep -m1 -E '^VERDICT: (READY|NOT READY \([0-9]+ blocking\))$' -- "$file" || true)"
  if [ -z "$line" ]; then
    printf 'BAD_VERDICT_LINE\n'
    return 1
  fi
  return 0
}

# check_review_aggregation <file> — the closing VERDICT line must be READY
# iff both reviewers' own stated sub-verdicts are READY (§7.3 item 7, AC-1).
check_review_aggregation() {
  local file="$1" code_sub sec_sub closing expect_ready actual_ready
  code_sub="$(grep -m1 -E '^mkr-code-reviewer: (READY|NOT READY \([0-9]+\))$' -- "$file" || true)"
  sec_sub="$(grep -m1 -E '^mkr-security-reviewer: (READY|NOT READY \([0-9]+\))$' -- "$file" || true)"
  closing="$(grep -m1 -E '^VERDICT: (READY|NOT READY \([0-9]+ blocking\))$' -- "$file" || true)"
  if [ -z "$code_sub" ] || [ -z "$sec_sub" ] || [ -z "$closing" ]; then
    printf 'MISSING_VERDICT_LINE\n'
    return 1
  fi
  if [ "$code_sub" = "mkr-code-reviewer: READY" ] && [ "$sec_sub" = "mkr-security-reviewer: READY" ]; then
    expect_ready=1
  else
    expect_ready=0
  fi
  if [ "$closing" = "VERDICT: READY" ]; then actual_ready=1; else actual_ready=0; fi
  if [ "$expect_ready" != "$actual_ready" ]; then
    printf 'INCONSISTENT:sub-verdicts want overall %s, got %s\n' \
      "$([ "$expect_ready" = 1 ] && echo READY || echo 'NOT READY')" "$closing"
    return 1
  fi
  return 0
}

# check_audit_structure <file> — specs/M4_Audit_Spec.md §7.3's required
# elements, in order: title (line 1), a provenance paragraph naming "no
# memory of the build, per DESIGN.md phase 9", the `| AC | Verdict |
# Evidence |` table, "**Additional checks the auditor ran independently:**",
# the optional "**Outstanding, not a defect" bullet list, and the closing
# "**Verdict:**" paragraph.
check_audit_structure() {
  local file="$1" title provenance table checks outstanding verdict
  title="$(grep -n -m1 '^# Grounding audit — ' -- "$file" | cut -d: -f1)"
  provenance="$(grep -n -m1 'no memory of the build, per DESIGN.md phase 9' -- "$file" | cut -d: -f1)"
  table="$(grep -n -m1 -F '| AC | Verdict | Evidence |' -- "$file" | cut -d: -f1)"
  checks="$(grep -n -m1 -F '**Additional checks the auditor ran independently:**' -- "$file" | cut -d: -f1)"
  outstanding="$(grep -n -m1 -F '**Outstanding, not a defect' -- "$file" | cut -d: -f1)"
  verdict="$(grep -n -m1 -F '**Verdict:**' -- "$file" | cut -d: -f1)"

  if [ "$title" != "1" ]; then printf 'MISSING:title\n'; return 1; fi
  if [ -z "$provenance" ]; then printf 'MISSING:provenance\n'; return 1; fi
  if [ -z "$table" ]; then printf 'MISSING:table\n'; return 1; fi
  if [ -z "$checks" ]; then printf 'MISSING:Additional checks\n'; return 1; fi
  if [ -z "$verdict" ]; then printf 'MISSING:Verdict\n'; return 1; fi

  if ! [ "$title" -lt "$provenance" ] || ! [ "$provenance" -lt "$table" ] \
     || ! [ "$table" -lt "$checks" ]; then
    printf 'ORDER_VIOLATION\n'
    return 1
  fi
  if [ -n "$outstanding" ]; then
    if ! [ "$checks" -lt "$outstanding" ] || ! [ "$outstanding" -lt "$verdict" ]; then
      printf 'ORDER_VIOLATION\n'
      return 1
    fi
  else
    if ! [ "$checks" -lt "$verdict" ]; then
      printf 'ORDER_VIOLATION\n'
      return 1
    fi
  fi
  return 0
}

# check_audit_verdict_cells <file> — every `| AC-N | <verdict> | ... |` row's
# Verdict cell is exactly VERIFIED or NOT VERIFIED (<reason>) — §7.3 item 3's
# strict two-literal vocabulary.
check_audit_verdict_cells() {
  local file="$1" line ac cell
  while IFS= read -r line; do
    ac="$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$2); print $2}')"
    cell="$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
    if ! [[ "$cell" =~ ^(VERIFIED|NOT\ VERIFIED\ \(.+\))$ ]]; then
      printf 'BAD_CELL:%s:%s\n' "$ac" "$cell"
      return 1
    fi
  done < <(grep -E '^\| AC-[0-9]+ \|' -- "$file")
  return 0
}

# check_audit_aggregation <file> — the closing Verdict paragraph reads
# exactly `**Verdict:** PASS` iff every row's Verdict cell is exactly
# VERIFIED, else `**Verdict:** FAIL (<n> not verified)` naming the count.
check_audit_aggregation() {
  local file="$1" line cell closing total not_verified=0 expect_pass actual_pass
  total=0
  while IFS= read -r line; do
    cell="$(printf '%s\n' "$line" | awk -F'|' '{gsub(/^[ \t]+|[ \t]+$/,"",$3); print $3}')"
    total=$((total+1))
    [ "$cell" = "VERIFIED" ] || not_verified=$((not_verified+1))
  done < <(grep -E '^\| AC-[0-9]+ \|' -- "$file")
  closing="$(grep -m1 -F '**Verdict:**' -- "$file" || true)"
  if [ -z "$closing" ]; then printf 'MISSING_VERDICT_LINE\n'; return 1; fi
  if [ "$not_verified" -eq 0 ]; then expect_pass=1; else expect_pass=0; fi
  if [ "$closing" = "**Verdict:** PASS" ]; then actual_pass=1; else actual_pass=0; fi
  if [ "$expect_pass" != "$actual_pass" ]; then
    printf 'INCONSISTENT:want %s (%d not verified), got [%s]\n' \
      "$([ "$expect_pass" = 1 ] && echo PASS || echo FAIL)" "$not_verified" "$closing"
    return 1
  fi
  if [ "$expect_pass" = 0 ] && [ "$closing" != "**Verdict:** FAIL ($not_verified not verified)" ]; then
    printf 'WRONG_COUNT:want %d, got [%s]\n' "$not_verified" "$closing"
    return 1
  fi
  return 0
}

# check_audit_ac_labels <file> — the provenance paragraph's AC-1…AC-N range
# vs. the table's actual row labels: every AC named exactly once, in order —
# distinguishes a duplicate+drop (same count, wrong set) from an out-of-order
# table (same set, wrong sequence) from a correct one.
check_audit_ac_labels() {
  local file="$1" range n expected=() actual=() i
  range="$(grep -oE 'AC-1…AC-[0-9]+' -- "$file" | head -n1)"
  if [ -z "$range" ]; then printf 'NO_AC_RANGE\n'; return 1; fi
  n="${range##*AC-}"
  for ((i = 1; i <= n; i++)); do expected+=("AC-$i"); done
  while IFS= read -r i; do actual+=("$i"); done < <(
    grep -oE '^\| AC-[0-9]+ ' -- "$file" | sed -E 's/^\| (AC-[0-9]+) $/\1/'
  )
  if [ "${#actual[@]}" -ne "${#expected[@]}" ]; then
    printf 'ROW_COUNT_MISMATCH:got %d want %d\n' "${#actual[@]}" "${#expected[@]}"
    return 1
  fi
  local sorted_actual sorted_expected
  sorted_actual="$(printf '%s\n' "${actual[@]}" | sort)"
  sorted_expected="$(printf '%s\n' "${expected[@]}" | sort)"
  if [ "$sorted_actual" != "$sorted_expected" ]; then
    printf 'LABEL_SET_MISMATCH:got [%s] want [%s]\n' "${actual[*]}" "${expected[*]}"
    return 1
  fi
  for i in "${!expected[@]}"; do
    if [ "${actual[$i]}" != "${expected[$i]}" ]; then
      printf 'ORDER_VIOLATION:%s before %s\n' "${actual[$i]}" "${expected[$i]}"
      return 1
    fi
  done
  return 0
}

# check_auditor_tools <file> — the agent's frontmatter tools: line is
# exactly the §6 AD-1 four-tool shape, not the three-tool reviewer shape.
check_auditor_tools() {
  local file="$1" tools_line
  tools_line="$(sed -n '2,/^---$/p' -- "$file" | grep -m1 '^tools:')"
  if [ "$tools_line" = "tools: Read, Grep, Glob, Bash" ]; then return 0; fi
  printf 'BAD_TOOLS:%s\n' "$tools_line"
  return 1
}

# check_merge_ask_before_execute <file> — the "**Ask.**" instruction appears
# before any merge-execution instruction (`gh pr merge`/`git merge`).
check_merge_ask_before_execute() {
  local file="$1" ask_line exec_line
  ask_line="$(grep -n -m1 -F '**Ask.**' -- "$file" | cut -d: -f1)"
  # "git merge --no-ff" specifically, not bare "git merge" — a conflict-check step legitimately
  # mentions "git merge-tree" (a dry-run, never an execution) before the ask, and a substring match
  # against bare "git merge" would misread that as the real execution and report a false ordering
  # violation.
  exec_line="$(grep -n -m1 -E '(gh pr merge|git merge --no-ff)' -- "$file" | cut -d: -f1)"
  if [ -z "$ask_line" ]; then printf 'MISSING:Ask\n'; return 1; fi
  if [ -z "$exec_line" ]; then printf 'MISSING:merge-execution\n'; return 1; fi
  if ! [ "$ask_line" -lt "$exec_line" ]; then
    printf 'ORDER_VIOLATION:execution before ask\n'
    return 1
  fi
  return 0
}

# check_merge_gh_fallback <file> — both a gh-available path and a
# gh-unavailable/git-only fallback are documented, the fallback discloses
# that CI status can't be mechanically confirmed, and the fallback never
# instructs a `git push` to a protected branch — branch-guard.sh (M3)
# denies that outright, so a fallback that pushed would be self-defeating.
check_merge_gh_fallback() {
  local file="$1"
  grep -q -F 'gh pr merge' -- "$file" || { printf 'MISSING:gh-available path\n'; return 1; }
  grep -q -F 'git merge --no-ff' -- "$file" || { printf 'MISSING:git-only fallback\n'; return 1; }
  grep -q -F 'CI status cannot be mechanically confirmed' -- "$file" \
    || { printf 'MISSING:CI-unconfirmable disclosure\n'; return 1; }
  if grep -q -F 'then `git push`' -- "$file" || grep -q -F '+ `git push`' -- "$file"; then
    printf 'REGRESSION:fallback instructs a git push to a protected branch\n'
    return 1
  fi
  grep -q -F 'Do not follow it with' -- "$file" \
    || { printf 'MISSING:explicit no-push disclosure\n'; return 1; }
  return 0
}

# check_merge_gating <file> — all three named gating stops (G4 record
# missing, CI not green, spec not ACCEPTED) are present and each positioned
# before the "**Ask.**" instruction.
check_merge_gating() {
  local file="$1" ask_line g4 ci spec
  ask_line="$(grep -n -m1 -F '**Ask.**' -- "$file" | cut -d: -f1)"
  g4="$(grep -n -m1 -F 'If no review record exists, stop here' -- "$file" | cut -d: -f1)"
  ci="$(grep -n -m1 -F 'If CI is not green, stop here' -- "$file" | cut -d: -f1)"
  spec="$(grep -n -m1 -F 'If the branch'"'"'s spec is not `ACCEPTED`, stop here' -- "$file" | cut -d: -f1)"
  if [ -z "$ask_line" ]; then printf 'MISSING:Ask\n'; return 1; fi
  if [ -z "$g4" ]; then printf 'MISSING:G4 gating stop\n'; return 1; fi
  if [ -z "$ci" ]; then printf 'MISSING:CI gating stop\n'; return 1; fi
  if [ -z "$spec" ]; then printf 'MISSING:spec gating stop\n'; return 1; fi
  if ! [ "$g4" -lt "$ask_line" ] || ! [ "$ci" -lt "$ask_line" ] || ! [ "$spec" -lt "$ask_line" ]; then
    printf 'ORDER_VIOLATION\n'
    return 1
  fi
  return 0
}

# check_design_structure <file> — specs/M5_Gates_Spec.md §7.3's required
# elements, in order: title (line 1), **Reviewers.**, **Scope.**, zero or
# more `## Finding N` sections, **Findings not pursued further**, and the
# closing **Verdict.** paragraph.
check_design_structure() {
  local file="$1" title reviewers scope fnp verdict
  title="$(grep -n -m1 '^# Design review — ' -- "$file" | cut -d: -f1)"
  reviewers="$(grep -n -m1 '^\*\*Reviewers\.\*\*' -- "$file" | cut -d: -f1)"
  scope="$(grep -n -m1 '^\*\*Scope\.\*\*' -- "$file" | cut -d: -f1)"
  fnp="$(grep -n -m1 -F '**Findings not pursued further**' -- "$file" | cut -d: -f1)"
  verdict="$(grep -n -m1 '^\*\*Verdict\.\*\*' -- "$file" | cut -d: -f1)"

  if [ "$title" != "1" ]; then printf 'MISSING:title\n'; return 1; fi
  if [ -z "$reviewers" ]; then printf 'MISSING:Reviewers\n'; return 1; fi
  if [ -z "$scope" ]; then printf 'MISSING:Scope\n'; return 1; fi
  if [ -z "$fnp" ]; then printf 'MISSING:Findings not pursued further\n'; return 1; fi
  if [ -z "$verdict" ]; then printf 'MISSING:Verdict\n'; return 1; fi

  if ! [ "$title" -lt "$reviewers" ] || ! [ "$reviewers" -lt "$scope" ] \
     || ! [ "$scope" -lt "$fnp" ] || ! [ "$fnp" -lt "$verdict" ]; then
    printf 'ORDER_VIOLATION\n'
    return 1
  fi

  local finding_lines fl
  finding_lines="$(grep -n -E '^## Finding [0-9]' -- "$file" | cut -d: -f1)"
  for fl in $finding_lines; do
    if ! [ "$scope" -lt "$fl" ] || ! [ "$fl" -lt "$fnp" ]; then
      printf 'FINDING_OUT_OF_PLACE:line %s\n' "$fl"
      return 1
    fi
  done
  return 0
}

# check_design_aggregation <file> — the closing **Verdict.** must be READY
# iff both reviewers' own stated sub-verdicts are READY (§7.3 element 6, AC-1).
check_design_aggregation() {
  local file="$1" dr_sub ar_sub closing expect_ready actual_ready
  dr_sub="$(grep -m1 -E '^mkr-design-reviewer: (READY|NOT READY \([0-9]+\))$' -- "$file" || true)"
  ar_sub="$(grep -m1 -E '^mkr-architecture-reviewer: (READY|NOT READY \([0-9]+\))$' -- "$file" || true)"
  closing="$(grep -m1 -E '^\*\*Verdict\.\*\* (READY|NOT READY \([0-9]+ blocking\))$' -- "$file" || true)"
  if [ -z "$dr_sub" ] || [ -z "$ar_sub" ] || [ -z "$closing" ]; then
    printf 'MISSING_VERDICT_LINE\n'
    return 1
  fi
  if [ "$dr_sub" = "mkr-design-reviewer: READY" ] && [ "$ar_sub" = "mkr-architecture-reviewer: READY" ]; then
    expect_ready=1
  else
    expect_ready=0
  fi
  if [ "$closing" = "**Verdict.** READY" ]; then actual_ready=1; else actual_ready=0; fi
  if [ "$expect_ready" != "$actual_ready" ]; then
    printf 'INCONSISTENT:sub-verdicts want overall %s, got %s\n' \
      "$([ "$expect_ready" = 1 ] && echo READY || echo 'NOT READY')" "$closing"
    return 1
  fi
  return 0
}

# check_gates_split_mechanic <file> — mkr-gates/SKILL.md names the uncommitted
# split mechanic (git stash push / git worktree add, §6 AD-3) and, separately,
# the already-committed disclosed-ask fallback — and does not duplicate
# mkr-loop's own decision-rule text rather than reusing it (§6 AD-4).
check_gates_split_mechanic() {
  local file="$1"
  grep -q -F 'git stash push -u' -- "$file" || { printf 'MISSING:git stash push -u\n'; return 1; }
  grep -q -F 'git worktree add' -- "$file" || { printf 'MISSING:git worktree add\n'; return 1; }
  grep -q -F 'do not attempt history surgery' -- "$file" \
    || { printf 'MISSING:already-committed disclosure\n'; return 1; }
  grep -qi 'mkr-loop' -- "$file" || { printf 'MISSING:mkr-loop reference\n'; return 1; }
  grep -qi 'six.question' -- "$file" || { printf 'MISSING:six-question reference\n'; return 1; }
  if grep -q -F 'Deep** if **any** of' -- "$file"; then
    printf 'REGRESSION:duplicates mkr-loop'"'"'s own decision-rule text\n'
    return 1
  fi
  return 0
}

# check_ship_ask_before_execute <file> — the "**Ask.**" instruction appears
# before the deploy-execution instruction, and the not-configured check
# appears before both (§7.5, AC-4/AC-5).
check_ship_ask_before_execute() {
  local file="$1" not_configured ask_line exec_line
  not_configured="$(grep -n -m1 -F 'MKR_DEPLOY` is empty' -- "$file" | cut -d: -f1)"
  ask_line="$(grep -n -m1 -F '**Ask.**' -- "$file" | cut -d: -f1)"
  exec_line="$(grep -n -m1 -F 'run `MKR_DEPLOY`' -- "$file" | cut -d: -f1)"
  if [ -z "$not_configured" ]; then printf 'MISSING:not-configured check\n'; return 1; fi
  if [ -z "$ask_line" ]; then printf 'MISSING:Ask\n'; return 1; fi
  if [ -z "$exec_line" ]; then printf 'MISSING:deploy-execution\n'; return 1; fi
  if ! [ "$not_configured" -lt "$ask_line" ] || ! [ "$ask_line" -lt "$exec_line" ]; then
    printf 'ORDER_VIOLATION\n'
    return 1
  fi
  return 0
}

# check_capture_threshold <file> — mkr-capture/SKILL.md states the fixed
# same-class-twice threshold (2) in its own body text, not a config variable
# reference (§6 AD-7).
check_capture_threshold() {
  local file="$1"
  grep -q -F '2 or more' -- "$file" || { printf 'MISSING:threshold literal\n'; return 1; }
  if grep -q -F 'MKR_CAPTURE_THRESHOLD' -- "$file"; then
    printf 'REGRESSION:references a config variable that does not exist\n'
    return 1
  fi
  return 0
}

# check_update_ask_before_apply <file> — the dry-run install.sh invocation,
# then "**Ask.**", then the real (no-`--dry-run`) install.sh invocation
# ("**Apply.**"), all in that order (specs/M6_Installer_Spec.md §7.3 steps
# 2, 6, 7).
check_update_ask_before_apply() {
  local file="$1" dry_line ask_line apply_line
  dry_line="$(grep -n -m1 -F -- '--dry-run' "$file" | cut -d: -f1)"
  ask_line="$(grep -n -m1 -F '**Ask.**' -- "$file" | cut -d: -f1)"
  apply_line="$(grep -n -m1 -F '**Apply.**' -- "$file" | cut -d: -f1)"
  if [ -z "$dry_line" ]; then printf 'MISSING:dry-run invocation\n'; return 1; fi
  if [ -z "$ask_line" ]; then printf 'MISSING:Ask\n'; return 1; fi
  if [ -z "$apply_line" ]; then printf 'MISSING:Apply\n'; return 1; fi
  if ! [ "$dry_line" -lt "$ask_line" ] || ! [ "$ask_line" -lt "$apply_line" ]; then
    printf 'ORDER_VIOLATION\n'
    return 1
  fi
  return 0
}

# check_update_force_language <file> — a `refused` path is named explicitly
# and skipped unless `--force` is confirmed, stated before the ask
# (specs/M6_Installer_Spec.md §7.3 step 5).
check_update_force_language() {
  local file="$1" force_line refused_line ask_line
  force_line="$(grep -n -m1 -F -- '--force' "$file" | cut -d: -f1)"
  refused_line="$(grep -n -m1 -E 'refused|locally-edited' -- "$file" | cut -d: -f1)"
  ask_line="$(grep -n -m1 -F '**Ask.**' -- "$file" | cut -d: -f1)"
  if [ -z "$force_line" ]; then printf 'MISSING:--force language\n'; return 1; fi
  if [ -z "$refused_line" ]; then printf 'MISSING:refused/locally-edited language\n'; return 1; fi
  if [ -z "$ask_line" ]; then printf 'MISSING:Ask\n'; return 1; fi
  if ! [ "$force_line" -lt "$ask_line" ] || ! [ "$refused_line" -lt "$ask_line" ]; then
    printf 'ORDER_VIOLATION:force/refused language after the ask\n'
    return 1
  fi
  return 0
}

# check_update_drift_labels <file> — the drift-report step enumerates all
# five report-relevant labels (specs/M6_Installer_Spec.md §7.3 step 4;
# `unchanged`/`forced-update` are excluded by design, not required here).
check_update_drift_labels() {
  local file="$1" label
  for label in created restored updated orphaned refused; do
    grep -q -F "\`$label\`" -- "$file" || { printf 'MISSING:%s\n' "$label"; return 1; }
  done
  return 0
}

# check_update_abort_on_precondition_failure <file> — a nonzero dry-run exit
# aborts before both the drift-report step and the ask
# (specs/M6_Installer_Spec.md §7.3 step 3).
check_update_abort_on_precondition_failure() {
  local file="$1" abort_line render_line ask_line
  abort_line="$(grep -n -m1 -F 'exits nonzero, stop here' -- "$file" | cut -d: -f1)"
  render_line="$(grep -n -m1 -F 'Render the drift report' -- "$file" | cut -d: -f1)"
  ask_line="$(grep -n -m1 -F '**Ask.**' -- "$file" | cut -d: -f1)"
  if [ -z "$abort_line" ]; then printf 'MISSING:abort-on-precondition-failure branch\n'; return 1; fi
  if [ -z "$render_line" ]; then printf 'MISSING:drift-report step\n'; return 1; fi
  if [ -z "$ask_line" ]; then printf 'MISSING:Ask\n'; return 1; fi
  if ! [ "$abort_line" -lt "$render_line" ] || ! [ "$abort_line" -lt "$ask_line" ]; then
    printf 'ORDER_VIOLATION:abort branch after drift-report or ask\n'
    return 1
  fi
  return 0
}

# section_between <file> <start-heading-regex> <end-heading-regex> — prints the lines strictly
# between two headings (exclusive of both), or to EOF if <end-heading-regex> is "EOF". Scoping
# each ecosystem's checks to its own section is deliberate: several ecosystems reuse identical
# "`MKR_X` is empty" phrasing, so an unscoped grep can't tell which section a mutation targeted.
section_between() {
  local file="$1" start="$2" end="$3"
  if [ "$end" = EOF ]; then
    sed -n "\%${start}%,\$p" -- "$file" | sed '1d'
  else
    sed -n "\%${start}%,\%${end}%p" -- "$file" | sed '1d;$d'
  fi
}

# check_literals_in <text> <label:pattern> ... — greps each literal fixed-string pattern against
# already-extracted text; MISSING:<label> on the first one not found.
check_literals_in() {
  local text="$1" pair label pattern
  shift
  for pair in "$@"; do
    label="${pair%%:*}"
    pattern="${pair#*:}"
    printf '%s\n' "$text" | grep -q -F -- "$pattern" || { printf 'MISSING:%s\n' "$label"; return 1; }
  done
  return 0
}

check_detect_markers() {
  check_literals_in "$(cat -- "$1")" \
    'package.json:Primary marker: `package.json`' \
    'python-marker:any one of `pyproject.toml`' \
    'go.mod:Primary marker: `go.mod`' \
    'Gemfile-ref:Primary marker: `Gemfile`'
}

check_detect_node() {
  local text
  text="$(section_between "$1" '^### Node/TypeScript$' '^### Python$')"
  check_literals_in "$text" \
    'TypeScript-naming:**"TypeScript"**' \
    'JavaScript-naming:**"JavaScript"**' \
    'scripts.test:scripts.test' \
    'MKR_TEST-empty:`MKR_TEST` is empty' \
    'scripts.build:scripts.build' \
    'MKR_BUILD-empty:`MKR_BUILD` is empty' \
    'scripts.lint:scripts.lint' \
    'MKR_LINT-empty:`MKR_LINT` is empty' \
    'tsc-noEmit:tsc --noEmit' \
    'MKR_TYPECHECK-empty:`MKR_TYPECHECK` is empty' \
    'MKR_COVERAGE-empty:`MKR_COVERAGE`: empty'
}

check_detect_python() {
  local text
  text="$(section_between "$1" '^### Python$' '^### Go$')"
  check_literals_in "$text" \
    'poetry-naming:**"Python (poetry)"**' \
    'pip-naming:**"Python (pip)"**' \
    'pytest-literal:pytest` when a `tests/`' \
    'MKR_TEST-empty:`MKR_TEST` is empty' \
    'MKR_BUILD-empty:`MKR_BUILD`: empty' \
    'MKR_LINT-empty:`MKR_LINT`: empty' \
    'MKR_TYPECHECK-empty:`MKR_TYPECHECK`: empty' \
    'MKR_COVERAGE-empty:`MKR_COVERAGE`: empty'
}

check_detect_go() {
  local text
  text="$(section_between "$1" '^### Go$' '^### Rails$')"
  check_literals_in "$text" \
    'go-test:go test ./...' \
    'go-build:go build ./...' \
    'MKR_TYPECHECK-empty:go build` already type-checks' \
    'MKR_LINT-empty:`MKR_LINT`: empty' \
    'MKR_COVERAGE-empty:`MKR_COVERAGE`: empty'
}

check_detect_rails() {
  local text
  text="$(section_between "$1" '^### Rails$' '^## 3\. No match$')"
  check_literals_in "$text" \
    'compound-marker:config/application.rb` **or** `bin/rails`' \
    'rspec-naming:**"Ruby on Rails (RSpec)"**' \
    'plain-naming:**"Ruby on Rails"**' \
    'bundle-exec-rspec:bundle exec rspec' \
    'rails-test:bin/rails test' \
    'MKR_BUILD-empty:`MKR_BUILD`: empty' \
    'MKR_LINT-empty:`MKR_LINT`: empty' \
    'MKR_TYPECHECK-empty:`MKR_TYPECHECK`: empty' \
    'MKR_COVERAGE-empty:`MKR_COVERAGE`: empty'
}

check_detect_no_match() {
  grep -q -F 'no recognized ecosystem detected' "$1" \
    || { printf 'MISSING:no-match language\n'; return 1; }
  return 0
}

check_detect_multi_match() {
  grep -q -F 'More than one match is expected and reported, not resolved' "$1" \
    || { printf 'MISSING:multi-match language\n'; return 1; }
  return 0
}

check_detect_tool_scope() {
  local file="$1"
  grep -q -F 'Read`, `Grep`, `Glob` only. Never `Write`/`Edit`' "$file" \
    || { printf 'MISSING:tool scope (Read/Grep/Glob only, no Write/Edit)\n'; return 1; }
  grep -q -i -F 'never writes any file' "$file" \
    || { printf 'MISSING:never-writes statement\n'; return 1; }
  return 0
}

check_init_step4_invokes_detect() {
  local file="$1"
  grep -q -F 'Invoke `mkr-detect`' "$file" || { printf 'MISSING:mkr-detect invocation\n'; return 1; }
  grep -q -F "don't assume them" "$file" \
    || { printf 'MISSING:confirm-dont-assume\n'; return 1; }
  return 0
}

check_init_step4_zero_match() {
  grep -q -F 'zero blocks' "$1" || { printf 'MISSING:zero-match language\n'; return 1; }
  return 0
}

check_init_step5_unchanged() {
  local file="$1"
  grep -q -F 'CLAUDE.md` from `seed/CLAUDE.md' "$file" \
    || { printf 'MISSING:CLAUDE.md file-naming\n'; return 1; }
  grep -q -F '.mkr/config` from `seed/config' "$file" \
    || { printf 'MISSING:.mkr/config file-naming\n'; return 1; }
  grep -q -F 'never write partial output' "$file" \
    || { printf 'MISSING:never-write-partial-output\n'; return 1; }
  return 0
}

# extract_gate_tiers <file> <heading-regex> — prints "<gate>\t<tier>" one per row, for the
# markdown table immediately following the first line matching <heading-regex>. Tier cells have
# any `**` bold markers stripped so a plain-text README cell can compare against DESIGN.md's own
# bolded ones.
extract_gate_tiers() {
  local file="$1" heading="$2" in=0 started=0 line gate tier
  while IFS= read -r line; do
    if [ "$in" -eq 0 ]; then
      [[ "$line" =~ $heading ]] && in=1
      continue
    fi
    if [ "$started" -eq 0 ]; then
      [[ "$line" == '|---'* ]] && started=1
      continue
    fi
    [[ "$line" == '|'* ]] || break
    IFS='|' read -r _ gate _ tier _ <<< "$line"
    gate="$(printf '%s' "$gate" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
    tier="$(printf '%s' "$tier" | sed -E 's/\*\*//g; s/^[[:space:]]+//; s/[[:space:]]+$//')"
    printf '%s\t%s\n' "$gate" "$tier"
  done < "$file"
}

# check_gates_table_matches <readme> <design> — specs/M6_ReleaseGates_Spec.md §7.2/AC-3.
# README's `## Gates` table's Tier column must match docs/DESIGN.md §4's own table cell-by-cell,
# same gate names, same row count — so the two can never silently drift apart.
check_gates_table_matches() {
  local readme="$1" design="$2" gate tier
  local -A design_tier
  local n_readme=0 n_design=0
  while IFS=$'\t' read -r gate tier; do
    design_tier["$gate"]="$tier"
    n_design=$((n_design+1))
  done < <(extract_gate_tiers "$design" '^## 4\. Gates and what actually enforces them$')
  while IFS=$'\t' read -r gate tier; do
    n_readme=$((n_readme+1))
    if [ -z "${design_tier[$gate]+x}" ]; then
      printf 'UNKNOWN_GATE:%s\n' "$gate"
      return 1
    fi
    if [ "$tier" != "${design_tier[$gate]}" ]; then
      printf 'MISMATCH:%s (readme=%s design=%s)\n' "$gate" "$tier" "${design_tier[$gate]}"
      return 1
    fi
  done < <(extract_gate_tiers "$readme" '^## Gates$')
  if [ "$n_readme" -eq 0 ]; then
    printf 'MISSING:## Gates table\n'
    return 1
  fi
  if [ "$n_readme" -ne "$n_design" ]; then
    printf 'ROW_COUNT_MISMATCH:got %s want %s\n' "$n_readme" "$n_design"
    return 1
  fi
  return 0
}

# check_claude_md_redacted <file> — TC-M6-48/AC-2. The one prose mention and all six gate-owner
# rows name `kikrgbh`.
check_claude_md_redacted() {
  local file="$1"
  check_literals_in "$(cat -- "$file")" \
    'prose:by kikrgbh' \
    'spec-approval:| spec approval | kikrgbh |' \
    'design:| design | kikrgbh |' \
    'review-gate:| review gate (G4) | kikrgbh |' \
    'pre-merge:| pre-merge | kikrgbh |' \
    'pre-deploy:| pre-deploy | kikrgbh |' \
    'incident:| incident / kill switch | kikrgbh |'
}

# check_mkr_config_redacted <file> — TC-M6-49/AC-3. All five MKR_GATE_* values are `"kikrgbh"`.
check_mkr_config_redacted() {
  local file="$1"
  check_literals_in "$(cat -- "$file")" \
    'gate-spec:MKR_GATE_SPEC="kikrgbh"' \
    'gate-design:MKR_GATE_DESIGN="kikrgbh"' \
    'gate-merge:MKR_GATE_MERGE="kikrgbh"' \
    'gate-deploy:MKR_GATE_DEPLOY="kikrgbh"' \
    'gate-review:MKR_GATE_REVIEW="kikrgbh"'
}

# check_gitignore_has_audit_entry <file> — TC-M6-50/AC-4. `.mkr/audit.jsonl` is gitignored.
check_gitignore_has_audit_entry() {
  grep -q -F -- '.mkr/audit.jsonl' "$1" || { printf 'MISSING:.mkr/audit.jsonl\n'; return 1; }
  return 0
}


# check_mkr_merge_third_branch <file> — TC-M6-54/AC-9. Step 3 names the new third branch (an
# annotation-confirmed non-code cause), textually distinct from the pre-existing gh-unavailable
# branch (which never mentions an "annotation"); step 7 (merge execution) names `--admin`. Also
# requires step 3's
# own empty-`steps`-array precondition (G4 rev-13-fix, .mkr/reviews/1072e99.md finding 1): a fork
# PR's own executed code could forge a misleading annotation, so the annotation may only be
# trusted once the job's own `steps` array is confirmed empty (the job never actually ran).
# Scoped to each step's own section via section_between so a mutation in one step can't be masked
# by the other's text.
check_mkr_merge_third_branch() {
  local file="$1" text3 text6 out
  text3="$(section_between "$file" '^## 3\.' '^## 4\.')"
  out="$(check_literals_in "$text3" \
    'third-branch-annotation:annotation' \
    'third-branch-non-code:unrelated to code correctness' \
    'third-branch-empty-steps:steps` array' \
    'third-branch-forge-guard:forge')" || { printf '%s' "$out"; return 1; }
  text7="$(section_between "$file" '^## 7\.' '^## 8\.')"
  check_literals_in "$text7" 'admin-flag:--admin'
}

# --------------------------------------------------------- RKP (mkr-rkp skill) helpers

# check_rkp_fixed_location <file> — TC-RKP-01/AC-8. docs/rkp/ is a fixed location, never sourced
# from a config variable.
check_rkp_fixed_location() {
  check_literals_in "$(cat -- "$1")" \
    'fixed-location:not read from any `MKR_*`/`config.sh` variable'
}

# check_rkp_topics <file> — TC-RKP-02/AC-1/AC-6. All nine doc topics named, scoped to just the
# topic table itself (not the later prose that also mentions some filenames) so a mutation
# removing one table row is independently detectable rather than masked by a second mention.
check_rkp_topics() {
  local file="$1" text
  text="$(section_between "$file" '^| # | Doc | Applies | Signal |$' '^Numbering is a fixed topic')"
  check_literals_in "$text" \
    'topic-01:`01-architecture.md`' \
    'topic-02:`02-data-model.md`' \
    'topic-03:`03-process-and-conventions.md`' \
    'topic-04:`04-user-journeys.md`' \
    'topic-05:`05-system-journeys.md`' \
    'topic-06:`06-rbac-capability-matrix.md`' \
    'topic-07:`07-glossary.md`' \
    'topic-08:`08-current-state-and-gaps.md`' \
    'topic-09:`09-dev-environment-runbook.md`'
}

# check_rkp_citation <file> — TC-RKP-03/AC-2. Every claim must cite a real file, never a
# paraphrase.
check_rkp_citation() {
  check_literals_in "$(cat -- "$1")" \
    'citation:Real file/line citations for every claim, not paraphrases.'
}

# check_rkp_scope_modes <file> — TC-RKP-04/AC-1/AC-3/AC-4/AC-5. All four scope-mode triggers,
# plus bootstrap's own README-creation clause.
check_rkp_scope_modes() {
  check_literals_in "$(cat -- "$1")" \
    'bootstrap-trigger:someone wants a KT package built and there'"'"'s nothing to refresh' \
    'bootstrap-readme:plus `README.md`, all created fresh' \
    'single-doc-trigger:Trigger: one doc is flagged stale, or you'"'"'re about to cite a specific' \
    'full-package-trigger:before handing the package to a new developer' \
    'partial-bootstrap-trigger:exists but is missing specific docs that the topic'
}

# check_rkp_refresh_discipline <file> — TC-RKP-04b/AC-3/AC-4. Edit-in-place/preserve-structure,
# and full-refresh checks every doc currently present.
check_rkp_refresh_discipline() {
  check_literals_in "$(cat -- "$1")" \
    'edit-in-place:Edit in place, preserve structure.** Update only what actually drifted' \
    'checks-every-present:present has been checked (touched or confirmed clean)'
}

# check_rkp_no_memory_shortcut <file> — TC-RKP-05/AC-3.
check_rkp_no_memory_shortcut() {
  check_literals_in "$(cat -- "$1")" \
    'no-memory-shortcut:If you built or last refreshed a doc in this same session, don'"'"'t rely'
}

# check_rkp_readme_date <file> — TC-RKP-06/AC-4.
check_rkp_readme_date() {
  check_literals_in "$(cat -- "$1")" \
    'readme-date:runs update `README.md`'"'"'s'
}

# check_rkp_partial_bootstrap_treatment <file> — TC-RKP-07/AC-5.
check_rkp_partial_bootstrap_treatment() {
  check_literals_in "$(cat -- "$1")" \
    'partial-bootstrap-treatment:as a bootstrap scoped to just those, and the existing ones as a normal refresh'
}

# check_rkp_absence_not_defect <file> — TC-RKP-08/AC-6.
check_rkp_absence_not_defect() {
  check_literals_in "$(cat -- "$1")" \
    'absence-not-defect:A topic'"'"'s absence is not a defect to work around'
}

# check_rkp_output <file> — TC-RKP-09/AC-7/AC-15. Scoped to the Output section only, so the
# bolded four-state vocabulary (distinct from the plain, unbolded restatements inside the
# section's own worked examples) is what's actually being checked.
check_rkp_output() {
  local file="$1" text
  text="$(section_between "$file" '^## Output$' '^## What this skill does not do$')"
  check_literals_in "$text" \
    'state-created:**created**' \
    'state-clean:**clean**' \
    'state-updated:**updated**' \
    'state-no-longer-applicable:**no longer applicable**' \
    'not-a-new-file:not a new file' \
    'uniform-trigger:single-doc refresh, full-package refresh, or partial bootstrap'"'"'s present-doc handling'
}

# check_rkp_tool_scope <file> — TC-RKP-10/AC-8.
check_rkp_tool_scope() {
  local file="$1"
  grep -q -F 'Tool scope: `Read`, `Grep`, `Glob`, `Write`, `Edit`. Never `Bash`.' -- "$file" \
    || { printf 'MISSING:tool scope (Read/Grep/Glob/Write/Edit, no Bash)\n'; return 1; }
  grep -q -F 'never writes outside `docs/rkp/`' -- "$file" \
    || { printf 'MISSING:never-writes-outside-docs/rkp statement\n'; return 1; }
  return 0
}

# check_rkp_command_invariant <file> — TC-RKP-11/AC-9.
check_rkp_command_invariant() {
  check_literals_in "$(cat -- "$1")" \
    'command-invariant:never from anything recalled earlier in the same session'
}

# check_rkp_doc_shape <file> — TC-RKP-13/AC-11. Header blockquote+date, Mermaid `;`-pitfall,
# See-also footer.
check_rkp_doc_shape() {
  check_literals_in "$(cat -- "$1")" \
    'header-blockquote:A header blockquote naming what the doc is grounded against and the grounding date' \
    'mermaid-pitfall:a bare `;` inside a sequence-diagram' \
    'see-also:See also" footer cross-linking sibling docs'
}

# check_rkp_adjusted_topic_list <file> — TC-RKP-14/AC-12.
check_rkp_adjusted_topic_list() {
  check_literals_in "$(cat -- "$1")" \
    'adjusted-topic-list:If the nine-topic shape genuinely doesn'"'"'t fit'
}

# check_rkp_ad5 <file> — TC-RKP-15/AC-15. Self-exclusion, the recheck action, its uniform
# three-mode scope (independently of the action itself), and the never-deletes clause.
check_rkp_ad5() {
  check_literals_in "$(cat -- "$1")" \
    'self-exclusion:Signal scans exclude `docs/rkp/` itself.** Every signal check above scans the target repo'"'"'s' \
    'recheck-action:target repo, not only re-deriving the facts already written inside the doc' \
    'uniform-scope:Present-conditional-doc signal recheck, applies uniformly to single-doc refresh, full-package' \
    'never-deletes:It never deletes the file itself — this skill'"'"'s tool scope has no delete capability'
}

# check_rkp_scope_hint_validity <file> — TC-RKP-16/AC-16. The "full package"/"nothing" exemption,
# the unknown-topic mismatch rule, and both branches of the signal-absent case (doc doesn't exist
# yet vs. doc already exists).
check_rkp_scope_hint_validity() {
  check_literals_in "$(cat -- "$1")" \
    'hint-exemption:it never applies when you'"'"'re asked for the full package or given no scope at' \
    'unknown-topic-mismatch:report the mismatch plainly and do nothing — never guess which topic was meant' \
    'doc-not-exist-yet:the doc doesn'"'"'t exist yet, don'"'"'t create it — report the signal is absent' \
    'doc-already-exists:separate rule — report it "no longer applicable" and leave the file in place'
}

# ------------------------------------------------------------- TC-M1-01..04

echo "== spec structure (TC-M1-01..04) =="

if check_spec_structure "$FIX/specs/valid.md" >/dev/null; then
  ok "TC-M1-01 valid spec — all 14 headings, in order"
else
  bad "TC-M1-01 valid spec — all 14 headings, in order" \
      "$(check_spec_structure "$FIX/specs/valid.md")"
fi

out="$(check_spec_structure "$FIX/specs/missing_heading.md" || true)"
if [[ "$out" == MISSING:*"9. Test-case register"* ]]; then
  ok "TC-M1-02 missing heading detected and named"
else
  bad "TC-M1-02 missing heading detected and named" "$out"
fi

out="$(check_spec_structure "$FIX/specs/swapped_headings.md" || true)"
if [[ "$out" == ORDER_VIOLATION:* ]]; then
  ok "TC-M1-03 swapped headings → ordering violation"
else
  bad "TC-M1-03 swapped headings → ordering violation" "$out"
fi

if check_status_line "$FIX/specs/valid.md" >/dev/null; then
  ok "TC-M1-04a valid Status line passes"
else
  bad "TC-M1-04a valid Status line passes" "$(check_status_line "$FIX/specs/valid.md")"
fi
if ! check_status_line "$FIX/specs/bad_status.md" >/dev/null; then
  ok "TC-M1-04b malformed Status line fails"
else
  bad "TC-M1-04b malformed Status line fails" "expected failure, got pass"
fi

echo "== spec section extension point (issue #2, docs/adr/0004) =="

# A spec carrying adopter-declared extra sections after §13 still passes the core-14 structural
# check — check_spec_structure's own doc comment says extra headings are ignored; this proves it.
EXTRA_SPEC="$(mktemp)"
cat "$FIX/specs/valid.md" > "$EXTRA_SPEC"
printf '
## 14. Data privacy

content

## 15. Migration plan

content
' >> "$EXTRA_SPEC"
if check_spec_structure "$EXTRA_SPEC" >/dev/null; then
  ok "G2a a spec with adopter-declared extra sections after §13 still passes the core-14 check"
else
  bad "G2a a spec with adopter-declared extra sections after §13 still passes the core-14 check"       "$(check_spec_structure "$EXTRA_SPEC")"
fi
rm -f "$EXTRA_SPEC"

ok2b=1
grep -q 'MKR_SPEC_EXTRA_SECTIONS' -- "$ROOT/.claude/skills/mkr-spec/SKILL.md" || ok2b=0
grep -q 'MKR_SPEC_EXTRA_SECTIONS' -- "$ROOT/.claude/agents/mkr-spec-reviewer.md" || ok2b=0
grep -q 'MKR_SPEC_EXTRA_SECTIONS' -- "$ROOT/.claude/skills/mkr-spec-review/SKILL.md" || ok2b=0
if [ "$ok2b" -eq 1 ]; then
  ok "G2b mkr-spec, mkr-spec-reviewer, and mkr-spec-review all document MKR_SPEC_EXTRA_SECTIONS"
else
  bad "G2b mkr-spec, mkr-spec-reviewer, and mkr-spec-review all document MKR_SPEC_EXTRA_SECTIONS" "not found in one or more"
fi

# ---------------------------------------------------------------- TC-M1-05,06

echo "== ADR shape and numbering (TC-M1-05, TC-M1-06) =="

if check_adr_shape "$FIX/adrs/valid/0001-fixture-decision.md" >/dev/null; then
  ok "TC-M1-05 valid ADR — 4 sections, in order"
else
  bad "TC-M1-05 valid ADR — 4 sections, in order" \
      "$(check_adr_shape "$FIX/adrs/valid/0001-fixture-decision.md")"
fi

out="$(check_adr_numbering "$FIX/adrs/dup" || true)"
if [[ "$out" == DUP_ADR_NUMBER:0002* ]]; then
  ok "TC-M1-06 duplicate ADR number detected, both paths named"
else
  bad "TC-M1-06 duplicate ADR number detected, both paths named" "$out"
fi

# ---------------------------------------------------------------- TC-M1-07,08

echo "== CLAUDE.md structure and placeholders (TC-M1-07, TC-M1-08) =="

if check_claude_md_structure "$FIX/claude_md/valid.md" >/dev/null \
   && check_no_placeholder "$FIX/claude_md/valid.md" >/dev/null; then
  ok "TC-M1-07 valid CLAUDE.md — 8 headings, no placeholder"
else
  bad "TC-M1-07 valid CLAUDE.md — 8 headings, no placeholder" \
      "$(check_claude_md_structure "$FIX/claude_md/valid.md"; check_no_placeholder "$FIX/claude_md/valid.md")"
fi

out="$(check_no_placeholder "$FIX/claude_md/with_placeholder.md" || true)"
if [[ "$out" == PLACEHOLDER:*'<owner of the spec-approval gate>'* ]]; then
  ok "TC-M1-08 leftover placeholder detected and cited"
else
  bad "TC-M1-08 leftover placeholder detected and cited" "$out"
fi

# ------------------------------------------------------------------- TC-M1-09

echo "== plan verdict shape (TC-M1-09) =="

if check_plan_verdict "CONFORMANT"; then
  ok "TC-M1-09a CONFORMANT accepted"
else
  bad "TC-M1-09a CONFORMANT accepted" "rejected"
fi
if check_plan_verdict "BLOCKED(missingMandatory=[code-review], orderingViolations=[])"; then
  ok "TC-M1-09b well-formed BLOCKED(...) accepted"
else
  bad "TC-M1-09b well-formed BLOCKED(...) accepted" "rejected"
fi
if ! check_plan_verdict "kind of blocked I guess"; then
  ok "TC-M1-09c malformed verdict rejected"
else
  bad "TC-M1-09c malformed verdict rejected" "accepted"
fi

# --------------------------------------------------------------- TC-M1-10,11

echo "== real repo artifacts (TC-M1-10, TC-M1-11) =="
echo "   (expected red until tasks 2-6 land — test-first, see file header)"

n=0
for f in "$ROOT"/.claude/commands/mkr-*.md; do
  [ -e "$f" ] || continue
  n=$((n+1))
  if out="$(check_frontmatter "$f" 0)"; then
    ok "TC-M1-10 $(basename "$f") frontmatter"
  else
    bad "TC-M1-10 $(basename "$f") frontmatter" "$out"
  fi
done
for f in "$ROOT"/.claude/skills/mkr-*/SKILL.md; do
  [ -e "$f" ] || continue
  n=$((n+1))
  if out="$(check_frontmatter "$f" 1)"; then
    ok "TC-M1-10 $(basename "$(dirname "$f")")/SKILL.md frontmatter"
  else
    bad "TC-M1-10 $(basename "$(dirname "$f")")/SKILL.md frontmatter" "$out"
  fi
done
for f in "$ROOT"/.claude/agents/mkr-*.md; do
  [ -e "$f" ] || continue
  n=$((n+1))
  if out="$(check_frontmatter "$f" 1)"; then
    ok "TC-M1-10 $(basename "$f") frontmatter"
  else
    bad "TC-M1-10 $(basename "$f") frontmatter" "$out"
  fi
done
if [ "$n" -eq 0 ]; then
  bad "TC-M1-10 at least one command/skill/agent file exists" "none found yet"
fi

# ------------------------------------------------------------------- TC-M1-12

echo "== TRIAGE block shape (TC-M1-12) =="

if check_triage_block "$FIX/triage/valid.txt" >/dev/null; then
  ok "TC-M1-12a valid TRIAGE block — 8 fields, in order"
else
  bad "TC-M1-12a valid TRIAGE block — 8 fields, in order" \
      "$(check_triage_block "$FIX/triage/valid.txt")"
fi
out="$(check_triage_block "$FIX/triage/missing_risky.txt" || true)"
if [[ "$out" == MISSING_FIELD:risky* ]]; then
  ok "TC-M1-12b missing 'risky' field detected and named"
else
  bad "TC-M1-12b missing 'risky' field detected and named" "$out"
fi

# ------------------------------------------------------------------- TC-M1-13

echo "== /mkr-init refuse-to-run guard (TC-M1-13) =="

out="$(check_init_refuse "$FIX/init_roots/self")"
if [ "$out" = "BLOCK" ]; then
  ok "TC-M1-13a self root (docs/DESIGN.md title matches) → BLOCK"
else
  bad "TC-M1-13a self root (docs/DESIGN.md title matches) → BLOCK" "$out"
fi
out="$(check_init_refuse "$FIX/init_roots/adopter")"
if [ "$out" = "PROCEED" ]; then
  ok "TC-M1-13b adopter root (no docs/DESIGN.md) → PROCEED"
else
  bad "TC-M1-13b adopter root (no docs/DESIGN.md) → PROCEED" "$out"
fi

# ------------------------------------------------------------------- TC-M1-14

echo "== Approver / MKR_GATE_SPEC consistency (TC-M1-14) =="

if check_approver "$FIX/specs/approver_match.md" "Alex" >/dev/null; then
  ok "TC-M1-14a Approver matches MKR_GATE_SPEC"
else
  bad "TC-M1-14a Approver matches MKR_GATE_SPEC" \
      "$(check_approver "$FIX/specs/approver_match.md" "Alex")"
fi
out="$(check_approver "$FIX/specs/approver_mismatch.md" "Alex" || true)"
if [[ "$out" == APPROVER_MISMATCH:* ]]; then
  ok "TC-M1-14b Approver mismatch detected and named"
else
  bad "TC-M1-14b Approver mismatch detected and named" "$out"
fi

# --------------------------------------------------------------- TC-M2-01..11
# specs/M2_CodeReview_Spec.md §9. Expected red until M2 tasks 4-9 land.

echo
echo "== M2: real repo artifacts (TC-M2-01) =="

M2_FILES=(
  "$ROOT/.claude/agents/mkr-code-reviewer.md"
  "$ROOT/.claude/agents/mkr-security-reviewer.md"
  "$ROOT/.claude/commands/mkr-code-review.md"
  "$ROOT/.claude/skills/mkr-code-review/SKILL.md"
)
for f in "${M2_FILES[@]}"; do
  if [ ! -e "$f" ]; then
    bad "TC-M2-01 $(basename "$f") exists" "not found yet"
    continue
  fi
  case "$f" in
    */agents/*)
      if out="$(check_frontmatter "$f" 1)"; then
        tools_line="$(sed -n '2,/^---$/p' -- "$f" | grep -m1 '^tools:')"
        if [ "$tools_line" = "tools: Read, Grep, Glob" ]; then
          ok "TC-M2-01 $(basename "$f") frontmatter + tools"
        else
          bad "TC-M2-01 $(basename "$f") frontmatter + tools" "BAD_TOOLS:$tools_line"
        fi
      else
        bad "TC-M2-01 $(basename "$f") frontmatter" "$out"
      fi
      ;;
    */commands/*)
      if out="$(check_frontmatter "$f" 0)"; then
        ok "TC-M2-01 $(basename "$f") frontmatter"
      else
        bad "TC-M2-01 $(basename "$f") frontmatter" "$out"
      fi
      ;;
    *)
      if out="$(check_frontmatter "$f" 1)"; then
        ok "TC-M2-01 $(basename "$(dirname "$f")")/SKILL.md frontmatter"
      else
        bad "TC-M2-01 $(basename "$(dirname "$f")")/SKILL.md frontmatter" "$out"
      fi
      ;;
  esac
done

echo
echo "== M2: Boundaries/Seams check is resolvable by a Read/Grep/Glob-only agent (issue #7 fix) =="

BOUNDARIES_AGENT="$ROOT/.claude/agents/mkr-code-reviewer.md"
BOUNDARIES_SKILL="$ROOT/.claude/skills/mkr-code-review/SKILL.md"
if [ -e "$BOUNDARIES_AGENT" ] && [ -e "$BOUNDARIES_SKILL" ]; then
  okb=1
  # The original bug: the agent's own Boundaries/Seams check told it to "Read `config.sh list
  # MKR_BOUNDARIES` (CLI mode)" directly — impossible for a Read/Grep/Glob-only agent (confirmed
  # by TC-M2-01's own tools check above). That exact imperative phrasing must be gone.
  grep -Pzoq '(?s)Read\s+.config\.sh\s+list\s+MKR_BOUNDARIES' -- "$BOUNDARIES_AGENT" && okb=0
  # In its place: the agent's "Inputs you will be given" section names MKR_BOUNDARIES as
  # something the caller resolves and hands it, and its check-6 text says it uses that given
  # value rather than fetching it.
  grep -Pzoq '(?s)MKR_BOUNDARIES.{0,40}resolved by the caller' -- "$BOUNDARIES_AGENT" || okb=0
  grep -Pzoq '(?s)MKR_BOUNDARIES.{0,10}value you were given' -- "$BOUNDARIES_AGENT" || okb=0
  # The orchestrating skill (which does have shell access) must be the one resolving it and
  # passing it to the agent at spawn time — the same pattern mkr-spec-review already uses
  # correctly for MKR_SPEC_EXTRA_SECTIONS.
  grep -Pzoq '(?s)config\.sh\s+list\s+MKR_BOUNDARIES' -- "$BOUNDARIES_SKILL" || okb=0
  grep -Pzoq '(?s)MKR_BOUNDARIES.{0,10}value from step' -- "$BOUNDARIES_SKILL" || okb=0
  if [ "$okb" -eq 1 ]; then
    ok "G7 MKR_BOUNDARIES is resolved by mkr-code-review (shell access) and given to mkr-code-reviewer as an input, never self-resolved by the tool-less agent"
  else
    bad "G7 MKR_BOUNDARIES is resolved by mkr-code-review (shell access) and given to mkr-code-reviewer as an input, never self-resolved by the tool-less agent" \
        "see $BOUNDARIES_AGENT / $BOUNDARIES_SKILL"
  fi
else
  bad "G7 mkr-code-reviewer.md / mkr-code-review/SKILL.md exist" "not found"
fi

echo
echo "== M1: mkr-plan documents its two new optional tokens (issue #6 test coverage) =="

PLAN_SKILL="$ROOT/.claude/skills/mkr-plan/SKILL.md"
if [ -e "$PLAN_SKILL" ]; then
  ok6=1
  grep -q 'ui-feedback-per-wave' -- "$PLAN_SKILL" || ok6=0
  grep -q 'build-directive-conformance' -- "$PLAN_SKILL" || ok6=0
  grep -qi 'incident-backed' -- "$PLAN_SKILL" || ok6=0
  if [ "$ok6" -eq 1 ]; then
    ok "G6 mkr-plan/SKILL.md documents both new optional tokens' meaning, not just their names"
  else
    bad "G6 mkr-plan/SKILL.md documents both new optional tokens' meaning, not just their names" "not found"
  fi
else
  bad "G6 mkr-plan/SKILL.md exists" "not found"
fi

echo
echo "== M1: mkr-adr's origin/<default-branch>-aware numbering (issue #8 test coverage) =="

ADR_SKILL="$ROOT/.claude/skills/mkr-adr/SKILL.md"
if [ -e "$ADR_SKILL" ]; then
  ok8=1
  grep -qi 'default-branch' -- "$ADR_SKILL" || ok8=0
  grep -q 'MKR_PROTECTED_BRANCHES' -- "$ADR_SKILL" || ok8=0
  grep -q 'git fetch origin' -- "$ADR_SKILL" || ok8=0
  grep -qi 'courtesy, not an enforced guarantee' -- "$ADR_SKILL" || ok8=0
  if [ "$ok8" -eq 1 ]; then
    ok "G8 mkr-adr/SKILL.md documents origin/<default-branch>-aware numbering via MKR_PROTECTED_BRANCHES"
  else
    bad "G8 mkr-adr/SKILL.md documents origin/<default-branch>-aware numbering via MKR_PROTECTED_BRANCHES" "not found"
  fi
else
  bad "G8 mkr-adr/SKILL.md exists" "not found"
fi

echo
echo "== M2: review record structure (TC-M2-02, TC-M2-03) =="

if check_review_structure "$FIX/reviews/valid.md" >/dev/null; then
  ok "TC-M2-02a valid record with a finding — 7 sections, in order"
else
  bad "TC-M2-02a valid record with a finding — 7 sections, in order" \
      "$(check_review_structure "$FIX/reviews/valid.md")"
fi
if check_review_structure "$FIX/reviews/zero_findings.md" >/dev/null; then
  ok "TC-M2-02b valid zero-finding record — 6 sections, finding section omitted"
else
  bad "TC-M2-02b valid zero-finding record — 6 sections, finding section omitted" \
      "$(check_review_structure "$FIX/reviews/zero_findings.md")"
fi

out="$(check_review_structure "$FIX/reviews/missing_section.md" || true)"
if [[ "$out" == MISSING:*"Verification discipline"* ]]; then
  ok "TC-M2-03 missing 'Verification discipline' detected and named"
else
  bad "TC-M2-03 missing 'Verification discipline' detected and named" "$out"
fi

echo
echo "== M2: review record verdict line shape (TC-M2-04) =="

if check_review_verdict_line "$FIX/reviews/valid.md" >/dev/null; then
  ok "TC-M2-04a well-formed VERDICT line accepted"
else
  bad "TC-M2-04a well-formed VERDICT line accepted" "$(check_review_verdict_line "$FIX/reviews/valid.md")"
fi
if ! check_review_verdict_line "$FIX/reviews/bad_verdict.md" >/dev/null; then
  ok "TC-M2-04b malformed VERDICT line rejected"
else
  bad "TC-M2-04b malformed VERDICT line rejected" "expected failure, got pass"
fi

echo
echo "== M2: MKR_GATE_REVIEW published (TC-M2-05, TC-M2-06) =="

M2_CFG_LIB="$ROOT/.claude/hooks/lib/config.sh"
M2_EMPTY_CFG="$(mktemp)"; trap 'rm -f "$M2_EMPTY_CFG"' EXIT
out="$(MKR_CONFIG="$M2_EMPTY_CFG" bash "$M2_CFG_LIB" dump 2>/dev/null | grep '^MKR_GATE_REVIEW=' || true)"
if [ "$out" = "MKR_GATE_REVIEW=" ]; then
  ok "TC-M2-05 MKR_GATE_REVIEW present and empty in dump against an empty config"
else
  bad "TC-M2-05 MKR_GATE_REVIEW present and empty in dump against an empty config" "got [$out]"
fi

M2_TMP_CFG="$(mktemp)"; trap 'rm -f "$M2_TMP_CFG"' EXIT
printf 'MKR_GATE_REVIEW=Alex\n' > "$M2_TMP_CFG"
out="$(MKR_CONFIG="$M2_TMP_CFG" bash "$M2_CFG_LIB" get MKR_GATE_REVIEW 2>/dev/null || true)"
dump_out="$(MKR_CONFIG="$M2_TMP_CFG" bash "$M2_CFG_LIB" dump 2>/dev/null | grep '^MKR_GATE_REVIEW=' || true)"
if [ "$out" = "Alex" ] && [ "$dump_out" = "MKR_GATE_REVIEW=Alex" ]; then
  ok "TC-M2-06 MKR_GATE_REVIEW override reachable via get and dump"
else
  bad "TC-M2-06 MKR_GATE_REVIEW override reachable via get and dump" "get=[$out] dump=[$dump_out]"
fi

echo
echo "== M2: CLAUDE.md Gate owners G4 row (TC-M2-07) =="

out="$(grep -A20 '^## Gate owners' -- "$ROOT/CLAUDE.md" | grep -i 'review gate' | grep -i 'G4' || true)"
if [ -n "$out" ]; then
  ok "TC-M2-07 CLAUDE.md Gate owners table has a G4 review-gate row"
else
  bad "TC-M2-07 CLAUDE.md Gate owners table has a G4 review-gate row" "no matching row found"
fi

echo
echo "== M2: pre-push-review-guard.sh (TC-M2-08, TC-M2-09) =="

GUARD="$ROOT/.claude/hooks/scripts/pre-push-review-guard.sh"
if [ -x "$GUARD" ]; then
  M2_REVIEWS_DIR="$(mktemp -d)"
  M2_GUARD_CFG="$(mktemp)"
  printf 'MKR_REVIEWS_DIR=%s/\n' "$M2_REVIEWS_DIR" > "$M2_GUARD_CFG"
  M2_SHA1="1111111111111111111111111111111111111111"
  M2_SHA2="2222222222222222222222222222222222222222"

  out="$(printf 'refs/heads/m2 %s refs/heads/m2 0000000000000000000000000000000000000000\n' "$M2_SHA1" \
    | MKR_CONFIG="$M2_GUARD_CFG" "$GUARD" 2>&1 1>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [[ "$out" == *"WARN:"*"${M2_SHA1:0:7}"* ]]; then
    ok "TC-M2-08 missing record → WARN, exit 0"
  else
    bad "TC-M2-08 missing record → WARN, exit 0" "rc=$rc out=[$out]"
  fi

  printf 'VERDICT: READY\n' > "$M2_REVIEWS_DIR/${M2_SHA2:0:7}.md"
  out="$(printf 'refs/heads/m2 %s refs/heads/m2 0000000000000000000000000000000000000000\n' "$M2_SHA2" \
    | MKR_CONFIG="$M2_GUARD_CFG" "$GUARD" 2>&1 1>/dev/null)"
  rc=$?
  if [ "$rc" -eq 0 ] && [ -z "$out" ]; then
    ok "TC-M2-09 existing record → silent, exit 0"
  else
    bad "TC-M2-09 existing record → silent, exit 0" "rc=$rc out=[$out]"
  fi
  rm -rf "$M2_REVIEWS_DIR" "$M2_GUARD_CFG"
else
  bad "TC-M2-08 pre-push-review-guard.sh exists and is executable" "not found yet"
  bad "TC-M2-09 pre-push-review-guard.sh exists and is executable" "not found yet"
fi

echo
echo "== M2: verdict aggregation rule (TC-M2-11) =="

if ! check_review_aggregation "$FIX/reviews/inconsistent_verdict.md" >/dev/null; then
  ok "TC-M2-11a contradictory sub-verdicts vs closing READY → detected"
else
  bad "TC-M2-11a contradictory sub-verdicts vs closing READY → detected" "expected failure, got pass"
fi
if check_review_aggregation "$FIX/reviews/zero_findings.md" >/dev/null; then
  ok "TC-M2-11b both sub-verdicts READY, closing READY → PASS"
else
  bad "TC-M2-11b both sub-verdicts READY, closing READY → PASS" \
      "$(check_review_aggregation "$FIX/reviews/zero_findings.md")"
fi
if check_review_aggregation "$FIX/reviews/valid.md" >/dev/null; then
  ok "TC-M2-11c one sub-verdict NOT READY, closing NOT READY → PASS"
else
  bad "TC-M2-11c one sub-verdict NOT READY, closing NOT READY → PASS" \
      "$(check_review_aggregation "$FIX/reviews/valid.md")"
fi

# --------------------------------------------------------------- TC-M3-15..17,19
# specs/M3_Guardrails_Spec.md §9. TC-M3-01..14,18 (the hook behavior cases) live in
# tests/hooks_test.sh instead — they need real git-repo fixtures, not static structural checks.

echo
echo "== M3: settings.json wiring (TC-M3-15) =="

SETTINGS="$ROOT/.claude/settings.json"
if [ -e "$SETTINGS" ] && python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$SETTINGS" >/dev/null 2>&1; then
  missing=()
  grep -q 'secret-guard.sh' -- "$SETTINGS" || missing+=("secret-guard.sh")
  grep -q 'branch-guard.sh' -- "$SETTINGS" || missing+=("branch-guard.sh")
  grep -q 'id-collision-guard.sh' -- "$SETTINGS" || missing+=("id-collision-guard.sh")
  grep -q 'spec-gate.sh' -- "$SETTINGS" || missing+=("spec-gate.sh")
  grep -q 'stop-checks.sh' -- "$SETTINGS" || missing+=("stop-checks.sh")
  grep -q 'audit-log.sh' -- "$SETTINGS" || missing+=("audit-log.sh")
  grep -q '"PreToolUse"' -- "$SETTINGS" || missing+=("PreToolUse key")
  grep -q '"PostToolUse"' -- "$SETTINGS" || missing+=("PostToolUse key")
  grep -q '"Stop"' -- "$SETTINGS" || missing+=("Stop key")
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "TC-M3-15 settings.json is valid JSON and wires all six scripts"
  else
    bad "TC-M3-15 settings.json is valid JSON and wires all six scripts" "missing: ${missing[*]}"
  fi
else
  bad "TC-M3-15 settings.json is valid JSON and wires all six scripts" "not found or not valid JSON (needs python3 to check parseability)"
fi

echo
echo "== M3: mkr-gate.yml shape (TC-M3-16) =="

GATE_YML="$ROOT/.github/workflows/mkr-gate.yml"
if [ -e "$GATE_YML" ]; then
  missing=()
  grep -q 'config.sh dump' -- "$GATE_YML" || missing+=("config.sh dump step")
  grep -qi 'ADR-number uniqueness\|duplicate ADR' -- "$GATE_YML" || missing+=("ADR-number uniqueness step")
  grep -q 'MKR_REVIEWS_DIR' -- "$GATE_YML" || missing+=("review-record step")
  grep -q 'find_review_record' -- "$GATE_YML" || missing+=("review-record fallback call")
  if [ "${#missing[@]}" -eq 0 ]; then
    ok "TC-M3-16 mkr-gate.yml has the required steps"
  else
    bad "TC-M3-16 mkr-gate.yml has the required steps" "missing: ${missing[*]}"
  fi
else
  bad "TC-M3-16 mkr-gate.yml has the required steps" "not found yet"
fi

echo
echo "== M3: mkr-gate.yml MKR_SETUP seam (issue #10) =="

if [ -e "$GATE_YML" ]; then
  ok10=1
  grep -q 'MKR_SETUP' -- "$GATE_YML" || ok10=0
  # The setup step must run BEFORE the main MKR_TEST/_COVERAGE/... step, not after — a bootstrap
  # that runs after the commands it's meant to enable would be useless.
  setup_line="$(grep -n 'MKR_SETUP' -- "$GATE_YML" | head -1 | cut -d: -f1)"
  main_line="$(grep -n 'config.sh dump' -- "$GATE_YML" | head -1 | cut -d: -f1)"
  if [ -z "$setup_line" ] || [ -z "$main_line" ] || [ "$setup_line" -ge "$main_line" ]; then
    ok10=0
  fi
  if [ "$ok10" -eq 1 ]; then
    ok "G10 mkr-gate.yml runs MKR_SETUP before the configured test/coverage/lint/build commands"
  else
    bad "G10 mkr-gate.yml runs MKR_SETUP before the configured test/coverage/lint/build commands" "setup_line=$setup_line main_line=$main_line"
  fi
else
  bad "G10 mkr-gate.yml runs MKR_SETUP before the configured test/coverage/lint/build commands" "not found"
fi

echo
echo "== CIGateHardening: mkr-gate.yml permissions/timeout/concurrency/trigger (TC-CGH-01..05) =="

# gate_block — everything from "  gate:" (the only job) to EOF.
gate_block="$(awk '/^  gate:/{f=1} f{print}' "$GATE_YML")"
# on_block / concurrency_block — a top-level key's own indented content, stopping at the next
# top-level (unindented) key.
on_block="$(awk '/^on:/{f=1; print; next} f && /^[[:space:]]/{print; next} {f=0}' "$GATE_YML")"
concurrency_block="$(awk '/^concurrency:/{f=1; print; next} f && /^[[:space:]]/{print; next} {f=0}' "$GATE_YML")"

if printf '%s\n' "$gate_block" | grep -A1 'permissions:' | grep -q 'contents: read'; then
  ok "TC-CGH-01 gate job has permissions: contents: read"
else
  bad "TC-CGH-01 gate job has permissions: contents: read" "$gate_block"
fi

if printf '%s\n' "$gate_block" | grep -qE 'timeout-minutes:[[:space:]]*[0-9]+'; then
  ok "TC-CGH-02 gate job has a numeric timeout-minutes"
else
  bad "TC-CGH-02 gate job has a numeric timeout-minutes" "$gate_block"
fi

if printf '%s\n' "$concurrency_block" | grep -q 'group:' \
   && printf '%s\n' "$concurrency_block" | grep -q 'cancel-in-progress: true'; then
  ok "TC-CGH-03 workflow has a concurrency group with cancel-in-progress: true"
else
  bad "TC-CGH-03 workflow has a concurrency group with cancel-in-progress: true" "$concurrency_block"
fi

if printf '%s\n' "$on_block" | grep -q 'pull_request:' \
   && printf '%s\n' "$on_block" | grep -q 'push:'; then
  ok "TC-CGH-04 on: block still triggers on both pull_request and push (§6 AD-3, investigated, kept)"
else
  bad "TC-CGH-04 on: block still triggers on both pull_request and push (§6 AD-3, investigated, kept)" "$on_block"
fi

if grep -q 'fetch-depth: 0' -- "$GATE_YML"; then
  ok "TC-CGH-05 checkout step still uses fetch-depth: 0 (§6 AD-4, investigated, kept)"
else
  bad "TC-CGH-05 checkout step still uses fetch-depth: 0 (§6 AD-4, investigated, kept)" "not found"
fi

echo
echo "== M3: MKR_TEST widened to the whole suite (TC-M3-19) =="

out="$(bash "$ROOT/.claude/hooks/lib/config.sh" get MKR_TEST 2>/dev/null || true)"
if [[ "$out" == *config_test.sh* ]] && [[ "$out" == *mkr_artifact_test.sh* ]]; then
  ok "TC-M3-19 MKR_TEST covers both test suites"
else
  bad "TC-M3-19 MKR_TEST covers both test suites" "got [$out]"
fi

# --------------------------------------------------------------- TC-M4-01..11
# specs/M4_Audit_Spec.md §9. Expected red until M4 tasks 4-7 land.

echo
echo "== M4: real repo artifacts (TC-M4-01) =="

M4_NAMED_FILES=(
  "$ROOT/.claude/agents/mkr-auditor.md"
  "$ROOT/.claude/skills/mkr-audit/SKILL.md"
  "$ROOT/.claude/skills/mkr-merge/SKILL.md"
)
for f in "${M4_NAMED_FILES[@]}"; do
  if [ ! -e "$f" ]; then
    bad "TC-M4-01 $(basename "$f") exists" "not found yet"
    continue
  fi
  if out="$(check_frontmatter "$f" 1)"; then
    ok "TC-M4-01 $(basename "$f") frontmatter"
  else
    bad "TC-M4-01 $(basename "$f") frontmatter" "$out"
  fi
done
M4_CMD_FILES=(
  "$ROOT/.claude/commands/mkr-audit.md"
  "$ROOT/.claude/commands/mkr-merge.md"
)
for f in "${M4_CMD_FILES[@]}"; do
  if [ ! -e "$f" ]; then
    bad "TC-M4-01 $(basename "$f") exists" "not found yet"
    continue
  fi
  if out="$(check_frontmatter "$f" 0)"; then
    ok "TC-M4-01 $(basename "$f") frontmatter"
  else
    bad "TC-M4-01 $(basename "$f") frontmatter" "$out"
  fi
done

echo
echo "== M4: mkr-auditor tool contract (TC-M4-02) =="

AUDITOR="$ROOT/.claude/agents/mkr-auditor.md"
if [ -e "$AUDITOR" ]; then
  if check_auditor_tools "$AUDITOR" >/dev/null; then
    ok "TC-M4-02a mkr-auditor.md tools: Read, Grep, Glob, Bash"
  else
    bad "TC-M4-02a mkr-auditor.md tools: Read, Grep, Glob, Bash" "$(check_auditor_tools "$AUDITOR")"
  fi
  M4_MUT_TOOLS="$(mktemp)"; trap 'rm -f "$M4_MUT_TOOLS"' EXIT
  sed 's/^tools: Read, Grep, Glob, Bash$/tools: Read, Grep, Glob/' "$AUDITOR" > "$M4_MUT_TOOLS"
  if ! check_auditor_tools "$M4_MUT_TOOLS" >/dev/null; then
    ok "TC-M4-02b mutated to three-tool shape → rejected"
  else
    bad "TC-M4-02b mutated to three-tool shape → rejected" "expected failure, got pass"
  fi
else
  bad "TC-M4-02 mkr-auditor.md exists" "not found yet"
fi

echo
echo "== M4: audit record structure (TC-M4-03) =="

if check_audit_structure "$FIX/audits/valid.md" >/dev/null; then
  ok "TC-M4-03a valid record — six elements, in order"
else
  bad "TC-M4-03a valid record — six elements, in order" \
      "$(check_audit_structure "$FIX/audits/valid.md")"
fi
out="$(check_audit_structure "$FIX/audits/no_verdict.md" || true)"
if [[ "$out" == MISSING:Verdict* ]]; then
  ok "TC-M4-03b missing closing Verdict paragraph detected and named"
else
  bad "TC-M4-03b missing closing Verdict paragraph detected and named" "$out"
fi
if check_audit_structure "$FIX/audits/no_outstanding.md" >/dev/null; then
  ok "TC-M4-03c optional 'Outstanding' section may be omitted"
else
  bad "TC-M4-03c optional 'Outstanding' section may be omitted" \
      "$(check_audit_structure "$FIX/audits/no_outstanding.md")"
fi
out="$(check_audit_structure "$FIX/audits/table_before_provenance.md" || true)"
if [[ "$out" == ORDER_VIOLATION* ]]; then
  ok "TC-M4-03d table before provenance → ordering violation"
else
  bad "TC-M4-03d table before provenance → ordering violation" "$out"
fi

echo
echo "== M4: audit verdict cells and aggregation (TC-M4-04) =="

if ! check_audit_aggregation "$FIX/audits/agg_mismatch.md" >/dev/null; then
  ok "TC-M4-04a NOT VERIFIED row with closing PASS → detected"
else
  bad "TC-M4-04a NOT VERIFIED row with closing PASS → detected" "expected failure, got pass"
fi
if check_audit_aggregation "$FIX/audits/valid.md" >/dev/null; then
  ok "TC-M4-04b all VERIFIED, closing PASS → PASS"
else
  bad "TC-M4-04b all VERIFIED, closing PASS → PASS" \
      "$(check_audit_aggregation "$FIX/audits/valid.md")"
fi
if check_audit_aggregation "$FIX/audits/not_verified_valid.md" >/dev/null; then
  ok "TC-M4-04c one NOT VERIFIED, closing FAIL (1 not verified) → PASS"
else
  bad "TC-M4-04c one NOT VERIFIED, closing FAIL (1 not verified) → PASS" \
      "$(check_audit_aggregation "$FIX/audits/not_verified_valid.md")"
fi
out="$(check_audit_verdict_cells "$FIX/audits/malformed_cell.md" || true)"
if [[ "$out" == BAD_CELL:* ]]; then
  ok "TC-M4-04d NOT VERIFIED cell missing its (<reason>) → detected"
else
  bad "TC-M4-04d NOT VERIFIED cell missing its (<reason>) → detected" "$out"
fi
out="$(check_audit_verdict_cells "$FIX/audits/partial_cell.md" || true)"
if [[ "$out" == BAD_CELL:* ]]; then
  ok "TC-M4-04e PARTIALLY VERIFIED cell → detected as neither literal value"
else
  bad "TC-M4-04e PARTIALLY VERIFIED cell → detected as neither literal value" "$out"
fi

echo
echo "== M4: audit AC-label ordering and uniqueness (TC-M4-05) =="

if check_audit_ac_labels "$FIX/audits/valid.md" >/dev/null; then
  ok "TC-M4-05a AC labels exactly once, in order → PASS"
else
  bad "TC-M4-05a AC labels exactly once, in order → PASS" \
      "$(check_audit_ac_labels "$FIX/audits/valid.md")"
fi
out="$(check_audit_ac_labels "$FIX/audits/dup_drop.md" || true)"
if [[ "$out" == LABEL_SET_MISMATCH:* ]]; then
  ok "TC-M4-05b duplicated + dropped AC row (same count) → detected"
else
  bad "TC-M4-05b duplicated + dropped AC row (same count) → detected" "$out"
fi
out="$(check_audit_ac_labels "$FIX/audits/out_of_order.md" || true)"
if [[ "$out" == ORDER_VIOLATION:* ]]; then
  ok "TC-M4-05c all AC labels present but out of order → detected"
else
  bad "TC-M4-05c all AC labels present but out of order → detected" "$out"
fi

echo
echo "== M4: config contract unchanged (TC-M4-06) =="

M4_CFG_LIB="$ROOT/.claude/hooks/lib/config.sh"
out="$(MKR_CONFIG="$ROOT/.mkr/config" bash "$M4_CFG_LIB" get MKR_AUDITS_DIR 2>/dev/null || true)"
if [ "$out" = ".mkr/audits/" ]; then
  ok "TC-M4-06 MKR_AUDITS_DIR unchanged"
else
  bad "TC-M4-06 MKR_AUDITS_DIR unchanged" "got [$out]"
fi
out="$(MKR_CONFIG="$ROOT/.mkr/config" bash "$M4_CFG_LIB" get MKR_GATE_MERGE 2>/dev/null || true)"
if [ "$out" = "kikrgbh" ]; then
  ok "TC-M4-06 MKR_GATE_MERGE names kikrgbh (M6_GoPublic redaction)"
else
  bad "TC-M4-06 MKR_GATE_MERGE names kikrgbh (M6_GoPublic redaction)" "got [$out]"
fi

echo
echo "== M4: CLAUDE.md Gate owners unchanged (TC-M4-07) =="

if grep -qF '| pre-merge | kikrgbh |' "$ROOT/CLAUDE.md" \
   && grep -qF '| incident / kill switch | kikrgbh |' "$ROOT/CLAUDE.md"; then
  ok "TC-M4-07 Gate owners table names kikrgbh for pre-merge and incident/kill-switch (M6_GoPublic redaction)"
else
  bad "TC-M4-07 Gate owners table names kikrgbh for pre-merge and incident/kill-switch (M6_GoPublic redaction)" \
      "row(s) missing or reworded"
fi

echo
echo "== M4: mkr-merge asks before executing (TC-M4-08) =="

MERGE_SKILL="$ROOT/.claude/skills/mkr-merge/SKILL.md"
if [ -e "$MERGE_SKILL" ]; then
  if check_merge_ask_before_execute "$MERGE_SKILL" >/dev/null; then
    ok "TC-M4-08a ask precedes merge-execution in mkr-merge/SKILL.md"
  else
    bad "TC-M4-08a ask precedes merge-execution in mkr-merge/SKILL.md" \
        "$(check_merge_ask_before_execute "$MERGE_SKILL")"
  fi
else
  bad "TC-M4-08a mkr-merge/SKILL.md exists" "not found yet"
fi
if ! check_merge_ask_before_execute "$FIX/merge_gate/execute_before_ask.md" >/dev/null; then
  ok "TC-M4-08b execution moved before the ask → detected"
else
  bad "TC-M4-08b execution moved before the ask → detected" "expected failure, got pass"
fi

echo
echo "== M4: mkr-merge gh fallback disclosure (TC-M4-09) =="

if [ -e "$MERGE_SKILL" ]; then
  if check_merge_gh_fallback "$MERGE_SKILL" >/dev/null; then
    ok "TC-M4-09a documents gh-available path, git-only fallback, and CI-unconfirmable disclosure"
  else
    bad "TC-M4-09a documents gh-available path, git-only fallback, and CI-unconfirmable disclosure" \
        "$(check_merge_gh_fallback "$MERGE_SKILL")"
  fi
  M4_MUT_PUSH="$(mktemp)"; trap 'rm -f "$M4_MUT_PUSH"' EXIT
  sed "s/\*\*Do not follow it with \`git push\`\*\* in a repo where/then \`git push\` in a repo where/" \
    "$MERGE_SKILL" > "$M4_MUT_PUSH"
  out="$(check_merge_gh_fallback "$M4_MUT_PUSH" || true)"
  if [[ "$out" == REGRESSION:* ]]; then
    ok "TC-M4-09b fallback reintroducing 'then \`git push\`' → detected as a regression"
  else
    bad "TC-M4-09b fallback reintroducing 'then \`git push\`' → detected as a regression" "$out"
  fi
else
  bad "TC-M4-09 mkr-merge/SKILL.md exists" "not found yet"
fi

echo
echo "== M4: mkr-merge's three gating stops (TC-M4-11) =="

if [ -e "$MERGE_SKILL" ]; then
  if check_merge_gating "$MERGE_SKILL" >/dev/null; then
    ok "TC-M4-11a all three gating stops present, before the ask"
  else
    bad "TC-M4-11a all three gating stops present, before the ask" \
        "$(check_merge_gating "$MERGE_SKILL")"
  fi
else
  bad "TC-M4-11a mkr-merge/SKILL.md exists" "not found yet"
fi
out="$(check_merge_gating "$FIX/merge_gate/missing_g4_stop.md" || true)"
if [[ "$out" == MISSING:*"G4"* ]]; then
  ok "TC-M4-11b missing G4 gating stop → detected and named"
else
  bad "TC-M4-11b missing G4 gating stop → detected and named" "$out"
fi
out="$(check_merge_gating "$FIX/merge_gate/missing_ci_stop.md" || true)"
if [[ "$out" == MISSING:*"CI"* ]]; then
  ok "TC-M4-11c missing CI gating stop → detected and named"
else
  bad "TC-M4-11c missing CI gating stop → detected and named" "$out"
fi
out="$(check_merge_gating "$FIX/merge_gate/missing_spec_stop.md" || true)"
if [[ "$out" == MISSING:*"spec"* ]]; then
  ok "TC-M4-11d missing spec gating stop → detected and named"
else
  bad "TC-M4-11d missing spec gating stop → detected and named" "$out"
fi

echo
echo "== M4: mkr-merge conflict check, bookkeeping, branch cleanup (issue #9, docs/adr/0006) =="

if [ -e "$MERGE_SKILL" ]; then
  ok9=1
  grep -qi 'git merge-tree' -- "$MERGE_SKILL" || ok9=0
  grep -qi 'propose' -- "$MERGE_SKILL" || ok9=0
  grep -q 'never auto-resolved\|never applies it\|never apply a resolution' -- "$MERGE_SKILL" || ok9=0
  if [ "$ok9" -eq 1 ]; then
    ok "G9a mkr-merge documents a conflict dry-run that proposes but never auto-applies a resolution"
  else
    bad "G9a mkr-merge documents a conflict dry-run that proposes but never auto-applies a resolution"         "not found"
  fi

  ok9b=1
  grep -qi 'Closes #N' -- "$MERGE_SKILL" || ok9b=0
  grep -qi 'gh issue' -- "$MERGE_SKILL" || ok9b=0
  if [ "$ok9b" -eq 1 ]; then
    ok "G9b mkr-merge documents the linked-issue bookkeeping step"
  else
    bad "G9b mkr-merge documents the linked-issue bookkeeping step" "not found"
  fi

  ok9c=1
  grep -qi 'now-merged source' -- "$MERGE_SKILL" || ok9c=0
  grep -q 'never read as a\|is never read as' -- "$MERGE_SKILL" || ok9c=0
  if [ "$ok9c" -eq 1 ]; then
    ok "G9c mkr-merge documents branch deletion as its own separate ask, not implied by the merge ask"
  else
    bad "G9c mkr-merge documents branch deletion as its own separate ask, not implied by the merge ask"         "not found"
  fi
else
  bad "G9 mkr-merge/SKILL.md exists" "not found yet"
fi

echo
echo "== G4ReviewRecordFallback: mkr-merge/SKILL.md documents the parent fallback (TC-RRF-07) =="

_g4_step2="$(awk '/^## 2\. G4 check/{f=1;next} /^## /&&f{exit} f{print}' "$MERGE_SKILL")"
if printf '%s\n' "$_g4_step2" | grep -q "parent"; then
  ok "TC-RRF-07 mkr-merge/SKILL.md step 2 documents the one-level parent fallback"
else
  bad "TC-RRF-07 mkr-merge/SKILL.md step 2 documents the one-level parent fallback" \
      "no mention of 'parent' in step 2's section"
fi

# --------------------------------------------------------------- TC-M5-01..12
# specs/M5_Gates_Spec.md §9. Expected red until M5 tasks 4-11 land.

echo
echo "== M5: real repo artifacts (TC-M5-01) =="

M5_AGENT_FILES=(
  "$ROOT/.claude/agents/mkr-design-reviewer.md"
  "$ROOT/.claude/agents/mkr-architecture-reviewer.md"
)
for f in "${M5_AGENT_FILES[@]}"; do
  if [ ! -e "$f" ]; then
    bad "TC-M5-01 $(basename "$f") exists" "not found yet"
    continue
  fi
  if out="$(check_frontmatter "$f" 1)"; then
    tools_line="$(sed -n '2,/^---$/p' -- "$f" | grep -m1 '^tools:')"
    if [ "$tools_line" = "tools: Read, Grep, Glob" ]; then
      ok "TC-M5-01 $(basename "$f") frontmatter + tools"
    else
      bad "TC-M5-01 $(basename "$f") frontmatter + tools" "BAD_TOOLS:$tools_line"
    fi
  else
    bad "TC-M5-01 $(basename "$f") frontmatter" "$out"
  fi
done

M5_SKILL_FILES=(
  "$ROOT/.claude/skills/mkr-design/SKILL.md"
  "$ROOT/.claude/skills/mkr-gates/SKILL.md"
  "$ROOT/.claude/skills/mkr-ship/SKILL.md"
  "$ROOT/.claude/skills/mkr-evals/SKILL.md"
  "$ROOT/.claude/skills/mkr-capture/SKILL.md"
)
for f in "${M5_SKILL_FILES[@]}"; do
  if [ ! -e "$f" ]; then
    bad "TC-M5-01 $(basename "$(dirname "$f")")/SKILL.md exists" "not found yet"
    continue
  fi
  if out="$(check_frontmatter "$f" 1)"; then
    ok "TC-M5-01 $(basename "$(dirname "$f")")/SKILL.md frontmatter"
  else
    bad "TC-M5-01 $(basename "$(dirname "$f")")/SKILL.md frontmatter" "$out"
  fi
done

M5_CMD_FILES=(
  "$ROOT/.claude/commands/mkr-design.md"
  "$ROOT/.claude/commands/mkr-ship.md"
)
for f in "${M5_CMD_FILES[@]}"; do
  if [ ! -e "$f" ]; then
    bad "TC-M5-01 $(basename "$f") exists" "not found yet"
    continue
  fi
  if out="$(check_frontmatter "$f" 0)"; then
    ok "TC-M5-01 $(basename "$f") frontmatter"
  else
    bad "TC-M5-01 $(basename "$f") frontmatter" "$out"
  fi
done

M5_ABSENT_CMDS=(
  "$ROOT/.claude/commands/mkr-gates.md"
  "$ROOT/.claude/commands/mkr-evals.md"
  "$ROOT/.claude/commands/mkr-capture.md"
)
for f in "${M5_ABSENT_CMDS[@]}"; do
  if [ ! -e "$f" ]; then
    ok "TC-M5-01 $(basename "$f") correctly absent (skill-only, §3)"
  else
    bad "TC-M5-01 $(basename "$f") correctly absent (skill-only, §3)" "unexpectedly exists"
  fi
done

echo
echo "== M5: design record structure and aggregation (TC-M5-02) =="

if check_design_structure "$FIX/designs/valid.md" >/dev/null; then
  ok "TC-M5-02a valid record with a finding — six elements, in order"
else
  bad "TC-M5-02a valid record with a finding — six elements, in order" \
      "$(check_design_structure "$FIX/designs/valid.md")"
fi
if ! check_design_aggregation "$FIX/designs/inconsistent_verdict.md" >/dev/null; then
  ok "TC-M5-02b one sub-verdict NOT READY, closing READY → detected"
else
  bad "TC-M5-02b one sub-verdict NOT READY, closing READY → detected" "expected failure, got pass"
fi
if check_design_structure "$FIX/designs/zero_findings.md" >/dev/null \
   && check_design_aggregation "$FIX/designs/zero_findings.md" >/dev/null; then
  ok "TC-M5-02c zero findings, both sub-verdicts READY, closing READY → PASS"
else
  bad "TC-M5-02c zero findings, both sub-verdicts READY, closing READY → PASS" \
      "structure=$(check_design_structure "$FIX/designs/zero_findings.md") aggregation=$(check_design_aggregation "$FIX/designs/zero_findings.md")"
fi

echo
echo "== M5: config keys published (TC-M5-03) =="

M5_CFG_LIB="$ROOT/.claude/hooks/lib/config.sh"
M5_EMPTY_CFG="$(mktemp)"; trap 'rm -f "$M5_EMPTY_CFG"' EXIT
dump_out="$(MKR_CONFIG="$M5_EMPTY_CFG" bash "$M5_CFG_LIB" dump 2>/dev/null)"
m5_ok=1
[[ "$dump_out" == *$'\n'"MKR_DESIGN_DIR=.mkr/designs/"$'\n'* ]] || m5_ok=0
[[ "$dump_out" == *$'\n'"MKR_DEPLOY="$'\n'* ]] || m5_ok=0
[[ "$dump_out" == *$'\n'"MKR_EVALS_DIR=.mkr/evals/"$'\n'* ]] || m5_ok=0
[[ "$dump_out" == *$'\n'"MKR_CAPTURE_LOG=.mkr/captures.jsonl"$'\n'* ]] || m5_ok=0
if [ "$m5_ok" = 1 ]; then
  ok "TC-M5-03 MKR_DESIGN_DIR/MKR_DEPLOY/MKR_EVALS_DIR/MKR_CAPTURE_LOG present in dump against an empty config"
else
  bad "TC-M5-03 MKR_DESIGN_DIR/MKR_DEPLOY/MKR_EVALS_DIR/MKR_CAPTURE_LOG present in dump against an empty config" \
      "$dump_out"
fi

echo
echo "== M5: config key overrides and mutation resistance (TC-M5-04) =="

M5_TMP_CFG="$(mktemp)"; trap 'rm -f "$M5_TMP_CFG"' EXIT
cat > "$M5_TMP_CFG" <<'CFGEOF'
MKR_DESIGN_DIR=custom-designs/
MKR_DEPLOY=./deploy.sh
MKR_EVALS_DIR=custom-evals/
MKR_CAPTURE_LOG=custom.jsonl
CFGEOF
for pair in "MKR_DESIGN_DIR:custom-designs/" "MKR_DEPLOY:./deploy.sh" \
            "MKR_EVALS_DIR:custom-evals/" "MKR_CAPTURE_LOG:custom.jsonl"; do
  name="${pair%%:*}"; want="${pair#*:}"
  got="$(MKR_CONFIG="$M5_TMP_CFG" bash "$M5_CFG_LIB" get "$name" 2>/dev/null || true)"
  if [ "$got" = "$want" ]; then
    ok "TC-M5-04 $name override reachable via get"
  else
    bad "TC-M5-04 $name override reachable via get" "got [$got] want [$want]"
  fi
done

M5_MUT_LIB="$(mktemp)"; trap 'rm -f "$M5_MUT_LIB"' EXIT
sed -E '/MKR_DESIGN_DIR MKR_DEPLOY MKR_EVALS_DIR/d' "$M5_CFG_LIB" > "$M5_MUT_LIB"
mut_dump="$(MKR_CONFIG="$M5_TMP_CFG" bash "$M5_MUT_LIB" dump 2>/dev/null | grep '^MKR_DESIGN_DIR=' || true)"
mut_get="$(MKR_CONFIG="$M5_TMP_CFG" bash "$M5_MUT_LIB" get MKR_DESIGN_DIR 2>/dev/null || true)"
if [ -z "$mut_dump" ] && [ "$mut_get" = "custom-designs/" ]; then
  ok "TC-M5-04 removing MKR_DESIGN_DIR from _mkr_names(): get still resolves, dump omits the row"
else
  bad "TC-M5-04 removing MKR_DESIGN_DIR from _mkr_names(): get still resolves, dump omits the row" \
      "dump=[$mut_dump] get=[$mut_get]"
fi

echo
echo "== M5: mkr-gates split mechanic (TC-M5-05) =="

GATES_SKILL="$ROOT/.claude/skills/mkr-gates/SKILL.md"
if [ -e "$GATES_SKILL" ]; then
  if check_gates_split_mechanic "$GATES_SKILL" >/dev/null; then
    ok "TC-M5-05a documents git-stash split and the already-committed disclosure"
  else
    bad "TC-M5-05a documents git-stash split and the already-committed disclosure" \
        "$(check_gates_split_mechanic "$GATES_SKILL")"
  fi
  M5_MUT_GATES="$(mktemp)"; trap 'rm -f "$M5_MUT_GATES"' EXIT
  sed 's/do not attempt history surgery/attempts a rebase automatically/' "$GATES_SKILL" > "$M5_MUT_GATES"
  out="$(check_gates_split_mechanic "$M5_MUT_GATES" || true)"
  if [[ "$out" == MISSING:*"already-committed"* ]]; then
    ok "TC-M5-05b already-committed disclosure removed → detected"
  else
    bad "TC-M5-05b already-committed disclosure removed → detected" "$out"
  fi
else
  bad "TC-M5-05 mkr-gates/SKILL.md exists" "not found yet"
fi

echo
echo "== M5: mkr-gates reuses mkr-loop's classification, does not duplicate it (TC-M5-06) =="

if [ -e "$GATES_SKILL" ]; then
  if check_gates_split_mechanic "$GATES_SKILL" >/dev/null; then
    ok "TC-M5-06a references mkr-loop's six-question classification"
  else
    bad "TC-M5-06a references mkr-loop's six-question classification" \
        "$(check_gates_split_mechanic "$GATES_SKILL")"
  fi
  M5_MUT_DUP="$(mktemp)"; trap 'rm -f "$M5_MUT_DUP"' EXIT
  { cat "$GATES_SKILL"; printf '\n- **Deep** if **any** of: duplicated decision text\n'; } > "$M5_MUT_DUP"
  out="$(check_gates_split_mechanic "$M5_MUT_DUP" || true)"
  if [[ "$out" == REGRESSION:* ]]; then
    ok "TC-M5-06b reintroducing mkr-loop's own decision-rule text → detected as a regression"
  else
    bad "TC-M5-06b reintroducing mkr-loop's own decision-rule text → detected as a regression" "$out"
  fi
else
  bad "TC-M5-06 mkr-gates/SKILL.md exists" "not found yet"
fi

echo
echo "== M5: mkr-ship asks before executing; G6 not auto-allowed (TC-M5-07) =="

SHIP_SKILL="$ROOT/.claude/skills/mkr-ship/SKILL.md"
if [ -e "$SHIP_SKILL" ]; then
  if check_ship_ask_before_execute "$SHIP_SKILL" >/dev/null; then
    ok "TC-M5-07a not-configured check, then ask, then execution — in order"
  else
    bad "TC-M5-07a not-configured check, then ask, then execution — in order" \
        "$(check_ship_ask_before_execute "$SHIP_SKILL")"
  fi
  M5_MUT_SHIP="$(mktemp)"; trap 'rm -f "$M5_MUT_SHIP"' EXIT
  sed 's/\*\*Ask\.\*\*/run `MKR_DEPLOY` first, then **Ask.**/' "$SHIP_SKILL" > "$M5_MUT_SHIP"
  if ! check_ship_ask_before_execute "$M5_MUT_SHIP" >/dev/null; then
    ok "TC-M5-07b execution moved before the ask → detected"
  else
    bad "TC-M5-07b execution moved before the ask → detected" "expected failure, got pass"
  fi
else
  bad "TC-M5-07a mkr-ship/SKILL.md exists" "not found yet"
fi

SETTINGS="$ROOT/.claude/settings.json"
if [ -e "$SETTINGS" ] && ! grep -qi 'deploy' -- "$SETTINGS"; then
  ok "TC-M5-07c settings.json names no deploy-shaped command (G6 not auto-allowed)"
else
  bad "TC-M5-07c settings.json names no deploy-shaped command (G6 not auto-allowed)" \
      "$([ -e "$SETTINGS" ] && grep -i 'deploy' -- "$SETTINGS" || echo 'settings.json not found')"
fi

echo
echo "== M5: mkr-ship not-configured path (TC-M5-08) =="

if [ -e "$SHIP_SKILL" ] && grep -q -F 'MKR_DEPLOY` is empty' -- "$SHIP_SKILL"; then
  ok "TC-M5-08 explicit not-configured/no-action instruction present"
else
  bad "TC-M5-08 explicit not-configured/no-action instruction present" "not found"
fi

echo
echo "== M5: mkr-evals seeded fixtures for mkr-spec-reviewer (TC-M5-09) =="

EVALS_FIX_DIR="$ROOT/.mkr/evals/fixtures/mkr-spec-reviewer"
if [ -d "$EVALS_FIX_DIR" ]; then
  n_files=$(find "$EVALS_FIX_DIR" -type f | wc -l | tr -d ' ')
  has_ready="$(grep -rlF 'expected: READY' -- "$EVALS_FIX_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  has_not_ready="$(grep -rlF 'expected: NOT READY' -- "$EVALS_FIX_DIR" 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n_files" -ge 2 ] && [ "$has_ready" -ge 1 ] && [ "$has_not_ready" -ge 1 ]; then
    ok "TC-M5-09 at least 2 fixtures, one expected READY and one expected NOT READY"
  else
    bad "TC-M5-09 at least 2 fixtures, one expected READY and one expected NOT READY" \
        "files=$n_files ready=$has_ready not_ready=$has_not_ready"
  fi
else
  bad "TC-M5-09 $EVALS_FIX_DIR exists" "not found yet"
fi

echo
echo "== M5: mkr-capture same-class-twice threshold (TC-M5-10) =="

CAPTURE_SKILL="$ROOT/.claude/skills/mkr-capture/SKILL.md"
if [ -e "$CAPTURE_SKILL" ]; then
  if check_capture_threshold "$CAPTURE_SKILL" >/dev/null; then
    ok "TC-M5-10a fixed threshold (2) stated, no MKR_CAPTURE_THRESHOLD reference"
  else
    bad "TC-M5-10a fixed threshold (2) stated, no MKR_CAPTURE_THRESHOLD reference" \
        "$(check_capture_threshold "$CAPTURE_SKILL")"
  fi
  M5_MUT_CAP="$(mktemp)"; trap 'rm -f "$M5_MUT_CAP"' EXIT
  { cat "$CAPTURE_SKILL"; printf '\nCheck against MKR_CAPTURE_THRESHOLD.\n'; } > "$M5_MUT_CAP"
  out="$(check_capture_threshold "$M5_MUT_CAP" || true)"
  if [[ "$out" == REGRESSION:* ]]; then
    ok "TC-M5-10b reintroducing a config-variable threshold → detected as a regression"
  else
    bad "TC-M5-10b reintroducing a config-variable threshold → detected as a regression" "$out"
  fi
else
  bad "TC-M5-10 mkr-capture/SKILL.md exists" "not found yet"
fi

echo
echo "== M5: CLAUDE.md Gate owners unchanged (TC-M5-11) =="

if grep -qF '| spec approval | kikrgbh |' "$ROOT/CLAUDE.md" \
   && grep -qF '| design | kikrgbh |' "$ROOT/CLAUDE.md" \
   && grep -qF '| review gate (G4) | kikrgbh |' "$ROOT/CLAUDE.md" \
   && grep -qF '| pre-merge | kikrgbh |' "$ROOT/CLAUDE.md" \
   && grep -qF '| pre-deploy | kikrgbh |' "$ROOT/CLAUDE.md" \
   && grep -qF '| incident / kill switch | kikrgbh |' "$ROOT/CLAUDE.md"; then
  ok "TC-M5-11 Gate owners table still has all six rows naming kikrgbh (M6_GoPublic redaction)"
else
  bad "TC-M5-11 Gate owners table still has all six rows naming kikrgbh (M6_GoPublic redaction)" \
      "row(s) missing or reworded"
fi

echo
echo "== M6: mkr-update scaffolding (TC-M6-16) =="

UPDATE_SKILL="$ROOT/.claude/skills/mkr-update/SKILL.md"
UPDATE_CMD="$ROOT/.claude/commands/mkr-update.md"
if [ -e "$UPDATE_SKILL" ]; then
  if out="$(check_frontmatter "$UPDATE_SKILL" 1)"; then
    ok "TC-M6-16 mkr-update/SKILL.md frontmatter"
  else
    bad "TC-M6-16 mkr-update/SKILL.md frontmatter" "$out"
  fi
else
  bad "TC-M6-16 mkr-update/SKILL.md exists" "not found yet"
fi
if [ -e "$UPDATE_CMD" ]; then
  if out="$(check_frontmatter "$UPDATE_CMD" 0)"; then
    ok "TC-M6-16 mkr-update.md command frontmatter"
  else
    bad "TC-M6-16 mkr-update.md command frontmatter" "$out"
  fi
else
  bad "TC-M6-16 mkr-update.md command exists" "not found yet"
fi

echo
echo "== M6: mkr-update asks before applying (TC-M6-17) =="

if [ -e "$UPDATE_SKILL" ]; then
  if check_update_ask_before_apply "$UPDATE_SKILL" >/dev/null; then
    ok "TC-M6-17a dry-run < ask < apply, in order, in mkr-update/SKILL.md"
  else
    bad "TC-M6-17a dry-run < ask < apply, in order, in mkr-update/SKILL.md" \
        "$(check_update_ask_before_apply "$UPDATE_SKILL")"
  fi
  M6_MUT_APPLY_FIRST="$(mktemp)"; trap 'rm -f "$M6_MUT_APPLY_FIRST"' EXIT
  sed 's/^## 6\. \*\*Ask\.\*\*$/## 6. AskX/' "$UPDATE_SKILL" > "$M6_MUT_APPLY_FIRST"
  printf '\n**Ask.**\n' >> "$M6_MUT_APPLY_FIRST"
  out="$(check_update_ask_before_apply "$M6_MUT_APPLY_FIRST" || true)"
  if [[ "$out" == ORDER_VIOLATION* ]]; then
    ok "TC-M6-17b ask moved after apply → detected"
  else
    bad "TC-M6-17b ask moved after apply → detected" "$out"
  fi
else
  bad "TC-M6-17 mkr-update/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-update names --force trade-off before asking (TC-M6-18) =="

if [ -e "$UPDATE_SKILL" ]; then
  if check_update_force_language "$UPDATE_SKILL" >/dev/null; then
    ok "TC-M6-18a --force/refused language precedes the ask"
  else
    bad "TC-M6-18a --force/refused language precedes the ask" \
        "$(check_update_force_language "$UPDATE_SKILL")"
  fi
  M6_MUT_NOFORCE="$(mktemp)"; trap 'rm -f "$M6_MUT_NOFORCE"' EXIT
  grep -v -i -E -- '--force|refused|locally-edited' "$UPDATE_SKILL" > "$M6_MUT_NOFORCE"
  out="$(check_update_force_language "$M6_MUT_NOFORCE" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-18b --force language removed → detected"
  else
    bad "TC-M6-18b --force language removed → detected" "$out"
  fi
else
  bad "TC-M6-18 mkr-update/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-update drift report enumerates all five labels (TC-M6-19) =="

if [ -e "$UPDATE_SKILL" ]; then
  if check_update_drift_labels "$UPDATE_SKILL" >/dev/null; then
    ok "TC-M6-19a drift report enumerates created/restored/updated/orphaned/refused"
  else
    bad "TC-M6-19a drift report enumerates created/restored/updated/orphaned/refused" \
        "$(check_update_drift_labels "$UPDATE_SKILL")"
  fi
  M6_MUT_DROPLABEL="$(mktemp)"; trap 'rm -f "$M6_MUT_DROPLABEL"' EXIT
  sed 's/`orphaned`, //' "$UPDATE_SKILL" > "$M6_MUT_DROPLABEL"
  out="$(check_update_drift_labels "$M6_MUT_DROPLABEL" || true)"
  if [[ "$out" == MISSING:orphaned* ]]; then
    ok "TC-M6-19b orphaned label dropped → detected"
  else
    bad "TC-M6-19b orphaned label dropped → detected" "$out"
  fi
else
  bad "TC-M6-19 mkr-update/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-update aborts on dry-run precondition failure (TC-M6-27) =="

if [ -e "$UPDATE_SKILL" ]; then
  if check_update_abort_on_precondition_failure "$UPDATE_SKILL" >/dev/null; then
    ok "TC-M6-27a abort-on-precondition-failure precedes drift-report and ask"
  else
    bad "TC-M6-27a abort-on-precondition-failure precedes drift-report and ask" \
        "$(check_update_abort_on_precondition_failure "$UPDATE_SKILL")"
  fi
  M6_MUT_NOABORT="$(mktemp)"; trap 'rm -f "$M6_MUT_NOABORT"' EXIT
  sed '/^## 3\. If this dry-run exits nonzero, stop here$/,/^## 4\./{/^## 4\./!d}' \
    "$UPDATE_SKILL" > "$M6_MUT_NOABORT"
  out="$(check_update_abort_on_precondition_failure "$M6_MUT_NOABORT" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-27b abort branch removed → detected"
  else
    bad "TC-M6-27b abort branch removed → detected" "$out"
  fi
else
  bad "TC-M6-27 mkr-update/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect scaffolding (TC-M6-28) =="

DETECT_SKILL="$ROOT/.claude/skills/mkr-detect/SKILL.md"
DETECT_CMD="$ROOT/.claude/commands/mkr-detect.md"
INIT_CMD="$ROOT/.claude/commands/mkr-init.md"
if [ -e "$DETECT_SKILL" ]; then
  if out="$(check_frontmatter "$DETECT_SKILL" 1)"; then
    ok "TC-M6-28 mkr-detect/SKILL.md frontmatter"
  else
    bad "TC-M6-28 mkr-detect/SKILL.md frontmatter" "$out"
  fi
else
  bad "TC-M6-28 mkr-detect/SKILL.md exists" "not found yet"
fi
if [ -e "$DETECT_CMD" ]; then
  if out="$(check_frontmatter "$DETECT_CMD" 0)"; then
    ok "TC-M6-28 mkr-detect.md command frontmatter"
  else
    bad "TC-M6-28 mkr-detect.md command frontmatter" "$out"
  fi
else
  bad "TC-M6-28 mkr-detect.md command exists" "not found yet"
fi

# mutate_missing <file> <needle> — copies <file> to a temp path with the first line
# containing <needle> deleted, prints the temp path.
mutate_missing() {
  local file="$1" needle="$2" tmp
  tmp="$(mktemp)"
  awk -v needle="$needle" 'index($0, needle) == 0' "$file" > "$tmp"
  printf '%s' "$tmp"
}

echo
echo "== M6: mkr-detect names all four primary markers (TC-M6-29) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_markers "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-29a all four primary markers named"
  else
    bad "TC-M6-29a all four primary markers named" "$(check_detect_markers "$DETECT_SKILL")"
  fi
  M6_MUT_NOGO="$(mutate_missing "$DETECT_SKILL" 'Primary marker: `go.mod`.')"
  out="$(check_detect_markers "$M6_MUT_NOGO" || true)"
  if [[ "$out" == MISSING:go.mod* ]]; then
    ok "TC-M6-29b go.mod marker removed → detected"
  else
    bad "TC-M6-29b go.mod marker removed → detected" "$out"
  fi
  rm -f "$M6_MUT_NOGO"
else
  bad "TC-M6-29 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect Node/TS detection (TC-M6-30) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_node "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-30a all eleven Node/TS claims present"
  else
    bad "TC-M6-30a all eleven Node/TS claims present" "$(check_detect_node "$DETECT_SKILL")"
  fi
  n30=0; total30=0
  for needle in '**"TypeScript"**' '**"JavaScript"**' '`scripts.test`' \
                '`MKR_TEST` is empty' '`scripts.build`' '`MKR_BUILD` is empty' \
                '`scripts.lint`' '`MKR_LINT` is empty' 'tsc --noEmit' \
                '`MKR_TYPECHECK` is empty' '`MKR_COVERAGE`: empty'; do
    total30=$((total30+1))
    m="$(mutate_missing "$DETECT_SKILL" "$needle")"
    out="$(check_detect_node "$m" || true)"
    [[ "$out" == MISSING:* ]] && n30=$((n30+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n30" -eq "$total30" ]; then
    ok "TC-M6-30b each of eleven claims independently detected when removed ($n30/$total30)"
  else
    bad "TC-M6-30b each of eleven claims independently detected when removed" "$n30/$total30"
  fi
else
  bad "TC-M6-30 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect Python detection (TC-M6-31) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_python "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-31a all eight Python claims present"
  else
    bad "TC-M6-31a all eight Python claims present" "$(check_detect_python "$DETECT_SKILL")"
  fi
  n31=0; total31=0
  for needle in '**"Python (poetry)"**' '**"Python (pip)"**' '`pytest`' \
                '`MKR_TEST` is empty' '`MKR_BUILD`: empty' '`MKR_LINT`: empty' \
                '`MKR_TYPECHECK`: empty' '`MKR_COVERAGE`: empty'; do
    total31=$((total31+1))
    m="$(mutate_missing "$DETECT_SKILL" "$needle")"
    out="$(check_detect_python "$m" || true)"
    [[ "$out" == MISSING:* ]] && n31=$((n31+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n31" -eq "$total31" ]; then
    ok "TC-M6-31b each of eight claims independently detected when removed ($n31/$total31)"
  else
    bad "TC-M6-31b each of eight claims independently detected when removed" "$n31/$total31"
  fi
else
  bad "TC-M6-31 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect Go detection (TC-M6-32) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_go "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-32a all five Go claims present"
  else
    bad "TC-M6-32a all five Go claims present" "$(check_detect_go "$DETECT_SKILL")"
  fi
  n32=0; total32=0
  for needle in 'go test ./...' 'go build ./...' 'already type-checks' \
                '`MKR_LINT`: empty' '`MKR_COVERAGE`: empty'; do
    total32=$((total32+1))
    m="$(mutate_missing "$DETECT_SKILL" "$needle")"
    out="$(check_detect_go "$m" || true)"
    [[ "$out" == MISSING:* ]] && n32=$((n32+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n32" -eq "$total32" ]; then
    ok "TC-M6-32b each of five claims independently detected when removed ($n32/$total32)"
  else
    bad "TC-M6-32b each of five claims independently detected when removed" "$n32/$total32"
  fi
else
  bad "TC-M6-32 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect Rails detection (TC-M6-33) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_rails "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-33a all nine Rails claims present"
  else
    bad "TC-M6-33a all nine Rails claims present" "$(check_detect_rails "$DETECT_SKILL")"
  fi
  n33=0; total33=0
  for needle in '(`config/application.rb` **or** `bin/rails`)' \
                '**"Ruby on Rails (RSpec)"**' 'Otherwise → Stack' \
                'bundle exec rspec' 'bin/rails test' \
                '`MKR_BUILD`: empty' '`MKR_LINT`: empty' \
                '`MKR_TYPECHECK`: empty' '`MKR_COVERAGE`: empty'; do
    total33=$((total33+1))
    m="$(mutate_missing "$DETECT_SKILL" "$needle")"
    out="$(check_detect_rails "$m" || true)"
    [[ "$out" == MISSING:* ]] && n33=$((n33+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n33" -eq "$total33" ]; then
    ok "TC-M6-33b each of nine claims independently detected when removed ($n33/$total33)"
  else
    bad "TC-M6-33b each of nine claims independently detected when removed" "$n33/$total33"
  fi
else
  bad "TC-M6-33 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect no-match case (TC-M6-34) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_no_match "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-34a no-match language present"
  else
    bad "TC-M6-34a no-match language present" "$(check_detect_no_match "$DETECT_SKILL")"
  fi
  m="$(mutate_missing "$DETECT_SKILL" 'no recognized ecosystem detected')"
  out="$(check_detect_no_match "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-34b no-match language removed → detected"
  else
    bad "TC-M6-34b no-match language removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-34 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect multi-match case (TC-M6-35) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_multi_match "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-35a multi-match language present"
  else
    bad "TC-M6-35a multi-match language present" "$(check_detect_multi_match "$DETECT_SKILL")"
  fi
  m="$(mutate_missing "$DETECT_SKILL" 'More than one match is expected and reported, not resolved')"
  out="$(check_detect_multi_match "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-35b multi-match language removed → detected"
  else
    bad "TC-M6-35b multi-match language removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-35 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: mkr-detect tool scope / never writes (TC-M6-36) =="

if [ -e "$DETECT_SKILL" ]; then
  if check_detect_tool_scope "$DETECT_SKILL" >/dev/null; then
    ok "TC-M6-36a tool scope Read/Grep/Glob only, never writes"
  else
    bad "TC-M6-36a tool scope Read/Grep/Glob only, never writes" "$(check_detect_tool_scope "$DETECT_SKILL")"
  fi
  M6_MUT_WRITE="$(mktemp)"
  sed 's/Read`, `Grep`, `Glob` only\. Never `Write`\/`Edit`/Read`, `Grep`, `Glob`, `Write` only/' \
    "$DETECT_SKILL" > "$M6_MUT_WRITE"
  out="$(check_detect_tool_scope "$M6_MUT_WRITE" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-36b Write grant added → detected"
  else
    bad "TC-M6-36b Write grant added → detected" "$out"
  fi
  rm -f "$M6_MUT_WRITE"
  m="$(mutate_missing "$DETECT_SKILL" 'never writes any file')"
  out="$(check_detect_tool_scope "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-36c never-writes sentence removed (tool-scope line untouched) → detected"
  else
    bad "TC-M6-36c never-writes sentence removed (tool-scope line untouched) → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-36 mkr-detect/SKILL.md exists" "not found yet"
fi

echo
echo "== M6: /mkr-init step 4 invokes mkr-detect (TC-M6-37) =="

if [ -e "$INIT_CMD" ]; then
  if check_init_step4_invokes_detect "$INIT_CMD" >/dev/null; then
    ok "TC-M6-37a mkr-detect invocation + confirm-dont-assume both present"
  else
    bad "TC-M6-37a mkr-detect invocation + confirm-dont-assume both present" \
        "$(check_init_step4_invokes_detect "$INIT_CMD")"
  fi
  m="$(mutate_missing "$INIT_CMD" 'Invoke `mkr-detect`')"
  out="$(check_init_step4_invokes_detect "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-37b mkr-detect invocation removed (confirm sentence intact) → detected"
  else
    bad "TC-M6-37b mkr-detect invocation removed (confirm sentence intact) → detected" "$out"
  fi
  rm -f "$m"
  m="$(mutate_missing "$INIT_CMD" "don't assume them")"
  out="$(check_init_step4_invokes_detect "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-37c confirm-dont-assume removed (invocation intact) → detected"
  else
    bad "TC-M6-37c confirm-dont-assume removed (invocation intact) → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-37 mkr-init.md exists" "not found"
fi

echo
echo "== M6: /mkr-init step 4 zero-match reaches the human (TC-M6-40) =="

if [ -e "$INIT_CMD" ]; then
  if check_init_step4_zero_match "$INIT_CMD" >/dev/null; then
    ok "TC-M6-40a zero-match language present"
  else
    bad "TC-M6-40a zero-match language present" "$(check_init_step4_zero_match "$INIT_CMD")"
  fi
  m="$(mutate_missing "$INIT_CMD" 'zero blocks')"
  out="$(check_init_step4_zero_match "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-40b zero-match language removed → detected"
  else
    bad "TC-M6-40b zero-match language removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-40 mkr-init.md exists" "not found"
fi

echo
echo "== M6: /mkr-init step 5 unchanged (TC-M6-39) =="

if [ -e "$INIT_CMD" ]; then
  if check_init_step5_unchanged "$INIT_CMD" >/dev/null; then
    ok "TC-M6-39a step 5 file-naming + never-write-partial-output both present"
  else
    bad "TC-M6-39a step 5 file-naming + never-write-partial-output both present" \
        "$(check_init_step5_unchanged "$INIT_CMD")"
  fi
  m="$(mutate_missing "$INIT_CMD" '`<root>/CLAUDE.md` from `seed/CLAUDE.md`')"
  m2="$(mutate_missing "$m" '`<root>/.mkr/config` from `seed/config`')"
  out="$(check_init_step5_unchanged "$m2" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-39b step 5 file-naming bullets removed → detected"
  else
    bad "TC-M6-39b step 5 file-naming bullets removed → detected" "$out"
  fi
  rm -f "$m" "$m2"
  m="$(mutate_missing "$INIT_CMD" 'never write partial output')"
  out="$(check_init_step5_unchanged "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-39c never-write-partial-output sentence removed → detected"
  else
    bad "TC-M6-39c never-write-partial-output sentence removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-39 mkr-init.md exists" "not found"
fi

echo
echo "== M6: README Gates table matches DESIGN.md §4 (TC-M6-44) =="

README="$ROOT/README.md"
DESIGN="$ROOT/docs/DESIGN.md"
if [ -e "$README" ]; then
  if check_gates_table_matches "$README" "$DESIGN" >/dev/null; then
    ok "TC-M6-44a README ## Gates table matches DESIGN.md §4 cell-by-cell"
  else
    bad "TC-M6-44a README ## Gates table matches DESIGN.md §4 cell-by-cell" \
        "$(check_gates_table_matches "$README" "$DESIGN")"
  fi
  M6_MUT_TIER="$(mktemp)"
  awk 'BEGIN{FS=OFS="|"} /^\| G4 review gate \|/ { $4=" BLOCK " } { print }' \
    "$README" > "$M6_MUT_TIER"
  out="$(check_gates_table_matches "$M6_MUT_TIER" "$DESIGN" || true)"
  if [[ "$out" == MISMATCH:*"G4 review gate"* ]]; then
    ok "TC-M6-44b G4's tier cell mutated → FAIL, naming the mismatch"
  else
    bad "TC-M6-44b G4's tier cell mutated → FAIL, naming the mismatch" "$out"
  fi
  rm -f "$M6_MUT_TIER"
else
  bad "TC-M6-44 README.md exists" "not found"
fi

# ----------------------------------------- M6_GoPublic (TC-M6-47..55)

LICENSE_FILE="$ROOT/LICENSE"
CLAUDE_MD_FILE="$ROOT/CLAUDE.md"
MKR_CONFIG_FILE="$ROOT/.mkr/config"
GITIGNORE_FILE="$ROOT/.gitignore"

echo
echo "== M6_GoPublic: CLAUDE.md redacted (TC-M6-48) =="

if [ -e "$CLAUDE_MD_FILE" ]; then
  if check_claude_md_redacted "$CLAUDE_MD_FILE" >/dev/null; then
    ok "TC-M6-48a CLAUDE.md prose + all six gate-owner rows name kikrgbh"
  else
    bad "TC-M6-48a CLAUDE.md prose + all six gate-owner rows name kikrgbh" \
        "$(check_claude_md_redacted "$CLAUDE_MD_FILE")"
  fi
  m="$(mktemp)"
  sed 's/| pre-merge | kikrgbh |/| pre-merge | Alex |/' "$CLAUDE_MD_FILE" > "$m"
  out="$(check_claude_md_redacted "$m" || true)"
  if [[ "$out" == MISSING:pre-merge* ]]; then
    ok "TC-M6-48b pre-merge row reverted to a different name → FAIL, naming the row"
  else
    bad "TC-M6-48b pre-merge row reverted to a different name → FAIL, naming the row" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-48 CLAUDE.md exists" "not found"
fi

echo
echo "== M6_GoPublic: .mkr/config redacted (TC-M6-49) =="

if [ -e "$MKR_CONFIG_FILE" ]; then
  if check_mkr_config_redacted "$MKR_CONFIG_FILE" >/dev/null; then
    ok "TC-M6-49a .mkr/config all five MKR_GATE_* name kikrgbh"
  else
    bad "TC-M6-49a .mkr/config all five MKR_GATE_* name kikrgbh" \
        "$(check_mkr_config_redacted "$MKR_CONFIG_FILE")"
  fi
  m="$(mktemp)"
  sed 's/MKR_GATE_MERGE="kikrgbh"/MKR_GATE_MERGE="Alex"/' "$MKR_CONFIG_FILE" > "$m"
  out="$(check_mkr_config_redacted "$m" || true)"
  if [[ "$out" == MISSING:gate-merge* ]]; then
    ok "TC-M6-49b MKR_GATE_MERGE reverted to a different value → FAIL, naming the variable"
  else
    bad "TC-M6-49b MKR_GATE_MERGE reverted to a different value → FAIL, naming the variable" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-49 .mkr/config exists" "not found"
fi

echo
echo "== M6_GoPublic: .gitignore excludes .mkr/audit.jsonl (TC-M6-50) =="

if [ -e "$GITIGNORE_FILE" ]; then
  if check_gitignore_has_audit_entry "$GITIGNORE_FILE" >/dev/null; then
    ok "TC-M6-50a .gitignore contains .mkr/audit.jsonl"
  else
    bad "TC-M6-50a .gitignore contains .mkr/audit.jsonl" "$(check_gitignore_has_audit_entry "$GITIGNORE_FILE")"
  fi
  m="$(mutate_missing "$GITIGNORE_FILE" '.mkr/audit.jsonl')"
  out="$(check_gitignore_has_audit_entry "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-M6-50b .mkr/audit.jsonl line removed → FAIL, naming its absence"
  else
    bad "TC-M6-50b .mkr/audit.jsonl line removed → FAIL, naming its absence" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-50 .gitignore exists" "not found"
fi

echo
echo "== M6_GoPublic: real-repo check — .mkr/audit.jsonl untracked (TC-M6-53) =="

out="$(cd "$ROOT" && git ls-files -- .mkr/audit.jsonl)"
if [ -z "$out" ]; then
  ok "TC-M6-53 .mkr/audit.jsonl is untracked"
else
  bad "TC-M6-53 .mkr/audit.jsonl is untracked" "still tracked: $out"
fi

echo
echo "== M6_GoPublic: mkr-merge SKILL.md third branch + --admin (TC-M6-54) =="

if [ -e "$MERGE_SKILL" ]; then
  if check_mkr_merge_third_branch "$MERGE_SKILL" >/dev/null; then
    ok "TC-M6-54a step 3 names the new third branch, step 6 names --admin"
  else
    bad "TC-M6-54a step 3 names the new third branch, step 6 names --admin" \
        "$(check_mkr_merge_third_branch "$MERGE_SKILL")"
  fi
  m="$(mutate_missing "$MERGE_SKILL" 'annotation')"
  out="$(check_mkr_merge_third_branch "$m" || true)"
  if [[ "$out" == MISSING:third-branch* ]]; then
    ok "TC-M6-54b step 3's new branch removed → FAIL, naming the missing branch"
  else
    bad "TC-M6-54b step 3's new branch removed → FAIL, naming the missing branch" "$out"
  fi
  rm -f "$m"
  m="$(mutate_missing "$MERGE_SKILL" '--admin')"
  out="$(check_mkr_merge_third_branch "$m" || true)"
  if [[ "$out" == MISSING:admin-flag* ]]; then
    ok "TC-M6-54c step 6's --admin sentence removed → FAIL, naming its absence"
  else
    bad "TC-M6-54c step 6's --admin sentence removed → FAIL, naming its absence" "$out"
  fi
  rm -f "$m"
  m="$(mutate_missing "$MERGE_SKILL" 'steps` array')"
  out="$(check_mkr_merge_third_branch "$m" || true)"
  if [[ "$out" == MISSING:third-branch-empty-steps* ]]; then
    ok "TC-M6-54d step 3's empty-steps forge-guard removed → FAIL, naming its absence"
  else
    bad "TC-M6-54d step 3's empty-steps forge-guard removed → FAIL, naming its absence" "$out"
  fi
  rm -f "$m"
else
  bad "TC-M6-54 mkr-merge/SKILL.md exists" "not found"
fi

# ------------------------------------------------------- RKP (mkr-rkp skill, TC-RKP-*)

RKP_SKILL="$ROOT/.claude/skills/mkr-rkp/SKILL.md"
RKP_CMD="$ROOT/.claude/commands/mkr-rkp.md"

echo
echo "== RKP: mkr-rkp.md command frontmatter =="

if [ -e "$RKP_CMD" ]; then
  if out="$(check_frontmatter "$RKP_CMD" 0)"; then
    ok "TC-RKP mkr-rkp.md command frontmatter"
  else
    bad "TC-RKP mkr-rkp.md command frontmatter" "$out"
  fi
else
  bad "TC-RKP mkr-rkp.md command exists" "not found yet"
fi

echo
echo "== RKP: docs/rkp/ fixed location, not a config variable (TC-RKP-01) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_fixed_location "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-01a fixed docs/rkp/ location stated"
  else
    bad "TC-RKP-01a fixed docs/rkp/ location stated" "$(check_rkp_fixed_location "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" 'not read from any `MKR_*`/`config.sh` variable')"
  out="$(check_rkp_fixed_location "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-01b fixed-location sentence removed → detected"
  else
    bad "TC-RKP-01b fixed-location sentence removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-01 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: all nine doc topics named (TC-RKP-02) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_topics "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-02a all nine topics named"
  else
    bad "TC-RKP-02a all nine topics named" "$(check_rkp_topics "$RKP_SKILL")"
  fi
  n=0; total=0
  for needle in '`01-architecture.md`' '`02-data-model.md`' '`03-process-and-conventions.md`' \
                '`04-user-journeys.md`' '`05-system-journeys.md`' '`06-rbac-capability-matrix.md`' \
                '`07-glossary.md`' '`08-current-state-and-gaps.md`' '`09-dev-environment-runbook.md`'; do
    total=$((total+1))
    m="$(mutate_missing "$RKP_SKILL" "$needle")"
    out="$(check_rkp_topics "$m" || true)"
    [[ "$out" == MISSING:* ]] && n=$((n+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n" -eq "$total" ]; then
    ok "TC-RKP-02b each of nine topics independently detected when removed ($n/$total)"
  else
    bad "TC-RKP-02b each of nine topics independently detected when removed" "$n/$total"
  fi
else
  bad "TC-RKP-02 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: real-file-citation requirement (TC-RKP-03) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_citation "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-03a citation requirement stated"
  else
    bad "TC-RKP-03a citation requirement stated" "$(check_rkp_citation "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" 'Real file/line citations for every claim, not paraphrases.')"
  out="$(check_rkp_citation "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-03b citation sentence removed → detected"
  else
    bad "TC-RKP-03b citation sentence removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-03 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: four scope modes + bootstrap README clause (TC-RKP-04) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_scope_modes "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-04a all four scope-mode triggers + bootstrap README clause present"
  else
    bad "TC-RKP-04a all four scope-mode triggers + bootstrap README clause present" \
        "$(check_rkp_scope_modes "$RKP_SKILL")"
  fi
  n=0; total=0
  for needle in "someone wants a KT package built and there's nothing to refresh" \
                'plus `README.md`, all created fresh' \
                "Trigger: one doc is flagged stale, or you're about to cite a specific" \
                'before handing the package to a new developer' \
                'exists but is missing specific docs that the topic'; do
    total=$((total+1))
    m="$(mutate_missing "$RKP_SKILL" "$needle")"
    out="$(check_rkp_scope_modes "$m" || true)"
    [[ "$out" == MISSING:* ]] && n=$((n+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n" -eq "$total" ]; then
    ok "TC-RKP-04b each of five claims independently detected when removed ($n/$total)"
  else
    bad "TC-RKP-04b each of five claims independently detected when removed" "$n/$total"
  fi
else
  bad "TC-RKP-04 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: edit-in-place + full-refresh checks every present doc (TC-RKP-04b) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_refresh_discipline "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-04ba both refresh-discipline rules present"
  else
    bad "TC-RKP-04ba both refresh-discipline rules present" "$(check_rkp_refresh_discipline "$RKP_SKILL")"
  fi
  n=0; total=0
  for needle in 'Edit in place, preserve structure.** Update only what actually drifted' \
                'present has been checked (touched or confirmed clean)'; do
    total=$((total+1))
    m="$(mutate_missing "$RKP_SKILL" "$needle")"
    out="$(check_rkp_refresh_discipline "$m" || true)"
    [[ "$out" == MISSING:* ]] && n=$((n+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n" -eq "$total" ]; then
    ok "TC-RKP-04bb both rules independently detected when removed ($n/$total)"
  else
    bad "TC-RKP-04bb both rules independently detected when removed" "$n/$total"
  fi
else
  bad "TC-RKP-04b mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: no memory shortcut (TC-RKP-05) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_no_memory_shortcut "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-05a no-memory-shortcut rule stated"
  else
    bad "TC-RKP-05a no-memory-shortcut rule stated" "$(check_rkp_no_memory_shortcut "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" "If you built or last refreshed a doc in this same session, don't rely")"
  out="$(check_rkp_no_memory_shortcut "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-05b rule removed → detected"
  else
    bad "TC-RKP-05b rule removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-05 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: full-package refresh updates README's Last-grounded date (TC-RKP-06) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_readme_date "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-06a README-date-update rule stated"
  else
    bad "TC-RKP-06a README-date-update rule stated" "$(check_rkp_readme_date "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" 'runs update `README.md`'"'"'s')"
  out="$(check_rkp_readme_date "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-06b rule removed → detected"
  else
    bad "TC-RKP-06b rule removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-06 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: partial bootstrap treatment (TC-RKP-07) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_partial_bootstrap_treatment "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-07a partial-bootstrap treatment rule stated"
  else
    bad "TC-RKP-07a partial-bootstrap treatment rule stated" \
        "$(check_rkp_partial_bootstrap_treatment "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" 'as a bootstrap scoped to just those, and the existing ones as a normal refresh')"
  out="$(check_rkp_partial_bootstrap_treatment "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-07b rule removed → detected"
  else
    bad "TC-RKP-07b rule removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-07 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: absent signal is never a defect to work around (TC-RKP-08) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_absence_not_defect "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-08a absence-not-defect rule stated"
  else
    bad "TC-RKP-08a absence-not-defect rule stated" "$(check_rkp_absence_not_defect "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" "A topic's absence is not a defect to work around")"
  out="$(check_rkp_absence_not_defect "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-08b rule removed → detected"
  else
    bad "TC-RKP-08b rule removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-08 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: output shape, four states + not-a-new-file + uniform trigger (TC-RKP-09) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_output "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-09a output shape complete"
  else
    bad "TC-RKP-09a output shape complete" "$(check_rkp_output "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" '**no longer applicable**')"
  out="$(check_rkp_output "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-09b one state (no-longer-applicable) removed → detected"
  else
    bad "TC-RKP-09b one state (no-longer-applicable) removed → detected" "$out"
  fi
  rm -f "$m"
  m="$(mutate_missing "$RKP_SKILL" 'not a new file')"
  out="$(check_rkp_output "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-09c not-a-new-file sentence removed → detected"
  else
    bad "TC-RKP-09c not-a-new-file sentence removed → detected" "$out"
  fi
  rm -f "$m"
  m="$(mutate_missing "$RKP_SKILL" "single-doc refresh, full-package refresh, or partial bootstrap's present-doc handling")"
  out="$(check_rkp_output "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-09d uniform-trigger scope narrowed → detected"
  else
    bad "TC-RKP-09d uniform-trigger scope narrowed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-09 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: tool scope Read/Grep/Glob/Write/Edit, never Bash, never writes outside docs/rkp/ (TC-RKP-10) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_tool_scope "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-10a tool scope correct, never writes outside docs/rkp/"
  else
    bad "TC-RKP-10a tool scope correct, never writes outside docs/rkp/" "$(check_rkp_tool_scope "$RKP_SKILL")"
  fi
  RKP_MUT_BASH="$(mktemp)"
  sed 's/`Read`, `Grep`, `Glob`, `Write`, `Edit`\. Never `Bash`\./`Read`, `Grep`, `Glob`, `Write`, `Edit`, `Bash`./' \
    "$RKP_SKILL" > "$RKP_MUT_BASH"
  out="$(check_rkp_tool_scope "$RKP_MUT_BASH" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-10b Bash grant added → detected"
  else
    bad "TC-RKP-10b Bash grant added → detected" "$out"
  fi
  rm -f "$RKP_MUT_BASH"
  RKP_MUT_NOEDIT="$(mktemp)"
  sed 's/`Write`, `Edit`\. Never `Bash`\./`Write`. Never `Bash`./' \
    "$RKP_SKILL" > "$RKP_MUT_NOEDIT"
  out="$(check_rkp_tool_scope "$RKP_MUT_NOEDIT" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-10c Edit dropped → detected"
  else
    bad "TC-RKP-10c Edit dropped → detected" "$out"
  fi
  rm -f "$RKP_MUT_NOEDIT"
  m="$(mutate_missing "$RKP_SKILL" 'never writes outside `docs/rkp/`')"
  out="$(check_rkp_tool_scope "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-10d never-writes-outside sentence removed → detected"
  else
    bad "TC-RKP-10d never-writes-outside sentence removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-10 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: command names the re-derive-from-source invariant (TC-RKP-11) =="

if [ -e "$RKP_CMD" ]; then
  if check_rkp_command_invariant "$RKP_CMD" >/dev/null; then
    ok "TC-RKP-11a invariant stated"
  else
    bad "TC-RKP-11a invariant stated" "$(check_rkp_command_invariant "$RKP_CMD")"
  fi
  m="$(mutate_missing "$RKP_CMD" 'never from anything recalled earlier in the same session')"
  out="$(check_rkp_command_invariant "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-11b invariant removed → detected"
  else
    bad "TC-RKP-11b invariant removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-11 mkr-rkp.md command exists" "not found yet"
fi

echo
echo "== RKP: per-doc shape — header blockquote, Mermaid pitfall, See-also footer (TC-RKP-13) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_doc_shape "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-13a all three shape rules present"
  else
    bad "TC-RKP-13a all three shape rules present" "$(check_rkp_doc_shape "$RKP_SKILL")"
  fi
  n=0; total=0
  for needle in 'A header blockquote naming what the doc is grounded against and the grounding date' \
                'a bare `;` inside a sequence-diagram' \
                'See also" footer cross-linking sibling docs'; do
    total=$((total+1))
    m="$(mutate_missing "$RKP_SKILL" "$needle")"
    out="$(check_rkp_doc_shape "$m" || true)"
    [[ "$out" == MISSING:* ]] && n=$((n+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n" -eq "$total" ]; then
    ok "TC-RKP-13b each of three shape rules independently detected when removed ($n/$total)"
  else
    bad "TC-RKP-13b each of three shape rules independently detected when removed" "$n/$total"
  fi
else
  bad "TC-RKP-13 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: propose an adjusted topic list when the nine don't fit (TC-RKP-14) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_adjusted_topic_list "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-14a adjusted-topic-list rule stated"
  else
    bad "TC-RKP-14a adjusted-topic-list rule stated" "$(check_rkp_adjusted_topic_list "$RKP_SKILL")"
  fi
  m="$(mutate_missing "$RKP_SKILL" "If the nine-topic shape genuinely doesn't fit")"
  out="$(check_rkp_adjusted_topic_list "$m" || true)"
  if [[ "$out" == MISSING:* ]]; then
    ok "TC-RKP-14b rule removed → detected"
  else
    bad "TC-RKP-14b rule removed → detected" "$out"
  fi
  rm -f "$m"
else
  bad "TC-RKP-14 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: AD-5 self-exclusion + uniform present-doc signal recheck (TC-RKP-15) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_ad5 "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-15a all four AD-5 rules present"
  else
    bad "TC-RKP-15a all four AD-5 rules present" "$(check_rkp_ad5 "$RKP_SKILL")"
  fi
  n=0; total=0
  for needle in 'Signal scans exclude `docs/rkp/` itself.** Every signal check above scans the target repo'"'"'s' \
                'target repo, not only re-deriving the facts already written inside the doc' \
                'Present-conditional-doc signal recheck, applies uniformly to single-doc refresh, full-package' \
                "It never deletes the file itself — this skill's tool scope has no delete capability"; do
    total=$((total+1))
    m="$(mutate_missing "$RKP_SKILL" "$needle")"
    out="$(check_rkp_ad5 "$m" || true)"
    [[ "$out" == MISSING:* ]] && n=$((n+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n" -eq "$total" ]; then
    ok "TC-RKP-15b each of four AD-5 rules independently detected when removed ($n/$total)"
  else
    bad "TC-RKP-15b each of four AD-5 rules independently detected when removed" "$n/$total"
  fi
else
  bad "TC-RKP-15 mkr-rkp/SKILL.md exists" "not found yet"
fi

echo
echo "== RKP: scope-hint validity — exemption, mismatch, both signal-absent branches (TC-RKP-16) =="

if [ -e "$RKP_SKILL" ]; then
  if check_rkp_scope_hint_validity "$RKP_SKILL" >/dev/null; then
    ok "TC-RKP-16a all four scope-hint-validity rules present"
  else
    bad "TC-RKP-16a all four scope-hint-validity rules present" "$(check_rkp_scope_hint_validity "$RKP_SKILL")"
  fi
  n=0; total=0
  for needle in "it never applies when you're asked for the full package or given no scope at" \
                'report the mismatch plainly and do nothing — never guess which topic was meant' \
                "the doc doesn't exist yet, don't create it — report the signal is absent" \
                'separate rule — report it "no longer applicable" and leave the file in place'; do
    total=$((total+1))
    m="$(mutate_missing "$RKP_SKILL" "$needle")"
    out="$(check_rkp_scope_hint_validity "$m" || true)"
    [[ "$out" == MISSING:* ]] && n=$((n+1)) || echo "     missed: $needle -> $out"
    rm -f "$m"
  done
  if [ "$n" -eq "$total" ]; then
    ok "TC-RKP-16b each of four rules independently detected when removed ($n/$total)"
  else
    bad "TC-RKP-16b each of four rules independently detected when removed" "$n/$total"
  fi
else
  bad "TC-RKP-16 mkr-rkp/SKILL.md exists" "not found yet"
fi

# --------------------------------------------------------------------- done

echo
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
