import PildoraDrugIndexLoader
import SwiftUI

/// A dismissible banner that surfaces the full drug-index download to the user.
///
/// Shows only while a download is in flight, briefly after it succeeds, or when
/// it fails (with a Retry action). It renders nothing in the common idle /
/// up-to-date states so it stays out of the way. Autocomplete works from the
/// bundled core index throughout — this banner is purely informational.
struct DrugIndexStatusView: View {
    @ObservedObject var provider: TieredDrugIndexProvider
    @State private var dismissed = false

    var body: some View {
        if let content, !dismissed {
            HStack(spacing: 12) {
                content.icon
                    .foregroundStyle(content.tint)
                    .font(.headline)

                VStack(alignment: .leading, spacing: 2) {
                    Text(content.title)
                        .font(.subheadline.weight(.medium))
                    if let subtitle = content.subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if case .downloading(let progress) = provider.state {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .padding(.top, 2)
                    }
                }

                Spacer(minLength: 0)

                if content.showsRetry {
                    Button("Retry") { provider.startFullIndexDownloadIfNeeded() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.borderless)
                }
                if content.dismissible {
                    Button {
                        dismissed = true
                    } label: {
                        Image(systemName: "xmark")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Dismiss")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .padding(.horizontal, 12)
            .padding(.top, 8)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.default, value: provider.state)
            .onChange(of: downloadPhaseKey) { _, _ in dismissed = false }
        }
    }

    // MARK: Presentation

    private struct Content {
        let icon: Image
        let tint: Color
        let title: String
        let subtitle: String?
        let showsRetry: Bool
        let dismissible: Bool
    }

    private var content: Content? {
        switch provider.state {
        case .idle, .upToDate:
            return nil
        case .downloading:
            return Content(
                icon: Image(systemName: "arrow.down.circle"),
                tint: .accentColor,
                title: "Updating drug database",
                subtitle: "Downloading the full index. Search works now using the built-in list.",
                showsRetry: false,
                dismissible: true
            )
        case .installed:
            return Content(
                icon: Image(systemName: "checkmark.circle.fill"),
                tint: .green,
                title: "Drug database updated",
                subtitle: "Autocomplete now covers the full medication list.",
                showsRetry: false,
                dismissible: true
            )
        case .failed:
            return Content(
                icon: Image(systemName: "exclamationmark.triangle.fill"),
                tint: .orange,
                title: "Couldn't update the drug database",
                subtitle: "You can keep searching the built-in list. We'll try again later.",
                showsRetry: true,
                dismissible: true
            )
        }
    }

    /// Changes whenever the download moves to a new phase, so a previously
    /// dismissed banner re-appears for a genuinely new event.
    private var downloadPhaseKey: Int {
        switch provider.state {
        case .idle: return 0
        case .downloading: return 1
        case .upToDate: return 2
        case .installed: return 3
        case .failed: return 4
        }
    }
}
