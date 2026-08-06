# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/).

## [0.3.0] - 2026-08-06

Fixes the `MKR_WORKTREE_POLICY=enforced` bootstrap trap, adds a Bash-capable manifest-integrity
check to CI, and closes an unusually long chain of guardrail-hook hardening found across a
7-round G4 review (`.mkr/reviews/d52a627.md`) — plus several installer/skill-doc fixes reported
from a real adopt.

### Added
- `worktree-edit-guard.sh` exempts the one commit that first turns `MKR_WORKTREE_POLICY` on — a
  narrow, allowlist-only escape hatch (`git commit -m "<msg>"`, nothing else). Previously no
  commit could ever enable the policy from inside the shared checkout it was about to start
  protecting, since creating a worktree first didn't help either.
- `mkr-gate.yml` verifies `.claude/mkr-manifest` integrity in CI (`.claude/hooks/lib/
  manifestcheck.sh`) — recomputes every recorded file's SHA-256 and mode bits and fails the gate
  on drift; inert on a repo with no manifest. Neither reviewer agent can compute a hash or stat a
  mode bit itself, so nothing previously caught this class of drift.
- `install.sh --skip-git-hook` — never classifies or installs the `.git/hooks/pre-push` symlink,
  letting the `.claude/`+`.github/` file-drop path succeed on its own in an environment that
  restricts writes under `.git/hooks/` (sandboxed runners, some CI/agent harnesses).
- `mkr-code-review/SKILL.md` now explicitly requires the G4 review record be committed alone, in
  its own commit, touching nothing else — closing a recurring adopter failure mode where a mixed
  commit can never satisfy either the exact-match or parent-only-fallback lookup path.

### Fixed
- `mkr-gate.yml`'s ADR-uniqueness check no longer aborts the whole CI job for a fresh adopter with
  zero ADRs (the normal starting state) — a literal, unexpanded glob was reaching `ls` under this
  step's own `pipefail`.
- `.github/CODEOWNERS` is no longer shipped to adopters (`docs/adr/0007`) — its content is a real
  GitHub username specific to this repo, either meaningless or a silent review-ownership collision
  elsewhere; an adopter is advised to write their own instead of silently getting nothing.
- A blanket `.gitignore` rule now also gets one loud, aggregated "N file(s) would be silently
  gitignored" summary line, easy to miss before among 50+ individual per-file WARNs.
- `mkr-merge` step 4 states the zero-spec case explicitly (a branch with no spec files at all is
  Quick depth, matching `spec-gate.sh`'s own treatment) — distinct from "a spec exists but isn't
  `ACCEPTED`," previously undefined.
- `mkr-detect` now names when it can't find scripts at the target root but a matching marker
  exists one level down (a monorepo shape), instead of a silent, technically-correct blank report.
- `mkr-ship` documents the existing `MKR_DEPLOY` workaround for a `gh workflow run ...`-shaped
  deploy.
- `PULL_REQUEST_TEMPLATE.md` no longer hardcodes this repo's own test commands.

### Security
- `worktree-edit-guard.sh`'s bootstrap-commit exemption was hardened across a chain of TOCTOU
  bypasses, each found on re-review: the staged-index check it relies on is a snapshot taken
  before the triggering Bash tool call has actually run, so a compound command could smuggle
  unreviewed content into the same commit via `&&`-chaining, bare `&` backgrounding, `<(...)`
  process substitution, or forcing an attacker-controlled `$GIT_EDITOR`/`-c core.editor=`
  subprocess mid-commit (git does not hold the index lock across an editor invocation). The
  exemption now only ever applies to a command that is exactly `git commit -m "<msg>"`.
- The shared detection logic deciding whether a Bash statement contains a `commit`/`checkout`/
  `switch` worth checking (used by both `worktree-edit-guard.sh` and `worktree-collision-guard.sh`,
  which had independently duplicated the same pattern) silently skipped any statement where a flag
  other than `-C` sat between `git` and the subcommand, or where the subcommand arrived via a bash
  variable (`git $V`) — not the guards under-scrutinizing, but never seeing the statement at all.
  Deduplicated into a shared `procwalk_statement_has_git_keyword` and hardened against both. Found
  and fixed pre-release, during this release's own G4 review.
- `mkr-gate.yml`'s new manifest-integrity check refuses to follow a symlink anywhere in a
  manifest-recorded path — not just the final path component — before hashing it, closing a
  fork-PR-visible disclosure of an outside file's existence and content hash.
- Known, accepted limit on the above: these guards are text-based keyword scanning, not full
  shell/git semantics — a git alias, `eval`, a shell function, or git's own plumbing (e.g.
  `commit-tree` + `update-ref` landing a commit under a different subcommand name entirely) is not
  detected. A backstop against accidental or unsophisticated bypass, not a hardened boundary
  against a deliberate, git-internals-literate adversary already able to run arbitrary Bash.

