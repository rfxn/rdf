# Node.js Governance Template

> Seed template for /r-init. Provides Node.js (plain JavaScript) best
> practices for merging with codebase scan results. Requires core profile.
> Assumes Node 18+ LTS baseline (built-in fetch, node:test). For
> TypeScript projects the typescript profile applies instead.

## Code Conventions

- Declare the module system explicitly: `"type": "module"` (ESM) or
  `"type": "commonjs"` in package.json -- never rely on the default
- Declare `"engines": { "node": ">=X" }` and enforce it in CI
- Commit exactly one lockfile (package-lock.json OR pnpm-lock.yaml OR
  yarn.lock) matching the package manager the project documents
- Use the `node:` prefix for builtin imports (`node:fs`, `node:path`) --
  disambiguates from npm packages and fails fast on typos
- Prefer builtin capabilities over dependencies: `fetch`, `node:test`,
  `node:util` parseArgs -- every dependency is an attack surface
- Executable entry points declare `"bin"` in package.json; libraries
  declare `"exports"` -- do not reach into package internals

## Anti-Patterns

- Floating promises -- every promise is awaited, returned, or explicitly
  voided with a comment; unhandled rejections crash Node 15+
- `process.exit()` in library code -- throw and let the caller decide;
  exit only from the CLI entry point
- Synchronous fs/crypto calls (`readFileSync`, `pbkdf2Sync`) on request
  paths -- blocks the event loop for every concurrent request
- `npm install` in CI -- use `npm ci` for lockfile-exact, reproducible
  installs
- Monkey-patching require/module internals -- breaks under ESM and
  bundlers; use dependency injection
- Swallowing errors in `.catch(() => {})` -- log or rethrow with context
- Wildcard or `latest` version ranges in dependencies -- pin or use caret
  ranges with a committed lockfile

## Error Handling

- Fail fast on programmer errors (TypeError, assertion); recover only
  from operational errors (network, fs, user input)
- Wrap-and-rethrow with `new Error("context", { cause: err })` -- never
  discard the original error
- One process-level `unhandledRejection` / `uncaughtException` handler:
  log, flush, exit nonzero -- never continue on unknown state
- Async resource cleanup in `finally` (or `await using` where available)

## Testing

- Tests live in `test/` or `*.test.js` colocated -- one convention per
  repo, documented in package.json scripts
- `npm test` must run the full suite with a nonzero exit on failure --
  CI calls the script, never the runner directly
- Prefer `node:test` for zero-dependency projects; jest/vitest acceptable
  when the project already depends on them
- Every bug fix lands with a regression test in the same commit

## Security

- `npm audit --omit dev` gates release builds; document accepted
  advisories with expiry dates
- No `postinstall` scripts in first-party packages without justification;
  review transitive postinstall scripts before adding a dependency
- Never interpolate untrusted input into `child_process.exec` -- use
  `execFile`/`spawn` with argument arrays
- Secrets come from the environment or a secret store -- never from
  committed .env files
