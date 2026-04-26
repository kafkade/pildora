# pildora-crypto Test Vectors

Cross-platform test vectors for validating that Swift FFI, WASM, and any
future implementations produce identical cryptographic output to the
canonical Rust implementation.

## Purpose

One implementation, one set of test vectors, zero divergence risk. Every
platform that consumes `pildora-crypto` must pass all vectors before
shipping.

## Vector Categories

| Category | Vectors | What is tested |
|---|---|---|
| `argon2id` | 4 | Password → 32-byte key (64 MiB, t=3, p=1) |
| `hkdf_sha256` | 3 | HKDF-SHA-256 extract-then-expand |
| `aes256_gcm` | 4 | AES-256-GCM encrypt with explicit nonce |
| `keywrap` | 2 | AES-256-GCM key wrapping with domain AAD |
| `blake2b` | 5 | BLAKE2b-256 hash (unkeyed) and MAC (keyed) |
| `key_hierarchy` | 2 | Full password → MK → auth\_key + MEK chain |
| `item_encryption` | 4 | Golden blobs: decrypt with known vault key |
| **Total** | **24** | |

## Vector Format

### Deterministic vectors (argon2id, hkdf, aes256\_gcm, keywrap, blake2b, key\_hierarchy)

All inputs are provided; the expected output is deterministic. Implementers
must verify that their output matches `expected_*_hex` exactly.

- **Hex encoding**: All binary values are lowercase hex strings.
- **Null salt**: `"salt_hex": null` means the HKDF salt parameter is omitted
  (not the same as an empty salt).
- **AAD**: For keywrap and AES-GCM, the `aad` or `aad_hex` field provides the
  authenticated associated data used during encryption.

### AES-256-GCM ciphertext format

The `expected_ciphertext_hex` field contains: `nonce(12) || ciphertext || tag(16)`.

### Item encryption golden blobs

These vectors use the public `item_encrypt` API, which generates random nonces
and random item keys internally. The blob bytes are captured once and committed.
Other platforms verify they can **decrypt** (not encrypt) the blob using the
provided vault key to recover the original plaintext.

Blob format (v1): `version(1) || nonce(12) || padded_ciphertext || tag(16) || wrapped_item_key(60)`.

## Regenerating Vectors

Deterministic vectors can be regenerated at any time (output will be
identical). Item encryption blobs contain random nonces — regenerating
will produce different blobs, so only regenerate if you also update the
committed `vectors.json`.

```shell
cargo run -p pildora-crypto --bin generate_vectors > crypto/test-vectors/vectors.json
```

## Validating Vectors

```shell
cargo test -p pildora-crypto --test test_vectors
```

## Guidelines for Other Platforms

### Swift (iOS / macOS / watchOS)

1. Bundle `vectors.json` as a test resource.
2. Parse the JSON and iterate each category.
3. For Argon2id, HKDF, BLAKE2b, and key hierarchy: compute the output and
   compare to `expected_*_hex`.
4. For AES-256-GCM and keywrap: use an explicit-nonce API (e.g.,
   `CryptoKit.AES.GCM.seal(nonce:)`) and compare.
5. For item encryption: pass the blob bytes and vault key to the FFI
   `item_decrypt` binding and verify the plaintext matches.

### TypeScript / WASM (Web)

1. Import `vectors.json` in your test framework.
2. Call the WASM-exported functions with the hex-decoded inputs.
3. Same comparison logic as Swift.

### Adding New Vectors

1. Add the generation logic to `crypto/src/bin/generate_vectors.rs`.
2. Add the corresponding struct and test to `crypto/tests/test_vectors.rs`.
3. Regenerate: `cargo run -p pildora-crypto --bin generate_vectors > crypto/test-vectors/vectors.json`
4. Run: `cargo test -p pildora-crypto --test test_vectors`
