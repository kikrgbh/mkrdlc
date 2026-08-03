---
description: Build or refresh the Repo Knowledge Package (docs/rkp/) - a refreshable, grounded knowledge-transfer doc set. Derives which doc topics apply per-repo from a signal, never a fixed list.
---

Run the `mkr-rkp` skill against the target path named (default: the current working directory's
repo root) and the scope named (default: resolved from whether `docs/rkp/` exists yet and, if it
does, whether anything looks stale — see the skill's own scope-selection rules).

Invariant this command exists to state, not to re-implement: `mkr-rkp` re-derives every fact from
source each time it runs — never from anything recalled earlier in the same session, even when
refreshing a doc it already touched this session. It never writes anywhere outside `docs/rkp/`,
and it never invents a doc topic the target repo doesn't actually show a signal for.
