---
description: Read a target repo's root for Node/TypeScript, Python, Go, and Rails ecosystem signals and report a proposed Stack description plus proposed MKR_TEST/MKR_BUILD/MKR_LINT/MKR_TYPECHECK/MKR_COVERAGE values. Never writes anything.
---

Run the `mkr-detect` skill against the target path named (default: the current working directory's
repo root).

Invariant this command exists to state, not to re-implement: `mkr-detect` never writes any file —
it only reports. When invoked from within `/mkr-init`'s own interview, its proposals still go
through that interview's "confirm them, don't assume them silently" rule; running it standalone
here is for seeing what it would propose, nothing more.
