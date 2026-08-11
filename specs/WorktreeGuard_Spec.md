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
| **Status** | DRAFT rev 6 |
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
(AD-1 through AD-5) that are currently only implicit in code comments, in an ADR
(`docs/adr/0012-worktree-guard-policy-tiers.md`).

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
  `tests/hooks_test.sh` (`TC-WG-01` through `TC-WG-60`, no `TC-WG-14` and no bare `TC-WG-15`, plus lettered sub-cases
  `15a`, `15b`, `28b`, `30b`) — and hardened through multiple prior G4 review rounds (TOCTOU fixes,
  command-substitution closes). One pre-existing, already-known scope boundary was found during this
  investigation and is documented, not fixed, in §6 ("Discovered gap 2"): **both guards'** gating is
  keyword-based (`worktree-edit-guard.sh` matches `commit` as a literal word;
  `worktree-collision-guard.sh` matches `checkout`/`switch`), and both are unconditionally bypassable
  by any mechanism that lands the same real-world effect under a different name — a git alias, a
  shell function, `eval`, or git's own plumbing (concretely, for the commit gate: `git commit-tree`
  + `git update-ref`). Closing that class is explicitly out of scope for the same reason
  `procwalk.sh`'s own comment
  gives it: it requires understanding what an operation *does*, not what it's called, which is the
  same "full shell parser" scope this project has already, repeatedly ruled out elsewhere. Beyond
  that one known-and-accepted boundary, nothing found during this investigation suggests either
  algorithm's *keyword-matching* logic is wrong for the threat model it targets (accidental or
  unsophisticated bypass, not a git-internals-literate adversary already running arbitrary Bash).
- Adding an `advisory` tier to `worktree-edit-guard.sh` to match `worktree-collision-guard.sh`'s
  three-tier behavior. A real asymmetry was found (§6) and is documented here, but closing it is a
  behavior change beyond message clarity — deferred to a follow-up change (not yet triaged or named;
  the recommendation lives in `docs/adr/0012-worktree-guard-policy-tiers.md`'s Consequences section
  as the pointer for whoever picks it up), not decided unilaterally inside a spec whose stated job is
  to document current behavior.
- The permission allow-list / sibling-worktree-path issue the same adopter report raised. That is a
  Claude Code harness/settings concern this repo's own config doesn't touch at all — handled by
  `specs/WorktreePermissionScope_Spec.md` (Standard depth, branch `worktree-permission-scope-docs`),
  a separately-triaged sibling change, not this one.

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

**Discovered gap 1 (documented here, deliberately not fixed in this change — see §3 Out of scope):**
because `MKR_WORKTREE_POLICY` is a single, shared config value, an adopter setting it to `advisory`
to dry-run the policy before enforcing it gets a warning on branch-switch collisions (AD-3) but
**zero signal at all** on an edit/commit made outside a registered worktree (AD-2 — `advisory` and
`off` are indistinguishable to this guard). There is no gradual on-ramp on the edit-guard side, only
an on/off switch. This may be part of why the reporting adopter went straight to a hard, unexplained
block: an `advisory` trial run would not have surfaced anything on the edit-guard side to prepare
them for what `enforced` would later do. Recommended as a follow-up change (give
`worktree-edit-guard.sh` a genuine `advisory` warn-only state, mirroring AD-3), not decided here —
also recorded, with the same "documented, not fixed" framing, in
`docs/adr/0012-worktree-guard-policy-tiers.md`.

