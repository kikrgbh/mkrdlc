# WorktreePermissionScope Spec

## 0. Triage

```
TRIAGE
depth:    standard
why:      this repo's own config/hooks don't touch Claude Code's permission allow-list at all — it's
          a harness/settings-level gap outside .claude/'s control — so the only actionable fix here is
          adopter-facing documentation, but adding a new doc section disqualifies it from Quick (Quick
          requires no new file/section beyond a test).
scope:    one change: document the gap and a workaround (e.g., use the EnterWorktree/ExitWorktree
          tools, which keep the session's existing permission scope intact by switching cwd within
          the same session, instead of manually creating a sibling worktree and starting a fresh
          session there where the original session's permission allow-list won't automatically cover
          the new path) somewhere adopters will find it before they hit the same blocker.
reuse:    checked .claude/settings.json in full — no permissions.allow block exists, confirming
          nothing here already handles this; checked docs/DESIGN.md and README.md — MKR_WORKTREE_POLICY
          is documented as a sample config value (DESIGN.md §6) and in the Gates table (README.md),
          but neither mentions the permission-allow-list interaction with worktree paths at all;
          checked seed/CLAUDE.md — carries no project-specific fact, correctly, so this doesn't belong
          there per CLAUDE.md's own non-negotiable ("seed/CLAUDE.md and seed/config carry no fact
          specific to this project") — scoped to this repo's own README.md, where MKR_WORKTREE_POLICY
          is already user-facing (the "Installing" section, README.md:86-96).
touches:  README.md (new subsection near "Installing")
risky:    none matched
gates:    spec: ✓  plan: ✓  design: ✗ (no contract change, no UI)  review: ✓  ground: ✓  adr: ✗  ship: ✗
done when: an adopter enabling MKR_WORKTREE_POLICY=enforced and creating a sibling worktree can find,
          in this repo's own docs, why their permission allow-list won't extend and what to do about it.
```

## 1. Header

| | |
|---|---|
| **Status** | ACCEPTED rev 3 (kikrgbh, 2026-08-11 — approved via explicit instruction in this session) |
| **Depth** | Standard |
| **Author** | agent |
| **Approver** | kikrgbh |

## 2. Intent

An adopter enabled `MKR_WORKTREE_POLICY=enforced` (which requires edits/commits to happen in a real,
registered git worktree rather than the shared checkout — see the companion
`specs/WorktreeGuard_Spec.md`) and reported a second, separate blocker: Claude Code's permission
allow-list, scoped to the path they originally launched a session against, does not extend to a
sibling worktree path created outside that original path. Every edit in the new worktree then
triggers a fresh approval prompt, even with auto mode on — because the harness has no reason to
believe the new path was ever granted anything.

This is not a bug in this repo's own hooks or config — `.claude/settings.json` carries no
`permissions` block at all, so there is nothing here to misconfigure. It is a direct consequence of
how `MKR_WORKTREE_POLICY=enforced` pushes adopters toward creating worktrees, combined with how
Claude Code scopes permission grants to a working directory. An adopter who creates that worktree by
starting a brand-new session rooted at the new path re-triggers permission scoping from scratch; an
adopter who instead stays in their existing session and moves into the worktree (e.g. via the
`EnterWorktree` tool) never leaves the session whose permissions were already granted, so nothing
re-triggers. Nothing in this repo currently tells an adopter that distinction exists before they hit
it the hard way.

## 3. Scope

**In scope:**
- A short, clearly-scoped addition to `README.md`, placed near the existing "Installing" section
  (the closest existing user-facing mention of `MKR_WORKTREE_POLICY`-adjacent setup), explaining:
  (a) what `MKR_WORKTREE_POLICY=enforced` requires of adopters (a real, registered worktree, not the
  shared checkout — one sentence, pointing at `specs/WorktreeGuard_Spec.md` for the full contract,
  not re-explaining it), and (b) the permission-allow-list gotcha and its workaround.
