# Browser Compatibility Matrix

> Reference doc for frontend profile. Copied to
> .claude/governance/reference/ during /r:init.

## Default Targets

| Browser | Version | Notes |
|---------|---------|-------|
| Chrome | last 2 | Primary target, Chromium-based |
| Firefox | last 2 | Gecko engine coverage |
| Safari | last 2 | WebKit, iOS default |
| Edge | last 2 | Chromium-based |

## Progressive Enhancement

- Core functionality works without JavaScript where feasible
- CSS features use @supports for graceful degradation
- Polyfills documented and justified (bundle cost vs coverage)

## Testing Protocol

- Playwright: headless Chromium for CI
- Manual: Safari + Firefox for visual/interaction verification
- Mobile: viewport testing at 320px, 768px, 1024px, 1440px
