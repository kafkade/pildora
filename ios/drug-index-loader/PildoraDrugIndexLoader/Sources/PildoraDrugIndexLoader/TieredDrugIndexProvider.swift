import Foundation
import PildoraDrugIndex

// MARK: - ActiveIndexBox

/// Thread-safe holder for the currently active `DrugIndex`.
///
/// Autocomplete reads happen on whatever thread the medication editor calls
/// from, while the tier can be swapped from `core` to `full` on the main actor
/// once a download completes. A lock keeps that swap race-free without forcing
/// every keystroke through the main actor.
final class ActiveIndexBox: @unchecked Sendable {
    private let lock = NSLock()
    private var index: DrugIndex
    private var _tier: IndexTier

    init(_ index: DrugIndex, tier: IndexTier) {
        self.index = index
        self._tier = tier
    }

    var tier: IndexTier {
        lock.lock(); defer { lock.unlock() }
        return _tier
    }

    func current() -> DrugIndex {
        lock.lock(); defer { lock.unlock() }
        return index
    }

    func set(_ index: DrugIndex, tier: IndexTier) {
        lock.lock(); defer { lock.unlock() }
        self.index = index
        self._tier = tier
    }
}

// MARK: - TieredDrugIndexProvider

/// The app-facing entry point for tiered drug autocomplete.
///
/// - Serves `DrugSuggesting` from the bundled **core** index immediately (fully
///   offline), transparently switching to the **full** index once it is
///   downloaded and installed.
/// - Publishes `activeTier` and download `state` for a progress UI.
///
/// Zero-knowledge: `suggestions(matching:limit:)` only ever queries the local
/// index; query text never leaves the device. Only the one-time full-index
/// download touches the network, and it fetches public reference data.
///
/// The app conforms this type to `PildoraMedicationList.DrugSuggesting` (a
/// one-line extension) so the medication editor can consume it directly; the
/// loader itself stays free of a medication-list dependency.
@MainActor
public final class TieredDrugIndexProvider: ObservableObject {

    /// Observable status of the full-index download for a progress UI.
    public enum DownloadState: Equatable, Sendable {
        case idle
        case downloading(progress: Double)
        case upToDate(version: String)
        case installed(version: String)
        case failed(reason: String)
    }

    @Published public private(set) var activeTier: IndexTier
    @Published public private(set) var state: DownloadState = .idle

    private let box: ActiveIndexBox
    private let store: InstalledIndexStore
    private let downloader: FullIndexDownloader?
    private var downloadTask: Task<Void, Never>?

    /// Build a provider.
    ///
    /// - Parameters:
    ///   - coreIndexURL: the bundled core index (`.db`) shipped with the app.
    ///   - store: where the downloaded full index is installed.
    ///   - downloader: performs the full-index download; `nil` disables the
    ///     network path (core-only mode, e.g. when no endpoint is configured).
    public init(
        coreIndexURL: URL,
        store: InstalledIndexStore,
        downloader: FullIndexDownloader?
    ) throws {
        self.store = store
        self.downloader = downloader

        // Prefer an already-installed, readable full index; fall back to core.
        if store.hasInstalledFullIndex(),
           let full = try? DrugIndex(path: store.installedFullIndexURL.path, readonly: true) {
            self.box = ActiveIndexBox(full, tier: .full)
            self.activeTier = .full
            if let v = store.installedVersion() {
                self.state = .upToDate(version: v)
            }
        } else {
            let core = try DrugIndex(path: coreIndexURL.path, readonly: true)
            self.box = ActiveIndexBox(core, tier: .core)
            self.activeTier = .core
        }
    }

    // MARK: Autocomplete

    /// Ranked drug + supplement matches for a prefix query, served from the
    /// active tier. Matches the shape of `PildoraMedicationList.DrugSuggesting`.
    public nonisolated func suggestions(matching query: String, limit: Int) throws -> [DrugSuggestion] {
        try box.current().search(query, limit: limit)
    }

    // MARK: Download control

    /// Kick off a background check + download of the full index if one is
    /// configured. Safe to call repeatedly; a download already in flight is not
    /// duplicated. Never blocks autocomplete and never throws — failures are
    /// reflected in `state` and leave the active index untouched.
    public func startFullIndexDownloadIfNeeded() {
        guard let downloader else { return }
        guard downloadTask == nil else { return }
        if case .downloading = state { return }

        state = .downloading(progress: 0)
        downloadTask = Task { [weak self] in
            await self?.runDownload(downloader)
            self?.downloadTask = nil
        }
    }

    private func runDownload(_ downloader: FullIndexDownloader) async {
        do {
            let outcome = try await downloader.updateIfAvailable { [weak self] progress in
                Task { @MainActor in
                    guard let self else { return }
                    if case .downloading = self.state {
                        self.state = .downloading(progress: progress)
                    }
                }
            }
            switch outcome {
            case .upToDate(let version):
                state = .upToDate(version: version)
            case .installed(let version):
                let full = try DrugIndex(path: store.installedFullIndexURL.path, readonly: true)
                box.set(full, tier: .full)
                activeTier = .full
                state = .installed(version: version)
            }
        } catch {
            // Graceful fallback: stay on the core index, surface the reason.
            state = .failed(reason: String(describing: error))
        }
    }
}
