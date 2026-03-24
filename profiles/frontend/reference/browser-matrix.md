# Browser Compatibility Matrix

> Reference doc for frontend profile. Copied to
> .rdf/governance/reference/ during /r-init.

## Default Targets

| Browser | Version | Notes |
|---------|---------|-------|
| Chrome | last 2 | Primary target, Chromium-based |
| Firefox | last 2 | Gecko engine coverage |
| Safari | last 2 | WebKit, iOS default |
| Edge | last 2 | Chromium-based |

## Progressive Enhancement Strategy

- Core functionality works without JavaScript where feasible -- forms
  submit, links navigate, content is readable
- CSS features use `@supports` for graceful degradation:
  ```css
  .grid { display: flex; flex-wrap: wrap; }
  @supports (display: grid) { .grid { display: grid; } }
  ```
- Polyfills documented and justified -- each polyfill adds bundle cost;
  require a comment with the target browser and removal date
- Feature detection over browser detection -- never sniff `User-Agent`;
  use `'IntersectionObserver' in window` or Modernizr-style checks
- Browserslist config (`.browserslistrc` or `package.json`) is the
  single source of truth for target browsers -- build tools (Babel,
  PostCSS, Autoprefixer) all read from it
- ES2020 baseline features available without polyfill: optional
  chaining (`?.`), nullish coalescing (`??`), `Promise.allSettled`,
  `globalThis`, dynamic `import()`

## Mobile Viewport Testing

| Breakpoint | Target | Notes |
|------------|--------|-------|
| 320px | Small phone (iPhone SE) | Minimum supported width |
| 768px | Tablet portrait | Navigation layout shift |
| 1024px | Tablet landscape / small desktop | Sidebar visibility |
| 1440px | Desktop | Maximum content width |

- Test at each breakpoint in both portrait and landscape orientation
- Touch targets minimum 44x44px (WCAG 2.5.5, iOS HIG)
- Verify no horizontal scrolling at 320px and above
- Test with on-screen keyboard visible -- fixed elements must not
  obscure input fields

## Testing Protocol

- Playwright: headless Chromium for CI
- Manual: Safari + Firefox for visual/interaction verification
- Mobile: viewport testing at each breakpoint in device emulation
- Real device testing for touch interactions and performance (at
  least one iOS Safari and one Android Chrome device)
