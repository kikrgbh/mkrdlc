---
name: mkr-gates
description: Re-triages a mid-session sub-slice of in-flight work (docs/DESIGN.md §3.E's escalation policy) using mkr-loop's own six-question classification, and — when the sub-slice trips a gate the current branch doesn't yet satisfy and its paths are still uncommitted — splits it onto its own branch via git stash and reports (or opens) a PR for it, so the sub-slice can go through its own loop while the session's remaining, already-in-scope work keeps going. Use whenever a later phase discovers something triage missed, or a human notices scope has grown mid-session.
---

# mkr-gates — mid-session escalation and split (docs/DESIGN.md §3.E, made mechanical)

`mkr-gates` never invents a new notion of what makes a change Standard or Deep — that's
`mkr-loop`'s job, and this skill re-runs it rather than re-deriving it. This skill's own job is
deciding, from that re-triage, whether the current branch already covers the sub-slice or whether
it needs to be split off, and then — carefully, and only when it is safe to do so mechanically —
doing the split.

## 1. Identify the sub-slice

Input: a set of paths that feel out of scope for the current work, named either by a human or by
another skill that hit `docs/DESIGN.md` §3.E's escalation trigger (a later phase discovered
something triage missed — the fix turns out to need a migration, the "small" change touches the
auth guard, etc.).

## 2. Re-triage, using `mkr-loop`'s own classification — not a second copy of it

Re-run `mkr-loop`'s §B six-question classification (paths touched, does it exist, contract change,
reversibility, UI/probabilistic surface, done-when) against **only** the sub-slice's own paths and
scope. Produce a second, independent `TRIAGE` block scoped to that sub-slice alone. Do not restate
`mkr-loop`'s decision rule here — invoke it, the same way `mkr-design` invokes `mkr-design-reviewer`
rather than re-implementing a design review inline.

## 3. Does the sub-slice's own triage already fit inside what the session already covers?

Compare the sub-slice's derived `gates:` line against what the **current session's own**,
already-recorded triage already covers.

- **Already covered** (e.g. the whole session is already Deep, and Deep already implies every gate
  the sub-slice would need) — report "no split needed, the session's existing triage already covers
  this," and hand control back with no branch mutation. This is the common case, and the point of
  step 2: it's what stops `mkr-gates` from splitting off ordinary, already-in-scope work by
  mistake.
- **Not covered** — a genuine escalation — continue to step 4.

## 4. Is the sub-slice still uncommitted?

Run `git status --porcelain -- <sub-slice paths>`.

- **Uncommitted (has output):** this is the case `mkr-gates` can split mechanically. Continue to
  step 5.
- **Already committed (no output, because the paths are clean relative to HEAD but differ from the
  branch's merge-base):** do not attempt history surgery — a rebase-shaped cherry-pick of specific
  commits carries real conflict and data-loss risk, and CLAUDE.md's non-negotiables warn against
  automating a hard-to-reverse action silently. `mkr-gates` does not attempt history surgery here.
  Instead: report the specific commits and paths involved, the sub-slice's own derived `TRIAGE`
  block, and ask the human to split it manually. Stop — do not continue to step 5.

## 5. Split: `git stash push`, isolated into a `git worktree` — not `git stash branch` in place

Uncommitted and untracked changes are working-directory-global, not branch-scoped: switching
branches with a plain checkout (or `git stash branch`, which checks the new branch out **in the
same working directory**) does not stop the session's own remaining, already-in-scope uncommitted
work from showing up on both branches at once. Real isolation needs a second, physically separate
checkout — a plain `git worktree add`, not a bespoke second-worktree convention invented here. (This
project already publishes an `MKR_WORKTREE_POLICY` config key naming the *concept* of worktree
isolation, off by default; this skill doesn't read or branch on its value — it always isolates the
split this way, since that's the only way the split is actually safe — but the name is worth noting
as the closest existing precedent for "this project already has a notion of worktree isolation.")

- `git stash push -u -m "<sub-slice and its derived depth>" -- <sub-slice paths>` — **`-u` is
  required whenever the sub-slice includes an untracked (brand-new) file or directory — the common
  case, since a sub-slice discovered mid-session is often new work.** Without `-u`, `git stash push
  -- <paths>` silently fails outright on an all-untracked pathspec ("did not match any file(s)
  known to git") rather than stashing nothing — a plain `git status --porcelain` check on the
  sub-slice's own paths beforehand is what step 4 already does, so this failure mode is avoidable,
  not silent, if `-u` is always included. **`-m` must come before the `--` pathspec separator**;
  `git stash push -- <paths> -m "..."` fails outright (`-m`'s argument is parsed as another
  pathspec once it follows `--`). This isolates exactly the named, still-uncommitted paths out of
  the current working directory, leaving the session's own remaining, already-in-scope work as the
  only thing left uncommitted there.
- `git branch <new-branch-name>` — from the current branch's HEAD, **without checking it out** in
  the current working directory.
- `git worktree add <worktree-path> <new-branch-name>` — a second, physically separate checkout
  (`<worktree-path>` a scratch location outside the session's own working tree, e.g. a sibling
  directory), so applying the stash there cannot touch the original working directory at all.
- Inside that new worktree: `git stash pop` — applies the isolated sub-slice there, and only there.
  The original working directory is untouched by this step; the session's own remaining work stays
  exactly as it was, confirmed by re-running `git status --porcelain` there afterward.
- Commit the sub-slice inside the new worktree (it is not itself a protected branch, so this and the
  next step need no ask — the same latitude creating and pushing any ordinary feature branch already
  has; only a push or merge *to a protected branch* is CLAUDE.md's "MUST ASK FIRST" case).
- If `gh` is available and authenticated: from inside the new worktree, `git push -u origin
  <new-branch-name>`, then `gh pr create` for it, with a description stating the re-triage result
  (the sub-slice's own `TRIAGE` block). If not: report the worktree path and branch name, and that
  pushing it and opening a PR need doing by hand.
- Remove the scratch worktree (`git worktree remove <worktree-path>`) once its branch is pushed (or
  its contents reported for a manual push) — the branch itself persists; only the second checkout
  was scratch.

## 6. Report back

Either way (split or not), report explicitly to the calling session:

- What (if anything) was split, and to which branch/PR.
- The sub-slice's own derived depth and gates (step 2's `TRIAGE` block).
- Confirmation that the original session's remaining, already-in-scope work is untouched on the
  current branch and can continue — this is the "session keeps going instead of halting" half of
  `docs/DESIGN.md` §8's M5 ship criterion. `mkr-gates` never itself decides to stop the calling
  session; it only ever hands control back, with or without a split having happened.
