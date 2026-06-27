import SwiftUI

/// Minimal smoke-test view that exercises the Rust → Swift FFI bridge.
///
/// Its only purpose is to prove that the Run Script build phase cross-compiled
/// `pildora-crypto-ffi`, linked the static library, and that the UniFFI
/// bindings call into Rust correctly at runtime. It is **not** a product
/// screen.
struct ContentView: View {
    @State private var result: RoundtripResult?

    var body: some View {
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
    ContentView()
}
