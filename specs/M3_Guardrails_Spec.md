# Guardrail hooks: secret scanning, branch protection, ADR-collision, spec-gate, stop-checks, audit log

## Intent

Six Claude-Code tool-hooks give the loop mechanical, offline-capable enforcement instead of prose:

- **BLOCK tier** (three hooks, work offline, no CI required): staging a secret, pushing to a
  protected branch, creating a colliding ADR number.
- **ASK tier** (one hook): a nudge, not a block, when source work starts with no accepted spec on
  the branch.
- **Stop-tier**: a session cannot silently end with the test suite red.
- **Passive**: every completed tool call is logged, never blocked.
- CI (`mkr-gate.yml`) re-enforces the test suite, ADR uniqueness, and the review-record
  requirement, so a `--no-verify` push or a machine without the hooks installed doesn't skip
  enforcement.
- Hook I/O is dependency-free bash (`grep`/`sed` against known shallow JSON fields, never a
  general parser) — no `jq`/`python3`/`node` required by any hook script.

## Scope

**In scope**
- `.claude/hooks/lib/hookio.sh` — shared, dependency-free hook-I/O library (stdin field reads,
  `PreToolUse`/`Stop` JSON output, statement splitting).
- `.claude/hooks/scripts/secret-guard.sh`, `branch-guard.sh`, `id-collision-guard.sh`,
  `spec-gate.sh`, `stop-checks.sh`, `audit-log.sh`.
- `.claude/settings.json` — wires all six hooks to their events/matchers.
- `.github/workflows/mkr-gate.yml` — CI enforcement.
- `tests/hooks_test.sh` — fixture-driven true-positive/false-positive cases per hook.
- `.mkr/config`'s `MKR_TEST` widened to run the whole test suite.

**Out of scope**
- GitHub branch-protection *rules* (requiring PRs into `main`, requiring the CI check to pass) —
  a one-time human action in GitHub's own repo settings.
- Reading these guards' state as part of a merge decision.
- Distributing this `settings.json`/`hooks/` tree into a fresh adopter repo.
- A configurable/pluggable secret-pattern list — a fixed pattern set only, not a config knob.
- Recording `PreToolUse` denials (a full audit trail of blocked, not just completed, actions) — a
  disclosed gap, not built.

## Architecture & key decisions

```
.claude/
├── settings.json                      wires every hook below
└── hooks/
    ├── lib/
    │   ├── config.sh                  sourced by every script below
    │   └── hookio.sh                  shared jq-free hook I/O
    └── scripts/
        ├── pre-push-review-guard.sh   git pre-push hook (unrelated mechanism)
        ├── secret-guard.sh            PreToolUse/Bash   — BLOCK
        ├── branch-guard.sh            PreToolUse/Bash   — BLOCK
        ├── id-collision-guard.sh      PreToolUse/Write  — BLOCK
        ├── spec-gate.sh               PreToolUse/Write|Edit — ASK
        ├── stop-checks.sh             Stop              — block-to-continue
        └── audit-log.sh               PostToolUse/*     — never blocks

.github/workflows/mkr-gate.yml          CI half of the review/branch-protection gates
.mkr/audit.jsonl                        audit-log.sh's output
```

- `PreToolUse` hooks deny/ask via `{"hookSpecificOutput": {"hookEventName": "PreToolUse",
  "permissionDecision": "allow"|"deny"|"ask", "permissionDecisionReason": "..."}}`. `Stop` hooks
  force continuation via `{"decision": "block", "reason": "..."}`. `.claude/settings.json`
  (committed) and `.claude/settings.local.json` (gitignored, personal) merge rather than override.
- **Hook I/O is jq-free.** `hookio.sh` reads only the specific, shallow fields each hook needs
  (`tool_name`, `tool_input.command`, `tool_input.file_path`) via anchored `grep -o`/`sed`, and
  emits fixed-shape JSON via `printf` plus a small string-escape helper — never a general parser.
- **Statement splitting is a quote-aware character walk, not a regex.** `hookio_split_statements`
  treats `;`/`&`/`|`/an unquoted newline as separators only outside quotes and only when not
  backslash-escaped, walking the string one character at a time with quote-state tracking — a
  naive character-class-exclusion split cannot tell a real separator from the same character
  inside a quoted argument (e.g. a commit message) or from ordinary redirection syntax (`2>&1`,
  `>&2`). Output is NUL-terminated, since a single logical statement can legitimately contain a
  raw newline (a multi-line quoted string, or a backslash-newline continuation). **Disclosed scope
  boundary**: not a full shell-grammar parser — does not understand command substitution,
  arithmetic expansion, ANSI-C quoting, here-documents, or shell control-flow keywords. A
  separator inside one of those constructs is not guaranteed to be recognized as non-separating —
  a backstop, not a substitute for human judgment.
