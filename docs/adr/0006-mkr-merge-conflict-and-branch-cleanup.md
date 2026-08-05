# 0006 — mkr-merge: propose-only conflict resolution, ask-gated branch deletion

## Status

Accepted

## Context

`mkr-merge` today covers G5 preflight (record/CI/spec checks) and executing a clean merge — it has
no conflict-resolution or branch-cleanup mechanics at all. A hypothetical prior `aidlc-merge` had
both (reported from an adopter repo, Misikiri, as "worth contributing, not blocking"). Two different
risk tiers hide inside that one request:

- **Plain bookkeeping** — updating the PR description, closing linked issues on merge — is
  additive: no new hard-to-reverse action, fits the ask-then-act shape `mkr-merge` already has.
  This ADR does not need to authorize that half; it's implemented directly, no architecture change.
- **Conflict resolution and branch deletion** are new, automated, hard-to-reverse-*adjacent*
  actions that don't fit `mkr-merge`'s existing design, which — per `specs/M4_Audit_Spec.md`'s
  "never merges unprompted" principle and CLAUDE.md's "MUST ASK FIRST" rule for anything touching a
  protected branch — only ever *asks* before touching one. An agent that silently resolves a merge
  conflict can silently discard one side's real change; an agent that deletes a branch removes the
  one thing that makes a bad merge recoverable without reflog archaeology. Both need their own
  decision before `mkr-merge` gains either capability.

## Decision

**Conflict resolution: propose-and-ask, never auto-resolve.** Before step 6 (execute the merge),
`mkr-merge` dry-runs the merge (`git merge-tree`, the same no-working-tree-touched mechanism
`reviewrecord.sh`'s own merge-commit verification already uses elsewhere in this repo) against the
target protected branch. A clean result proceeds as today. A conflicting result stops immediately —
`mkr-merge` states which files conflict, what each side changed, and a specific proposed
resolution — but never applies it. The human must approve that exact proposal, in this session, the
same explicit-go-ahead discipline step 5 already requires for the merge itself; approving the merge
in step 5 never counts as also approving a conflict resolution proposed under this step, since
they're different decisions with different consequences.

**Branch deletion: a separate ask, after a successful merge, never bundled into the merge
confirmation.** Once step 6's merge has actually happened (and, on the `gh` path, actually pushed —
never for the local `git merge --no-ff` fallback, where deleting the source branch before its
merge commit is even pushed would strand that commit), `mkr-merge` asks a second, explicit
question: delete the now-merged source branch? A "yes" to step 5's merge question is not read as a
"yes" here — a human who wants the merge but wants to keep the branch (for a hotfix backport, an
audit trail, anything) must not have it deleted because they approved something else.

## Consequences

- `mkr-merge` gains two genuinely new capabilities without violating its own "never proceed
  unprompted" design: each new hard-to-reverse action gets its own explicit ask, not folded into
  an existing one.
- A merge conflict no longer silently blocks the session with nothing but "conflict, fix it
  yourself" — `mkr-merge` does the diagnostic work and proposes a concrete fix, but the human
  still decides.
- An adopter who wants branch auto-deletion on every merge (e.g. `gh pr merge --delete-branch`'s
  own default-on behavior elsewhere) does not get that from `mkr-merge` — every deletion is asked
  for, every time. This is a deliberate cost: the alternative (a config toggle to skip the ask)
  would let one project-level setting silently authorize a hard-to-reverse action, forever, with no
  per-instance human in the loop — exactly what CLAUDE.md's "MUST ASK FIRST" rule for a protected
  branch exists to prevent.
- The `git merge-tree` conflict dry-run adds one more git subprocess call to `mkr-merge`'s own
  preflight, before the merge itself — negligible cost, no working tree or index touched (matching
  `reviewrecord.sh`'s own established use of the same flag).
