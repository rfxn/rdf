# TypeScript Governance Template

> Seed template for /r-init. Merged with codebase scan results during
> governance generation. Not copied verbatim -- scan data overrides
> where conflicts exist.

## Strict Mode

- `strict: true` in `tsconfig.json` -- non-negotiable baseline that
  enables all strict checks simultaneously
- `noUncheckedIndexedAccess: true` -- array and object index access
  returns `T | undefined`, forcing null checks
- Never use `any` -- use `unknown` with type guards for truly unknown
  data, or a specific type/union for known shapes
- `as` type assertions are a code smell -- prefer type guards
  (`if (isUser(x))`) or discriminated unions that narrow naturally
- Do not use `@ts-ignore` or `@ts-expect-error` without an inline
  comment explaining why the type system cannot express the constraint
- Enable `exactOptionalPropertyTypes` to distinguish between `undefined`
  and missing properties
- Prefer `satisfies` operator over `as` for type checking without
  widening -- `const config = { ... } satisfies Config`

## Async Discipline

- Every async function call must be `await`ed or explicitly handled --
  floating promises are silent failures
- Use `eslint-plugin-promise` with `no-floating-promises` rule enabled
- Never use `.then()` chains in async/await code -- pick one style per
  codebase and enforce it
- `Promise.all()` for concurrent independent operations --
  `Promise.allSettled()` when partial failure is acceptable
- Always handle promise rejection -- unhandled rejections crash Node.js
  in modern versions
- Avoid `async` on functions that don't `await` -- it wraps the return
  in an unnecessary promise
- Use `AbortController` for cancellable async operations

## Error Handling

- Throw `Error` instances (or subclasses), never strings or plain objects
  -- stack traces require `Error` instances
- Define typed error classes for domain errors:
  `class NotFoundError extends Error { ... }`
- Express middleware: use `express-async-errors` or wrap async handlers
  to catch rejected promises -- Express 4.x does not catch them natively
- Fastify: async error handling is native -- thrown errors automatically
  become error responses
- Never catch errors silently (`catch (e) {}`) -- log, re-throw, or
  handle with explicit intent
- Use `Result` pattern (from `neverthrow` or custom) for expected
  failure cases instead of exceptions
- Validate error shapes in catch blocks -- `catch (e: unknown)` is
  the correct type annotation

## Package Management

- `pnpm` preferred for deterministic installs, disk efficiency, and
  strict dependency isolation
- Lockfile (`pnpm-lock.yaml`, `package-lock.json`) must be committed
  to version control
- Use `--save-exact` for application dependencies -- semver ranges
  cause "works on my machine" drift
- Verify packages exist before adding -- LLMs hallucinate package names
  that look plausible but do not exist on npm
- Audit dependencies: `pnpm audit` or `npm audit` in CI pipeline
- Prefer scoped packages (`@org/pkg`) over unscoped names to prevent
  dependency confusion attacks
- Review `postinstall` scripts in new dependencies -- they execute
  arbitrary code during install

## Input Validation

- Validate all external input at the API boundary using Zod, Joi, or
  similar runtime schema validation
- Never trust `req.body`, `req.query`, or `req.params` without
  validation -- TypeScript types do not exist at runtime
- Parse, don't validate: use Zod's `.parse()` to transform unknown
  input into typed, validated data in one step
- Define validation schemas alongside route handlers, not in a separate
  validation layer -- co-location prevents schema drift
- Return structured validation errors with field-level detail, not
  generic 400 responses

## Exports

- Named exports only -- `export default` breaks tree-shaking, makes
  imports inconsistent, and complicates refactoring
- Explicit barrel files (`index.ts`) -- export only the public API,
  not every internal module
- Do not re-export types from third-party packages in your public API
  -- it couples consumers to your dependencies
- Group related exports in a single barrel file per domain module
- Use `export type` for type-only exports to enable proper tree-shaking
  and avoid circular dependency issues

## Node.js Patterns

- Never call `process.exit()` in library code -- let the application
  decide when to exit. Libraries throw errors or return failure values
- Implement graceful shutdown: listen for `SIGTERM` and `SIGINT`,
  close database connections, drain HTTP connections, then exit
- Use structured logging (pino or winston) -- never `console.log` in
  production code
- Stream large payloads instead of buffering in memory -- respect
  backpressure signals from writable streams
- Use `node:` prefix for built-in modules (`import fs from "node:fs"`)
  to distinguish from npm packages
- Health check endpoints: separate liveness (`/healthz`) from
  readiness (`/readyz`) -- liveness is "process alive", readiness
  is "dependencies connected"
- Environment variables: load and validate at startup (via `dotenv` +
  Zod schema), fail fast on missing required values

## Security

- Prototype pollution: freeze objects from untrusted sources, use `Map`
  instead of plain objects for dynamic keys, avoid `Object.assign` with
  user input
- Dependency confusion: use scoped packages (`@org/pkg`), configure
  `.npmrc` with `registry` per scope
- SQL injection: always use parameterized queries -- never template
  literals or string concatenation for SQL
- XSS: sanitize HTML output, use framework-native escaping (React JSX
  auto-escapes), never use `dangerouslySetInnerHTML` without sanitization
- SSRF: validate URLs before fetching -- allowlist target hosts, reject
  private IP ranges
- Rate limiting: apply at the reverse proxy or middleware layer, not
  per-handler
- Secrets: load from environment variables, never hardcode in source --
  use `dotenv` for local development only