- **`branch-guard.sh` blocks push only, not a local commit on a protected branch** — matches the
  gate's stated job ("push to protected"); a local commit on a protected branch is handled at the
  agent-preflight layer instead, not duplicated as a hard block.
- **`spec-gate.sh` ships wired in the one committed `settings.json`, but is inert until
  `.mkr/config` exists** — the script checks `config.sh active` first and allows silently on a
  fresh, un-adopted clone, so a first `git clone` of this template is never surprised by an `ask`.
- **`spec-gate.sh`'s "no approved spec" check is branch-scoped, not precise**: it checks
  mechanically whether *this branch* has added a spec file (new or modified under
  `MKR_SPECS_DIR`, since the merge-base with the first entry of `MKR_PROTECTED_BRANCHES`) whose
  own `Status` line reaches `ACCEPTED` — it cannot judge whether that spec actually covers the
  edit in question, and it never fires at all for a path already under
  `MKR_SPECS_DIR`/`MKR_ADR_DIR`/`docs/`/`tests/`/`README.md`/`CLAUDE.md`/`VERSION`.
- **`audit-log.sh` is `PostToolUse`-only**; it does not record what a `PreToolUse` guard denied. A
  denial is already visible to the user directly via the guard's own reason text in the same
  session — a disclosed, not a hidden, gap.
- **`.mkr/config`'s `MKR_TEST` widens to run the whole suite** (`tests/config_test.sh` and
  `tests/mkr_artifact_test.sh`), since `stop-checks.sh` and `mkr-gate.yml` both read it and would
  otherwise silently exercise only part of the suite.

## Interfaces / contracts

**`secret-guard.sh`** — `PreToolUse`, matcher `Bash`. Scans a `git add`/`commit` invocation's
about-to-be-staged content. Each git statement is classified **wildcard** (`-A`/`.`/`--all`, no
path arguments, or `commit -a`/`--all`/a bundled short-flag cluster containing `a` such as `-am`)
— scans staged, unstaged, and untracked content broadly — or **targeted** (`git add <explicit
paths>`) — scans only those paths' working-tree content. Scanned content is checked against a
**fixed**, non-configurable pattern set:

| Pattern | Matches |
|---|---|
| `AKIA[0-9A-Z]{16}` / `ASIA[0-9A-Z]{16}` | AWS access key ID |
| `-----BEGIN (RSA \|EC \|OPENSSH \|DSA \|)?PRIVATE KEY-----` | PEM private key header |
| `gh[pousr]_[A-Za-z0-9]{36}` | GitHub token |
| `xox[baprs]-[A-Za-z0-9-]{10,}` | Slack token |

Any match → `deny`, reason names the pattern class (never the matched secret text) and the file.
No match → `allow`, silently. **Disclosed residual limitations**: a targeted add's path
extraction is unquoted whitespace word-splitting, so a filename containing a space or a
shell-variable-indirected path is not resolved and scanned by name (though a wildcard
add/commit still catches it via the broad scan); and every check requires the literal token
`git` adjacent to `add`/`commit` — a deliberately self-evasive wrapper (e.g. a shell function
renaming `git`) is not recognized. Both are named limits, not chased with a full shell/command
parser — a backstop, not the only check.

**`branch-guard.sh`** — `PreToolUse`, matcher `Bash`. Resolves the push's target branch from an
explicit refspec, or the current branch for a bare `git push`. If the resolved name is in
`MKR_PROTECTED_BRANCHES` → `deny`, reason names the branch and points at opening a PR instead;
otherwise → `allow`. Exotic refspecs (globs, uncommon flags) are a known limitation: anything the
parser can't confidently resolve to a branch name is **unresolved and allowed**, never a false
`deny` — fails open on parse uncertainty, since this is a backstop, not the only check.

**`id-collision-guard.sh`** — `PreToolUse`, matcher `Write`. Covers `MKR_ADR_DIR` plus any
directory listed in `MKR_ID_DIRS` (a project-declared extension point for other NNNN-numbered
artifact types, e.g. a migrations directory — same numbering convention, not ADR-specific). If the
written path doesn't match `<dir>[0-9]{4}-.*$` for any covered `dir`, `allow` immediately.
Otherwise: `deny` (naming the existing file) if the four-digit prefix collides with an existing
file in that directory — checked against the local working tree first, then, best-effort, against
`origin/main` (a bounded `git fetch`; any failure — no `origin` remote, no network, a timeout —
falls back to the local-only result rather than denying). Else `allow`.

