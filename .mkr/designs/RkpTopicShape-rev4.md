# Design review — RkpTopicShape rev 4

**Reviewers.** Two independent fresh agents, re-run (unlike G4's re-review, no per-file scoping —
both simply re-read the whole of §6/§7/§8 again), each briefed on exactly what they'd missed at G3
rev 3 (a hostile `MKR_RKP_TOPICS` token was never actually tested against the "same trust boundary"
claim), so they'd apply the right scrutiny this round.

mkr-design-reviewer: NOT READY (1)
mkr-architecture-reviewer: READY

**Scope.** `specs/RkpTopicShape_Spec.md`, rev 4, §6/§7/§8. Changed since rev 3 (G4 security finding,
not a G3 finding): AD-3 (§6) corrected — declared tokens are now validated as bare filenames before
any write, with a failing token refused and reported by name; §7's contract and `SKILL.md`-content
list updated to match; new AC7.

`mkr-architecture-reviewer` adversarially re-tested the fix against the exact hostile example G4
cited (`../../../.github/workflows/pwn.yml`) and several variants (absolute paths, dotfiles,
encoded-traversal tokens), and confirmed the "no `/`" constraint is structurally sufficient — a
token with no path separator cannot resolve outside its containing directory, and the containing
directory (`docs/rkp/`) is still fixed and unparameterized. Confirmed the fix genuinely closes the
gap rather than relocating it, and that AD-3 now honestly states the invariant is prose-enforced
(no hook-based technical enforcement exists in this bash/Markdown stack) rather than overclaiming
code-level enforcement that doesn't exist. `READY`.

## Finding 1 — blocking, confirmed — the validation rule wasn't threaded through §7's other
list-consuming behaviors

`mkr-design-reviewer` found that while the write-step validation itself is correctly specified, §7's
"Non-empty" bullet still makes four other claims about a declared list in the same breath —
`README.md`'s doc-list table "lists exactly this list," single-doc refresh's scope-hint validity
"valid iff it's in this list," partial bootstrap's missing-vs-present enumeration, and bootstrap/
full-package reporting — none of which are qualified against the new possibility that a listed
token gets refused rather than written. Two implementers reading §7 as written could reasonably
diverge: one shows a refused entry as a broken `README.md` row; another silently drops it; a third
treats a refused-but-listed scope-hint target as "unrecognized" rather than "refused." This is a
gap the rev-4 fix itself introduced — before token validation existed, every declared entry could
safely be assumed to "unconditionally apply," so no such ambiguity existed at rev 3.

**Not fixed in this round** — routed back to the spec for rev 5 (see rev 5's own G3 re-review
record for the resolution).

**Findings not pursued further.** None.

**Verdict.** NOT READY (1 blocking)
