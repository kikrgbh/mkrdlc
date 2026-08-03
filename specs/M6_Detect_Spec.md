# `mkr-detect`: repo ecosystem detection for `/mkr-init`

## Intent

`/mkr-init` step 4's interview previously started from a blank page even when the target repo's
ecosystem was unambiguous from a single file on disk. `mkr-detect` reads a target repo's root for
Node/TypeScript, Python, Go, and Rails signals and reports a proposed Stack description plus
proposed `MKR_TEST`/`MKR_COVERAGE`/`MKR_TYPECHECK`/`MKR_LINT`/`MKR_BUILD` values per matching
ecosystem — read-only, reporting only, never writing anything. A repo matching none of the four is
told so plainly, not silently defaulted; a repo matching more than one has every match reported,
not one guessed past the others.

## Scope

**In scope**
- `mkr-detect` (skill + command) — detection over the four ecosystems.
- `/mkr-init` step 4 — rewritten to invoke `mkr-detect` in place of an ad hoc best-effort read,
  carrying its existing "confirm them, don't assume them silently" rule forward unchanged.

**Out of scope**
- Any ecosystem beyond Node/TypeScript, Python, Go, and Rails.
- Distinguishing *which* specific test runner/linter/type-checker a repo uses beyond each
  ecosystem's one conventional signal (e.g. Jest vs. Vitest vs. Mocha) — unmatched cases are
  reported empty for the human to fill in, not guessed.
- Any change to `/mkr-init` step 5 ("Write") — `mkr-detect` only proposes; `/mkr-init` remains the
  sole writer of `CLAUDE.md`/`.mkr/config`.
- Widening `mkr-evals`' fixture shape to cover a skill's proposal output instead of an agent's
  binary verdict.

## Architecture & key decisions

- **Prompt-only, no backing script**, unlike `install.sh`. `mkr-detect` only reads and reports —
  it never writes, so none of the atomicity/backup/staging machinery that justifies a script
  applies. Checked structurally in the test suite, not executed.
- **One conventional signal per ecosystem, not an exhaustive tool matrix.** Each ecosystem reads
  exactly one primary marker file and, where a convention exists, one place within it to read a
  proposed command from. Anything not expressed there is reported empty, for the human to fill in
  during the interview, not guessed.
- **Signals for more than one ecosystem are all reported, never silently resolved to one.** A
  monorepo matching two ecosystems' primary markers gets both reported, each with its own proposed
  values; merging them into one `CLAUDE.md` Stack description is the interview's call, not
  `mkr-detect`'s.
- **`mkr-detect` never writes; `/mkr-init` remains the sole writer.** It slots in as step 4's
  detection source, not a second writer with its own opinion about when it's safe to commit an
  answer.

**Detection signals, per ecosystem:**

| Ecosystem | Primary marker (must be present at repo root) | Narrowing signal | Proposed Stack line |
|---|---|---|---|
| Node/TypeScript | `package.json` | `tsconfig.json` present | "TypeScript" — else "JavaScript" |
| Python | `pyproject.toml`, `setup.py`, or `requirements.txt` (any one) | `poetry.lock` present | "Python (poetry)" — else "Python (pip)" |
| Go | `go.mod` | — | "Go" |
| Rails | `Gemfile` **and** (`config/application.rb` or `bin/rails`) | `spec/` dir **and** `rspec` named in `Gemfile` | "Ruby on Rails (RSpec)" — else "Ruby on Rails" |

**Proposed command values, per ecosystem** (empty means "no convention read, leave for the
interview" — never a guess):

| Ecosystem | `MKR_TEST` | `MKR_BUILD` | `MKR_LINT` | `MKR_TYPECHECK` | `MKR_COVERAGE` |
|---|---|---|---|---|---|
| Node/TS | `package.json`'s `scripts.test`, verbatim, if present — else empty | `scripts.build` if present — else empty | `scripts.lint` if present — else empty | `tsc --noEmit` if `tsconfig.json` present — else empty | empty |
| Python | `pytest` if a `tests/` directory exists at repo root — else empty | empty | empty | empty | empty |
| Go | `go test ./...` | `go build ./...` | empty | empty — `go build` already type-checks | empty |
| Rails | `bundle exec rspec` if `spec/` **and** `rspec` in `Gemfile` — else `bin/rails test` | empty | empty | empty | empty |

## Interfaces / contracts

**`mkr-detect` (skill + command).** Tool scope: `Read`, `Grep`, `Glob` only; never `Write`/`Edit`.
Input: a target repo root — invoked internally by `/mkr-init` step 4, or directly via the
standalone `/mkr-detect` command with an optional target-path argument (default: cwd, resolved via
`git rev-parse --show-toplevel` when inside a git work tree).

1. Check each ecosystem's primary marker at the target root; more than one match is expected and
   reported, not resolved. A marker file that exists but is malformed/unparseable is treated as
   absent, never guessed at.
2. For each matching ecosystem, read its narrowing signal and its one conventional command
   location to propose values — empty where no convention exists. Rails' `rspec` narrowing signal
   is a case-insensitive substring match in `Gemfile`'s text, not a full parser.
3. If no ecosystem's marker is present, report "no recognized ecosystem detected" rather than
   defaulting to any one ecosystem's values.
4. Report one block per matching ecosystem, naming the proposed Stack line and each proposed
   command value (or "no convention read") — never written anywhere.

**`/mkr-init` step 4 (rewritten).** Invokes `mkr-detect` against the target root. One or more
ecosystem blocks are presented to the human as proposals; the interview's existing "confirm them,
don't assume them silently" rule governs from there, unchanged. Zero blocks ("no recognized
ecosystem detected") is stated to the human plainly before the interview continues from a blank
starting point. Step 5 ("Write") is untouched: still the only place `CLAUDE.md`/`.mkr/config` are
written, and still refuses to write partial output.

## Data model

No new `config.sh` variable — `mkr-detect` proposes values for `MKR_TEST`, `MKR_COVERAGE`,
`MKR_TYPECHECK`, `MKR_LINT`, and `MKR_BUILD`, all already published in `config.sh`'s schema.

No new generated artifact — `mkr-detect` never writes a file; its output is a report consumed
in-session by `/mkr-init`'s own interview.
