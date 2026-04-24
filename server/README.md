# Pildora Sync Server

Thin encrypted blob sync server, built with Go.

## Overview

The sync server stores and retrieves encrypted blobs. It **cannot read, decrypt, or analyze** any user health data.

- **Auth**: SRP-6a (zero-knowledge — server stores SRP verifier, never the password)
- **Storage**: PostgreSQL (encrypted blobs, account metadata, timestamps)
- **Sync**: Encrypted blob sync with version vectors, last-write-wins conflict resolution
- **What the server sees**: encrypted ciphertext, blob sizes, timestamps, email, subscription status
- **What the server cannot see**: medication names, schedules, doses, health data, vault contents

## Status

🚧 Not yet implemented. Planned for Phase 2 (Encrypted Cloud Sync).
