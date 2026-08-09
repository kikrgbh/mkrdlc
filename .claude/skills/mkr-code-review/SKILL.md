---
name: mkr-code-review
description: Runs G4's audit step - spawns mkr-code-reviewer and mkr-security-reviewer (fresh context, parallel, independent) against the current diff, then writes a review record to MKR_REVIEWS_DIR in the specs/M2_CodeReview_Spec.md §7.3 shape. Use after verify (phase 6), before a push, on any non-Quick change.
---

# mkr-code-review — phase 7's G4 audit

`mkr-code-review` never forms its own judgment about the diff — that's the two reviewer agents'
job, each run in a fresh context specifically so neither has any memory of writing the code or any
knowledge of the other's findings. This skill's job is orchestration and recording, in this order.

## 1. Resolve the diff and the target SHA

The diff is the working tree against the current branch's merge-base with the first entry of
`MKR_PROTECTED_BRANCHES` (via `config.sh get MKR_PROTECTED_BRANCHES`, CLI mode) — i.e., what would
be pushed — unless the caller names a specific commit range. The target SHA is the commit about to
be pushed, or the current `HEAD` if the diff is still uncommitted work. Its **short SHA** — used
throughout this skill and by `pre-push-review-guard.sh` — is always the first 7 characters of the
full SHA, a fixed length, not git's own variable-length `--short` abbreviation (which can grow
past 7 as commit count grows); fixed length is what lets the hook compute the expected filename
independently, with no shared state, and it matches this repo's own `.mkr/reviews/` precedent
(`4e507dd.md`, `6a08c95.md`, `7c0e242.md`).

## 2. Resolve `MKR_REVIEWS_DIR` and `MKR_BOUNDARIES`

Run `config.sh get MKR_REVIEWS_DIR` (CLI mode) to place the record. Also run `config.sh list
MKR_BOUNDARIES` (CLI mode) — `mkr-code-reviewer`'s Boundaries/Seams check needs this value and has
no shell access of its own to resolve it. Both are the caller's job for the same reason: the
agents you spawn in step 4 can't run `config.sh` themselves.

## 3. Is this a first review or a re-review?

Check whether `<MKR_REVIEWS_DIR><short-sha-of-the-previous-round's-commit>.md` exists for an
ancestor of the current diff (i.e., a prior round already ran on an earlier revision of the same
change).

- **First review:** spawn both `mkr-code-reviewer` and `mkr-security-reviewer` on the diff.
- **Re-review** (specs/M2_CodeReview_Spec.md §6 AD-2): re-run a reviewer if **either** (a) that
  reviewer had a blocking finding in the prior round, **or** (b) the new diff touches a file or
  line range that reviewer's prior round never covered (check the prior record's own `Scope`
  section against the new diff — don't assume). A reviewer meeting neither condition keeps its
  prior round's verdict and findings rather than being re-run for no new information. State in the
  record which reviewers actually ran this round and why (§7.3 `Scope`).

## 4. Spawn the reviewer(s)

Use the Agent tool. When both must run, spawn them **in the same message** so they run in parallel,
each given: the diff, the path to the spec it implements, the `MKR_BOUNDARIES` value from step 2
(`mkr-code-reviewer` only needs this — its own Boundaries/Seams check — but passing it to both is
harmless), and — only if that specific reviewer is being re-run — the prior round's record, so it
can check whether its own earlier finding was actually addressed rather than take the new diff's
claim on faith. Do not summarize the diff's intent to either agent, do not mention what the other
agent is checking, and do not pre-empt either verdict.

## 5. Collect verdicts and merge findings

Each agent ends with `VERDICT: READY` or `VERDICT: NOT READY (<n> blocking)` plus a findings list.
Overall gate result is `READY` only if **both** agents' verdicts (current-round or carried-over,
per step 3) are `READY`; otherwise `NOT READY`, with the total blocking count being the sum across
both. When merging both agents' findings into the one record (§6), renumber them into a single
running sequence — `Finding 1, 2, 3…` across both reviewers combined, not two separate lists each
restarting at 1 — since the record is one artifact, not two stapled together.