- Stating the workaround plainly: stay in the same session and move into the new worktree (e.g. via
  `EnterWorktree`) rather than starting a fresh session rooted at a manually-created sibling path; if
  a fresh session against the new path is unavoidable, its permission scope has to be established
  for that path independently, the same as it would for any other new working directory.

**Out of scope:**
- Any code-level fix. Claude Code's permission-scoping behavior is outside this repo's control —
  there is no hook, no config value, and no reasonable guardrail-script mechanism that changes how
  a *different, freshly-launched session* is granted permissions. This spec produces documentation
  only.
- Re-explaining `worktree-edit-guard.sh`/`worktree-collision-guard.sh` behavior — that is the
  companion `specs/WorktreeGuard_Spec.md`'s job (separate branch, separate spec); this document
  cross-references it rather than duplicating it.
- Any change to `docs/DESIGN.md`'s sample `.mkr/config` (§6) — the sample already shows
  `MKR_WORKTREE_POLICY="advisory"` with its three-value comment; no change to that sample is needed
  for this gap.

**Dependency (found on G1 re-review, rev 2):** `specs/WorktreeGuard_Spec.md`, the file AC1/AC3 point
the README link at, does not exist on this branch, on `main`, or anywhere in this repo's history
except the sibling branch `worktree-guard-spec` — where it is drafted and, as of that spec's own
rev 2, `READY` at G1, pending human approval (`kikrgbh`) and eventual merge. This is an ordinary
cross-branch sequencing situation, not a defect in either spec, but it has to be handled explicitly
rather than assumed away: §12's task breakdown sequences this change's actual README edit (the step
that writes the live link) to land only after `specs/WorktreeGuard_Spec.md` merges to `main`, so the
link this spec's AC1/AC3 require is never merged dangling.

## 4. Affected users & journey change

**Before:** an adopter turns on `MKR_WORKTREE_POLICY=enforced`, gets pushed toward creating a
worktree by the edit guard's own deny message (`git worktree add ../<name> <branch>`), does so, and
— if they start a new session there rather than staying in the one that already had permissions
granted — hits a wall of repeated approval prompts with no visible connection to the policy they just
turned on. Nothing in this repo's docs prepares them for it.

**After:** the README states the connection explicitly, before an adopter reaches this point via
trial and error: turning on `MKR_WORKTREE_POLICY=enforced` means you'll be working from worktrees,
and staying in the same session while doing so (via `EnterWorktree`) avoids a second, unrelated
permission-scope problem that a brand-new session at the new path would otherwise hit.

## 5. Reuse check

- Read `.claude/settings.json` in full — only a `hooks` block; no `permissions` configuration exists
  anywhere in this repo to extend or fix.
- Read `README.md` in full (`Installing`, `Gates`, `Layout`, `Running the tests` sections) — no
  existing mention of `MKR_WORKTREE_POLICY`, worktrees, or permission scoping.
- Read `docs/DESIGN.md` §6 (the sample `CLAUDE.md`/`.mkr/config`) and §4 (gates table) — the sample
  shows `MKR_WORKTREE_POLICY="advisory"     # off | advisory | enforced` as a config value but adds
  no adopter-facing explanation of what enabling it implies for worktree creation or session
  permission scope; §9 "Decisions still open" has no entry for this either.
- Read `seed/CLAUDE.md` and `seed/config` — correctly empty of any project-specific fact per
  `CLAUDE.md`'s own non-negotiable; this gap is specific enough to this repo's own adoption story
  (its README already documents the loop/gates/installing) that it belongs there, not invented as a
  new seed-file convention this change would be the only user of.
- Confirmed empirically, in the course of doing this exact work in this session: `EnterWorktree`
  (when available) creates the worktree AND switches the current session's working directory into
  it in one step, keeping already-granted permissions in effect — used directly, for both this
  change and its companion, with no repeated approval prompts.
