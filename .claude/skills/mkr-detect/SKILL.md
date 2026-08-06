---
name: mkr-detect
description: Reads a target repo's root for Node/TypeScript, Python, Go, and Rails ecosystem signals and reports a proposed Stack description plus proposed MKR_TEST/MKR_BUILD/MKR_LINT/MKR_TYPECHECK/MKR_COVERAGE values per matching ecosystem. Never writes anything - read-only, reporting only. Reports "no recognized ecosystem detected" when none match, and every match when more than one does, never guessing past either. Use directly, or invoked by /mkr-init step 4 to replace its ad hoc best-effort read.
---

# mkr-detect — systematic repo profiling for TS/Python/Go/Rails

Tool scope: `Read`, `Grep`, `Glob` only. Never `Write`/`Edit` — `mkr-detect` never writes any file;
it only reports. `/mkr-init` step 5 remains the sole writer of `CLAUDE.md`/`.mkr/config`.

## 1. Resolve the target root

Two call shapes:

- Invoked internally by `/mkr-init` step 4: use its own step-1 resolution — `$CLAUDE_PROJECT_DIR`
  if set, else `git rev-parse --show-toplevel`.
- Invoked as the standalone `/mkr-detect` command: an optional target-path argument; if omitted,
  default to the current working directory, resolved via `git rev-parse --show-toplevel` when
  inside a git work tree, else the literal cwd.

## 2. Classify

For each of the four ecosystems below, check whether its primary marker is present at the target
root. **More than one match is expected and reported, not resolved** — a monorepo with both a
`package.json` and a `go.mod` gets both ecosystems reported, never one silently picked over the
other. A marker file that exists but is malformed or unparseable (e.g. invalid JSON in
`package.json`) is treated the same as if the value it would have produced were absent — never a
guess at its intended content.

### Node/TypeScript

Primary marker: `package.json`.

- Naming: `tsconfig.json` present at the target root → Stack line reads **"TypeScript"**.
  `tsconfig.json` absent → Stack line reads **"JavaScript"**.
- `MKR_TEST`: `package.json`'s own `scripts.test` value, verbatim, if present. If `scripts.test` is
  absent, `MKR_TEST` is empty — never a guessed test command.
- `MKR_BUILD`: `package.json`'s own `scripts.build` value, verbatim, if present. If `scripts.build`
  is absent, `MKR_BUILD` is empty.
- `MKR_LINT`: `package.json`'s own `scripts.lint` value, verbatim, if present. If `scripts.lint` is
  absent, `MKR_LINT` is empty.
- `MKR_TYPECHECK`: `tsc --noEmit` when `tsconfig.json` is present. When `tsconfig.json` is absent,
  `MKR_TYPECHECK` is empty.
- `MKR_COVERAGE`: empty — no single convention to propose.

### Python

Primary marker: any one of `pyproject.toml`, `setup.py`, `requirements.txt`.

- Naming: `poetry.lock` present at the target root → Stack line reads **"Python (poetry)"**.
  `poetry.lock` absent → Stack line reads **"Python (pip)"**.
- `MKR_TEST`: `pytest` when a `tests/` directory exists at the target root. When no `tests/`
  directory exists, `MKR_TEST` is empty.
- `MKR_BUILD`: empty — no single convention to propose.
- `MKR_LINT`: empty — no single convention to propose.
- `MKR_TYPECHECK`: empty — no single convention to propose.
- `MKR_COVERAGE`: empty — no single convention to propose.

### Go

Primary marker: `go.mod`.

- Naming: Stack line reads **"Go"**.
- `MKR_TEST`: `go test ./...`.
- `MKR_BUILD`: `go build ./...`.
- `MKR_TYPECHECK`: empty — `go build` already type-checks.
- `MKR_LINT`: empty — no single convention to propose.
- `MKR_COVERAGE`: empty — no single convention to propose.

### Rails

Primary marker: `Gemfile` **and** (`config/application.rb` **or** `bin/rails`) — a bare `Gemfile`
alone, e.g. from an unrelated gem dependency, is not Rails on its own; both halves of this
condition must hold.

- Naming: a `spec/` directory exists **and** `rspec` appears (case-insensitive substring match — a
  best-effort convention check, not a full Gemfile parser) anywhere in `Gemfile`'s text → Stack
  line reads **"Ruby on Rails (RSpec)"**. Otherwise → Stack line reads **"Ruby on Rails"**.
- `MKR_TEST`: `bundle exec rspec` when the RSpec condition above holds; otherwise `bin/rails test`.
- `MKR_BUILD`: empty — no build step.
- `MKR_LINT`: empty — no single convention to propose.
- `MKR_TYPECHECK`: empty — no single convention to propose.
- `MKR_COVERAGE`: empty — no single convention to propose.

## 3. No match

If no ecosystem's primary marker is present at the target root, report "no recognized ecosystem
detected" plainly — never default to any one ecosystem's values.

**Known limitation, state it rather than leave it implicit (specs/M6_Detect_Spec.md's own
root-only architecture — mkr-detect checks exactly the target root, never a subdirectory, by
design; widening that is out of this spec's scope, not a bug to silently work around here):** a
monorepo whose real ecosystem markers live under `packages/*/`, `apps/*/`, or similar has nothing
at the root for §2 to find, and reads identically to a repo with no recognized ecosystem at all —
or, if an ecosystem *does* match at the root but none of its command conventions are present there
either (e.g. a root `package.json` with no `scripts.test`/`scripts.build`/`scripts.lint`), every
proposed value comes back empty for the same reason. Either case, say so plainly alongside the
result: this only ever read the target root, so a monorepo-shaped project may need its
subdirectories checked by hand during the interview — don't let a blank report or "no recognized
ecosystem detected" read as "this repo has no ecosystem" when it may just mean "not at the root."

## 4. Report

One block per matching ecosystem, naming the proposed Stack line and each proposed command value
(or "no convention read" for an empty one). Nothing is ever written to disk — this is a report
consumed in-session, not a file mkr-detect produces.
