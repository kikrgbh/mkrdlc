# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/).

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
