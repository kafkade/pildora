# iOS Encrypted Data Model (SQLCipher)

Reference for the on-device encrypted persistence layer implemented in
[`ios/data-layer/PildoraDataLayer`](../ios/data-layer/PildoraDataLayer/)
(issue #44). It covers the schema, encryption boundary, key derivation, and the
migration policy.

This is the **local storage** model: entities are stored as queryable columns
inside a SQLCipher-encrypted database file. It is deliberately distinct from the
**sync** model in [`roadmap.md`](roadmap.md) §9, where entities cross the network
as opaque, versioned encrypted blobs the server cannot read. On-device we need to
query, filter, and index; over the wire we expose nothing.

## Encryption boundary

- **One vault = one encryption boundary = one database file** (`vault-<id>.db`).
- Each file is encrypted by SQLCipher with a key derived from that vault's key.
- No cross-vault leakage is possible; deleting a vault is deleting its file;
  re-keying a vault means writing a new file.
- iOS Data Protection (`NSFileProtectionCompleteUntilFirstUserAuthentication`)
  is layered on top of SQLCipher as defense-in-depth.

## Key derivation

```text
Master Password
  → Argon2id → MUK
    → unwrap Vault Key (VK)              [pildora-crypto]
      → derive_sqlcipher_key(VK)         [crypto-uniffi FFI]
        = HKDF-SHA256(ikm = VK, salt = 0×32, info = "pildora-sqlcipher-db-key", 32 B)
          → lowercase hex → SQLCipher passphrase
```

All cryptography lives in `pildora-crypto`; the Swift layer only calls the FFI
via the `DatabaseKeyDeriving` seam. The derivation is domain-separated (the DB
key never equals the vault key) and locked across Rust and Swift by a shared
known-answer vector.

## Schema

Every health table carries a `vaultId` foreign key. Timestamps are stored with
millisecond precision. The current schema version is `v2` (see
[Migration policy](#migration-policy)).

### vault

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | Primary key |
| `name` | TEXT | Encrypted at rest; can leak a condition, so never plaintext |
| `icon` | TEXT? | Optional |
| `color` | TEXT? | Optional |
| `profileType` | TEXT | `personal` / `child` / `dependent` / `pet` / `other` |
| `createdAt` | DATETIME | |
| `updatedAt` | DATETIME | |

### medication

Medications **and** supplements/vitamins.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | Primary key |
| `vaultId` | TEXT | → `vault(id)` cascade, indexed |
| `name` | TEXT | |
| `genericName` | TEXT? | |
| `dosage` | TEXT | e.g. "88 mcg" |
| `form` | TEXT | `tablet` / `capsule` / `liquid` / … |
| `category` | TEXT | `prescription` / `overTheCounter` / `supplement` / `vitamin` |
| `frequency` | TEXT | Free text, e.g. "Once daily" |
| `prescriber` | TEXT? | |
| `pharmacy` | TEXT? | |
| `notes` | TEXT? | |
| `rxnormId` | TEXT? | Link to the local drug index (Phase 3) |
| `drugReferenceId` | TEXT? | Link to a bundled `DrugReference` (Phase 3) |
| `startDate` | DATETIME? | |
| `endDate` | DATETIME? | |
| `createdAt` | DATETIME | |
| `updatedAt` | DATETIME | |

### schedule

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | Primary key |
| `medicationId` | TEXT | → `medication(id)` cascade, indexed |
| `vaultId` | TEXT | → `vault(id)` cascade, indexed |
| `pattern` | TEXT | `daily` / `specific_days` / `every_n_days` / `prn` |
| `timesJson` | TEXT | JSON array of `"HH:mm"` strings |
| `daysJson` | TEXT? | JSON weekday tokens for `specific_days` |
| `intervalDays` | INTEGER? | for `every_n_days` |
| `startDate` | DATETIME | |
| `endDate` | DATETIME? | |
| `createdAt` | DATETIME | |
| `updatedAt` | DATETIME | |

### dose_log

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | Primary key |
| `medicationId` | TEXT | → `medication(id)` cascade |
| `scheduleId` | TEXT? | → `schedule(id)` set null (nil for PRN) |
| `vaultId` | TEXT | → `vault(id)` cascade, indexed |
| `scheduledAt` | DATETIME? | Due time (nil for PRN) |
| `recordedAt` | DATETIME | When the event was logged |
| `status` | TEXT | `taken` / `skipped` / `missed` / `snoozed` |
| `skipReason` | TEXT? | |
| `notes` | TEXT? | |
| `createdAt` | DATETIME | |

Composite index `idx_dose_log_medication_recorded` on `(medicationId, recordedAt)`
serves the common history and Today-view range queries.

### inventory

| Column | Type | Notes |
| --- | --- | --- |
| `id` | TEXT | Primary key |
| `medicationId` | TEXT | → `medication(id)` cascade, **unique** |
| `vaultId` | TEXT | → `vault(id)` cascade, indexed |
| `currentCount` | INTEGER | On-hand quantity |
| `refillThreshold` | INTEGER? | Low-stock trigger |
| `refillReminderEnabled` | INTEGER | Whether a low-stock refill reminder is scheduled (default `1`; added in **v2**) |
| `lastRefillDate` | DATETIME? | |
| `updatedAt` | DATETIME | |

## Relationships

```text
vault (1) ──< medication (N)
                 ├──< schedule (N)
                 ├──< dose_log (N)   (dose_log.scheduleId ─> schedule, set null)
                 └──< inventory (1)
```

Deleting a medication cascades to its schedules, dose logs, and inventory.
Deleting a vault cascades to all of its health data.

## Migration policy

Schema evolution uses GRDB's `DatabaseMigrator` (see `Migrations.swift`):

- Each change is a new `registerMigration("vN-…")` block with a unique id.
- **Existing migrations are never edited** — the migrator records which have run,
  so each applies exactly once and user databases upgrade in place.
- `eraseDatabaseOnSchemaChange` is left **off** in production (data is preserved).
- The current version identifier is `SchemaMigrations.currentVersion`.

Applied migrations:

- **v1** — initial schema (`vault`, `medication`, `schedule`, `dose_log`, `inventory`).
- **v2** (`v2-inventory-refill-reminder`) — adds `inventory.refillReminderEnabled`
  (`INTEGER NOT NULL DEFAULT 1`), so existing rows upgrade in place with reminders
  enabled.

Phase 3 additions (drug-reference links, interaction data) will land as additive
`v3+` migrations; the nullable `rxnormId` / `drugReferenceId` columns already
reserve the join points.

## Performance

The acceptance target is a single-item store → retrieve roundtrip under 10 ms.
Measured on plain SQLite the roundtrip is sub-millisecond; SQLCipher adds a
modest 5–15% per-page overhead, keeping the encrypted path well within budget.
`PerformanceTests` guards the threshold.
