# Frontend Governance Template

> Seed template for /r-init. Provides web/frontend conventions for
> merging with codebase scan results. Framework-agnostic (React, Vue,
> Svelte, vanilla). Requires core profile.
> Assumes ES2020+ baseline with "last 2 versions" browser targets.

## Code Conventions

- Separate concerns: data fetching, state management, and presentation
  live in distinct layers -- never fetch inside a render function
- Single-responsibility components -- if a component manages its own
  data fetching AND renders a complex UI, split it
- Define API contracts (response types, error shapes, pagination)
  before implementing the UI that consumes them
- Local state by default -- promote to global state (store, context)
  only when two or more unrelated components need the same data
- Side effects belong in hooks, services, or lifecycle methods -- never
  in render paths or computed/derived values
- Colocate files by feature (`feature/Component.tsx`, `feature/api.ts`,
  `feature/Component.test.tsx`), not by type (`components/`, `hooks/`)
- API calls behind a service layer -- components call `getUser()`,
  not `fetch('/api/users/1')`

## Anti-Patterns

- Prop drilling through 3+ levels -- use context, composition, or a
  state manager instead
- `useEffect` (or equivalent) as an event handler -- effects are for
  synchronization, not for responding to clicks or form submissions
- Storing derived state in state -- compute it inline or memoize;
  `const fullName = first + last`, not `setFullName(first + last)`
- `index` as `key` in dynamic lists -- causes stale state and wrong
  DOM reuse when items are reordered, inserted, or deleted
- Inline object/array/function literals in JSX props or template
  bindings -- creates new references every render, breaking memoization
  (`useMemo`, `React.memo`, `shouldComponentUpdate`)
- Catching errors in components without an error boundary above --
  unhandled render errors crash the entire tree
- CSS `!important` -- signals a specificity war; refactor selectors or
  use a scoping strategy (CSS modules, Shadow DOM)
- Layout thrashing -- reading a layout property (offsetHeight) then
  writing a style (height) in the same synchronous frame forces an
  expensive reflow; batch reads before writes
- Barrel files (`index.ts` re-exporting everything) -- prevent
  tree-shaking and create circular dependency risks

## Error Handling

- Error boundaries at route level minimum -- prevent one broken
  section from unmounting the entire application
- Distinguish API error types: network failures (offline, timeout),
  server errors (5xx), validation errors (4xx) -- each needs different
  UI treatment and retry logic
- Every async data path renders three states: loading, error, and
  empty -- never assume data will always arrive
- Client-side validation for UX (instant feedback), server-side
  validation for security (never trust the client)
- Retry failed network requests with exponential backoff -- at least
  for idempotent operations (GET, PUT)
- Global error handler (`window.onerror`, `unhandledrejection`) for
  catching escapes -- log to error tracking service

## Security

- XSS: never use `dangerouslySetInnerHTML`, `v-html`, or `innerHTML`
  with untrusted content -- sanitize with DOMPurify first
- Content Security Policy: no `unsafe-inline` scripts, no `unsafe-eval`;
  use nonces or hashes for necessary inline scripts
- CSRF: token-based protection for state-changing requests; `SameSite`
  cookie attribute set to `Strict` or `Lax`
- Auth tokens: store in `httpOnly` cookies, not `localStorage` --
  `localStorage` is accessible to any script on the origin
- `postMessage`: always validate `event.origin` against an allowlist
  before processing messages
- Third-party scripts: use Subresource Integrity (SRI) hashes; load
  non-critical third-party scripts with `async` or `defer`
- Sensitive data (tokens, PII, secrets): never store in
  `localStorage`, `sessionStorage`, or URL parameters

## CSS / Styling

- Pick one methodology and enforce it: BEM, utility-first (Tailwind),
  CSS modules, or CSS-in-JS -- never mix approaches in one project
- Design tokens for all visual values (colors, spacing, typography,
  radii) -- no magic numbers like `padding: 13px` or `color: #3a7`
- Responsive breakpoints defined in a single source of truth -- one
  variables file, not scattered media queries with different values
- Dark mode via CSS custom properties on a root selector -- never
  duplicate entire stylesheets
- Animations: use `transform` and `opacity` only (GPU-composited);
  respect `prefers-reduced-motion` with `@media` query
- z-index: define a token scale (`z-dropdown: 100`, `z-modal: 200`,
  `z-toast: 300`) -- never ad-hoc values like `z-index: 9999`

## Accessibility

- Semantic HTML first -- `<nav>`, `<main>`, `<article>`, `<button>`,
  not `<div onClick>` for everything
- ARIA: `aria-label` on interactive elements without visible text;
  use ARIA roles only when no semantic HTML element exists
- Keyboard: all interactive flows navigable via Tab/Shift-Tab/Enter/Esc;
  manage focus on route changes and modal open/close
- Color: WCAG 2.1 AA minimum -- 4.5:1 for normal text, 3:1 for large
  text and UI components; never convey information by color alone
- Screen reader: test critical workflows with a screen reader; use
  `aria-live` regions for dynamic content updates
- Forms: every input has an associated `<label>`; related fields grouped
  with `<fieldset>`/`<legend>`; errors linked via `aria-describedby`

## Testing

- Unit: mock external dependencies (API, router, store); test behavior
  not implementation details; snapshot tests only for stable,
  rarely-changing output
- Integration: verify API contracts (response shapes match types); test
  DOM structure and accessibility of critical elements; CSS regression
  via visual diff for key pages and states
- E2E: headless Chromium default; cover critical user workflows, not
  every page; use `data-testid` for stable selectors, never CSS classes;
  mock network for deterministic data
- Visual regression: screenshot diff for key pages and component states;
  fail CI on unexpected visual changes
- Accessibility: axe-core in CI for automated checks; manual screen
  reader testing for critical flows; eslint-plugin-jsx-a11y (or
  framework equivalent) in lint step

## Build & Deployment

- Bundle size budgets enforced in CI -- fail the build when JS or CSS
  exceeds threshold (use `bundlesize` or `size-limit`)
- Tree-shaking: verify with bundle analyzer that unused exports are
  eliminated; avoid side-effectful imports in library code
- Asset optimization: WebP/AVIF with `<picture>` fallback for images;
  subset fonts to used glyphs; SVGO for SVG files
- Source maps: enabled in dev; production maps only to error tracking
  service (Sentry, Datadog), never publicly served
- Environment variables: build-time injection via framework convention
  (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`); never committed to repo;
  `.env.example` checked in with placeholder values
