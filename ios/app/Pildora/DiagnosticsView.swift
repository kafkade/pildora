import PildoraDrugIndexLoader
import SwiftUI

/// Developer diagnostics: exercises the Rust → Swift crypto FFI bridge and
/// surfaces the drug-index tier / download status.
///
/// Preserves the original FFI smoke test (encrypt/decrypt roundtrip) so the
/// bridge stays verifiable from the running app, now tucked behind a tab rather
/// than being the app's only screen.
struct DiagnosticsView: View {
    @State private var result: RoundtripResult?
    /// Optional so the standalone `#Preview` (FFI only) keeps working.
    var drugIndex: TieredDrugIndexProvider?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)

                Text("Pildora crypto FFI")
                    .font(.headline)

                switch result {
                case .none:
                    ProgressView()
                case .success(let plaintext, let blobSize):
                    Label("FFI roundtrip OK", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green)
                    Text("Decrypted: \"\(plaintext)\"")
                        .font(.subheadline)
                    Text("Encrypted blob: \(blobSize) bytes")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                case .failure(let message):
                    Label("FFI roundtrip failed", systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red)
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let drugIndex {
                    Divider().padding(.vertical, 4)
                    DrugIndexDiagnosticsRow(provider: drugIndex)
                }
            }
            .padding()
            .navigationTitle("Diagnostics")
        }
        .task { result = runRoundtrip() }
    }

    /// Encrypt then decrypt a sample string entirely through the Rust crypto
    /// library to verify the FFI bridge end to end.
    private func runRoundtrip() -> RoundtripResult {
        let message = "hello from Pildora"
        do {
            let vaultKey = generateVaultKey()
            let plaintext = Data(message.utf8)
            let blob = try itemEncrypt(plaintext: plaintext, vaultKey: vaultKey)
            let decrypted = try itemDecrypt(blobBytes: blob, vaultKey: vaultKey)
            guard let roundtripped = String(data: decrypted, encoding: .utf8),
                  roundtripped == message else {
                return .failure("decrypted value did not match original")
            }
            return .success(plaintext: roundtripped, blobSize: blob.count)
        } catch {
            return .failure(String(describing: error))
        }
    }
}

private enum RoundtripResult {
    case success(plaintext: String, blobSize: Int)
    case failure(String)
}

/// Compact diagnostics row showing which drug-index tier is active and the
/// full-index download status.
private struct DrugIndexDiagnosticsRow: View {
    @ObservedObject var provider: TieredDrugIndexProvider

    var body: some View {
        VStack(spacing: 4) {
            Text("Drug index")
                .font(.headline)
            Label(tierText, systemImage: provider.activeTier == .full ? "checkmark.seal" : "shippingbox")
                .font(.subheadline)
            Text(stateText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var tierText: String {
        switch provider.activeTier {
        case .core: return "Active tier: core (bundled, offline)"
        case .full: return "Active tier: full (downloaded)"
        }
    }

    private var stateText: String {
        switch provider.state {
        case .idle: return "Idle"
        case .downloading(let progress): return "Downloading full index… \(Int(progress * 100))%"
        case .upToDate(let version): return "Full index up to date (v\(version))"
        case .installed(let version): return "Full index installed (v\(version))"
        case .failed(let reason): return "Download failed: \(reason)"
        }
    }
}

#Preview {
    DiagnosticsView()
}
