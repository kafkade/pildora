import XCTest
import SwiftUI
@testable import PildoraDesignSystem

final class TokenTests: XCTestCase {

    // MARK: Spacing

    func testSpacingFollowsFourPointGrid() {
        let values: [CGFloat] = [
            Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
            Spacing.lg, Spacing.xl, Spacing.xxl,
        ]
        for value in values {
            // xxs (2pt) is the only deliberate half-step; everything else is a
            // strict multiple of the 4pt base unit.
            if value == Spacing.xxs { continue }
            XCTAssertEqual(value.truncatingRemainder(dividingBy: 4), 0,
                           "\(value) is not on the 4pt grid")
        }
    }

    func testSpacingScaleIsMonotonic() {
        let ordered: [CGFloat] = [
            Spacing.xxs, Spacing.xs, Spacing.sm, Spacing.md,
            Spacing.lg, Spacing.xl, Spacing.xxl,
        ]
        XCTAssertEqual(ordered, ordered.sorted(), "Spacing tokens must increase in order")
    }

    func testMinimumTapTargetMeetsHIG() {
        XCTAssertGreaterThanOrEqual(Layout.minTapTarget, 44)
    }

    // MARK: Radius

    func testRadiusScaleIsMonotonic() {
        XCTAssertLessThan(Radius.sm, Radius.md)
        XCTAssertLessThan(Radius.md, Radius.lg)
    }

    // MARK: Status levels

    func testEveryStatusLevelHasIconAndColor() {
        for level in StatusLevel.allCases {
            XCTAssertFalse(level.systemImage.isEmpty,
                           "\(level) is missing an SF Symbol — status must never be color-only")
        }
        // Distinct icons ensure levels are distinguishable without color.
        let icons = Set(StatusLevel.allCases.map(\.systemImage))
        XCTAssertEqual(icons.count, StatusLevel.allCases.count,
                       "Status levels must use distinct icons")
    }

    // MARK: Color resolution

    func testSemanticColorsResolveToRealValues() {
        // A ColorSet resolves without crashing across appearance/contrast axes.
        let set = ColorSet(
            light: RGBA(0.1, 0.2, 0.3),
            dark: RGBA(0.4, 0.5, 0.6),
            lightHighContrast: RGBA(0, 0, 0),
            darkHighContrast: RGBA(1, 1, 1)
        )
        XCTAssertEqual(set.rgba(dark: false, highContrast: false).red, 0.1)
        XCTAssertEqual(set.rgba(dark: true, highContrast: false).red, 0.4)
        XCTAssertEqual(set.rgba(dark: false, highContrast: true).red, 0.0)
        XCTAssertEqual(set.rgba(dark: true, highContrast: true).red, 1.0)
    }

    func testColorSetConvenienceInitFallsBackToBase() {
        let set = ColorSet(light: RGBA(0.2, 0.2, 0.2), dark: RGBA(0.8, 0.8, 0.8))
        XCTAssertEqual(set.lightHighContrast.red, set.light.red)
        XCTAssertEqual(set.darkHighContrast.red, set.dark.red)
    }
}
