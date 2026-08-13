# Design review — RkpTopicShape rev 2

**Reviewers.** Two independent fresh agents, spawned in parallel, neither aware of the other's
findings until each had formed its own judgment.

mkr-design-reviewer: NOT READY (1)
mkr-architecture-reviewer: READY

**Scope.** `specs/RkpTopicShape_Spec.md`, rev 2, §6/§7/§8.

## Finding 1 — blocking, confirmed — no defined behavior for a present-on-disk doc no longer in `MKR_RKP_TOPICS`

§7 specifies what happens when a listed filename is missing on disk (partial bootstrap: treated as
a from-scratch write for that entry) but never specifies the inverse: a file physically present
under `docs/rkp/` that is *not* (or no longer) named in the declared list. This is a real, foreseeable
state, not a corner case — it's exactly AD-1's own motivating example (a repo resplitting/renaming
docs, e.g. moving `02-data-model.md`'s subject into `03-db-design.md`) applied to a
`MKR_RKP_TOPICS` edit made after the shape was first declared, or a repo switching from the default
signal-derived table to a declared list that drops a previously-created doc. The default mode has a
named answer for the analogous situation (the present-conditional-doc signal recheck reports "no
longer applicable" when a present doc's signal disappears) — AD-2 correctly says that recheck
doesn't run for declared topics, but leaves no replacement behavior for this case. Two implementers
reading §7 as written could reasonably diverge: silently ignore the file forever, flag it for
review, or treat it as an error.

**Fix, applied in spec rev 3:** §7's `MKR_RKP_TOPICS` contract gains one explicit rule: a
`docs/rkp/` file present on disk but not in a non-empty `MKR_RKP_TOPICS` is left untouched and
unreported by any `mkr-rkp` run — the same "never deletes, human decision, not silent" posture the
present-conditional-doc signal recheck already takes for its own no-longer-applicable case (per
`SKILL.md`'s existing "It never deletes the file itself... a human decision, not a silent one"), and
consistent with §3's existing "adopter-authored list contents get no validation" trust boundary —
reconciling a dropped/renamed entry against what's actually on disk is the adopter's own call, not
something this skill infers. §12 task 5a is updated to include writing this rule alongside the rest
of the declared-shape subsection; a fourth mutation-resistant assertion (`TC-RKP-17e`) is added to
§9's `TC-RKP-17` entry to cover it.

**How verified:** re-read the fix against the design-reviewer's exact framing — the new rule directly
answers "what happens to a present-but-undeclared file" without inventing new mechanism (no new
signal, no new recheck pass), and stays consistent with AD-2/AD-3/AD-4's existing "declared topics
are the adopter's own fiat, `mkr-rkp` never second-guesses them" logic already in the spec.

## Finding 2 — non-blocking, confirmed — default-mode-only scoping of the "fixed topic→number map" sentence

`SKILL.md`'s pre-existing "Numbering is a fixed topic→number map, never a renumbered gap-filler"
sentence sits in the same section the new declared-shape subsection is inserted after, and isn't
explicitly called out as default-mode-only the way AD-2's signal-exclusion/recheck non-application
is. Likely already covered by §7's general "substitute the declared list wherever this file says
'the topic table above'" framing, but left as-is rather than adding a redundant clause — the general
substitution framing is the same mechanism that already resolves every other default-mode-specific
sentence in that section, and singling out just this one risks implying the others need the same
treatment when they don't.

## Finding 3 — non-blocking, confirmed — `README.md`'s doc-list table during partial bootstrap under a declared shape

Whether `README.md`'s table lists a declared-but-not-yet-created doc mid-partial-bootstrap, or only
entries with a file already on disk, isn't made fully explicit. Low risk — `README.md` is written
last per the existing Bootstrap procedure (`SKILL.md`: "Write `README.md` last, once the other docs
exist... describe the finished package, not a plan for one"), which already answers this by
construction: by the time `README.md` is written, every doc in scope for that bootstrap run exists.
Left as-is; the existing procedural ordering already resolves it without a spec change.

## Finding 4 — non-blocking, confirmed — declared filenames as write-path components

Unlike `MKR_SPEC_EXTRA_SECTIONS`/`MKR_PLAN_MANDATORY` tokens (never write-path components),
`MKR_RKP_TOPICS` tokens become filenames `mkr-rkp` writes under `docs/rkp/` — a token containing
`../` isn't addressed in §6–§8. Same trust level the rest of `.mkr/config`-driven, `SKILL.md`-guided
agent judgment already carries (§3 already declines to validate list contents at all), not a new
boundary the architecture reviewer's own checklist requires naming — but worth removing the
ambiguity for whoever implements this.

**Fix, applied in spec rev 3:** AD-3 gains one clause: "declared filenames are trusted the same as
any other adopter-authored config content — no path-escape check is performed, the same trust
boundary §3 already states for the rest of a declared list's contents."

**Findings not pursued further.** None.

**Verdict.** NOT READY (1 blocking)
