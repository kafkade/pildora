import SwiftUI

/// Developer diagnostics: exercises the Rust → Swift crypto FFI bridge.
///
/// Preserves the original FFI smoke test (encrypt/decrypt roundtrip) so the
/// bridge stays verifiable from the running app, now tucked behind a tab rather
/// than being the app's only screen.
struct DiagnosticsView: View {
    @State private var result: RoundtripResult?

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

#Preview {
    DiagnosticsView()
}