## [0.2.0] - 2026-08-05

Eleven fixes and enhancements reported from an adopter repo (Misikiri) that installed `mkr-aidlc`,
covering `install.sh`, the guardrail hooks, and several loop skills.

### Added
- `install.sh` installs `pre-push-review-guard.sh` as a real git `pre-push` hook, and prints an
  advisory to add `.mkr/audit.jsonl` to `.gitignore` (never edits the file itself).
- `install.sh --uninstall [--confirm]` removes exactly what `.claude/mkr-manifest` records, plus
  an owned `.git/hooks/pre-push` symlink — report-only unless `--confirm` is also given
  (`docs/adr/0005-install-uninstall-narrow-delete.md`). Plain install runs also report (never
  touch) unrecognized files at a template-owned location, a possible leftover from a different
  toolkit.
- `install.sh` opportunistically union-merges a divergent `.claude/settings.json` via `jq` instead
  of refusing outright, when `jq` is on `PATH` — every hook the template ships ends up present,
  nothing the adopter added is ever removed. Falls back to the original refuse/`--force` behavior
  whenever `jq` is unavailable or either file fails to parse.
- `mkr-gate.yml` runs an optional `MKR_SETUP` bootstrap command before the configured
  `MKR_TEST`/`_COVERAGE`/`_TYPECHECK`/`_LINT`/`_BUILD` commands, for a repo that needs its own
  multi-step setup (a real monorepo, a pinned runtime version, etc.).
- `mkr-code-reviewer` gains a sixth check, Boundaries/Seams, against a project-declared
  `MKR_BOUNDARIES` list.
- `mkr-plan` ships two new optional tokens, `ui-feedback-per-wave` and
  `build-directive-conformance`.
- `reviewrecord.sh`'s passing-verdict literal is configurable via `MKR_REVIEW_VERDICT_STRING`
  (default `VERDICT: READY`), instead of hardcoded.
- `id-collision-guard.sh` is now `origin/<default-branch>`-aware (a bounded, best-effort
  `git fetch`, `<default-branch>` being the first entry of `MKR_PROTECTED_BRANCHES`) and its
  ID-namespace coverage is extensible beyond ADRs via `MKR_ID_DIRS`.
- `mkr-adr`'s numbering step also checks `origin/<default-branch>`, not just the local working
  tree.
- `mkr-spec` supports adopter-declared extra sections via `MKR_SPEC_EXTRA_SECTIONS`, appended
  after the core 14 (`docs/adr/0004-spec-section-extension-point.md`).
- `mkr-merge` gains a pre-merge conflict check that proposes a resolution rather than auto-
  resolving, post-merge PR/linked-issue bookkeeping, and a branch-deletion step gated behind its
  own separate ask (`docs/adr/0006-mkr-merge-conflict-and-branch-cleanup.md`).

### Security
- `install.sh --uninstall` now validates every manifest-recorded path before deleting it (rejects
  anything outside `.claude/`/`.github/` or containing a `..` segment) — found and fixed during
  this release's own G4 review, before ever shipping; a crafted `.claude/mkr-manifest` entry could
  otherwise have deleted arbitrary files.
- `id-collision-guard.sh`'s `origin/<default-branch>` fetch now separates its git options from the
  branch-name argument with `--`, closing a `git fetch` argument-injection path through a crafted
  `MKR_PROTECTED_BRANCHES` value — also found and fixed pre-release, during the same review.

## [0.1.1] - 2026-08-03

Initial public release, seeded from the private development repo's cleaned tracked files, with a
fresh, history-free `git init` — see `docs/DESIGN.md` and `docs/adr/` for the design and its
recorded decisions.

- The AIDLC loop: skills, agents, hooks, and commands under `.claude/`, landed and versioned in
  your own repo.
- `install.sh` for a `curl | bash` one-liner install, and `/mkr-update` for deliberate updates.
- Guardrail hooks (secret scanning, branch protection, worktree collision detection, review-record
  enforcement) wired via `.claude/settings.json`.
- `docs/adr/` — the architecture decisions behind the design, kept alongside the code.
