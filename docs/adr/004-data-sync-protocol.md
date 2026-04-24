# ADR-004: Data Sync Protocol

**Status:** Accepted
**Date:** 2026-04-24

## Context

Pildora must support multi-device sync (iPhone ↔ iPad ↔ web ↔ CLI) while
maintaining zero-knowledge — the sync server stores only encrypted blobs it
cannot read. We need a sync protocol that handles conflict resolution on
encrypted data, since the server cannot merge or inspect field values.

This decision applies to Phase 2+. The MVP (Phase 1) is local-only with no
sync.

## Decision

**Item-level encrypted blob sync with last-write-wins (LWW) conflict
resolution.**

### How it works

1. Each item (medication, dose log, schedule, etc.) is encrypted on-device,
   producing an encrypted blob.
2. Each blob is tagged with a Lamport timestamp and a device ID, embedded
   inside the encrypted envelope.
3. On sync, the client pushes new/modified blobs to the server.
4. The server stores: `{vault_id, item_id, encrypted_blob, version, updated_at}`
   — it cannot read any content.
5. When pulling, the client downloads blobs modified since the last sync
   checkpoint.
6. If two devices modified the same item between syncs, the client decrypts
   both versions and the **higher Lamport timestamp wins** (LWW).
7. The losing version is preserved in a local conflict log for 30 days, giving
   the user a chance to review if needed.

### Server storage model

```sql
CREATE TABLE encrypted_items (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    item_type TEXT NOT NULL,
    encrypted_blob BLOB NOT NULL,
    version INTEGER NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
```

The server cannot query, filter, or index any encrypted content. All querying
happens on-device after decryption.

### Sync frequency

Batch sync on a timer (every 15 minutes when app is active) rather than on each
action. This prevents real-time behavioral inference from sync timing patterns.

## Alternatives Considered

**CRDTs (Conflict-free Replicated Data Types):** Elegant for conflict-free
merging, but CRDTs require the merge logic to operate on plaintext fields —
the merge function needs to understand the data structure (e.g., "take the
union of two medication lists"). This is incompatible with encrypted blobs
where the server cannot read or merge content. Rejected.

**Full vault re-download on each sync:** Simpler but too expensive at scale.
A vault with 50 medications, 365 days of dose logs, and vaccination records
would transfer megabytes on each sync. Item-level sync transfers only changed
items. Rejected.

**Operational Transform (OT):** Designed for real-time collaborative editing
(Google Docs). Overkill for medication tracking where concurrent edits to the
same item are rare (you don't edit a dose log from two devices simultaneously).
Rejected.

**Client-side CRDT on decrypted data:** The client decrypts, applies CRDT merge
locally, re-encrypts, and pushes back. Theoretically possible but adds
significant complexity for a low-frequency conflict scenario. Deferred — may
revisit if LWW proves insufficient.

## Consequences

- Concurrent edits to the **same item** from two devices will lose the older
  edit (LWW). This is acceptable for medication data where concurrent edits
  are rare.
- The conflict log provides a safety net — users can recover lost edits within
  30 days.
- Blob padding (512B, 2KB, 8KB, 32KB buckets) should be applied to prevent
  the server from inferring content type from blob size.
- Schema versioning is embedded in the encrypted blob format (version byte).
  Client-side migration runs on decryption — no server-side migrations needed.
- The server is intentionally "dumb" — it stores and retrieves blobs. This
  keeps the server thin and reduces the attack surface.
