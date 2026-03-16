# Frontend Governance

> RDF frontend profile — conventions for web/frontend development.
> Framework-agnostic, applicable to Vue, React, or vanilla JS projects.
> Requires the core profile.

---

## Architecture Conventions

### Component Structure

- Separate concerns: data fetching, state management, presentation
- Components should be independently testable
- Shared utilities in dedicated module, not duplicated across components
- API contracts defined before implementation (response types, error shapes)

### CSS / Styling

- Use a consistent methodology (BEM, utility-first, or CSS modules)
- Design tokens for colors, spacing, typography — no magic numbers
- Responsive breakpoints defined in a single source of truth
- Dark mode support via CSS custom properties, not duplicate stylesheets

### JavaScript / TypeScript

- Strict mode enabled (`"strict": true` in tsconfig or `"use strict"`)
- No `any` types in TypeScript — use `unknown` with type guards
- Error boundaries at route level minimum
- API calls abstracted behind service layer (not inline in components)

---

## Testing Conventions

### Unit Tests

- Component tests mock external dependencies (API, router, store)
- Test behavior, not implementation (user-visible output, not internal state)
- Snapshot tests only for stable, rarely-changing components

### Integration Tests

- API contract tests: validate response shapes match TypeScript interfaces
- DOM structural tests: verify critical elements present and accessible
- CSS regression: visual diff for key pages/states

### End-to-End Tests (Playwright)

- Headless Chromium as default browser target
- Test critical user workflows, not every page
- Stable selectors: `data-testid` attributes, not CSS classes
- Network mocking for deterministic test data
- Screenshot comparison for visual regression

---

## Accessibility

- Semantic HTML elements (`<nav>`, `<main>`, `<article>`, not `<div>` for everything)
- ARIA labels on interactive elements without visible text
- Keyboard navigation for all interactive flows
- Color contrast ratios meet WCAG 2.1 AA minimum
- Screen reader testing for critical workflows

---

## Build & Deployment

- Bundle size budgets defined and enforced in CI
- Tree-shaking enabled — no side-effect-only imports without annotation
- Asset optimization: images, fonts, SVGs
- Source maps in development, stripped in production
- Environment variables via build-time injection, never committed

---

## Reporting Conventions

- Frontend QA findings use `domain:fe` label
- Playwright test results stored in `test-results/` (gitignored)
- Visual regression baselines committed, diffs reviewed in PR
- Use `fe-qa` and `fe-uat` agent personas for QA and UAT work
