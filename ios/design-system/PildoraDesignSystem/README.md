# PildoraDesignSystem

The shared SwiftUI **design system** for the Pildora iOS / iPadOS / watchOS apps
(**issue #43**, Phase 0 / Epic #10). It provides the design tokens and base
component library that every screen builds on, so the apps are visually
consistent and accessible from the first feature.

## What's inside

| Layer | Contents |
|---|---|
| **Tokens** | `Colors` (semantic, light + dark + high-contrast), `Typography` (Dynamic Type scale), `Spacing` (4pt/8pt grid), `Radius`, `Layout.minTapTarget` |
| **Components** | `PildoraButton` (+`PildoraButtonStyle`), `Card`, `PildoraTextField`, `ListRow`, `StatusBadge` (+`StatusLevel`), `SourceTag` |
| **Modifiers** | `sectionHeaderStyle()`, `groupedListStyle()`, `minimumTapTarget()` |
| **Catalog** | `DesignSystemCatalog` — a `public` view + SwiftUI previews showing every token and component in light/dark/Dynamic Type XL |

`Theme` is an umbrella namespace, so `Theme.Spacing.lg`, `Theme.Colors.surface`,
and `Theme.Typography.body` are equivalent to the direct `Spacing.lg`,
`Colors.surface`, `Typography.body`.

## Accessibility is not optional

- **Never color-only:** `StatusBadge` always pairs a semantic color with an SF
  Symbol and text.
- **Dynamic Type:** all typography tokens are built on semantic
  `Font.TextStyle`s and scale to accessibility sizes (xxxLarge+). Persona 2
  (Margaret, 67) drives the high-contrast color variants.
- **Tap targets:** interactive components meet the 44×44pt minimum.
- **VoiceOver:** components combine their text into single labels and mark
  headings with `.isHeader`.

## Usage

```swift
import SwiftUI
import PildoraDesignSystem

struct Example: View {
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.lg) {
            Text("Medications").sectionHeaderStyle()

            Card {
                ListRow(systemImage: "pills", title: "Ibuprofen", subtitle: "200 mg") {
                    StatusBadge("In stock", level: .success)
                }
            }

            PildoraTextField("Name", text: $name, placeholder: "e.g. Ibuprofen")
            PildoraButton("Save", variant: .primary) { /* … */ }
        }
        .padding(Spacing.lg)
        .background(Colors.background)
    }
}
```

See [`docs/ios-design-system.md`](../../../docs/ios-design-system.md) for the
full contributor guide.

## Platforms

macOS 14 / iOS 17 / watchOS 10. The Watch app shares the **color tokens**;
Watch-specific components are a separate concern (issue #43).

macOS support exists so the package builds and previews on the SwiftPM toolchain
(and in CI) — the shipping targets are the Apple platforms above.

## Build & test

```sh
swift test --package-path ios/design-system/PildoraDesignSystem
```

Validated in CI by the **iOS Packages (macOS)** job in
`.github/workflows/validate.yml`.
