# CLAUDE.md

## What this project is
<one paragraph — what it does and for whom>

## Stack
<languages · frameworks · package manager · database · layout>

## Commands
<install command>
<test command>
<coverage command>
<typecheck command>
<lint command>
<build command>
<run command>

## How we build — the AIDLC loop

triage → spec → ⟦spec approved⟧ → plan → ⟦plan conformant⟧ → design → ⟦design gate⟧
→ tests → implement → verify → review → ⟦review gate⟧ → merge → ground → ship

No code is written for a non-trivial change until its spec is agreed. Humans own intent and
guardrails; the agent runs the loop; review happens at gates, not per keystroke.

Depth: **Quick** (typo/config — implement + test + a one-line review note) ·
**Standard** (a feature in an existing module — the full loop, single pass) ·
**Deep** (new module, auth, data model, anything hard to reverse — full loop + ADR + audit).
State which you picked, and why, before starting.

## Allowed actions
- **MAY:** read code · write and run tests · draft specs · surgical edits on a feature branch ·
  typecheck/lint · open PRs.
- **MUST ASK FIRST:** push or merge to a protected branch · change CI/CD or infra ·
  touch auth, tenancy or the data model · read or rotate secrets · delete data · deploy.
- **MUST NEVER:** commit secrets · disable a guardrail or weaken a test to make CI pass ·
  force-push a shared branch.

## Gate owners
A gate without a named owner is not a gate.
<owner of the spec-approval gate>
<owner of the design gate>
<owner of the pre-merge gate>
<owner of the pre-deploy gate>
<owner of incident response / the kill switch>

## Non-negotiables
<3–7 project-specific invariants — the rules that must never be traded away>

## Conventions
<code style and diff-size conventions>
<commit message and branching conventions>
<when a decision requires an ADR>
