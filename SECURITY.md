# Security Policy

## Supported Versions

Only the latest tagged release receives security fixes. RDF is a
development-time governance framework — it runs on developer machines,
not production servers — but its shell tooling executes with your user
privileges, so we treat command injection, unsafe temp-file handling,
and path-traversal issues as security bugs.

| Version | Supported |
|---------|-----------|
| Latest release | Yes |
| Older tags | No |

## Reporting a Vulnerability

**Do not open a public issue for security reports.**

Email **ryan@rfxn.com** with:

- A description of the issue and the affected file(s)
- Reproduction steps or a proof of concept
- The version or commit hash you tested against

You will receive an acknowledgment within 72 hours. Fixes for confirmed
issues ship in the next tagged release, with credit in the changelog
unless you request otherwise.

## Scope Notes

- RDF agents and commands are prompt content, not executable code — but
  the `bin/`, `lib/`, and `state/` shell tooling is in scope.
- Third-party AI runtimes (Claude Code, Codex, Antigravity CLI, Gemini CLI) are out of
  scope; report those to their vendors.
