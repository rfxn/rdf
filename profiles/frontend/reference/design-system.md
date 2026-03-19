# Design System Reference

> Reference doc for frontend profile. Copied to
> .claude/governance/reference/ during /r:init.

## Token Categories

| Category | Examples | Source of Truth |
|----------|----------|-----------------|
| Color | primary, secondary, error, surface | CSS custom properties |
| Spacing | xs, sm, md, lg, xl | CSS custom properties |
| Typography | heading, body, caption, mono | CSS custom properties |
| Breakpoints | mobile, tablet, desktop, wide | Sass/CSS variables |
| Shadows | sm, md, lg | CSS custom properties |

## Component Conventions

- Each component: own directory with index, styles, tests
- Props interface exported and documented
- Storybook or equivalent for visual catalog (if project uses it)
- Variant naming: size (sm/md/lg), variant (primary/secondary/ghost)

## Consistency Rules

- Never use raw color values -- always reference tokens
- Never use raw pixel values for spacing -- always reference scale
- Icon system: single source (SVG sprite, icon font, or component lib)
- Animation durations from token scale, not ad-hoc values
