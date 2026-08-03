# 0003 — MIT-0 over MIT

## Status

Accepted

## Context

`mkr-aidlc` is a template: its whole value is in adopters copying its files into their own repos
and editing them freely — replacing skills, rewriting hooks, deleting what they don't need.
Standard MIT requires the copyright and permission notice to be preserved in copies, which is a
reasonable expectation for a library that stays a dependency, but is friction for a template whose
files are meant to be forked, edited, and redistributed as part of someone else's project without
carrying a notice that no longer describes what's there.

## Decision

License the repo under MIT-0 (MIT No Attribution): the same permissive grant as MIT, minus the
requirement to reproduce the copyright/permission notice in copies or substantial portions of the
software.

## Consequences

- Adopters can copy `.claude/` into their own repo, modify it beyond recognition, and never need to
  carry or reproduce this project's license text.
- No attribution is required or expected in downstream use — consistent with treating the template
  as adopted, not vendored.
- The repo stays MIT-0 from its first commit (§3); nothing here changes at M6 when the repo goes
  public.
