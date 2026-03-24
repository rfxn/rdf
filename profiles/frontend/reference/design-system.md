# Design System Reference

> Reference doc for frontend profile. Copied to
> .rdf/governance/reference/ during /r-init.

## Token Categories

| Category | Examples | Source of Truth |
|----------|----------|-----------------|
| Color | primary, secondary, error, surface | CSS custom properties |
| Spacing | xs (4px), sm (8px), md (16px), lg (24px), xl (32px) | CSS custom properties |
| Typography | heading, body, caption, mono | CSS custom properties |
| Breakpoints | mobile (320px), tablet (768px), desktop (1024px), wide (1440px) | Sass/CSS variables |
| Shadows | sm (subtle), md (card), lg (modal/dropdown) | CSS custom properties |
| Animation | fast (100ms), normal (200ms), slow (400ms) | CSS custom properties |
| Border Radius | sm (2px), md (4px), lg (8px), full (9999px) | CSS custom properties |
| Z-Index | dropdown (100), sticky (200), modal (300), toast (400) | CSS custom properties |

## Token Rules

- Never use raw color values -- always reference a token:
  `color: var(--color-primary)`, not `color: #3b82f6`
- Never use raw pixel values for spacing -- always reference the scale:
  `padding: var(--space-md)`, not `padding: 13px`
- Semantic tokens layer on top of primitive tokens:
  `--color-error: var(--red-500)` -- swap primitives without touching
  semantic usage
- Animation durations from the token scale -- ad-hoc values like
  `transition: 0.35s` drift across components

## Component Conventions

- Each component: own directory with index, styles, tests
- Props interface exported and documented
- Storybook or equivalent for visual catalog (if project uses it)

### Variant Naming

| Dimension | Values | Purpose |
|-----------|--------|---------|
| Size | `sm`, `md`, `lg` | Controls padding, font size, icon size |
| Variant | `primary`, `secondary`, `ghost`, `outline` | Visual treatment |
| State | `default`, `hover`, `active`, `disabled`, `loading` | Interaction state |

- Combine dimensions with consistent prop names:
  `<Button size="sm" variant="primary" disabled />`
- Default values: `size="md"`, `variant="primary"`, `state="default"`
- Never encode multiple dimensions in one prop -- `type="small-primary"`
  is not composable

## Icon System

- Choose one approach per project: SVG sprite sheet, component library
  (e.g., `lucide-react`, `heroicons`), or inline SVG components
- Consistent sizing tied to spacing tokens -- icons use `--icon-sm` (16px),
  `--icon-md` (20px), `--icon-lg` (24px)
- Icons inherit `currentColor` for fill/stroke -- color controlled by
  parent text color, not per-icon overrides
- Decorative icons: `aria-hidden="true"` -- screen readers skip them
- Meaningful icons: `aria-label` on the icon or visible adjacent text
- Avoid icon fonts -- SVG is sharper, more accessible, tree-shakeable

## Consistency Rules

- Token overrides happen at the theme level, not the component level --
  a single component should not redefine `--color-primary`
- Icon system: single source, one consistent import path across the
  project
- Component API patterns consistent across the library -- if `Button`
  uses `variant`, `Card` uses `variant` (not `type` or `style`)
