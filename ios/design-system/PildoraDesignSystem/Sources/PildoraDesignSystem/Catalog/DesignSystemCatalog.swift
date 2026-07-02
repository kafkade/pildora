import SwiftUI

// MARK: - Design System Catalog

/// A living catalog that renders every design token and base component in one
/// scrollable screen. Use it to visually verify the design system across light
/// mode, dark mode, and Dynamic Type sizes (including accessibility sizes).
///
/// It is a `public` view so app targets can embed it (e.g. behind a Diagnostics
/// tab); the `#Preview`s below exercise the key accessibility configurations.
public struct DesignSystemCatalog: View {
    public init() {}

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.xl) {
                colorSection
                typographySection
                spacingSection
                componentSection
            }
            .padding(Spacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Colors.background)
    }

    // MARK: Colors

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Colors").sectionHeaderStyle()
            ForEach(Self.colorSwatches, id: \.name) { swatch in
                HStack(spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                        .fill(swatch.color)
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: Radius.sm, style: .continuous)
                                .strokeBorder(Colors.separator, lineWidth: 1)
                        )
                    Text(swatch.name)
                        .font(Typography.body)
                        .foregroundStyle(Colors.textPrimary)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    // MARK: Typography

    private var typographySection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Typography").sectionHeaderStyle()
            Group {
                Text("Large Title").font(Typography.largeTitle)
                Text("Title").font(Typography.title)
                Text("Section Header").font(Typography.sectionHeader)
                Text("Card Title").font(Typography.cardTitle)
                Text("Card Subtitle").font(Typography.cardSubtitle)
                Text("Body — scales with Dynamic Type").font(Typography.body)
                Text("Callout").font(Typography.callout)
                Text("Caption").font(Typography.caption)
            }
            .foregroundStyle(Colors.textPrimary)
        }
    }

    // MARK: Spacing

    private var spacingSection: some View {
        VStack(alignment: .leading, spacing: Spacing.sm) {
            Text("Spacing").sectionHeaderStyle()
            ForEach(Self.spacingSamples, id: \.name) { sample in
                HStack(spacing: Spacing.md) {
                    Rectangle()
                        .fill(Colors.primary)
                        .frame(width: sample.value, height: 16)
                    Text("\(sample.name) · \(Int(sample.value))pt")
                        .font(Typography.caption)
                        .foregroundStyle(Colors.textSecondary)
                }
            }
        }
    }

    // MARK: Components

    private var componentSection: some View {
        VStack(alignment: .leading, spacing: Spacing.md) {
            Text("Components").sectionHeaderStyle()

            Card {
                VStack(alignment: .leading, spacing: Spacing.sm) {
                    Text("Card").font(Typography.cardTitle)
                    Text("A grouped surface container.")
                        .font(Typography.cardSubtitle)
                        .foregroundStyle(Colors.textSecondary)
                    SourceTag("Source: openFDA · Jan 12, 2026")
                }
            }

            VStack(spacing: Spacing.sm) {
                PildoraButton("Primary action", variant: .primary) {}
                PildoraButton("Secondary action", variant: .secondary) {}
                PildoraButton("Delete", systemImage: "trash", variant: .destructive) {}
            }

            PildoraTextField(
                "Medication name",
                text: .constant("Ibuprofen"),
                placeholder: "e.g. Ibuprofen",
                systemImage: "pills"
            )
            PildoraTextField(
                "Dosage",
                text: .constant(""),
                placeholder: "Required",
                errorMessage: "Enter a dosage"
            )

            Card(padding: Spacing.sm) {
                VStack(spacing: 0) {
                    ListRow(systemImage: "pills", title: "Ibuprofen", subtitle: "200 mg · as needed") {
                        StatusBadge("In stock", level: .success)
                    }
                    Divider().overlay(Colors.separator)
                    ListRow(systemImage: "leaf", title: "Vitamin D", subtitle: "1000 IU · daily") {
                        StatusBadge("Low: 6 left", level: .warning)
                    }
                }
            }

            VStack(alignment: .leading, spacing: Spacing.sm) {
                ForEach(StatusLevel.allCases, id: \.self) { level in
                    StatusBadge(String(describing: level).capitalized, level: level)
                }
            }
        }
    }

    // MARK: Catalog data

    private struct Swatch { let name: String; let color: Color }
    private struct SpacingSample { let name: String; let value: CGFloat }

    private static let colorSwatches: [Swatch] = [
        Swatch(name: "primary", color: Colors.primary),
        Swatch(name: "secondary", color: Colors.secondary),
        Swatch(name: "surface", color: Colors.surface),
        Swatch(name: "surfaceElevated", color: Colors.surfaceElevated),
        Swatch(name: "textPrimary", color: Colors.textPrimary),
        Swatch(name: "textSecondary", color: Colors.textSecondary),
        Swatch(name: "success", color: Colors.success),
        Swatch(name: "warning", color: Colors.warning),
        Swatch(name: "error", color: Colors.error),
        Swatch(name: "info", color: Colors.info),
    ]

    private static let spacingSamples: [SpacingSample] = [
        SpacingSample(name: "xxs", value: Spacing.xxs),
        SpacingSample(name: "xs", value: Spacing.xs),
        SpacingSample(name: "sm", value: Spacing.sm),
        SpacingSample(name: "md", value: Spacing.md),
        SpacingSample(name: "lg", value: Spacing.lg),
        SpacingSample(name: "xl", value: Spacing.xl),
        SpacingSample(name: "xxl", value: Spacing.xxl),
    ]
}

// MARK: - Previews

#if DEBUG
#Preview("Catalog · Light") {
    DesignSystemCatalog()
        .preferredColorScheme(.light)
}

#Preview("Catalog · Dark") {
    DesignSystemCatalog()
        .preferredColorScheme(.dark)
}

#Preview("Catalog · Dynamic Type XL") {
    DesignSystemCatalog()
        .environment(\.dynamicTypeSize, .accessibility3)
}
#endif