## 6. Write the review record

Write (first review) or replace (re-review — the record is keyed to the SHA about to be pushed
now, not the prior round's SHA) `<MKR_REVIEWS_DIR><short-sha>.md` in this exact shape
(specs/M2_CodeReview_Spec.md §7.3):

```
# Code review — <short-sha> (<one-line description of the change>)

**Reviewers.** Two independent fresh agents, spawned in parallel [or: re-run per AD-2, naming
which], neither aware of the other's findings until each had formed its own judgment.

mkr-code-reviewer: READY|NOT READY (<n>)
mkr-security-reviewer: READY|NOT READY (<n>)

**Scope.** <files/commit range reviewed; on a re-review, what changed since the prior round and
which reviewer(s) actually ran again>

[zero or more:]
## Finding <n> — <blocking|non-blocking>, <confirmed|plausible> — <one-line description>

<the finding, the fix if any, and how it was independently verified — not accepted from the
reviewer's prose alone>

## Findings not pursued further

<anything raised and explicitly declined, with why — or "None." if nothing was>

## Verification discipline

<what was independently reproduced vs. taken on the reviewers' own word>

## Verdict

VERDICT: READY|NOT READY (<n> blocking)
```

The two `mkr-*-reviewer: ` lines are this skill's own translation of each agent's raw
`VERDICT: READY`/`VERDICT: NOT READY (<n> blocking)` output into the record's per-reviewer
sub-verdict line — same vocabulary, without the word "blocking" (the count alone), so the record's
closing `Verdict` section is checkable against these two lines directly (specs/M2_CodeReview_Spec.md
§7.3 item 7): **the closing line must read `VERDICT: READY` if and only if both sub-verdicts above
are `READY`.** Never write a closing verdict that contradicts the two sub-verdicts stated in
`Reviewers` — that mismatch is exactly what `mkr-code-review`'s own structural test (TC-M2-11)
exists to catch, and it will be a defect in this skill's output if it happens.

A `READY` record with zero findings omits the `## Finding` section entirely (six sections total,
not seven with an empty body).

The closing line's exact literal is `config.sh get MKR_REVIEW_VERDICT_STRING` (CLI mode; default
`VERDICT: READY`) — `pre-push-review-guard.sh` matches against this, not a hardcoded string, so a
project that has customized it needs the record's closing line to actually say that, not the
default, or the guard will never recognize it as passing.

**Commit the record alone, in its own commit, touching nothing else.** `reviewrecord.sh`'s
parent-only fallback (the mechanism that lets a trailing commit "review" the commit before it,
since a commit can never name a file after its own not-yet-computed SHA) only matches when that
trailing commit's diff touches nothing outside `MKR_REVIEWS_DIR`/`MKR_SPECS_DIR`/`MKR_ADR_DIR`/
`MKR_AUDITS_DIR` — a deliberate
security boundary, not an arbitrary restriction, since a looser check would let unreviewed code
ride along with a legitimate-looking record. Before committing the record file, confirm nothing
else is staged or about to be swept in (`git status`; never `git commit -a`/`-am` here) — a record
committed alongside even one unrelated doc or code change satisfies neither the exact-match check
(this commit's own SHA isn't known yet) nor the fallback (the commit isn't record-only), and there
is no way to recover from inside that commit — only a further, genuinely separate trailing commit
containing just the record, named after the now-already-existing prior commit's SHA, can close the
gap afterward.

## 7. Route blocking findings

If the overall result is `NOT READY`, state which findings block and that they route back to
phase 5 (implement) per docs/DESIGN.md §2 — this skill does not attempt fixes itself, the same
read-only posture the two agents themselves have. The next `/mkr-code-review` invocation after a
fix lands is a re-review (step 3), not a fresh first review.
