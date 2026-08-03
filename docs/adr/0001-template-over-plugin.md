# 0001 — Template over plugin

## Status

Accepted

## Context

A Claude Code plugin was considered as the delivery mechanism for this method: user-scope install,
skill content resolved at runtime over an MCP `consult` call, and packaging (`plugin.json`,
`marketplace.json`, `${CLAUDE_PLUGIN_ROOT}` paths) aimed at a marketplace.

A plugin binds one developer. It follows them across every repo they open and can be silently
uninstalled at any time, by them or by an update. Nothing commits it to the team, so a gate the
plugin enforces is honestly a *soft* gate — DESIGN.md principle 2 (enforcement honesty) cannot be
satisfied by a mechanism nobody else on the team can see or is bound by. The plugin's own skill
content also violated principle 1 (files, not fetches): resolving over `consult` means the method
lives somewhere the team can't read, diff, or edit as part of a normal PR.

## Decision

Ship the method as a template: committed files under `.claude/` that land in the repo itself, not
a user-scope install. `mkr-aidlc` **is** the template — there is no separate `template/` directory
and no MCP dependency (AD-4). Everyone who clones the repo gets the same loop; weakening or
removing a gate is a reviewable diff in `.claude/settings.json` or a skill file, not one
developer's private opt-out.

The cost is explicit: updates are deliberate (`/mkr-update`, M6) rather than automatic. A plugin
wrapper could still be layered over the same committed files later — this is not a one-way door.

## Consequences

- Gates enforced via committed hooks/CI are binding on the team, not on an individual's local
  install; removing one is a diff someone has to approve.
- No network dependency, no MCP server, no marketplace packaging.
- The repo must be self-hosting (AD-4): the copy we use and the copy we ship are the same files,
  so drift between "used" and "shipped" is structurally impossible.
- Adopting or updating the template touches the adopter's working tree instead of a background
  auto-update; that seam is fully specified in M6, not M0.