**Discovered gap 2 (pre-existing, already documented in source, given equivalent treatment here —
found on G4 security review of this spec itself):** `worktree-edit-guard.sh`'s commit gating (AD-2)
and `worktree-collision-guard.sh`'s checkout/switch gating (AD-3) both work by matching
`commit`/`checkout`/`switch` as literal keywords in the Bash command text
(`procwalk_statement_has_git_keyword`). `procwalk.sh`'s own comment on that function names a "KNOWN,
ACCEPTED SCOPE BOUNDARY" this spec's first draft omitted: a git alias, a shell function, `eval`, or
git's own plumbing achieving the identical real-world effect under a different name — concretely,
`git commit-tree <tree> -p <parent> -m msg` followed by `git update-ref refs/heads/<branch> <sha>` —
lands a real commit directly in the shared checkout with **no** `commit`/`checkout`/`switch` keyword
ever appearing anywhere in the statement, unconditionally bypassing `worktree-edit-guard.sh` end to
end. This requires none of the TOCTOU sophistication (chaining, backgrounding, process substitution,
`GIT_EDITOR` smuggling) the four prior G4 rounds closed — it is a structurally different class,
already known and already accepted at the source level (`procwalk.sh`'s own comment states plainly
that closing it "requires understanding what an operation *does*, not what it's *called*," the same
"full shell parser" scope this project has already, repeatedly ruled out). This spec's first draft
asserted "nothing found... suggests either algorithm is wrong" (§3) without surfacing this — a real
gap given the spec's own stated purpose is to be the contract an adopter can trust *without* opening
the source. Corrected here: **the keyword-matching approach is deliberately, not accidentally,
scoped to defend against accidental or unsophisticated bypass, not a git-internals-literate
adversary already able to run arbitrary Bash** — the same threat-model boundary
`is_single_bare_git_commit`'s own comment states for the narrower TOCTOU class. Not fixed here, for
the same reason: this is existing, shipped, already-accepted scope, and no change to that scope was
ever in this change's stated intent (§2).

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

Gates: a real, non-file-path `git checkout`/`git switch` statement only (§6 AD-3), matched as a
literal `checkout`/`switch` keyword — **not every statement with the identical real-world effect**
(the AD-3 keyword-matching boundary documented in §6 "Discovered gap 2": a branch-ref update via
git plumbing under a different subcommand name is not gated). Question asked: does a live process
outside this session's own process tree currently hold the resolved target directory as its `cwd`
(`procwalk_foreign_cwd`)? Decision: `off` → inert, no output; `advisory` → stderr warning naming
every colliding pid, `hookio_pretooluse_decision` never invoked; `enforced` →
`hookio_pretooluse_decision deny` naming every colliding pid. Target directory resolution: explicit
`git -C <dir>` on the matched statement, else the most recent preceding `cd <dir>` in the same
command (subject to the safe/unsafe statement-boundary tracking `procwalk_split_tagged` performs),
else the payload's own `cwd` field, else `${CLAUDE_PROJECT_DIR:-$PWD}`.

### 7.4 `worktree-edit-guard.sh`'s own contract

Gates: `Write`, `Edit`, and every real, non-excluded `git commit` occurrence in a `Bash` command
(§6 AD-2), matched as a literal `commit` keyword — **not every statement with the identical
real-world effect** (the AD-2 keyword-matching boundary documented in §6 "Discovered gap 2": `git
commit-tree <tree> -p <parent> -m msg` + `git update-ref refs/heads/<branch> <sha>` lands a real
commit with no `commit` keyword ever appearing, unconditionally bypassing this guard). Question
asked: does the target resolve, walking up to the nearest existing ancestor directory and then to
that directory's git-worktree top-level, to a path `git worktree list --porcelain` at the project
root recognizes as a genuine linked worktree — never the root's own main checkout? Decision:
`enforced` → checked, `hookio_pretooluse_decision deny` naming the action and the fix (`git
worktree add ../<name> <branch>`) on failure; any other policy value → fully inert, **no warning at
any tier** (the AD-2/AD-3 asymmetry documented in §6 "Discovered gap 1"). One exemption:
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
| `TC-WG-01`..`TC-WG-60` + `15a`/`15b`/`28b`/`30b` (existing, `tests/hooks_test.sh`, 62 cases, no `TC-WG-14` or bare `TC-WG-15`) | Both guards' full behavior across all three policy tiers, TOCTOU variants, nested paths, bootstrap exemption | Already passing — reused as acceptance evidence (AC5), not modified unless AC2 requires a message-text assertion update |
| `TC-WGSPEC-01` | `specs/WorktreeGuard_Spec.md` exists, `Status` field reads `ACCEPTED` | Verify by reading §1's `Status` line directly at the time of interest — deliberately not restated as a point-in-time snapshot here, since that snapshot went stale twice in this document's own revision history (rev 3→4, rev 4→5) each time §1 changed without this row being updated in lockstep; §11 DoD's own first checkbox is the durable source of truth for this criterion's current state |
| `TC-WGSPEC-02` | Every AD-1..AD-5 claim in §6 is checked against current source at design review (G3) and grounding audit (phase 9) — not just asserted | G3 half done (independently re-verified against source across all three G3 rounds: `.mkr/designs/WorktreeGuard-rev2.md`, `-rev3.md`, `-rev4.md`); phase-9 audit half still pending |
| `TC-WGSPEC-03` | The discovered advisory-tier asymmetry (§6) is documented in this spec AND in the filed ADR, not left undocumented in either | Done — documented in both §6 and `docs/adr/0012-worktree-guard-policy-tiers.md` |
| `TC-WGSPEC-04` | `docs/adr/0012-worktree-guard-policy-tiers.md` documents AD-1 through AD-5 and is linked from this spec's §6 | Done |
| `TC-WGSPEC-05` (conditional) | If G3 review concludes a deny/warn message needs a wording fix (§6, §10 AC2): the updated string names the specific failure condition, and a corresponding case is added to `tests/hooks_test.sh` asserting the new text | N/A — G3 concluded no wording fix is required (`.mkr/designs/WorktreeGuard-rev2.md`) |
| `TC-WGSPEC-06` | AC2 itself: `mkr-design-reviewer` and `mkr-architecture-reviewer`, each reading only the current `§7.3`/`§7.4` deny/warn text (no other context), independently state in their G3 verdict which of the two conditions each message describes; a recorded mismatch or "cannot tell" from either reviewer fails this case and triggers the `TC-WGSPEC-05` wording fix | Done — both reviewers independently identified both conditions correctly; see `.mkr/designs/WorktreeGuard-rev2.md` |
| `TC-WGSPEC-07` | The pre-existing, source-documented commit-guard bypass class (git alias/shell function/`eval`/`git commit-tree`+`git update-ref`, `procwalk.sh`'s own "KNOWN, ACCEPTED SCOPE BOUNDARY" comment) is named explicitly in this spec (§3, §6 "Discovered gap 2") and in the ADR, with the same "documented, not fixed" treatment as `TC-WGSPEC-03`'s asymmetry gap — not silently omitted the way the spec's own first draft omitted it | Done — found on G4 security review, fixed in this revision |

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
  no `TC-WG-14` or bare `TC-WG-15`, plus `15a`/`15b`/`28b`/`30b`) continue to pass, modified only if AC2 requires a
  message-text assertion update — proving this change did not alter either guard's blocking *logic*.
  *(traces to §2 — this change documents existing, tested behavior and must not alter it as a side
  effect; and to §3 — no redesign of blocking algorithms)*
