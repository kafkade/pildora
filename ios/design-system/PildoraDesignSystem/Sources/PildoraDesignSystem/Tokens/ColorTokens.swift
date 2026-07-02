import SwiftUI

// MARK: - Color primitives

/// A single sRGB color value used to build a `ColorSet`.
struct RGBA: Sendable {
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(_ red: Double, _ green: Double, _ blue: Double, _ alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

/// A resolvable color across appearance (light/dark) and contrast
/// (normal/high) axes. This gives the design system explicit control over dark
/// mode *and* the high-contrast requirement of Persona 2 (Margaret, 67), rather
/// than relying solely on system-semantic colors.
struct ColorSet: Sendable {
    let light: RGBA
    let dark: RGBA
    let lightHighContrast: RGBA
    let darkHighContrast: RGBA

    /// Full control over all four appearance/contrast combinations.
    init(light: RGBA, dark: RGBA, lightHighContrast: RGBA, darkHighContrast: RGBA) {
        self.light = light
        self.dark = dark
        self.lightHighContrast = lightHighContrast
        self.darkHighContrast = darkHighContrast
    }

    /// Convenience: high-contrast variants fall back to the base values.
    init(light: RGBA, dark: RGBA) {
        self.init(light: light, dark: dark, lightHighContrast: light, darkHighContrast: dark)
    }

    func rgba(dark: Bool, highContrast: Bool) -> RGBA {
        switch (dark, highContrast) {
        case (false, false): return light
        case (false, true): return lightHighContrast
        case (true, false): return self.dark
        case (true, true): return darkHighContrast
        }
    }
}

extension Color {
    /// Resolves a `ColorSet` into a SwiftUI `Color` that reacts to the active
    /// interface style and accessibility-contrast setting at render time.
    init(_ set: ColorSet) {
        #if os(watchOS)
        // watchOS uses a permanently dark interface and does not expose a
        // trait-based dynamic provider, so resolve the dark values directly.
        let rgba = set.rgba(dark: true, highContrast: false)
        self = Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        #elseif canImport(UIKit)
        self = Color(uiColor: UIColor { traits in
            let dark = traits.userInterfaceStyle == .dark
            let high = traits.accessibilityContrast == .high
            let rgba = set.rgba(dark: dark, highContrast: high)
            return UIColor(red: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        })
        #elseif canImport(AppKit)
        self = Color(nsColor: NSColor(name: nil) { appearance in
            let match = appearance.bestMatch(from: [
                .aqua,
                .darkAqua,
                .accessibilityHighContrastAqua,
                .accessibilityHighContrastDarkAqua,
            ])
            let dark = match == .darkAqua || match == .accessibilityHighContrastDarkAqua
            let high = match == .accessibilityHighContrastAqua
                || match == .accessibilityHighContrastDarkAqua
            let rgba = set.rgba(dark: dark, highContrast: high)
            return NSColor(srgbRed: rgba.red, green: rgba.green, blue: rgba.blue, alpha: rgba.alpha)
        })
        #else
        let rgba = set.rgba(dark: false, highContrast: false)
        self = Color(.sRGB, red: rgba.red, green: rgba.green, blue: rgba.blue, opacity: rgba.alpha)
        #endif
    }
}

// MARK: - Semantic color tokens

/// Semantic color tokens. Reference these — never raw `Color(.sRGB…)` — so
/// light mode, dark mode, and high-contrast accessibility settings are honored
/// automatically and consistently everywhere.
///
/// Watch apps share these same tokens (per issue #43).
public enum Colors {

    // Brand / interactive
    public static let primary = Color(ColorSet(
        light: RGBA(0.00, 0.40, 0.80),
        dark: RGBA(0.30, 0.62, 1.00),
        lightHighContrast: RGBA(0.00, 0.29, 0.63),
        darkHighContrast: RGBA(0.47, 0.73, 1.00)
    ))
    /// Foreground for content placed on top of `primary` (e.g. button labels).
    public static let onPrimary = Color(ColorSet(
        light: RGBA(1, 1, 1),
        dark: RGBA(1, 1, 1),
        lightHighContrast: RGBA(1, 1, 1),
        darkHighContrast: RGBA(0, 0, 0)
    ))
    public static let secondary = Color(ColorSet(
        light: RGBA(0.35, 0.35, 0.37),
        dark: RGBA(0.68, 0.68, 0.70)
    ))

    // Surfaces
    /// The base window/screen background.
    public static let background = Color(ColorSet(
        light: RGBA(1.00, 1.00, 1.00),
        dark: RGBA(0.07, 0.07, 0.075)
    ))
    /// A grouped content surface (cards, grouped list backgrounds).
    public static let surface = Color(ColorSet(
        light: RGBA(0.949, 0.949, 0.969),
        dark: RGBA(0.11, 0.11, 0.12)
    ))
    /// A raised surface layered above `surface`.
    public static let surfaceElevated = Color(ColorSet(
        light: RGBA(1.00, 1.00, 1.00),
        dark: RGBA(0.17, 0.17, 0.18)
    ))

    // Text
    public static let textPrimary = Color(ColorSet(
        light: RGBA(0.05, 0.05, 0.05),
        dark: RGBA(0.96, 0.96, 0.96),
        lightHighContrast: RGBA(0, 0, 0),
        darkHighContrast: RGBA(1, 1, 1)
    ))
    public static let textSecondary = Color(ColorSet(
        light: RGBA(0.35, 0.35, 0.37),
        dark: RGBA(0.68, 0.68, 0.70),
        lightHighContrast: RGBA(0.20, 0.20, 0.22),
        darkHighContrast: RGBA(0.85, 0.85, 0.87)
    ))
    public static let separator = Color(ColorSet(
        light: RGBA(0.82, 0.82, 0.84),
        dark: RGBA(0.28, 0.28, 0.30),
        lightHighContrast: RGBA(0.55, 0.55, 0.57),
        darkHighContrast: RGBA(0.60, 0.60, 0.62)
    ))

    // Status
    public static let success = Color(ColorSet(
        light: RGBA(0.13, 0.55, 0.24),
        dark: RGBA(0.28, 0.78, 0.40),
        lightHighContrast: RGBA(0.08, 0.42, 0.16),
        darkHighContrast: RGBA(0.40, 0.86, 0.52)
    ))
    public static let warning = Color(ColorSet(
        light: RGBA(0.72, 0.45, 0.00),
        dark: RGBA(1.00, 0.72, 0.20),
        lightHighContrast: RGBA(0.55, 0.34, 0.00),
        darkHighContrast: RGBA(1.00, 0.80, 0.35)
    ))
    public static let error = Color(ColorSet(
        light: RGBA(0.75, 0.10, 0.12),
        dark: RGBA(1.00, 0.42, 0.42),
        lightHighContrast: RGBA(0.60, 0.05, 0.07),
        darkHighContrast: RGBA(1.00, 0.55, 0.55)
    ))
    public static let info = Color(ColorSet(
        light: RGBA(0.00, 0.40, 0.80),
        dark: RGBA(0.30, 0.62, 1.00),
        lightHighContrast: RGBA(0.00, 0.29, 0.63),
        darkHighContrast: RGBA(0.47, 0.73, 1.00)
    ))
}