- Checked whether `specs/WorktreeGuard_Spec.md` (the file this spec's README link points at) exists
  yet, anywhere: it does not, on this branch or `main` — confirmed by directory listing and a
  repo-wide grep for `WorktreeGuard` finding only this spec's own references and the two guard
  scripts' source-comment citations. It exists only on the sibling branch `worktree-guard-spec`,
  `READY` at G1 as of that spec's own rev 2, not yet merged. See the Dependency note in §3.

## 6. Architecture & key decisions

No architecture change — this spec produces a documentation addition, not a system change. The one
decision worth recording: **where the note lives.** Considered and rejected: `docs/DESIGN.md` §6's
sample config (too deep in a design rationale doc most adopters won't read before hitting the
problem) and a new top-level doc file (adds a file for two paragraphs of content, when README.md
already has the exact right section to extend). `README.md`, near "Installing," was chosen because
it's the first document an adopter reads, and it already introduces `MKR_WORKTREE_POLICY`-adjacent
concepts (the Gates table already lists `worktree-edit-guard.sh`'s enforcement tier implicitly via
G1's `spec-gate.sh` row, though not by name).

## 7. Interfaces / contracts

None — no code, no config schema, no hook touched.

## 8. Data model

No data model change.

## 9. Test-case register

Documentation changes have no executable test surface in this repo (`MKR_TEST` runs
`config_test.sh`/`mkr_artifact_test.sh`/`hooks_test.sh`/`install_test.sh`, none of which assert
README prose). Acceptance is verified by direct inspection against §10 below, not a bash test case.

| ID | Covers | Verification |
|---|---|---|
| `TC-WPS-01` | README.md states what `MKR_WORKTREE_POLICY=enforced` requires and links `specs/WorktreeGuard_Spec.md` | Manual read-through at self-review and G4 |
| `TC-WPS-02` | README.md states the permission-allow-list gotcha and the `EnterWorktree`-first workaround | Manual read-through at self-review and G4 |
| `TC-WPS-03` | No code, hook, or config file changed by this diff (confirms scope held) | `git diff --stat` against the merge base shows only `README.md` |
| `TC-WPS-04` | The added section does NOT re-explain `worktree-edit-guard.sh`/`worktree-collision-guard.sh`'s own blocking logic inline — no restatement of the registration check, the collision check, or the AD-1..AD-5 decisions those scripts implement; a one-clause pointer plus the link is all AC3 allows | Manual read-through at self-review and G4: flag any sentence describing what either guard script checks or how, beyond naming that `MKR_WORKTREE_POLICY=enforced` requires a registered worktree |

## 10. Acceptance criteria

- **AC1** — `README.md` contains a section, reachable from a first read-through, stating that
  `MKR_WORKTREE_POLICY=enforced` requires working from a real, registered worktree. *(traces to §2
  — nothing currently tells an adopter this)*
- **AC2** — That section states the permission-allow-list gotcha (a fresh session rooted at a
  manually-created sibling worktree path re-triggers permission scoping) and the workaround
  (stay in the same session; use `EnterWorktree` to move into the worktree instead). *(traces to §2
  — the adopter's actual reported blocker)*
- **AC3** — The section cross-references `specs/WorktreeGuard_Spec.md` rather than re-explaining
  guard behavior inline. *(traces to §3 — scope boundary against the companion spec; tracked by
  `TC-WPS-04`)*
- **AC4** — `git diff --stat` against the branch point shows only `README.md` changed. *(traces to
  §3 — documentation-only, no code-level workaround invented)*

## 11. Definition of Done

- [ ] `specs/WorktreePermissionScope_Spec.md` reaches `Status: ACCEPTED (kikrgbh, <date>)` via G1
      (`mkr-spec-review`) — spec approval itself is NOT blocked by the dependency below; only the
      actual README edit and this change's own merge are.
- [x] `specs/WorktreeGuard_Spec.md` (branch `worktree-guard-spec`) has merged to `main` (§3
      Dependency) — confirmed via `git show origin/main:specs/WorktreeGuard_Spec.md`, `Status:
      ACCEPTED rev 11`.
- [x] README.md addition drafted satisfying AC1–AC3 — done, `826165a`, new "Worktrees" section
      between "Installing" and "Build status".
- [x] `git diff --stat` confirms AC4 (README.md only) — confirmed, `README.md | 12 ++++++++++++`.
- [x] Self-review against §10 — AC1-AC4 all checked directly against the added section's text.
- [x] `bash tests/config_test.sh && bash tests/mkr_artifact_test.sh && bash tests/hooks_test.sh &&
      bash tests/install_test.sh` (this repo's full `MKR_TEST`) still green — proves the doc-only
      change didn't accidentally touch anything executable. Done: 123/123, 249/249, 180/180, 74/74.
- [x] G4 code review (`mkr-code-review`) run despite being docs-only, since depth is Standard, not
      Quick. — done: `.mkr/reviews/eb3aa12.md`, `VERDICT: READY` (both sub-verdicts READY).
- [ ] Merged via G5 preflight (`mkr-merge`).
- [ ] Grounding audit (phase 9, `mkr-audit`) run against the merged commit.

## 12. Task breakdown

Ordered against `MKR_PLAN_MANDATORY` (`spec-first reuse-check test-first self-review verify
code-review`):

1. **spec-first** — this document (done, pending G1).
2. **reuse-check** — completed in §5.
3. Run `mkr-spec-review` (G1) against this draft; revise per findings.
4. **test-first** — n/a in the executable sense (§9); the "test" here is stating AC1–AC4 before
   writing the README prose, which is already done above.
5. Confirm `specs/WorktreeGuard_Spec.md` (branch `worktree-guard-spec`) has merged to `main` (§3
   Dependency) before proceeding — if not yet merged, this task holds here rather than merging a
   dangling link; spec approval (step 3 above) can still complete independently of this wait.
6. Implement: write the README.md section per AC1–AC3.
7. **self-review** — re-read the added section against §10 before calling it done; confirm AC4 via
   `git diff --stat`.
8. **verify** — run this repo's full `MKR_TEST` suite; confirm nothing beyond `README.md` changed.
9. **code-review** — `mkr-code-review` (G4: `mkr-code-reviewer` + `mkr-security-reviewer`), even
   though the diff is docs-only, because depth is Standard.
10. `mkr-merge` (G5) — human (`kikrgbh`) approval before merge.
11. `mkr-audit` (phase 9) — grounding audit against the merged commit.

## 13. Review history

| Rev | Verdict | Reviewer | Notes |
|---|---|---|---|
| 1 | NOT READY (1 blocking) | `mkr-spec-reviewer` | `§9`'s register had no row verifying AC3's negative assertion ("rather than re-explaining guard behavior inline") — `TC-WPS-01` only checked that the link to the companion spec exists, so a README section that both links it and duplicates its guard-behavior detail would have passed every listed case while violating AC3. Non-blocking nit: §3's first out-of-scope item didn't use the "not applicable"/named-handler phrasing the other two used. |
| 2 | NOT READY (1 blocking) | `mkr-spec-reviewer` | Rev-1 fix for `TC-WPS-04` verified as correctly landed. New finding on fresh full re-review: `specs/WorktreeGuard_Spec.md`, the file AC1/AC3 require the README to link, does not exist on this branch, on `main`, or anywhere except the sibling branch `worktree-guard-spec` — confirmed by directory listing and repo-wide grep. AC1/AC3 were unsatisfiable as written without either relocating the cross-reference or sequencing this spec behind that one merging. Non-blocking nit carried over: §3's first out-of-scope item still lacks the "not applicable" phrasing. |
| 3 | READY | `mkr-spec-reviewer` | Rev-2 fix re-verified: reviewer independently confirmed `specs/WorktreeGuard_Spec.md` still doesn't exist on this branch/`main`, read it directly on `worktree-guard-spec` (confirmed `DRAFT rev 2`, `READY` at G1, pending human approval — matches this spec's own characterization), and checked all four changed sections (§3/§5/§11/§12) landed as claimed. No new blocking findings. Non-blocking nits: §3's first out-of-scope item still lacks the "not applicable" phrasing (carried over from rev 1/2); §5's grep description is slightly incomplete (misses a `tests/hooks_test.sh` comment match, doesn't change the conclusion). Pending human G1 approval (`kikrgbh`). |
