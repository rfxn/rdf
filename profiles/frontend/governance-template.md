# Frontend Governance Template

> Seed template for /r:init. Provides web/frontend conventions for
> merging with codebase scan results. Framework-agnostic (Vue, React,
> Svelte, vanilla). Requires core profile.

## Architecture Conventions

- Separate concerns: data fetching, state management, presentation
- Components independently testable
- Shared utilities in dedicated module, not duplicated
- API contracts defined before implementation (response types, error shapes)

## CSS / Styling

- Consistent methodology (BEM, utility-first, or CSS modules)
- Design tokens for colors, spacing, typography -- no magic numbers
- Responsive breakpoints in a single source of truth
- Dark mode via CSS custom properties, not duplicate stylesheets

## JavaScript / TypeScript

- Strict mode enabled
- No `any` types in TypeScript -- use `unknown` with type guards
- Error boundaries at route level minimum
- API calls behind service layer, not inline in components

## Accessibility

- Semantic HTML elements (nav, main, article -- not div for everything)
- ARIA labels on interactive elements without visible text
- Keyboard navigation for all interactive flows
- WCAG 2.1 AA color contrast minimum
- Screen reader testing for critical workflows

## Testing

### Unit Tests
- Mock external dependencies (API, router, store)
- Test behavior, not implementation
- Snapshots only for stable, rarely-changing components

### Integration Tests
- API contract tests: response shapes match interfaces
- DOM structural tests: critical elements present and accessible
- CSS regression: visual diff for key pages/states

### End-to-End Tests
- Headless Chromium default
- Critical user workflows, not every page
- Stable selectors: data-testid, not CSS classes
- Network mocking for deterministic data

## Build & Deployment

- Bundle size budgets enforced in CI
- Tree-shaking enabled
- Asset optimization: images, fonts, SVGs
- Source maps in dev, stripped in production
- Environment variables via build-time injection, never committed
