# WorktreeGuard Spec

## 0. Triage

```
TRIAGE
depth:    deep
why:      touches a non-negotiable in CLAUDE.md (guardrail script behavior — worktree-edit-guard.sh
          and worktree-collision-guard.sh must never be weakened or reinterpreted without a spec),
          and it retroactively formalizes a contract (specs/WorktreeGuard_Spec.md) that two shipped
          hook scripts already cite as authoritative (§7.3, §7.4, §6 AD-1/AD-4) but that was never
          actually written or accepted — confirmed absent from git history entirely.
scope:    one change: write specs/WorktreeGuard_Spec.md documenting the ACTUAL current behavior of
          both guards (registration-based edit/commit blocking vs. live-process collision on
          checkout/switch), decide whether the adopter-visible confusion between the two warrants a
          behavior/message fix in worktree-edit-guard.sh, and land whichever fix the spec calls for.
reuse:    checked git log --all for specs/WorktreeGuard_Spec.md (zero hits, never existed) and read
          both guard scripts in full — the underlying blocking logic already exists and, per current
          code, already allows edits in a genuinely git-worktree-add-registered worktree; nothing to
          build from scratch, this is spec-and-clarity work over existing logic.
touches:  .claude/hooks/scripts/worktree-edit-guard.sh, .claude/hooks/scripts/worktree-collision-guard.sh,
          specs/WorktreeGuard_Spec.md (new), docs/adr/ (new)
risky:    none matched (MKR_RISKY_PATHS = .claude/hooks/lib/config.sh only; not touched)
gates:    spec: ✓  plan: ✓  design: ✓ (Deep, always)  review: ✓  ground: ✓ (mandatory)
          adr: ✓ (formalizes a security-boundary contract adopters rely on)  ship: ✗
done when: specs/WorktreeGuard_Spec.md is ACCEPTED and accurately documents both guards including
          the registration-vs-collision distinction; an adopter reading a deny message can tell
          which of the two conditions they hit without reading the source.
```

## 1. Header

| | |
|---|---|
| **Status** | DRAFT rev 2 |
| **Depth** | Deep |
| **Author** | agent |
| **Approver** | kikrgbh |

## 2. Intent