- **AC6** — The pre-existing, source-documented commit-guard bypass class (§6 "Discovered gap 2") is
  named explicitly in both this spec and the filed ADR, with the same "documented, not fixed"
  treatment `AC3` requires for the advisory-tier asymmetry — not omitted the way this spec's own
  first draft omitted it. *(traces to §2 — the spec's own stated purpose is to be a contract an
  adopter can trust without opening the source; found missing on G4 security review; tracked by
  `TC-WGSPEC-07`)*

## 11. Definition of Done

- [ ] `specs/WorktreeGuard_Spec.md` reaches `Status: ACCEPTED (kikrgbh, <date>)` via G1
      (`mkr-spec-review`) — rev 4 achieved this (`ACCEPTED rev 4, kikrgbh, 2026-08-11`), but a G4
      finding (a stale §9 row, self-inconsistent with this very line) required a rev-5 fix, and
      rev 5's own fix reproduced the identical staleness in the opposite direction (caught at G1,
      not G4) — rev 6 closes it structurally: `TC-WGSPEC-01`'s row no longer restates a
      point-in-time snapshot of `Status` at all, so it cannot go stale again the same way. This box
      stays unchecked until rev 6 is re-approved. §6/§7/§8 remain untouched, so no further G3
      re-review is needed — only G1.
- [x] G3 design gate run (`mkr-design-reviewer` + `mkr-architecture-reviewer`, independent, parallel)
      against §6/§7/§8; AC2/`TC-WGSPEC-06`'s message-clarity question resolved with a recorded
      verdict either way. — done: rev 2 (`.mkr/designs/WorktreeGuard-rev2.md`, both READY, AC2 needs
      no wording fix); rev 3 re-review (`.mkr/designs/WorktreeGuard-rev3.md`,
      `mkr-architecture-reviewer` NOT READY 1 blocking, fixed in rev 4); rev 4 re-review
      (`.mkr/designs/WorktreeGuard-rev4.md`, both READY, zero blocking). Current content (rev 4) is
      G3-clean.
- [x] AC2 required no message-wording fix (rev-2 design gate verdict, unaffected by later content
      fixes) — `TC-WGSPEC-05` therefore does not apply to this change; N/A, not skipped.
