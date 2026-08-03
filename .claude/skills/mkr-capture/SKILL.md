---
name: mkr-capture
description: Cross-cutting CAPTURE (docs/DESIGN.md §2) - appends a structured entry to MKR_CAPTURE_LOG for a correction or incident, and once the same class of mistake has recurred, states so explicitly and proposes a durable rule instead of logging silently forever. Use any time a human corrects the agent's approach, or an incident occurs, in any phase of the loop.
---

# mkr-capture — correction/incident → failure log → same class twice → a rule

`mkr-capture` never guesses whether a correction is worth recording — every correction or incident
gets logged, unconditionally. Its judgment is reserved for one narrower question: has this exact
*class* of mistake now happened more than once, in which case silence stops being acceptable and a
durable rule needs proposing.

## 1. Classify

Input: a short class slug (a category, not a one-off description — e.g. `stale-cross-ref`,
`undisclosed-deviation`, not "forgot to update section 9 line 3"), a one-line description, and,
optionally, the spec or commit it relates to.

## 2. Append

Resolve `MKR_CAPTURE_LOG` (`config.sh get MKR_CAPTURE_LOG`, CLI mode). Append one JSONL line,
matching `.mkr/audit.jsonl`'s own append-only shape (M3):

```
{"ts":"<ISO-8601>","class":"<slug>","description":"<one line>","ref":"<spec/commit, if applicable>"}
```

(`ref` omitted from the object entirely if not applicable — not written as an empty string.)

## 3. Count and threshold

Count existing entries in the log sharing this **exact** `class` (including the one just appended).

- **Count is 1** (first occurrence): log only. Report that this was recorded, and move on — nothing
  else to do yet.
- **Count is now 2 or more:** state this explicitly — "this class (`<slug>`) has now recurred `<k>`
  times" — and propose a durable rule: a `CLAUDE.md` non-negotiable, an ADR, or a specific skill/hook
  change that would have caught it the first time. The threshold is fixed at 2, matching
  `docs/DESIGN.md` §2's own literal wording ("same class twice → a rule") — not a project-configured
  number, since a single project has never yet had a real reason to want a different one.

## 4. What this skill does not do

It does not decide whether the proposed rule is adopted — that's the same human judgment every
other durable decision in this loop gets (an ADR still needs the same acceptance any other ADR
does; a `CLAUDE.md` change is still a diff someone reviews). `mkr-capture`'s job ends at proposing
the rule plainly, with the evidence (the recurring log entries) attached.
