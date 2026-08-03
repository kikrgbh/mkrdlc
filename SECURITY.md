# Security Policy

`mkrdlc` is a template: skills, agents, and guardrail hooks that land inside your own repo's
`.claude/` directory. Most of its "attack surface" is the shell scripts under `.claude/hooks/` and
the CI workflow at `.github/workflows/mkr-gate.yml` — both run with your own permissions, on your
own machine or your own CI runner.

## Reporting a vulnerability

If you find a security issue — a guardrail hook that can be bypassed, a prompt-injection path
through a skill or agent, an unsafe pattern in `install.sh`, or anything else with real security
impact — please report it privately rather than opening a public issue:

- Preferred: open a [GitHub Security Advisory](https://github.com/kikrgbh/mkrdlc/security/advisories/new)
  on this repo (requires private vulnerability reporting to be enabled — if that link 404s,
  private reporting isn't turned on yet; use the fallback below).
- Otherwise: contact the maintainer listed in [CODEOWNERS](.github/CODEOWNERS).

Please include:
- What the vulnerability is and its potential impact.
- Steps to reproduce it, ideally against a fresh `install.sh` checkout.
- Any suggested fix, if you have one.

This is a solo-maintained project — expect an initial response within a few days, not hours.
There's no bug-bounty program; credit in the fix's commit message or `CHANGELOG.md` is the thanks
on offer.

## Supported versions

Only the latest tagged release is supported. There's no long-term-support branch.
