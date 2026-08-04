# Code review: mkr-code-review, the two reviewer agents, and the G4 gate

## Intent

- `/mkr-code-review` is the independent check between "the code is written" and "it's pushed."
- It spawns `mkr-code-reviewer` and `mkr-security-reviewer` — two fresh-context agents with different lenses, neither aware of the other's findings until both have formed independent judgments — against the current diff.
- It records a verdict to `.mkr/reviews/<sha>.md` in a defined shape.
- A local `pre-push-review-guard.sh` warns, never blocks, if a push is about to happen with no matching review record.

## Scope

**In scope**
- `.claude/skills/mkr-code-review/SKILL.md` + `.claude/commands/mkr-code-review.md` — resolves the diff under review, spawns both reviewer agents, collects their verdicts, decides the overall gate result, writes the review record, decides re-review scope on a later revision.
- `.claude/agents/mkr-code-reviewer.md` — fresh context, read-only tools, correctness/reuse/standards/simplicity/boundaries lens.
- `.claude/agents/mkr-security-reviewer.md` — fresh context, read-only tools, adversarial security lens.
- `.claude/hooks/scripts/pre-push-review-guard.sh` — a real git `pre-push` hook that warns (never blocks) if no review record matches the SHA about to be pushed.
- The review record format — codified as the shape both the skill and a structural test check against.
- `.claude/hooks/lib/config.sh` — adds `MKR_GATE_REVIEW`, `MKR_BOUNDARIES`, and `MKR_REVIEW_VERDICT_STRING`.
- `CLAUDE.md` — adds the missing "review gate (G4)" row to the Gate owners table.

**Out of scope**
- CI hard-enforcement of "a review record exists for the merge commit's parent" — this milestone ships the WARN half only.
- `settings.json` wiring for the other guards (`secret-guard.sh`, `branch-guard.sh`, `id-collision-guard.sh`, `spec-gate.sh`) — a different mechanism (Claude-Code tool-hooks) from a git `pre-push` hook.
- `mkr-merge`, the grounding audit's tie-in to a review record.
- `mkr-design`, `mkr-design-reviewer`/`mkr-architecture-reviewer`, formal G3 tooling.
- Judging whether a reviewer agent's findings are correct, as opposed to well-formed.
- Distribution, `mkr-detect`, going public.

## Architecture & key decisions

- Two reviewers, symmetric with the (future) design gate's pair: different lenses, both must return `READY`, run in parallel, neither aware of the other's findings until each has formed its own judgment.
- Re-review scope on a changed HEAD: a reviewer is re-run only if (a) it had a blocking finding on the prior round, or (b) the new diff touches a file or line range outside what its prior `READY` verdict actually covered. A stale `READY` is never silently trusted against code it never saw. The record's own `Scope` section is what makes "what did this reviewer actually see" checkable.
- Runs locally, pre-push, as a genuine git `pre-push` hook — a different mechanism from the Claude-Code `settings.json` tool-hooks that wire the other guards, so it needs no `settings.json` entry to fire on a raw `git push`. It warns only; a hard stop is a separate CI check, not this hook.
- `MKR_GATE_REVIEW` joins the `MKR_GATE_*` family in `config.sh`, one per named gate in `CLAUDE.md`'s Gate owners table; the table's previously-missing G4 row is added.
- `MKR_BOUNDARIES` lets a project declare its own architectural boundaries/seams (e.g. "domain/ never imports adapters/ directly") for `mkr-code-reviewer`'s Boundaries/Seams check — project-configurable the same way `MKR_RISKY_PATHS` already is, not hardcoded to one project's module layout. Empty (the default) means the check is skipped, not silently failed.
- `mkr-code-review` cannot review the spec that builds it, since the skill and both agents don't exist until the spec is implemented — G1 for this spec is a human reading it directly.

## Interfaces / contracts

### `mkr-code-review` (skill + command)
Input: the current diff — by default, the working tree against the branch's merge-base with the first protected branch (i.e., what would be pushed). Steps:
1. Resolve the diff and its target SHA (the commit about to be pushed, or `HEAD` if uncommitted).
2. Spawn `mkr-code-reviewer` and `mkr-security-reviewer` in parallel, each given the diff, the spec it implements, and no memory of having built either.
3. Overall gate result is `READY` only if both agents return `READY`; otherwise `NOT READY`, with findings from both merged into one record and renumbered across the merge, not restarted per reviewer.
4. Write (or update, on a re-review) `.mkr/reviews/<short-sha>.md`. A short SHA is a fixed 7-character prefix of the full commit SHA — not git's own variable-length `--short` abbreviation — so the hook (below) can compute the expected filename independently, with no shared state.
5. Blocking findings route back to implementation; the skill never attempts fixes itself.

