# Contributing

Thanks for considering a contribution. `mkrdlc` builds itself with the same loop it ships — the
fastest way to understand how a change should land here is to read `docs/DESIGN.md` and skim a
merged spec under `specs/`.

## The short version

1. **Open an issue first** for anything beyond a typo or a doc fix — a quick discussion up front
   saves a rewritten PR later.
2. **Non-trivial changes get a spec.** `docs/DESIGN.md` §3 defines Quick/Standard/Deep depth; a
   spec under `specs/` is expected for Standard and Deep changes, following the 14-section shape
   `specs/*_Spec.md` already use.
3. **Tests before implementation.** This repo's own test suite (`bash tests/*.sh`, or `MKR_TEST` in
   `.mkr/config`) must pass before a PR is opened, and stay green after.
4. **Small, reviewable diffs.** Match the surrounding style; avoid speculative abstraction; one
   logical change per PR.
5. **Conventional Commits** for commit messages (`feat:`, `fix:`, `docs:`, `test:`, etc.).

## Running the checks locally

```sh
bash tests/config_test.sh && bash tests/mkr_artifact_test.sh && bash tests/hooks_test.sh && bash tests/install_test.sh
```

All four must pass before you open a PR — the same command CI runs via
`.github/workflows/mkr-gate.yml`.

## What review looks like

This is currently a solo-maintained project (see [CODEOWNERS](.github/CODEOWNERS)) — there's no
required-reviewer policy beyond the maintainer's own pass. `main` is branch-protected: the `gate`
CI check must pass before a PR merges.

## Code of conduct

Participation in this project is governed by our [Code of Conduct](CODE_OF_CONDUCT.md).
