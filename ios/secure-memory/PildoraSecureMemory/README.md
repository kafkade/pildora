# PildoraSecureMemory

Swift library for **issue #40** — a move-only secure-memory wrapper that
guarantees sensitive key material is zeroized from memory when it is no longer
needed.

This is the Swift counterpart to the Rust `zeroize::ZeroizeOnDrop` key types in
[`crypto/src/keys.rs`](../../../crypto/src/keys.rs). It resolves the production
hardening item flagged in
[ADR-007](../../../docs/adr/007-rust-swift-ffi-bridge.md) (Security
considerations) and the [FFI spike README](../../ffi-spike/README.md).

## Why this exists

UniFFI manages allocation across the Rust → Swift boundary, but Swift `Data` and
`[UInt8]` are **not guaranteed to be zeroized** when their storage is released.
Key material (master key, vault key, MEK, auth key) that crosses into Swift
memory can therefore linger in deallocated pages.

`SecureBytes`:

- owns a heap-allocated mutable byte buffer,
- securely wipes that buffer on `deinit` (via `memset_s` / `explicit_bzero`,
  with a volatile-loop fallback), and
- is a move-only (`~Copyable`) type, so the compiler forbids the silent copies
  that would otherwise scatter key material across memory.

This is **defense-in-depth**. iOS already provides hardware memory encryption
(Secure Enclave) and per-app address-space isolation; this wrapper additionally
shortens the lifetime of plaintext key material inside the app's own address
space.

## Usage

```swift
import PildoraSecureMemory

// 1. Wrap key material returned from the FFI bridge immediately.
var vaultKey = SecureBytes(generateVaultKey())   // [UInt8] -> SecureBytes

// 2. Access the bytes only through scoped accessors — no copies escape.
vaultKey.withUnsafeBytes { raw in
    // pass `raw` straight into the next crypto call …
}

// 3. Fill key material in place, avoiding an unmanaged intermediate buffer.
let derived = SecureBytes(count: 32) { buffer in
    // write 32 bytes directly into secured storage
}

// 4. `vaultKey` and `derived` are wiped from memory when they leave scope.
//    Call `zeroize()` to wipe earlier if a value must outlive the secret.
```

Because `SecureBytes` is `~Copyable`, values are **moved**, not copied. After
`let moved = consume original`, the compiler rejects any further use of
`original`. This is the copy-prevention guarantee the type exists to provide.

## API surface

| Member | Purpose |
|---|---|
| `init(count:)` | Allocate a zero-filled buffer. |
| `init(count:initializingWith:)` | Allocate and fill in place (no intermediate copy). |
| `init(_ bytes: [UInt8])` | Copy an existing array into secured storage. |
| `init(_ data: Data)` | Copy `Data` into secured storage. |
| `withUnsafeBytes(_:)` | Scoped read-only access (`borrowing`). |
| `withUnsafeMutableBytes(_:)` | Scoped in-place mutation (`mutating`). |
| `zeroize()` | Overwrite contents with zeros immediately (idempotent). |
| `count` / `isEmpty` | Size inspection. |
| `redactedDescription` | Size-only string; never reveals contents. |

`secureZero(_:)` is also exposed as a standalone primitive for wiping any
`UnsafeMutableBufferPointer<UInt8>` / `UnsafeMutableRawBufferPointer`.

## Sensitive FFI APIs

The following calls from the UniFFI bridge (`crypto-uniffi`, exposed to Swift as
shown in [`ffi-spike`](../../ffi-spike/)) return **sensitive material**. The
returned `[UInt8]` / `String` should be moved into `SecureBytes` immediately and
its lifetime kept as short as possible.

| FFI call | Returns | Sensitivity |
|---|---|---|
| `deriveMasterKey(password:salt:)` | 32-byte master key | 🔴 Highest — derives all sub-keys |
| `deriveMasterKeyWithParams(...)` | 32-byte master key | 🔴 Highest |
| `deriveSubKeys(masterKey:)` | `auth_key` (32 B) + `mek` (32 B) | 🔴 MEK wraps every vault key |
| `generateVaultKey()` | 32-byte vault key | 🔴 Encrypts all items in a vault |
| `unwrapVaultKey(wrappedVk:mek:)` | 32-byte vault key | 🔴 |
| `itemDecrypt(blobBytes:vaultKey:)` | Decrypted plaintext bytes | 🟠 Decrypted health data |
| `decryptJson(blobBytes:vaultKey:)` | Decrypted JSON string | 🟠 Decrypted health data |

Inputs that carry key material (for example the `vaultKey` / `mek` arguments and
the `password` to `deriveMasterKey`) are equally sensitive on the way **in**.
Source them from a `SecureBytes` via `withUnsafeBytes` and build the throwaway
`[UInt8]` argument inside that closure.

Non-sensitive calls — `generateSalt()`, `blake2bHash(data:)`, `wrapVaultKey`
output (already encrypted), and `itemEncrypt` / `encryptJson` blobs (ciphertext)
— do not require `SecureBytes`.

> Note: `String` values returned by `decryptJson` cannot be wiped in place
> (Swift strings may use copy-on-write storage). When the plaintext is a secret,
> prefer `itemDecrypt` and wrap the resulting bytes in `SecureBytes`.

## Status

✅ Self-contained library. Builds and tests with plain `swift test` — no Rust
toolchain or XCFramework required. Wire it into the app and the FFI call sites
when the iOS app target is assembled (Phase 1).

```bash
cd ios/secure-memory/PildoraSecureMemory
swift test
```

## Dependencies

- None. Pure Foundation / Swift standard library.
- Implements the hardening item from [ADR-007](../../../docs/adr/007-rust-swift-ffi-bridge.md).