### `mkr-code-reviewer` / `mkr-security-reviewer` (agents)
- Tools: `Read, Grep, Glob` only — read-only, cannot edit the diff, the codebase, or the record.
- Input: the diff under review, the spec it implements, and — for a re-review — the prior round's record, so each agent can tell whether its own earlier finding was actually addressed.
- `mkr-code-reviewer`'s lens: correctness against the spec's acceptance criteria, reuse, standards, simplicity, and (when `MKR_BOUNDARIES` is configured) boundaries/seams.
- `mkr-security-reviewer`'s lens: adversarial — assume the diff is hostile input until proven otherwise; check anything that parses, evals, sources, or execs untrusted content; verify safety claims by reproducing them.
- Output: `VERDICT: READY` or `VERDICT: NOT READY (<n> blocking)` plus a findings list, each citing a file and line range.

### Review record format
Written to `<MKR_REVIEWS_DIR><short-sha>.md`. Required shape, in order:
1. `# Code review — <sha> (<one-line description>)`
2. **Reviewers.** Names both agents, states they ran independently and in parallel, states each one's lens, and states each one's own sub-verdict explicitly.
3. **Scope.** Exactly what was reviewed — files, commit range, and (on a re-review) what changed since the prior round.
4. One `##` per finding — zero or more. A `READY` record with no findings omits this section entirely. Each finding states: blocking or non-blocking, confirmed or plausible, the defect, and — for a blocking finding — the fix and how it was independently verified.
5. **Findings not pursued further** — anything raised and explicitly declined, with why.
6. **Verification discipline** — a closing statement of what was independently reproduced versus taken on the reviewers' word.
7. **Verdict.** `READY` or `NOT READY (<n> blocking)`, dated. Must equal `READY` if and only if both sub-verdicts stated in §2 are `READY` — a deterministic, checkable rule.

### `pre-push-review-guard.sh`
A git `pre-push` hook (bash). Resolves the SHA(s) about to be pushed from stdin, takes the first 7 characters of each (the fixed-length short SHA), and checks whether `<MKR_REVIEWS_DIR><short-sha>.md` exists for each and satisfies `_reviewrecord_is_ready` (an anchored line-prefix match against `MKR_REVIEW_VERDICT_STRING`, default `VERDICT: READY` — configurable so a project can customize its review record's own passing-verdict literal without patching `reviewrecord.sh`). If any is missing or not ready, prints a `WARN:` line naming the missing record and exits 0 — it never blocks the push. Sources `config.sh` for `MKR_REVIEWS_DIR` and (via `reviewrecord.sh`, which self-sources `config.sh` defensively if not already loaded) `MKR_REVIEW_VERDICT_STRING`.

**Installing it as a real git hook.** `install.sh` symlinks `.git/hooks/pre-push` to the shipped `pre-push-review-guard.sh` (found among the enumerated `.claude/` paths by basename, never by a hardcoded `.claude/hooks/scripts/` literal — TC-M6-14a's static check forbids install.sh from referencing that path directly) whenever the target's `.git/hooks/pre-push` is absent, already a symlink to that same file, or `--force` is given. An adopter's own pre-existing, different `pre-push` hook is refused like any other divergent path, backed up before an `--force` overwrite. A configured `core.hooksPath` (an adopter already routing hooks elsewhere) is left alone entirely — this only ever touches the default `.git/hooks/` location.

## Data model

One new `config.sh` variable, following the existing `MKR_GATE_*` shape:

| Variable | Default | Consumed by | For |
|---|---|---|---|
| `MKR_GATE_REVIEW` | empty — project-set only, no shell default, matching the other `MKR_GATE_*` names | `mkr-code-review`, `CLAUDE.md`'s Gate owners table | G4's named owner |
| `MKR_REVIEWS_DIR` | `.mkr/reviews/` (already published) | `mkr-code-review` (write), `pre-push-review-guard.sh` (read) | where records live |
| `MKR_BOUNDARIES` | empty — no boundaries declared, matching `MKR_RISKY_PATHS`'s shape | `mkr-code-reviewer` (read, CLI mode) | project-declared architectural boundaries/seams for the Boundaries/Seams check |
| `MKR_REVIEW_VERDICT_STRING` | `VERDICT: READY` | `reviewrecord.sh` (`_reviewrecord_is_ready`) | the literal line-prefix a review record must carry to count as a passing verdict |
