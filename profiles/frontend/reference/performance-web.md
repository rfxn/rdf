# Web Performance Reference

> Reference doc for frontend profile. Copied to
> .rdf/governance/reference/ during /r-init.
> Targets are guidelines -- adjust per project based on audience
> and infrastructure.

## Core Web Vitals Targets

| Metric | Good | Needs Improvement | Poor |
|--------|------|-------------------|------|
| LCP (Largest Contentful Paint) | < 2.5s | 2.5s -- 4.0s | > 4.0s |
| INP (Interaction to Next Paint) | < 200ms | 200ms -- 500ms | > 500ms |
| CLS (Cumulative Layout Shift) | < 0.1 | 0.1 -- 0.25 | > 0.25 |

### Measurement Tools
- `web-vitals` library -- collect real user metrics (RUM), send to analytics
- Lighthouse CI (`lhci`) -- synthetic lab measurement in CI pipeline
- Chrome DevTools Performance panel -- diagnose specific bottlenecks
- PageSpeed Insights -- field data from Chrome User Experience Report

### CI Integration
- Performance budgets as build gates -- fail CI when LCP or bundle
  size regresses beyond threshold
- Lighthouse CI with assertions: `--assert.preset=lighthouse:recommended`
- Track metrics over time in a dashboard (SpeedCurve, Grafana) to
  catch gradual regressions that pass per-build thresholds

## Bundle Size Budgets

| Asset Type | Budget (compressed) | Rationale |
|------------|-------------------|-----------|
| JS (initial) | ~170 KB gzip | ~1s parse on mid-tier mobile (Moto G4) |
| CSS (initial) | ~50 KB gzip | Blocks render -- keep minimal |
| Images (per page) | ~500 KB total | Largest contributor to page weight |
| Fonts | ~100 KB total | Subset to used glyphs, 1-2 families max |

### Monitoring
- `size-limit` or `bundlesize` in CI -- define per-entry-point limits
  in `package.json` or config file
- Bundle analyzer (`webpack-bundle-analyzer`, `rollup-plugin-visualizer`,
  `@next/bundle-analyzer`) -- run periodically to identify bloat
- Dependency auditing: `npx depcheck` for unused dependencies,
  `bundlephobia.com` before adding new ones

## Render Optimization

### Critical Rendering Path
- Inline critical CSS (above-fold styles) in `<head>` -- load remaining
  CSS asynchronously with `media="print" onload="this.media='all'"`
- Minimize render-blocking resources -- `defer` scripts, async
  non-critical CSS, preload critical assets
- `<link rel="preconnect">` for third-party origins (fonts, CDN, API)

### Font Loading
- `font-display: swap` -- show fallback immediately, swap when loaded
- Preload critical font files: `<link rel="preload" as="font" crossorigin>`
- Subset fonts to used character ranges (Latin, extended Latin) --
  tools: `glyphhanger`, `subfont`
- Self-host fonts -- avoids third-party DNS lookup and cookie overhead

### Image Optimization
- Modern formats: WebP/AVIF with `<picture>` fallback to JPEG/PNG
- Responsive images: `srcset` with width descriptors, `sizes` attribute
- SVG for icons, logos, and simple illustrations -- optimize with SVGO
- `width` and `height` attributes on `<img>` -- prevents CLS by
  reserving space before load

## Lazy Loading

### Route-Based Code Splitting
- Dynamic `import()` for route components -- each route loads only its
  own code (`React.lazy`, Vue async components, SvelteKit load)
- Prefetch likely next routes on link hover or viewport intersection
- Shared dependencies in a common chunk -- avoid duplicating React/Vue
  across route bundles

### Image and Component Lazy Loading
- `loading="lazy"` on below-fold images -- native browser support,
  no JavaScript required
- Intersection Observer for complex cases (carousels, infinite scroll,
  progressive image loading)
- Component-level code splitting for heavy widgets (charts, editors,
  maps) -- load on interaction or viewport entry

### Prefetch and Preload
- `<link rel="prefetch">` for resources needed on likely next navigation
- `<link rel="preload">` for resources needed on current page but
  discovered late (fonts, critical images)
- Do not preload everything -- excess preloads compete with critical
  resources and waste bandwidth

## Caching Strategy

### HTTP Cache Headers
- Hashed static assets (JS, CSS, images): `Cache-Control: public,
  max-age=31536000, immutable` -- filename changes on content change
- HTML documents: `Cache-Control: no-cache` -- always revalidate to
  get latest asset references
- API responses: `Cache-Control` per endpoint sensitivity -- `no-store`
  for user-specific data, short `max-age` for semi-static lists

### Service Worker Patterns
- Cache-first for static assets (JS, CSS, fonts, images) -- fast
  repeat loads, update in background
- Network-first for API data -- fresh content with offline fallback
- Stale-while-revalidate for semi-static content (product listings,
  blog posts) -- fast display, background refresh

### Asset Fingerprinting
- Content-hash in filenames (`app.a1b2c3.js`) -- enables aggressive
  caching with automatic cache busting on deploy
- Build tool handles fingerprinting (webpack `[contenthash]`, Vite
  default behavior) -- never manually version filenames
- Long-lived vendor chunk separated from app code -- vendor bundle
  stays cached across app deployments
