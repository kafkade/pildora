# iOS Design System

Contributor guide for `PildoraDesignSystem`
([`ios/design-system/PildoraDesignSystem`](../ios/design-system/PildoraDesignSystem)),
the shared SwiftUI foundation for the Pildora iOS / iPadOS / watchOS apps
(**issue #43** — Phase 0 deliverable, Section 14.2 Epic #10).

The goal: **every screen looks like the same app and is accessible by default.**
Reach for a token or component before writing a raw color, font, or padding.

## Table of contents

- [Principles](#principles)
- [Design tokens](#design-tokens)
  - [Color](#color)
  - [Typography](#typography)
  - [Spacing & radius](#spacing--radius)
- [Components](#components)
- [View modifiers](#view-modifiers)
- [Accessibility checklist](#accessibility-checklist)
- [Preview catalog](#preview-catalog)
- [Adding to the design system](#adding-to-the-design-system)

## Principles

1. **Tokens over literals.** Never hard-code `Color(red:…)`, `.font(.system(size:))`,
   or `padding(16)`. Use `Colors`, `Typography`, and `Spacing` so light mode,
   dark mode, high contrast, and Dynamic Type all work automatically.
2. **Accessibility is a requirement, not a polish pass.** Persona 2 (Margaret,
   67) needs large text and high contrast from day one. Status is never
   communicated by color alone.
3. **Local-first & cross-platform.** The package builds on macOS/iOS/watchOS so
   it compiles under SwiftPM and in CI; the Watch shares color tokens only.

## Design tokens

Import the package, then reference tokens directly or via the `Theme` umbrella
(they are identical):

```swift
import PildoraDesignSystem

.padding(Spacing.lg)                 // direct
.padding(Theme.Spacing.lg)           // grouped
.foregroundStyle(Colors.textSecondary)
.font(Typography.body)
```

### Color

Semantic tokens on `Colors` (aka `Theme.Colors`). Each resolves to the correct
value for the active appearance **and** accessibility-contrast setting at render
time:

| Token | Use for |
|---|---|
| `primary` / `onPrimary` | brand/interactive fills and their foreground |
| `secondary` | secondary controls / de-emphasized accents |
| `background` | the base screen background |
| `surface` | cards and grouped content surfaces |
| `surfaceElevated` | a layer raised above `surface` |
| `textPrimary` / `textSecondary` | body text / supporting text |
| `separator` | hairlines and dividers |
| `success` / `warning` / `error` / `info` | status semantics |

Each token defines four values — light, dark, light-high-contrast, and
dark-high-contrast — so the high-contrast accessibility setting is honored, not
just light/dark. Prefer a semantic token over a raw `Color`; if you need a new
semantic role, add it to `ColorTokens.swift` rather than inlining a color.

### Typography

`Typography` tokens are built on semantic `Font.TextStyle`s, so text scales with
Dynamic Type all the way to the accessibility sizes (`.accessibility1`…`5`,
i.e. xxxLarge+):

`largeTitle`, `title`, `sectionHeader`, `cardTitle`, `cardSubtitle`, `body`,
`bodyEmphasized`, `callout`, `caption`, `captionSmall`.

Never use `.font(.system(size:))` — it defeats Dynamic Type. Where a fixed
dimension is unavoidable (e.g. a min button height), use `@ScaledMetric` so it
still grows with the user's text size.

### Spacing & radius

`Spacing` is a strict 4pt/8pt grid: `xxs`(2) · `xs`(4) · `sm`(8) · `md`(12) ·
`lg`(16) · `xl`(24) · `xxl`(32). `xs` (4pt) is the base unit and `lg` (16pt) is
the default content padding.

`Radius`: `sm`(8) · `md`(12) · `lg`(16) · `pill`. `Layout.minTapTarget` is the
44pt Human Interface Guidelines minimum for interactive elements.

## Components

| Component | Summary |
|---|---|
| `PildoraButton(_:systemImage:variant:action:)` | Text/label button. Variants: `.primary`, `.secondary`, `.destructive`. Full-width, ≥44pt, dims on press. Or apply `PildoraButtonStyle(_:)` to any `Button`. |
| `Card { … }` | Rounded `surface` container with standard padding + radius. |
| `PildoraTextField(_:text:placeholder:systemImage:isSecure:errorMessage:)` | Labeled field with optional icon, secure mode, and inline error (shown as an `error` `StatusBadge`). |
| `ListRow(systemImage:title:subtitle:trailing:)` | Icon/title/subtitle row with a trailing accessory; enforces 44pt height. |
| `StatusBadge(_:level:)` | Icon **+** text **+** color badge. `StatusLevel`: `.neutral`/`.info`/`.success`/`.warning`/`.error`. |
| `SourceTag(_:)` | Drug-reference attribution line (e.g. `"Source: openFDA · Jan 12, 2026"`). |

### `SourceTag` and the disclaimer rule

Any displayed drug reference data must show its source and date, and interaction
warnings must include the "informational only" disclaimer. `SourceTag` lives in
the design system so that attribution is presented consistently everywhere
reference data appears.

## View modifiers

- `sectionHeaderStyle()` — section-header font + VoiceOver `.isHeader` trait.
- `groupedListStyle()` — inset-grouped list on iOS, sensible fallbacks elsewhere.
- `minimumTapTarget()` — guarantees a 44×44pt hit area.

## Accessibility checklist

Before shipping a component or screen, verify:

- [ ] Colors come from `Colors`; contrast holds in light **and** dark.
- [ ] Text uses `Typography`; layout survives Dynamic Type at `.accessibility5`.
- [ ] Status is conveyed by icon **and** text, never color alone.
- [ ] Interactive elements are ≥44×44pt.
- [ ] VoiceOver reads a sensible label; headings use `.isHeader`.
- [ ] It renders correctly in the [preview catalog](#preview-catalog).

## Preview catalog

`DesignSystemCatalog` is a `public` view that renders every token and component
on one screen. Open `Catalog/DesignSystemCatalog.swift` in Xcode to use the
built-in previews (light, dark, Dynamic Type XL), or embed the view in an app
(e.g. behind a Diagnostics tab) to audit the system on-device.

## Adding to the design system

1. Add tokens under `Sources/PildoraDesignSystem/Tokens/`, components under
   `Components/`, and shared modifiers under `Modifiers/`.
2. Keep everything **cross-platform** (`#if os(...)`/`canImport(UIKit)` guards)
   so `swift build` succeeds on the macOS toolchain.
3. Add the new element to `DesignSystemCatalog` so it's visually reviewable.
4. Add/extend tests in `Tests/PildoraDesignSystemTests` (e.g. grid conformance,
   icon-per-status invariants).
5. Run `swift test --package-path ios/design-system/PildoraDesignSystem`.

CI runs this package in the **iOS Packages (macOS)** job. That job's name is a
merge-gate identity managed in `kafkade/github-infra` — adding packages to its
`swift test` loop does **not** change the check name, so no IaC change is needed;
renaming or removing the job would.
