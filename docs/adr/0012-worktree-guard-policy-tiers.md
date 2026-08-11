# 0012 — Worktree guard policy tiers and the registration/collision split

## Status

Accepted

## Context

`worktree-edit-guard.sh` and `worktree-collision-guard.sh` (`.claude/hooks/scripts/`) have shipped
since this repo's initial public release, gated by a single `MKR_WORKTREE_POLICY` config value. Both
scripts' own header comments have cited `specs/WorktreeGuard_Spec.md §7.3`/`§7.4`/`§6 AD-1`/`AD-4`
as their contract of record from the start — but that spec file was never actually written or
accepted, so the design decisions below existed only as code comments, with no ADR and no
independently-reviewed contract an adopter or reviewer could check the shipped behavior against.

This gap surfaced concretely: an adopter enabled `MKR_WORKTREE_POLICY=enforced`, hit a block, and
reported it as a bug — but their description conflated the two guards' distinct conditions
(`worktree-edit-guard.sh` never checks for a live process at all; `worktree-collision-guard.sh` does,
but only gates branch switching). `specs/WorktreeGuard_Spec.md` was subsequently drafted, reviewed
(G1 `ACCEPTED rev 2`), and independently design-reviewed (G3 `READY`, `.mkr/designs/WorktreeGuard-rev2.md`)
to give the guards the contract they'd always claimed to have. This ADR formalizes the decisions that
spec's §6 documents as already-shipped, already-tested (62 `TC-WG-*` cases in `tests/hooks_test.sh`)
behavior — it records a decision already made and validated in code, not a new one being proposed.

## Decision

**AD-1 — `MKR_WORKTREE_POLICY` has three conventional values, unvalidated.** `off` (default,
`config.sh`), `advisory`, `enforced`. No validation is performed on the string; any other value
(including a typo) is treated by each guard as "not enforced."

**AD-2 — `worktree-edit-guard.sh` gates `Write`/`Edit`/a bare `git commit`** by checking whether the
target resolves to a path `git worktree list --porcelain` recognizes as a genuine linked worktree of
the project — never the main checkout itself. This guard has exactly two effective states:
`enforced` (checked) and everything else (fully inert, no warning at any other tier).

**AD-3 — `worktree-collision-guard.sh` gates `git checkout`/`git switch`** (branch-switching only; a
file-path `git checkout -- <path>` form is never gated) by checking, via a single `/proc` pass,
whether a live process outside this session's own process tree currently holds the target directory
as its `cwd`. This guard has three effective states: `off` (inert), `advisory` (warns to stderr,
names the colliding pid, never blocks), `enforced` (denies, names the colliding pid).

**AD-4 — registration is checked against `git worktree list`'s own authoritative registry, never a
git-dir string shape.** `procwalk_is_registered_worktree` does not trust `git -C <dir> rev-parse
--absolute-git-dir`'s own returned string, since a bare or anchored `*/worktrees/*` substring test is
spoofable in one command (`git init --separate-git-dir=<anywhere>/.git/worktrees/<name> <dir>`,
fabricating a matching string for a completely unrelated, non-linked repo). An empty/unresolvable
git-dir always allows, checked before the registration test.

**AD-5 — the bootstrap-policy-commit exemption.** The single commit that first sets
`MKR_WORKTREE_POLICY=enforced` is exempted from `worktree-edit-guard.sh` in the shared checkout,
because by the time that commit runs the guard already reads `enforced` off the just-staged file,
with no worktree yet to have made the commit from otherwise. The exemption is scoped narrowly (the
project's own top-level checkout only; a staged diff touching exactly `.mkr/config` and nothing
else; a one-line change landing on `MKR_WORKTREE_POLICY=enforced`; and only when nothing else in the
same Bash tool call can run between the check and the commit itself) and has been hardened against
every TOCTOU variant found across four prior G4 review rounds (chained commits, backgrounded
commands, process substitution, `GIT_EDITOR`/`-e` smuggling).

**Accepted but deferred: the advisory-tier asymmetry.** Because `MKR_WORKTREE_POLICY` is a single,
shared value, an adopter setting it to `advisory` to dry-run the policy gets a warning on
branch-switch collisions (AD-3) but zero signal on an edit/commit made outside a registered worktree
(AD-2 — `advisory` and `off` are indistinguishable to that guard). There is no gradual on-ramp on the
edit-guard side, only an on/off switch — likely part of why the reporting adopter went straight to a
hard, unexplained block. **Recommendation, not decided here:** give `worktree-edit-guard.sh` a
genuine `advisory` warn-only state, mirroring AD-3. Deferred to a follow-up change; closing it now
would be a behavior change beyond this ADR's scope of formalizing what already shipped.

## Consequences

- Both guards now have a citable, independently G1/G3-reviewed contract of record
  (`specs/WorktreeGuard_Spec.md`) that their own header comments' `§7.3`/`§7.4` citations resolve to,
  closing the "contract cited but never written" gap this ADR exists to close.
- An adopter hitting either guard's deny/warn message can now check that message against a real
  spec instead of reading two bash scripts and a shared library to understand what was blocked and
  why — independently confirmed at G3: the current message text already lets an adopter distinguish
  the two conditions without a wording change.
- The advisory-tier asymmetry remains real and adopter-visible until the deferred follow-up lands: an
  `advisory` dry run will not surface an edit/commit-location violation the same policy value would
  later block outright at `enforced`. This is a known, accepted gap, not an oversight — tracked here
  and in the spec so it doesn't surface again as an unexplained surprise.
- AD-4's registry-based check costs one `git worktree list --porcelain` invocation per gated
  operation rather than a cheaper string-shape test — accepted because the string-shape alternative
  is spoofable in one command and this is a security-relevant boundary, not a hot path.
