# PildoraDataLayer

Encrypted, vault-scoped on-device persistence for the Pildora iOS app —
**issue #44** (Phase 0 / S13). Built on [GRDB.swift](https://github.com/groue/GRDB.swift)
over SQLCipher, this package is the data foundation the feature slices
(`medication-list` #50, `today-view` #47) persist against.

It graduates the [`sqlcipher-spike`](../../sqlcipher-spike/) prototype into a
production package: the five-entity data model, CRUD repositories, a versioned
migration framework, and the crypto glue that derives the SQLCipher key from a
vault key.

## Status

✅ Implemented and unit-tested. Encryption is active in the Xcode app target
(SQLCipher + `GRDBCIPHER`); command-line `swift test` runs the same code on
plain SQLite, so the model, migrations, and CRUD are fully exercised while the
on-disk cipher is validated in the app.

## Architecture

```text
Vault key (32 B, from pildora-crypto)
  → derive_sqlcipher_key  (Rust FFI: HKDF-SHA256, info "pildora-sqlcipher-db-key")
    → 32 B → lowercase hex → SQLCipher passphrase
      → one vault = one .db file  (NSFileProtectionCompleteUntilFirstUserAuthentication)
        → GRDB DatabaseQueue (WAL, foreign_keys = ON)
          → versioned migrations → typed CRUD for 5 entities
```

### One vault = one database file

Each vault is a hard encryption boundary stored in its own SQLCipher file
(`vault-<id>.db`), managed by `VaultDatabaseManager`. This means no cross-vault
data can leak, re-keying a vault is creating a new file, and deleting a vault is
deleting a file. Multi-vault is supported from day one even though the UX ships
later.

### Data model

Columns live inside the encrypted database (queryable on-device) — this is the
local storage layer, distinct from the opaque-blob sync model in
[`docs/roadmap.md`](../../../docs/roadmap.md) §9. Every health table carries a
`vaultId`.

| Table | Purpose | Key relationships |
| --- | --- | --- |
| `vault` | Profile / encryption boundary metadata | parent of all health data |
| `medication` | Medications **and** supplements/vitamins | `vaultId` → vault (cascade) |
| `schedule` | Dose recurrence (JSON times/days) | `medicationId` → medication (cascade) |
| `dose_log` | Taken / skipped / missed / snoozed events | `medicationId` → medication (cascade), `scheduleId` → schedule (set null) |
| `inventory` | On-hand count + refill threshold | `medicationId` → medication (unique, cascade) |

Full column-level detail and the migration policy are in
[`docs/ios-data-model.md`](../../../docs/ios-data-model.md).

## Key derivation

The SQLCipher passphrase is **not** the vault key. It is derived from it by the
Rust FFI function `derive_sqlcipher_key` (in `crypto-uniffi`) using HKDF-SHA256
with the domain label `pildora-sqlcipher-db-key`, keeping all cryptography in
`pildora-crypto`. The package stays decoupled from the FFI static library via
the `DatabaseKeyDeriving` protocol: the app injects an adapter that calls the
FFI, and tests inject a byte-compatible double.

```swift
import pildora_crypto_ffi

struct FFIDatabaseKeyDeriver: DatabaseKeyDeriving {
    func deriveDatabaseKey(vaultKey: Data) throws -> Data {
        try deriveSqlcipherKey(vaultKey: vaultKey)
    }
}
```

The derivation is locked across languages by a shared known-answer vector: the
Rust test `ffi_derive_sqlcipher_key_known_answer` and the Swift test
`testDeriverMatchesRustKnownAnswerVector` assert the same 32-byte output for a
fixed input key.

## Usage

```swift
let manager = try VaultDatabaseManager(keyDeriver: FFIDatabaseKeyDeriver())

// Open (or create) a vault's encrypted database.
let db = try manager.open(vaultId: vault.id, vaultKey: vaultKey)

try db.insertVault(vault)
try db.insertMedication(
    Medication(vaultId: vault.id, name: "Levothyroxine", dosage: "88 mcg")
)

let meds = try db.fetchMedications(vaultId: vault.id)
```

## Enabling SQLCipher (Xcode app target)

`swift test` links plain SQLite. To encrypt on device, the app target must build
GRDB against SQLCipher and define the `GRDBCIPHER` compilation condition. With
Swift Package Manager the supported path is a SQLCipher-backed GRDB (for example
CocoaPods `pod 'GRDB.swift/SQLCipher'`, or an SPM SQLCipher wrapper), plus:

```text
SWIFT_ACTIVE_COMPILATION_CONDITIONS = $(inherited) GRDBCIPHER
```

When enabled, `AppDatabase.cipherVersion()` returns the linked SQLCipher
version; otherwise it returns `nil`.

## Build & test

```bash
cd ios/data-layer/PildoraDataLayer
swift test
```

## Security notes

- The database passphrase is derived on unlock and **never persisted**.
- iOS Data Protection (`completeUntilFirstUserAuthentication`) is layered on top
  of SQLCipher as defense-in-depth (no-op on macOS / under `swift test`).
- No plaintext health data is written to disk; vault metadata (name, icon)
  lives only inside the encrypted database because names can leak conditions.

## Files

```text
ios/data-layer/PildoraDataLayer/
  Package.swift
  Sources/PildoraDataLayer/
    Models/        Vault, Medication, Schedule, DoseLog, InventoryRecord, Enums
    Database/      AppDatabase (CRUD), Migrations, VaultDatabaseManager,
                   DatabaseKeyDeriving (+ errors/constants)
  Tests/PildoraDataLayerTests/
    TestSupport, KeyDerivingTests, MigrationTests, CRUDTests,
    VaultDatabaseManagerTests, PerformanceTests
```