**`spec-gate.sh`** — `PreToolUse`, matcher `Write|Edit`.
1. `config.sh active` returns inactive → `allow`, silently.
2. Path under `MKR_SPECS_DIR`/`MKR_ADR_DIR`/`docs/`/`tests/`/`README.md`/`CLAUDE.md`/`VERSION` →
   `allow`.
3. No resolvable protected-branch base, or not inside a git work tree → `allow` (fail open).
4. Any spec file touched on this branch since the merge-base whose content contains a line
   matching `**Status**...ACCEPTED` → `allow`.
5. Else → `ask`, reason: no spec on this branch has reached `ACCEPTED` yet.

**`stop-checks.sh`** — `Stop`, no matcher. No changes at all → `allow`. Changed paths none
test-relevant (`tests/`, `.claude/hooks/`, `.claude/agents/`, `.claude/skills/`,
`.claude/commands/`, `specs/`) → `allow`. `MKR_TEST` unset → `allow` (never blocks an
un-configured project). Otherwise runs `MKR_TEST`; passes → `allow`; fails → blocks the stop,
reason includes the command and its tail output.

**`audit-log.sh`** — `PostToolUse`, matcher `*`. Appends one JSONL line per completed tool call to
`.mkr/audit.jsonl` (creating the file/directory if absent):

```json
{"ts":"<UTC ISO-8601>","session_id":"<from stdin>","tool_name":"<from stdin>","summary":"<command or file_path, truncated to 200 chars>"}
```

Always `allow` — this hook cannot deny. A write failure is swallowed rather than surfaced as a
block; observability must never itself become a new way to block work.

**`.claude/settings.json`** wires: `PreToolUse`/`Bash` → `secret-guard.sh` + `branch-guard.sh`;
`PreToolUse`/`Write` → `id-collision-guard.sh` + `spec-gate.sh`; `PreToolUse`/`Edit` →
`spec-gate.sh`; `PostToolUse`/`*` → `audit-log.sh`; `Stop` → `stop-checks.sh`.

**`.github/workflows/mkr-gate.yml`** — triggers on `pull_request` and `push` to any protected
branch. One job: (0) if `MKR_SETUP` is non-empty, run it first — a repo-declared bootstrap step
(installing workspace packages, selecting a runtime version, etc.) a real monorepo needs before
any of the commands below mean anything; the seam this workflow otherwise didn't have, since each
`MKR_*` command had to be fully self-sufficient; (1) resolve and run each of
`MKR_TEST`/`_COVERAGE`/`_TYPECHECK`/`_LINT`/`_BUILD` that is non-empty, fail on any nonzero exit;
(2) fail if any ADR four-digit prefix repeats (a CI backstop for a clone or commit made outside
the hooks); (3) fail unless a review record exists for the target commit's fixed 7-character short
SHA — the PR head SHA on a `pull_request` run, falling back to the push SHA on a `push` run (never
the synthetic merge commit `pull_request` runs otherwise expose).

## Data model

Two new `config.sh` contract variables. `MKR_ID_DIRS` — space-separated, empty by default,
directories `id-collision-guard.sh` also numbers `NNNN-*` collisions against, beyond the always-
covered `MKR_ADR_DIR`. `MKR_SETUP` — a single command, empty by default (opt-in), run by
`mkr-gate.yml` before the configured `MKR_TEST`/`_COVERAGE`/`_TYPECHECK`/`_LINT`/`_BUILD` commands
— a repo's own bootstrap step, not run at all when empty (the existing single-command-repo
behavior is unchanged). Every other hook consumes existing published names
(`MKR_PROTECTED_BRANCHES`, `MKR_ADR_DIR`, `MKR_SPECS_DIR`, `MKR_REVIEWS_DIR`,
`MKR_TEST`/`_COVERAGE`/`_TYPECHECK`/`_LINT`/`_BUILD`, and the `active` CLI verb).

One project-fact edit: `.mkr/config`'s `MKR_TEST` widens to run both test suites.

One new artifact shape, not a config variable: `.mkr/audit.jsonl` — one JSON object per line,
fields `ts` (UTC ISO-8601 string), `session_id` (string), `tool_name` (string), `summary`
(string, ≤200 chars). Append-only, no schema version field.
