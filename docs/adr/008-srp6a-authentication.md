# ADR-008: SRP-6a Authentication

**Status:** Accepted
**Date:** 2026-06-27

## Context

Pildora's Phase 2 cloud sync (ADR-004) lets users back up and synchronize their
encrypted vaults across devices. Sync requires the server to authenticate the
account holder — but the project's foundational principle (ADR-001) is
zero-knowledge: **the server must never see the master password, the Master Key,
or any value from which they can be derived offline more cheaply than attacking
the verifier itself.**

Conventional password authentication (send password → server hashes and
compares) violates this directly: the server observes the plaintext password.
Even server-side Argon2 means the server sees the password in transit.

We need a Password-Authenticated Key Exchange (PAKE) that:

1. Proves the client knows the password without revealing it to the server.
2. Lets the server store only a *verifier*, never a password or password-hash
   that is usable for online impersonation.
3. Produces a shared session key for binding subsequent sync requests.
4. Runs in our single Rust crypto crate (`pildora-crypto`, ADR-001/ADR-006) so
   both the client (via FFI/WASM) and the Axum sync server (ADR-006) share one
   audited implementation.

The roadmap (Phase 0 deliverable S13, Section 14.1 Spike #4) selected SRP-6a
(Secure Remote Password, RFC 2945 / RFC 5054) for this role.

## Decision

### Use SRP-6a with the RFC 5054 3072-bit group and SHA-256

We implement SRP-6a in a new `pildora-crypto::srp` module. Parameters:

| Parameter | Choice |
|---|---|
| Group | RFC 5054 3072-bit safe-prime group (= RFC 3526 MODP group 15) |
| Generator `g` | 5 |
| Hash `H` | SHA-256 |
| Multiplier | `k = H(N \| PAD(g))` (SRP-6a, prevents the SRP-6 two-for-one guessing attack) |
| Ephemeral size | 256-bit random `a`, `b` |

A 3072-bit group provides ~128-bit security, matching the AES-256-GCM /
Argon2id-derived keys elsewhere in the hierarchy. SHA-256 is already a crate
dependency (HKDF-SHA-256).

### Protocol flows

**Registration** (client-side, once per account):

```text
MK      = Argon2id(password, s)   # s = the account's Argon2id salt
AuthKey = HKDF(MK, "pildora:v1:auth-key")
x       = OS2IP(AuthKey) mod N    # private exponent (never leaves the device)
v       = g^x mod N               # verifier (uploaded to the server)
```

The server stores `(identity I, salt s, verifier v)`, where **`s` is the same
Argon2id salt used to derive `MK`** (see "Salt semantics" below). It never
receives `x`, the Master Key, `AuthKey`, or the password.

**Authentication** (client ↔ server):

```text
client → server:  identity I                          # who is logging in
server → client:  salt s (= argon_salt)               # so the client can re-derive x
client:  MK = Argon2id(password, s); AuthKey = HKDF(MK); x = OS2IP(AuthKey) mod N
client:  a (random 256-bit), A = g^a mod N            → send A
server:  b (random 256-bit), B = (k*v + g^b) mod N    → send B
both:    u = H(PAD(A) | PAD(B))
client:  S = (B - k*g^x)^(a + u*x) mod N
server:  S = (A * v^u)^b mod N
both:    K = H(PAD(S))                                  # shared session key
client → server:  M1 = H( H(N) XOR H(PAD(g)) | H(I) | s | PAD(A) | PAD(B) | K )
server:  verify M1, then
server → client:  M2 = H( PAD(A) | M1 | K )
client:  verify M2
```

If both proofs verify, both parties hold the same session key `K`, which Phase 2
will use to authenticate sync requests. **The server learns nothing about the
password**: even a malicious server only ever sees `A`, `M1`, and the stored
verifier `v`, none of which permit online impersonation, and `v` is only
vulnerable to the same offline dictionary attack as any password hash.

### Salt semantics

The SRP salt `s` **is the account's Argon2id salt** — the salt fed to
`Argon2id(password, s)` to produce the Master Key. This is a deliberate
consequence of the `x`-from-`AuthKey` divergence: because

```text
x = OS2IP( HKDF( Argon2id(password, s) ) ) mod N
```

the client cannot compute `x` at login without that Argon2id salt. So the server
persists `s` at registration and returns it to the client at the start of
authentication, exactly where RFC 5054 already transmits the SRP salt. There is
no second, independent salt: the Argon2id salt and the SRP salt are one and the
same value. `s` continues to be mixed into `M1` per RFC 5054 to bind it to the
transcript.

This is safe to reveal: the Argon2id salt is not secret (it only needs to be
unique per account to prevent rainbow-table reuse), and disclosing it does not
weaken the Argon2id work factor that protects the verifier.

### Key-exchange / session key

`K = H(PAD(S))` is a 256-bit shared secret established as a side effect of the
authentication. Phase 2 may use it directly as a bearer/MAC key for the sync
session or feed it through HKDF for per-purpose subkeys. That binding is out of
scope for this spike (the handshake is validated in-process only; exposing it
over Axum endpoints is Phase 2 work).

### Encoding convention

All group elements are hashed and serialized as **fixed-width `N_LEN` (384-byte)
big-endian, left-zero-padded** values (RFC 5054 `PAD()`). This removes any
length ambiguity in `k`, `u`, `K`, `M1`, and `M2`, which is essential because
the same byte-exact transcript must be reproduced by the Swift (FFI) and
TypeScript (WASM) ports. The identity `I` and salt `s` are included in `M1` to
bind the proof to the account.

### Validation

Per RFC 5054, the handshake aborts if `A mod N == 0`, `B mod N == 0`, or
`u == 0`. Proof comparison uses a length-checked, branch-free byte compare.

## Divergence from RFC 5054

**This is the one intentional deviation from RFC 5054 and the reason we
implemented SRP from scratch rather than using the RustCrypto `srp` crate.**

RFC 5054 defines the private exponent as:

```text
x = H(salt | H(identity | ":" | password))
```

Pildora instead derives `x` from the existing key hierarchy's **Authentication
Key**:

```text
x = OS2IP(AuthKey) mod N
```

where `AuthKey` is the 32-byte HKDF-SHA-256 output from
`key_hierarchy::derive_sub_keys()` (HKDF info `pildora:v1:auth-key`), interpreted
as a big-endian integer (`OS2IP`). Because `AuthKey` is 256-bit and `N` is
3072-bit, `x < N` always holds and the `mod N` reduction is a defensive no-op.

### Why diverge

1. **Single source of password strength.** ADR-001 already runs the password
   through Argon2id (memory-hard) to produce the Master Key, then HKDF to derive
   `AuthKey`, which the hierarchy explicitly reserves "for SRP-6a." Re-hashing
   the raw password inside SRP with a bare `H(s | H(I:P))` would introduce a
   *second, far weaker* (single SHA-256) password-to-secret path. An attacker who
   stole the verifier could then dictionary-attack it through cheap SHA-256
   instead of through Argon2id. Deriving `x` from `AuthKey` ensures the verifier
   inherits the full Argon2id work factor.
2. **Domain isolation.** `AuthKey` is HKDF-separated from the Master Encryption
   Key (`pildora:v1:auth-key` vs `pildora:v1:master-encryption-key`) and is used
   for nothing else, so using it directly as the SRP secret needs no additional
   domain separation and cannot leak information about the MEK or vault keys.
3. **Reproducible per-step test vectors.** Building on `num-bigint` lets us emit
   known-answer vectors for every intermediate (`k`, `x`, `v`, `A`, `B`, `u`,
   `S`, `K`, `M1`, `M2`) that the Swift and WASM ports must match byte-for-byte.
   The RustCrypto `srp` crate does not expose these intermediates.

The salt `s` is still carried through registration and included in `M1` for
protocol fidelity and transcript binding, but its RFC 5054 cryptographic role
(stretching the password inside `x`) is instead fulfilled by the Argon2id salt
upstream in the hierarchy.

## Security analysis

### Interaction with the Argon2id → MK → AuthKey hierarchy

```text
password ──Argon2id(salt)──► MK ──HKDF "auth-key"──► AuthKey ──OS2IP──► x ──g^x──► v
```

- **Offline attack cost.** The verifier `v` is the only password-derived value
  the server stores. Recovering the password from `v` requires inverting
  `g^x mod N` (discrete log — infeasible) or guessing the password and replaying
  the *full* `Argon2id → HKDF → modexp` chain per guess. The Argon2id work factor
  (64 MiB, 3 iterations) therefore gates offline attacks on a stolen verifier,
  exactly as it gates attacks on stolen vault ciphertext.
- **Zero-knowledge preserved.** The server never receives the password, MK, or
  `x`. SRP's design means a passive or active server learns nothing usable for
  online impersonation. This holds for the divergent `x` derivation because the
  divergence only changes *how the client computes `x` locally*; the wire
  protocol and the server's view are unchanged from standard SRP-6a.
- **No new key-reuse risk.** `AuthKey` is HKDF-isolated and used solely for SRP,
  so reusing it as the SRP exponent does not expose the MEK, vault keys, or item
  keys even if the discrete-log assumption were ever broken.

### ⚠️ Constant-time / memory-hygiene caveat (follow-up, not this spike)

`num-bigint`'s modular exponentiation is **not constant-time**, and `BigUint`
does not implement `Zeroize`, so big-integer secret intermediates (`x`, `S`, and
the `a`/`b` exponents once widened) cannot be reliably wiped from memory and may
be exposed to timing/cache side channels. The implementation mitigates what it
can — the random ephemerals `a`/`b` and the session key `K` are held in
`ZeroizeOnDrop` byte wrappers, and proof comparison is branch-free — but full
side-channel hardening (most likely a migration to `crypto-bigint`'s
constant-time `BoxedUint`/`MontyForm`) is **deferred to Phase 2 hardening**. This
is acceptable for a Phase 0 spike that runs the handshake in-process; it must be
resolved before SRP is exposed over the network. This caveat is duplicated as a
`NOTE` at the top of `crypto/src/srp.rs`.

### Other limitations

- **No identity hiding.** Like standard SRP, the identity `I` is sent in the
  clear. Account enumeration mitigations (e.g. a constant-time "unknown user"
  path with a dummy verifier) are a server-side Phase 2 concern.
- **Verifier theft = offline target.** As above, a stolen verifier is offline
  attackable; its protection rests on Argon2id, not on SRP.

## Alternatives considered

**RustCrypto `srp` crate.** Mature and well-reviewed, but (a) it hard-codes the
RFC 5054 `x = H(s | H(I:P))` derivation, which would bypass our Argon2id work
factor as described above, and (b) it does not expose per-step intermediates for
the cross-platform known-answer vectors that the Swift/WASM ports require.
Rejected for both reasons.

**OPAQUE (aPAKE).** A modern asymmetric PAKE with stronger pre-computation
resistance and built-in credential storage. Attractive long-term, but
substantially more complex, less mature in pure-Rust implementations, and
heavier to port byte-exact across Swift/WASM. Revisit in a future ADR if/when
SRP's limitations bite.

**Standard password auth with server-side Argon2 (roadmap fallback).** Simplest,
but the server observes the plaintext password, directly violating the
zero-knowledge principle. Rejected.

## Consequences

- `pildora-crypto` gains a `srp` module and `num-bigint` / `num-traits`
  dependencies (pure Rust; compiles to native and WASM, so the module is not
  feature-gated).
- A new `CryptoError::Srp` variant reports protocol failures.
- Deterministic known-answer vectors for SRP are added to
  `crypto/test-vectors/vectors.json` (the `srp6a` section) and validated in
  `crypto/tests/test_vectors.rs`; a client↔server roundtrip plus negative cases
  live in `crypto/tests/srp_handshake.rs`.
- **Phase 2 must, before any network exposure:** (1) replace `num-bigint` with a
  constant-time big-integer backend, (2) define the sync server's verifier
  storage schema and the SRP HTTP endpoint sequence, (3) bind the session key
  `K` to sync requests, and (4) add account-enumeration mitigations.
- The `x`-from-`AuthKey` derivation is now a fixed part of the key hierarchy
  contract: changing the `pildora:v1:auth-key` HKDF info or the `OS2IP mod N`
  rule would invalidate every existing verifier.
