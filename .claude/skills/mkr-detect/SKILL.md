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

## 3. No match, or a root match with nothing to propose

mkr-detect only ever reads the target *root* — it never walks the tree looking for markers deeper
down. That is correct for a single-package repo, but silently misleading for a monorepo (the real
code living under `packages/*/`, `apps/*/`, etc.): a root `package.json` with no `scripts.*`, or no
primary marker at the root at all, is technically correct but reads as "nothing here" when the
actual answer is "the markers are one level down." Never leave that implicit. In either of the two
cases below, before reporting, `Glob` the target root's immediate subdirectories (depth 1) for the
same primary markers §2 checks: `*/package.json`, `*/pyproject.toml`, `*/setup.py`,
`*/requirements.txt`, `*/go.mod`, `*/Gemfile` — a plain existence check, no parsing, no recursion
past depth 1.

- **No ecosystem's primary marker at the root, but at least one subdirectory hit**: report "no
  recognized ecosystem detected at the target root — found `<marker>` under `<subdir>/` (and
  any others hit) — check subdirectories" instead of a bare "no recognized ecosystem detected."
  Never guess or propose values for the subdirectory itself; naming it is the whole fix; this
  step never recurses into re-running §2's classification 1 level down.
- **An ecosystem matched at the root, but every one of that ecosystem's proposed values came back
  empty** (e.g. a root `package.json` with no `scripts.test`/`scripts.build`/`scripts.lint`) —
  add the same subdirectory hint alongside that ecosystem's block: "no scripts at root — found
  `<marker>` under `<subdir>/` — check subdirectories" rather than silently returning blank
  fields with nothing pointing at where the real values might live.
- **Neither condition holds** (a genuine no-match with no subdirectory hits either): report "no
  recognized ecosystem detected" plainly, exactly as before — never default to any one
  ecosystem's values.

## 4. Report

One block per matching ecosystem, naming the proposed Stack line and each proposed command value
(or "no convention read" for an empty one, with §3's subdirectory hint attached if that block's
values are all empty). Nothing is ever written to disk — this is a report consumed in-session, not
a file mkr-detect produces.
