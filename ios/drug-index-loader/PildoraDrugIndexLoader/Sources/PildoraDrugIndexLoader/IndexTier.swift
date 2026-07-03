import Foundation

// MARK: - IndexTier

/// Which of the two shipped index tiers is currently serving autocomplete.
///
/// - ``core``: the compact index bundled inside the app (works fully offline).
/// - ``full``: the larger index downloaded from the CDN on first launch.
public enum IndexTier: String, Sendable, Equatable {
    case core
    case full
}