- [x] `docs/adr/0012-worktree-guard-policy-tiers.md` filed, formalizing AD-1 through AD-5, the
      documented-but-deferred advisory-tier gap, AND (added in rev 3) the pre-existing
      commit-guard bypass class (§6 "Discovered gap 2"/AC6/`TC-WGSPEC-07`).
- [ ] `bash tests/hooks_test.sh` green, including all pre-existing `TC-WG-*` cases unmodified (or
      only the specific assertions AC2 required) and any new `TC-WGSPEC-*` cases — confirmed green
      (180/180, including all 62 `TC-WG-*` cases) against rev 2's diff; re-confirm against the final
      diff once content is human-re-approved (rev 3/4 are docs-only, no guard source touched, so no
      change in outcome is expected, but re-confirming against the actual final SHA is the discipline
      AC5 itself requires, not an assumption).
- [ ] G4 code review (`mkr-code-reviewer` + `mkr-security-reviewer`) run if any guard source
      changed. History: rev 2's diff got `mkr-code-reviewer: READY`,
      `mkr-security-reviewer: NOT READY (1 blocking, fixed in rev 3)`; the rev-4 diff (after
      human approval) got both fresh — `mkr-security-reviewer: READY` (independently re-verified
      its own rev-2 finding is fixed), `mkr-code-reviewer: NOT READY (1 blocking, fixed in rev 5,
      then structurally closed in rev 6)`. Re-review still needed on the final rev-6 diff — per
      G4's own re-review rule, only `mkr-code-reviewer` needs to re-run (it had the blocking
      finding; `mkr-security-reviewer`'s `READY` scope already covered these same lines).
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
| 2 | READY (G1); ACCEPTED (kikrgbh, 2026-08-11); READY (G3, `.mkr/designs/WorktreeGuard-rev2.md`); **NOT READY (G4, 1 blocking)** | `mkr-spec-reviewer`; `mkr-design-reviewer`+`mkr-architecture-reviewer`; `mkr-security-reviewer` | G1 fixes as below; approved by `kikrgbh`; G3 both READY (AC2 resolved: no message-wording fix needed). **Then, at G4** (code review of the resulting diff, `mkr-security-reviewer`): 1 blocking finding — this spec's §3 asserted "nothing found... suggests either algorithm is wrong" and §6 gave the advisory-tier asymmetry an explicit "documented, not fixed" callout while silently omitting a more severe, already-known, already-source-documented gap: `procwalk.sh`'s own "KNOWN, ACCEPTED SCOPE BOUNDARY" comment states a git alias/shell function/`eval`/`git commit-tree`+`git update-ref` sequence unconditionally bypasses `worktree-edit-guard.sh`'s keyword-based commit gating end to end, with zero TOCTOU sophistication required. Independently confirmed by re-reading `procwalk.sh` directly (already read in full earlier in this same session, prior to this finding). Original rev-2 fixes for reference: §7 restructured into `7.1`/`7.2`/`7.3`/`7.4` matching both scripts' citations exactly; `TC-WGSPEC-06` added covering AC2; case count corrected (§3, §5, §9, AC5) via `grep -oE 'TC-WG-[0-9]+[a-z]?' tests/hooks_test.sh \| sort -u -V \| wc -l`. |
| 3 | READY (G1); READY (G3, `mkr-design-reviewer`); **NOT READY (G3, `mkr-architecture-reviewer`, 1 blocking)** | `mkr-spec-reviewer`; `mkr-design-reviewer`+`mkr-architecture-reviewer` | G1: fixes the G4 finding above — §3 corrected (no longer claims "nothing found... wrong"), §6 gains "Discovered gap 2", new `AC6`/`TC-WGSPEC-07`, ADR updated. Reviewer independently re-read `procwalk.sh` and confirmed the bypass class is real; `READY`, no blocking. Non-blocking cosmetic fixes applied inline: `Status` shape tightened, `TC-WGSPEC-01` row corrected, §3's vague out-of-scope bullets now name concrete handlers, AC5's trace anchored to §2 too. **G3 re-review** (§6 changed materially, so re-run per `mkr-design`'s own re-review process, both agents given the rev-2 record for context): `mkr-design-reviewer` independently re-verified the bypass class against `procwalk.sh` directly and returned `READY`. `mkr-architecture-reviewer` returned **NOT READY (1 blocking)**: §7.3/§7.4 — the sections both guard scripts cite by number as their own contract of record — didn't carry the "Discovered gap 2" caveat that §6 introduces, even though §7.4 already carried the equivalent backlink for "Discovered gap 1" (the advisory-tier asymmetry). An adopter following the guards' own header citations into §7.3/§7.4 directly would get an incomplete picture. Non-blocking: §3's out-of-scope bullet named only the commit-gate instance of the bypass, not the checkout/switch-gate instance §6 also documents. |
| 4 | READY (G3, both); ACCEPTED (kikrgbh, 2026-08-11); **NOT READY (G4, 1 blocking)** | `mkr-design-reviewer`+`mkr-architecture-reviewer`; `mkr-code-reviewer` | Fixes the G3 architecture finding above: §7.3 now states the AD-3 keyword-matching boundary inline ("not every statement with the identical real-world effect... Discovered gap 2"); §7.4 states the equivalent AD-2 boundary inline, and also gains an explicit "Discovered gap 1" backlink alongside the already-present asymmetry note. §6's first discovered-gap paragraph is now explicitly labeled "Discovered gap 1" for consistent cross-referencing with "Discovered gap 2". §3's out-of-scope bullet widened to cover both guards (previously named only the commit-gate instance). Both reviewers independently re-verified the fix against the actual §7.3/§7.4 text (not the revision's own claim) and did a fresh full pass over §6/§7/§8 against current source, finding no new blocking defects. Record: `.mkr/designs/WorktreeGuard-rev4.md`. **Process note:** rev 3 and rev 4's G3 rounds ran without a fresh human (`kikrgbh`) G1 re-approval in between — flagged explicitly to the human before G4/merge; human then reviewed and approved rev 4 (`ACCEPTED rev 4, kikrgbh, 2026-08-11`). **Then, at G4** (final-diff re-review, both `mkr-code-reviewer` and `mkr-security-reviewer` fresh): `mkr-security-reviewer` independently re-verified its own rev-2 finding is genuinely fixed against live source — `READY`, no new findings. `mkr-code-reviewer` found 1 blocking, self-inflicted: `TC-WGSPEC-01`'s §9 row still read "Pending... `DRAFT rev 3`" even though §1's header and §11 DoD both already said `ACCEPTED rev 4` — a stale row from mid-revision never synced when Status was updated. Also non-blocking: `TC-WGSPEC-02`'s citation only named the rev-2 design record despite rev-3/rev-4 re-verifying the same claims; the "no `TC-WG-14`" parenthetical (three occurrences) omitted that bare `TC-WG-15` is also absent. |
| 5 | NOT READY (G1, 1 blocking) | `mkr-spec-reviewer` | Fixes the G4 finding above: `TC-WGSPEC-01`'s row corrected to `Done — ACCEPTED rev 4 (kikrgbh, 2026-08-11)`. Also fixed both non-blocking notes: `TC-WGSPEC-02` now cites all three G3 records (`rev2`/`rev3`/`rev4`); all three "no `TC-WG-14`" occurrences (§3, §9, AC5) now also state "or bare `TC-WG-15`". **Reviewer caught a recursion of the same bug**: cross-checking §1/§9/§11 directly (as instructed) rather than trusting the spec's own "Answer" column, `TC-WGSPEC-01`'s freshly-corrected row asserted `Status` currently reads `ACCEPTED` — but `Status` had already reverted to `DRAFT rev 5` (this very revision, since rev 4's acceptance was superseded by the G4 finding this row exists to fix) by the time this row was written. The identical §1/§9 desync class, now stale in the opposite direction, introduced by the very commit meant to close it. Non-blocking, also noted: §3's advisory-tier handler is honestly "not yet triaged," the `DRAFT rev N` shape had grown an unprecedented parenthetical, and §11's G4 checkbox note hadn't kept pace with the narrative in the DoD's first bullet. |
| 6 | pending (G1 only) | — | Closes the recursion structurally rather than patching the snapshot a third time: `TC-WGSPEC-01`'s row no longer restates `Status` as a point-in-time fact at all — it now says to read §1 directly, with an explicit note that this row's own history (stale twice, in opposite directions) is exactly why it stopped trying. `Status` line tightened back to the bare `DRAFT rev 6` shape (the explanatory parenthetical moved to this row instead, where it belongs to history rather than to the live gate state). §11's first bullet and G4 checkbox both rewritten to track the current rev number and the actual G4 history without needing further edits every time `Status` flips. Resubmitted for G1 only — §6/§7/§8 still untouched. |
