# WCAG 2.1 AA Compliance Checklist

> Reference doc for frontend profile. Copied to
> .rdf/governance/reference/ during /r:init.
> Covers WCAG 2.1 Level AA. Not exhaustive -- prioritizes criteria
> most commonly failed in web applications.

## Perceivable

### Text Alternatives (1.1)
- Every `<img>` has `alt` text describing its purpose, or `alt=""` if decorative
- Icon buttons have `aria-label` or visually hidden text
- Complex images (charts, diagrams) have long description via `aria-describedby`
- Background images that convey meaning have a text alternative in the DOM

### Time-Based Media (1.2)
- Video has captions (synchronized, accurate, including speaker identification)
- Audio-only content has a text transcript
- Pre-recorded video has audio description for visual-only information

### Adaptable (1.3)
- Content structure conveyed through semantic HTML (`<h1>`-`<h6>`, `<nav>`,
  `<main>`, `<aside>`, `<table>` with `<th>`) -- not visual styling alone
- Reading order in DOM matches visual order -- CSS layout does not reorder
  content in a way that changes meaning
- Input purpose identified via `autocomplete` attribute on common fields
  (name, email, address, credit card)

### Distinguishable (1.4)
- Text color contrast: 4.5:1 minimum for normal text, 3:1 for large text
  (18pt / 14pt bold)
- UI component and graphical object contrast: 3:1 against adjacent colors
- Text resizable to 200% without loss of content or functionality
- Content reflows at 320px viewport width without horizontal scrolling
- No loss of information when user overrides text spacing (line height 1.5x,
  paragraph spacing 2x, letter spacing 0.12em, word spacing 0.16em)
- Audio that auto-plays for more than 3 seconds has pause/stop/volume control

## Operable

### Keyboard Accessible (2.1)
- All functionality available via keyboard (Tab, Shift-Tab, Enter, Space,
  Arrow keys, Escape)
- No keyboard traps -- focus can always move away from any component
- Custom widgets follow WAI-ARIA Authoring Practices keyboard patterns
  (combobox, dialog, tabs, menu)

### Enough Time (2.2)
- Session timeouts: warn before expiration, allow extension
- Auto-updating content (feeds, tickers) has pause/stop control
- No time limits on form completion unless essential (e.g., auction)

### Seizure-Safe (2.3)
- No content flashes more than 3 times per second
- Animations respect `prefers-reduced-motion` media query

### Navigable (2.4)
- Skip link as first focusable element -- targets `<main>` content
- Page titles are descriptive and unique (`<title>`)
- Focus order follows logical reading sequence
- Link purpose clear from link text alone (no "click here" / "read more"
  without context)
- Multiple navigation mechanisms (nav menu, sitemap, search)
- Visible focus indicator on all interactive elements -- default outline or
  custom style with sufficient contrast

### Input Modalities (2.5)
- Pointer cancellation: `mouseup`/`pointerup` for activation, not `mousedown`
  -- allows user to move pointer away to cancel
- `aria-label` matches or contains visible label text (Label in Name)
- No functionality relies solely on motion (shake, tilt) without alternative

## Understandable

### Readable (3.1)
- Page language declared via `<html lang="en">` (or appropriate code)
- Language changes within content marked with `lang` attribute on container

### Predictable (3.2)
- No unexpected context changes on focus or input (no auto-submit on
  select change, no auto-navigate on focus)
- Consistent navigation across pages -- same order, same labels
- Consistent identification -- same function uses same label/icon throughout

### Input Assistance (3.3)
- Error messages identify the field and describe the error in text
  (not just red border or icon)
- Required fields identified before submission (asterisk with legend, or
  `aria-required="true"`)
- Error prevention for legal/financial/data-deletion actions: confirm,
  review, or reversible
- Labels or instructions provided for all inputs -- placeholder text alone
  is not sufficient (disappears on focus)

## Robust

### Compatible (4.1)
- Valid HTML -- no duplicate IDs, proper nesting, closed tags
- Custom components expose `name`, `role`, `value` to assistive technology
  via ARIA attributes
- Status messages (success, error, progress) announced to screen readers
  via `role="status"` or `role="alert"` -- no focus shift required

## Testing Methodology

### Automated (CI Integration)
- `axe-core` via `@axe-core/playwright`, `cypress-axe`, or `jest-axe` --
  catches ~30-40% of WCAG issues automatically
- `eslint-plugin-jsx-a11y` (React) or equivalent linting for template a11y
- `pa11y-ci` for page-level automated audits in CI pipeline
- Lighthouse accessibility audit score threshold as build gate

### Manual Keyboard Testing
- Tab through entire page -- verify focus order is logical
- Activate every interactive element with Enter and Space
- Navigate composite widgets with Arrow keys
- Close modals/dialogs with Escape
- Verify focus returns to trigger element after dialog close
- Verify focus is managed on route changes (SPA)

### Screen Reader Testing
- NVDA on Windows (free, Firefox) -- primary screen reader for testing
- VoiceOver on macOS (built-in, Safari) -- secondary testing
- Test critical workflows: navigation, forms, data tables, modals
- Verify live regions announce dynamic updates
- Verify headings create navigable document outline

### Color Contrast Tools
- WebAIM Contrast Checker -- manual verification of specific pairs
- Browser DevTools accessibility panel -- real-time contrast checking
- Figma/design tool plugins -- catch issues before implementation
- Automated color contrast check in CI via axe-core rules