An adopter enabled `MKR_WORKTREE_POLICY=enforced`, hit a block, and reported it as a bug: they
described `worktree-edit-guard.sh` as blocking edits "whenever it detects a live process has that
directory open." Investigation (this session, against commit `a98a37a`) found the report conflates
two distinct hooks that ship together but answer different questions — `worktree-edit-guard.sh`
never checks for a live process at all; `worktree-collision-guard.sh` does, but only gates branch
switching, not edits or commits. Both scripts' own header comments cite `specs/WorktreeGuard_Spec.md
§7.3/§7.4/§6 AD-1/AD-4` as their contract of record. That file has never existed — confirmed via
`git log --all --oneline -- '*WorktreeGuard*'` returning nothing across the entire history. So there
is currently no accepted document an adopter, a reviewer, or a future maintainer can check the
shipped behavior against, and no way to tell — short of reading two bash scripts and a shared
library — which of two different failure conditions a given deny message describes.

This spec exists to give the guards the contract they already claim to have, make the distinction
between the two guards self-evident from the deny/warn text alone, and record the design decisions
(AD-1 through AD-5) that are currently only implicit in code comments, in an ADR.

## 3. Scope

**In scope:**
- Document the ground-truth behavior of `worktree-edit-guard.sh` and `worktree-collision-guard.sh`
  as they exist at commit `a98a37a`, including the shared `MKR_WORKTREE_POLICY` tiers (`off` /
  `advisory` / `enforced`) and the two guards' differing handling of the middle tier.
- Independently verify (at design review, G3) whether either guard's current deny/warn message text
  already lets an adopter distinguish "not a registered worktree" from "another process has this
  directory open" without reading source — my own read of both messages during investigation
  suggests they already do (see §6), but that read should not be self-certified; it needs an
  independent reviewer's confirmation or correction.
- If G3 review concludes the messages are NOT already self-explanatory, implement the smallest
  wording fix that makes them so, and add test coverage for the new text.
- File an ADR formalizing AD-1 through AD-5 (the design decisions currently stated only in the two
  scripts' own header/inline comments).

**Out of scope:**
- Redesigning either guard's actual blocking algorithm (worktree registration lookup, live-process
  collision detection). Both are already extensively covered — 62 `TC-WG-*` cases in
  `tests/hooks_test.sh` (`TC-WG-01` through `TC-WG-60`, no `TC-WG-14`, plus lettered sub-cases
  `15a`, `15b`, `28b`, `30b`) — and hardened through multiple prior G4 review rounds (TOCTOU fixes,
  command-substitution closes). Nothing found during this investigation suggests either algorithm is
  wrong.
- Adding an `advisory` tier to `worktree-edit-guard.sh` to match `worktree-collision-guard.sh`'s
  three-tier behavior. A real asymmetry was found (§6) and is documented here, but closing it is a
  behavior change beyond message clarity — deferred to a follow-up change, not decided unilaterally
  inside a spec whose stated job is to document current behavior.
- The permission allow-list / sibling-worktree-path issue the same adopter report raised. That is a
  Claude Code harness/settings concern this repo's own config doesn't touch at all, and is tracked as
  its own, separately-triaged change.

## 4. Affected users & journey change

**Before:** an adopter enabling `MKR_WORKTREE_POLICY=enforced` has no document to check their own
understanding against. A denied edit/commit and a denied checkout use different wording for
different reasons, but nothing states that they ARE different reasons, or which guard owns which.
Self-diagnosis requires reading `.claude/hooks/scripts/*.sh` and `.claude/hooks/lib/procwalk.sh`.

**After:** `specs/WorktreeGuard_Spec.md` exists as the accepted contract, is linked from both guard
scripts' own header comments (already true — the citation just now resolves to a real file), and
states plainly which guard fires on which condition. If G3 review finds the deny/warn text itself
still isn't self-explanatory, that text is fixed as part of this change so an adopter never needs to
open the spec file, let alone the source, to understand why a given command was blocked.

## 5. Reuse check

- `git log --all --oneline -- '*WorktreeGuard*'` — zero hits. Confirmed the spec never existed at
  any point in this repo's history, not just currently missing from the working tree.
- Read `.claude/hooks/scripts/worktree-edit-guard.sh` and `.claude/hooks/scripts/worktree-collision-guard.sh`
  in full, plus their shared library `.claude/hooks/lib/procwalk.sh` (`procwalk_is_registered_worktree`,
  `procwalk_foreign_cwd`, `procwalk_resolve_target_dir(s)`, `procwalk_checkout_pathspec_form`,
  `procwalk_statement_has_git_keyword`) — the registration and collision-detection logic already
  exists and needs no rebuilding; this is a documentation-and-possibly-message-wording task over
  existing, working logic, not new capability.
- Read `tests/hooks_test.sh`'s existing worktree-guard coverage in full — verified with
  `grep -oE 'TC-WG-[0-9]+[a-z]?' tests/hooks_test.sh | sort -u -V | wc -l` after an earlier draft of
  this section understated the count from a partial read: `TC-WG-01` through `TC-WG-60` (no
  `TC-WG-14`), plus lettered sub-cases `15a`, `15b`, `28b`, `30b` — 62 distinct cases spanning both
  guards, all three policy tiers, TOCTOU variants, nested paths, and the bootstrap-commit exemption.
  This is already exhaustive evidence of current behavior — this spec documents a contract already
  enforced by tests, it does not need to invent new test scaffolding from scratch.
- Checked `docs/adr/` (`0001` through `0011`) — none documents the worktree guard design decisions.
  Confirmed genuine gap, not overlooked existing coverage.
- Checked `.claude/settings.json` — confirms both hooks are already wired into `PreToolUse` for
  `Bash` (both guards) and `Write`/`Edit` (edit-guard only), consistent with what the source says
  each guard gates.
- Personally reproduced `worktree-collision-guard.sh`'s live-process block in this session: a plain
  `git checkout -b <name>` in the shared repo root was denied with `another live process has this
  worktree open (worktree-collision-guard.sh) ... pid 11904: -bash`; `git worktree add` from the
  same root succeeded immediately after. This is first-hand confirmation of AD-3 below, not just a
  read of the code.

## 6. Architecture & key decisions

Both guards are `PreToolUse` hooks, active only when `mkr_get MKR_WORKTREE_POLICY` (read fresh off
`.mkr/config` per invocation, no caching) resolves to a non-default value; the default (`off`, set in
`config.sh`) makes both fully inert.

**AD-1 — `MKR_WORKTREE_POLICY` has three conventional values, unvalidated.** `off` (default),
`advisory`, `enforced`. `config.sh` performs no validation of the string — any other value is treated
by each guard as "not enforced," which for `worktree-edit-guard.sh` means fully inert (see AD-2) and
for `worktree-collision-guard.sh` means advisory (see AD-3). There is no rejection or warning for an
unrecognized value (e.g. a typo).

**AD-2 — `worktree-edit-guard.sh` gates `Write`/`Edit`/a bare `git commit`, and asks exactly one
question:** does the target resolve (walking up to the nearest existing ancestor directory, then to
that directory's own git worktree top-level) to a path `git worktree list --porcelain` at the
project root recognizes as a genuine **linked** worktree — never the root's own main checkout? This
guard has exactly two effective states: `enforced` (checked) and everything else (**not checked, and
no warning is ever emitted** — this is a real asymmetry with AD-3, discussed below). A `git commit`
is checked once per real, non-excluded occurrence in a compound Bash command (not just the last),
via an allowlist (`is_single_bare_git_commit`) narrow enough to reject every TOCTOU shape found
across four prior G4 review rounds (chained commits, backgrounded commands, process substitution,
`GIT_EDITOR`/`-e` smuggling) rather than a blocklist that would need to name each one.

**AD-3 — `worktree-collision-guard.sh` gates `git checkout`/`git switch` (branch-switching only —
a file-path `git checkout -- <path>` form is never gated, at any tier; `switch` has no such
pathspec-restore mode at all, so it is never excluded), and asks a different question:** does a live
process **outside this session's own process tree** currently have the target directory as its
`cwd`, checked by a single pass over `/proc` (`procwalk_foreign_cwd`)? This guard has three
effective states: `off` (inert), `advisory` (warns to stderr, names the colliding pid, never blocks
— `TC-WG-02`), `enforced` (denies, names the colliding pid — `TC-WG-03`, and reproduced live in this
session against a genuine collision).

**AD-4 — registration is checked against `git worktree list`'s own authoritative registry, never a
git-dir string shape.** `procwalk_is_registered_worktree` deliberately does not trust `git -C <dir>
rev-parse --absolute-git-dir`'s own returned string — a bare or even anchored `*/worktrees/*`
substring test is spoofable in one command (`git init --separate-git-dir=<anywhere>/.git/worktrees/<name>
<dir>`, which fabricates a matching git-dir string for a completely unrelated, non-linked repo). An
empty/unresolvable git-dir always allows, checked before the registration test — "not a repo at all"
and "a repo, but not this project's registered worktree" are kept as two independently testable
failure modes rather than collapsed into one.

**AD-5 — the bootstrap-policy-commit exemption.** The single commit that first sets
`MKR_WORKTREE_POLICY=enforced` is itself exempted from `worktree-edit-guard.sh` in the shared
checkout, because by the time that commit's `git commit` invocation runs, the guard already reads
`enforced` straight off the just-staged/just-written file — with no worktree yet to have made the
commit from otherwise. `is_bootstrap_policy_commit` scopes the exemption narrowly: only the project's
own top-level checkout, only a staged diff touching exactly `.mkr/config` and nothing else, only a
one-line change landing on `MKR_WORKTREE_POLICY=enforced`, and only when `is_single_bare_git_commit`
has already proven nothing else in the same Bash tool call can run between the check and the commit
itself (`TC-WG-46` through `TC-WG-54` cover the exemption and every TOCTOU variant found against it).

**Discovered gap (documented here, deliberately not fixed in this change — see §3 Out of scope):**
because `MKR_WORKTREE_POLICY` is a single, shared config value, an adopter setting it to `advisory`
to dry-run the policy before enforcing it gets a warning on branch-switch collisions (AD-3) but
**zero signal at all** on an edit/commit made outside a registered worktree (AD-2 — `advisory` and
`off` are indistinguishable to this guard). There is no gradual on-ramp on the edit-guard side, only
an on/off switch. This may be part of why the reporting adopter went straight to a hard, unexplained
block: an `advisory` trial run would not have surfaced anything on the edit-guard side to prepare
them for what `enforced` would later do. Recommended as a follow-up change (give
`worktree-edit-guard.sh` a genuine `advisory` warn-only state, mirroring AD-3), not decided here.

**Message-wording question (resolved at design review, not pre-decided here):** read cold, both
current deny/warn strings already name their own guard script by filename and state a specific,
different condition —
`worktree-edit-guard.sh`: `"<action> directly in the shared checkout is not allowed under
MKR_WORKTREE_POLICY=enforced (worktree-edit-guard.sh) — create a worktree first: git worktree add
../<name> <branch>, then <action> there."`
`worktree-collision-guard.sh`: `"another live process has this worktree open
(worktree-collision-guard.sh), switching branches here can pull it out from under that session:
<pid list>"`.
Neither mentions the other guard's condition, and each is arguably already self-explanatory once
read in full — but this session drafted the code that produces both, and a self-assessment of "is my
own error message clear" is exactly the judgment G3's independent reviewers exist to check, not
something to certify unilaterally. §10 AC2 makes this an explicit, externally-verified acceptance
criterion rather than an assumption carried into implementation.

## 7. Interfaces / contracts

Both guards' own header comments cite specific subsection numbers here as their contract of
record — `worktree-collision-guard.sh` cites `§7.3`, `worktree-edit-guard.sh` cites `§7.4` — so
this section is numbered to match rather than left as one undivided block; accepting this spec is
what makes those two citations resolve to something real.

### 7.1 Shared hook I/O contract

Both guards are `PreToolUse` hooks wired in `.claude/settings.json`, invoked with a JSON payload on
stdin and reading via `hookio_stdin`/`hookio_field` (`.claude/hooks/lib/hookio.sh`):

| field | used by | meaning |
|---|---|---|
| `tool_name` | both | `Write`, `Edit`, or `Bash` |
| `tool_input.file_path` | edit-guard | target of a `Write`/`Edit` |
| `tool_input.command` | both | the raw Bash command string |
| `cwd` | both (via `procwalk_resolve_target_dir(s)`) | fallback target directory when no `-C`/`cd` is resolvable from the command itself |

Output is via `hookio_pretooluse_decision allow\|deny\|ask [reason]`
(`.claude/hooks/lib/hookio.sh`), which emits the Claude Code hook JSON shape
(`"permissionDecision":"deny"`, etc.) on stdout; an `advisory`-tier warning from
`worktree-collision-guard.sh` is instead a plain line to **stderr**, no JSON, never blocking.

### 7.2 Shared environment contract

`MKR_WORKTREE_POLICY` via `.claude/hooks/lib/config.sh`'s `mkr_get` (git-root-relative
`.mkr/config`, no caller sourcing per AD-2 of `CLAUDE.md`'s own non-negotiables); `PROCWALK_PROC_ROOT`
(test-only override of `/proc`, collision-guard/`procwalk.sh` only); `CLAUDE_PROJECT_DIR` as the
final directory fallback when neither `cwd` nor any in-command `-C`/`cd` resolves.

### 7.3 `worktree-collision-guard.sh`'s own contract

Gates: a real, non-file-path `git checkout`/`git switch` statement only (§6 AD-3). Question asked:
does a live process outside this session's own process tree currently hold the resolved target
directory as its `cwd` (`procwalk_foreign_cwd`)? Decision: `off` → inert, no output; `advisory` →
stderr warning naming every colliding pid, `hookio_pretooluse_decision` never invoked; `enforced` →
`hookio_pretooluse_decision deny` naming every colliding pid. Target directory resolution: explicit
`git -C <dir>` on the matched statement, else the most recent preceding `cd <dir>` in the same
command (subject to the safe/unsafe statement-boundary tracking `procwalk_split_tagged` performs),
else the payload's own `cwd` field, else `${CLAUDE_PROJECT_DIR:-$PWD}`.

### 7.4 `worktree-edit-guard.sh`'s own contract

Gates: `Write`, `Edit`, and every real, non-excluded `git commit` occurrence in a `Bash` command
(§6 AD-2). Question asked: does the target resolve, walking up to the nearest existing ancestor
directory and then to that directory's git-worktree top-level, to a path `git worktree list
--porcelain` at the project root recognizes as a genuine linked worktree — never the root's own main
checkout? Decision: `enforced` → checked, `hookio_pretooluse_decision deny` naming the action and
the fix (`git worktree add ../<name> <branch>`) on failure; any other policy value → fully inert,
**no warning at any tier** (the AD-2/AD-3 asymmetry documented in §6). One exemption:
`is_bootstrap_policy_commit` (§6 AD-5) allows the single commit that first turns
`MKR_WORKTREE_POLICY=enforced` on to land directly in the shared checkout.

Neither guard's contract changes in this spec unless §10 AC2's independent review concludes the
message text needs it — and if so, only the string content in §7.3/§7.4 above, never the JSON/stderr
shape in §7.1.

## 8. Data model

No data model change. Both guards are stateless per-invocation checks against `.mkr/config` and
`/proc`; neither reads nor writes any other persisted state.

## 9. Test-case register

| ID | Covers | Status |
|---|---|---|
| `TC-WG-01`..`TC-WG-60` + `15a`/`15b`/`28b`/`30b` (existing, `tests/hooks_test.sh`, 62 cases, no `TC-WG-14`) | Both guards' full behavior across all three policy tiers, TOCTOU variants, nested paths, bootstrap exemption | Already passing — reused as acceptance evidence (AC5), not modified unless AC2 requires a message-text assertion update |
| `TC-WGSPEC-01` | `specs/WorktreeGuard_Spec.md` exists, `Status` field reads `ACCEPTED` | New |
| `TC-WGSPEC-02` | Every AD-1..AD-5 claim in §6 is checked against current source at design review (G3) and grounding audit (phase 9) — not just asserted | New (process, not a bash test) |
| `TC-WGSPEC-03` | The discovered advisory-tier asymmetry (§6) is documented in this spec AND in the filed ADR, not left undocumented in either | New (process) |
| `TC-WGSPEC-04` | docs/adr/00NN documents AD-1 through AD-5 and is linked from this spec's §6 | New |
| `TC-WGSPEC-05` (conditional) | If G3 review concludes a deny/warn message needs a wording fix (§6, §10 AC2): the updated string names the specific failure condition, and a corresponding case is added to `tests/hooks_test.sh` asserting the new text | New, conditional on design outcome |
| `TC-WGSPEC-06` | AC2 itself: `mkr-design-reviewer` and `mkr-architecture-reviewer`, each reading only the current `§7.3`/`§7.4` deny/warn text (no other context), independently state in their G3 verdict which of the two conditions each message describes; a recorded mismatch or "cannot tell" from either reviewer fails this case and triggers the `TC-WGSPEC-05` wording fix | New (process — recorded in the G3 design record, not a bash test) |

## 10. Acceptance criteria

- **AC1** — `specs/WorktreeGuard_Spec.md` exists, reaches `Status: ACCEPTED` via G1, and documents
  both guards' actual current behavior: the shared `MKR_WORKTREE_POLICY` tiers, what each guard
  gates, and the registration-vs-collision distinction. *(traces to §2 — no contract of record
  exists today)*
- **AC2** — An independent reviewer (G3: `mkr-design-reviewer` and `mkr-architecture-reviewer`),
  reading only the current deny/warn message text with no other context, can correctly state which
  of the two conditions (not-a-registered-worktree vs. live-process-collision) a given message
  describes. If either reviewer cannot, the message text is revised until they can, and that revision
  ships as part of this change. *(traces to §4 — self-diagnosis without reading source; tracked by
  `TC-WGSPEC-06`)*
- **AC3** — The discovered `advisory`-tier asymmetry between the two guards is explicitly documented
  in both this spec (§6) and the filed ADR, with a stated recommendation, rather than left as tribal
  knowledge from this investigation. *(traces to §2 — auditability)*
- **AC4** — An ADR exists formalizing AD-1 through AD-5. *(traces to §0 gates line: `adr: ✓`)*
- **AC5** — All 62 existing `TC-WG-*` cases in `tests/hooks_test.sh` (`TC-WG-01` through `TC-WG-60`,
  no `TC-WG-14`, plus `15a`/`15b`/`28b`/`30b`) continue to pass, modified only if AC2 requires a
  message-text assertion update — proving this change did not alter either guard's blocking *logic*.
  *(traces to §3 — no redesign of blocking algorithms)*

## 11. Definition of Done

- [ ] `specs/WorktreeGuard_Spec.md` reaches `Status: ACCEPTED (kikrgbh, <date>)` via G1
      (`mkr-spec-review`).
- [ ] G3 design gate run (`mkr-design-reviewer` + `mkr-architecture-reviewer`, independent, parallel)
      against §6/§7/§8; AC2/`TC-WGSPEC-06`'s message-clarity question resolved with a recorded
      verdict either way.
- [ ] If AC2 requires it: message-wording fix implemented in the affected guard(s), plus
      `TC-WGSPEC-05`.
- [ ] `docs/adr/00NN-<slug>.md` filed, formalizing AD-1 through AD-5 and the documented-but-deferred
      advisory-tier gap.
- [ ] `bash tests/hooks_test.sh` green, including all pre-existing `TC-WG-*` cases unmodified (or
      only the specific assertions AC2 required) and any new `TC-WGSPEC-*` cases.
- [ ] G4 code review (`mkr-code-reviewer` + `mkr-security-reviewer`) run if any guard source changed.
- [ ] Merged via G5 preflight (`mkr-merge`).
- [ ] Grounding audit (phase 9, `mkr-audit`) run against the merged commit, independently
      reproducing AC1–AC5 against real repo state, not this spec's own say-so.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. **spec-first** — this document (done, pending G1).
2. **reuse-check** — completed in §5; no further reuse discovery expected before design.
3. Run `mkr-spec-review` (G1) against this draft; revise per findings.
4. Run `mkr-design` (G3: `mkr-design-reviewer` + `mkr-architecture-reviewer`) against §6/§7/§8 —
   resolves AC2/`TC-WGSPEC-06` (message clarity) and AC3 (asymmetry documentation adequacy) with
   independent, fresh verdicts.
5. **test-first** — write `TC-WGSPEC-01`..`04` and `06` (and `05` if G3 requires the message fix)
   before any corresponding source change.
6. Implement: any message-wording fix G3 required (smallest diff that satisfies AC2); file the ADR
   (`mkr-adr` skill) formalizing AD-1..AD-5 and the deferred advisory-tier gap.
7. **self-review** — re-read the diff against §10's five acceptance criteria before calling it done.
8. **verify** — `bash tests/hooks_test.sh` and `bash tests/config_test.sh` both green.
9. **code-review** — `mkr-code-review` (G4: `mkr-code-reviewer` + `mkr-security-reviewer`) if any
   guard source changed; skipped only if the entire change ends up being docs/ADR with zero source
   diff, per `mkr-code-review`'s own trigger ("after verify, before a push, on any non-Quick
   change" — still run even for a docs-only Deep change, since the depth is Deep regardless of diff
   size).
10. `mkr-merge` (G5) — human (`kikrgbh`) approval before merge.
11. `mkr-audit` (phase 9, mandatory at Deep) — grounding audit against the merged commit.

## 13. Review history

| Rev | Verdict | Reviewer | Notes |
|---|---|---|---|
| 1 | NOT READY (3 blocking) | `mkr-spec-reviewer` | (1) §7 had no `7.3`/`7.4` subsections though both guard scripts cite them by number as their contract of record. (2) AC2 (independent reviewer can identify the failure condition from message text alone) had no `§9` test-case row. (3) The `TC-WG-01`..`TC-WG-57`/"59 distinct cases" claim, repeated in §5/§9/AC5, was factually wrong — the file actually has 62 distinct cases through `TC-WG-60` (no `TC-WG-14`) plus `15a`/`15b`/`28b`/`30b`. Non-blocking nit: §3's second/third out-of-scope items didn't name a specific handler. |
| 2 | pending | — | Fixed all three: §7 restructured into `7.1` (shared I/O) / `7.2` (shared env) / `7.3` (collision-guard) / `7.4` (edit-guard), matching both scripts' citations exactly. Added `TC-WGSPEC-06` covering AC2, referenced from AC2/§11/§12. Corrected the case count everywhere it appeared (§3, §5, §9, AC5) after re-deriving it with `grep -oE 'TC-WG-[0-9]+[a-z]?' tests/hooks_test.sh \| sort -u -V \| wc -l` rather than the partial read rev 1 relied on. Re-submitted for G1. |
