---
description: Run phase 9's ground step - spawn mkr-auditor against a spec's acceptance criteria and a real commit, and record a grounding-audit verdict.
---

Run the `mkr-audit` skill against the spec named (default: the newest `ACCEPTED` spec on this
branch) and the commit named (default: `HEAD`).

Invariant this command exists to state, not to re-implement: `mkr-auditor` must run in a genuinely
fresh context, with no memory of building the change — never paraphrase the spec's claims to it,
never share what you expect it to find. It has `Bash`, unlike the read-only G3/G4 reviewer agents,
because grounding means reproducing claims, not just reading them. A `FAIL` does not block
anything mechanically — it is evidence for whoever is deciding whether the change is actually
done, the same way a Definition of Done checklist is.
