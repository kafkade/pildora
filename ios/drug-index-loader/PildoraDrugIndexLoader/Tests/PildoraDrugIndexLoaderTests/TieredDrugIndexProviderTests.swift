import Foundation
import PildoraDrugIndex
import XCTest

@testable import PildoraDrugIndexLoader

@MainActor
final class TieredDrugIndexProviderTests: XCTestCase {

    private var storeDir: URL!

    override func setUpWithError() throws {
        storeDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-store-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: storeDir)
    }

    // MARK: - Core-only / offline

    func testCoreOnlyServesSuggestionsWithoutNetwork() throws {
        let fixture = try IndexFixture.make()
        let store = try InstalledIndexStore(directory: storeDir)
        let provider = try TieredDrugIndexProvider(
            coreIndexURL: fixture.coreURL, store: store, downloader: nil
        )

        XCTAssertEqual(provider.activeTier, .core)
        XCTAssertEqual(provider.state, .idle)

        let hits = try provider.suggestions(matching: IndexFixture.commonPrefix, limit: 10)
        XCTAssertTrue(hits.contains { $0.displayName == IndexFixture.commonName })
        // The full-only drug is absent from core.
        let warf = try provider.suggestions(matching: IndexFixture.fullOnlyPrefix, limit: 10)
        XCTAssertFalse(warf.contains { $0.displayName == IndexFixture.fullOnlyName })
    }

    func testStartDownloadNoOpWhenCoreOnly() throws {
        let fixture = try IndexFixture.make()
        let store = try InstalledIndexStore(directory: storeDir)
        let provider = try TieredDrugIndexProvider(
            coreIndexURL: fixture.coreURL, store: store, downloader: nil
        )
        provider.startFullIndexDownloadIfNeeded()
        XCTAssertEqual(provider.state, .idle)
        XCTAssertEqual(provider.activeTier, .core)
    }

    // MARK: - Successful swap

    func testSwapsToFullAfterSuccessfulDownload() async throws {
        let fixture = try IndexFixture.make()
        let store = try InstalledIndexStore(directory: storeDir)
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }
        let downloader = FullIndexDownloader(
            baseURL: testBaseURL, client: client, store: store,
            maxAttempts: 3, retryBackoff: .zero
        )
        let provider = try TieredDrugIndexProvider(
            coreIndexURL: fixture.coreURL, store: store, downloader: downloader
        )

        XCTAssertEqual(provider.activeTier, .core)
        provider.startFullIndexDownloadIfNeeded()
        try await waitForTerminalState(provider)

        XCTAssertEqual(provider.state, .installed(version: fixture.indexVersion))
        XCTAssertEqual(provider.activeTier, .full)

        // Now the full-only drug resolves.
        let warf = try provider.suggestions(matching: IndexFixture.fullOnlyPrefix, limit: 10)
        XCTAssertTrue(warf.contains { $0.displayName == IndexFixture.fullOnlyName })
    }

    // MARK: - Failure fallback + retry

    func testStaysOnCoreWhenDownloadFails() async throws {
        let fixture = try IndexFixture.make()
        let store = try InstalledIndexStore(directory: storeDir)
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }
        client.failDownloadsBeforeSuccess = 99  // always fail
        let downloader = FullIndexDownloader(
            baseURL: testBaseURL, client: client, store: store,
            maxAttempts: 2, retryBackoff: .zero
        )
        let provider = try TieredDrugIndexProvider(
            coreIndexURL: fixture.coreURL, store: store, downloader: downloader
        )

        provider.startFullIndexDownloadIfNeeded()
        try await waitForTerminalState(provider)

        guard case .failed = provider.state else {
            return XCTFail("expected .failed, got \(provider.state)")
        }
        XCTAssertEqual(provider.activeTier, .core)
        // Autocomplete still works from the bundled core.
        let hits = try provider.suggestions(matching: IndexFixture.commonPrefix, limit: 10)
        XCTAssertTrue(hits.contains { $0.displayName == IndexFixture.commonName })
    }

    func testRetryAfterFailureEventuallySwaps() async throws {
        let fixture = try IndexFixture.make()
        let store = try InstalledIndexStore(directory: storeDir)
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }
        client.fetchError = URLError(.notConnectedToInternet)  // manifest fetch fails first
        let downloader = FullIndexDownloader(
            baseURL: testBaseURL, client: client, store: store,
            maxAttempts: 1, retryBackoff: .zero
        )
        let provider = try TieredDrugIndexProvider(
            coreIndexURL: fixture.coreURL, store: store, downloader: downloader
        )

        provider.startFullIndexDownloadIfNeeded()
        try await waitForTerminalState(provider)
        guard case .failed = provider.state else {
            return XCTFail("expected first attempt to fail, got \(provider.state)")
        }
        XCTAssertEqual(provider.activeTier, .core)

        // "Network came back" — a later retry succeeds.
        client.fetchError = nil
        provider.startFullIndexDownloadIfNeeded()
        try await waitForTerminalState(provider)

        XCTAssertEqual(provider.state, .installed(version: fixture.indexVersion))
        XCTAssertEqual(provider.activeTier, .full)
    }

    // MARK: - Latency

    func testFullIndexSuggestionLatencyUnder50ms() async throws {
        let fixture = try IndexFixture.make()
        let store = try InstalledIndexStore(directory: storeDir)
        let client = MockDownloadClient()
        client.manifestData = fixture.manifestData()
        client.artifactProvider = { try fixture.makeArtifactFile() }
        let downloader = FullIndexDownloader(
            baseURL: testBaseURL, client: client, store: store,
            maxAttempts: 1, retryBackoff: .zero
        )
        let provider = try TieredDrugIndexProvider(
            coreIndexURL: fixture.coreURL, store: store, downloader: downloader
        )
        provider.startFullIndexDownloadIfNeeded()
        try await waitForTerminalState(provider)
        XCTAssertEqual(provider.activeTier, .full)

        let start = DispatchTime.now()
        _ = try provider.suggestions(matching: IndexFixture.commonPrefix, limit: 10)
        let elapsedMs = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        XCTAssertLessThan(elapsedMs, 50, "autocomplete took \(elapsedMs)ms")
    }

    // MARK: - Helpers

    /// Poll until the provider leaves `.idle`/`.downloading`, or time out.
    private func waitForTerminalState(
        _ provider: TieredDrugIndexProvider,
        timeout: TimeInterval = 5
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            switch provider.state {
            case .installed, .upToDate, .failed:
                return
            case .idle, .downloading:
                try await Task.sleep(nanoseconds: 5_000_000)  // 5ms
            }
        }
        XCTFail("timed out waiting for terminal state (last: \(provider.state))")
    }
}
