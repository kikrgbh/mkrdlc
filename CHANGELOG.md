# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/).

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
