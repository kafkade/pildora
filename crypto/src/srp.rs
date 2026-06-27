//! SRP-6a (Secure Remote Password) zero-knowledge authentication.
//!
//! This module implements the SRP-6a protocol (RFC 5054 / RFC 2945) from
//! scratch on top of [`num_bigint`], so that Pildora can (a) emit per-step
//! known-answer test vectors for cross-platform validation and (b) derive the
//! SRP private exponent `x` from the existing key hierarchy rather than from
//! RFC 5054's `x = H(salt | H(I | ":" | P))`.
//!
//! # Protocol summary
//!
//! ```text
//! Registration (client → server, once):
//!     x = OS2IP(AuthKey) mod N           (private exponent, never sent)
//!     v = g^x mod N                      (verifier, stored by server)
//!
//! Authentication:
//!     client:  a (random), A = g^a mod N
//!     server:  b (random), B = (k*v + g^b) mod N
//!     both:    u = H(PAD(A) | PAD(B))
//!     client:  S = (B - k*g^x)^(a + u*x) mod N
//!     server:  S = (A * v^u)^b mod N
//!     both:    K = H(PAD(S))             (shared session key)
//!     client → server:  M1 = H(H(N) XOR H(PAD(g)) | H(I) | s | PAD(A) | PAD(B) | K)
//!     server → client:  M2 = H(PAD(A) | M1 | K)
//! ```
//!
//! # Divergence from RFC 5054
//!
//! The private exponent `x` is **not** `H(salt | H(identity | ":" | password))`.
//! Instead it is derived deterministically from the [`AuthKey`] produced by
//! [`crate::key_hierarchy::derive_sub_keys`] (HKDF info `pildora:v1:auth-key`):
//!
//! ```text
//! x = OS2IP(AuthKey) mod N
//! ```
//!
//! `AuthKey` is a 256-bit HKDF output and `N` is 3072-bit, so `x < N` always and
//! the reduction is a defensive no-op. This binds SRP to the full
//! Argon2id → MK → `AuthKey` hierarchy while keeping the server zero-knowledge:
//! it only ever stores the verifier `v`. See ADR-008 for the full rationale and
//! security analysis.
//!
//! # Salt semantics
//!
//! The SRP salt `s` **is the account's Argon2id salt** — the same salt used to
//! derive the Master Key (`MK = Argon2id(password, s)`). Because `x` is derived
//! from `AuthKey = HKDF(MK)`, the client needs that Argon2id salt at login to
//! re-derive `MK → AuthKey → x`.
//!
//! Therefore:
//!
//! - **Registration** stores `(identity I, salt s = argon_salt, verifier v)` on
//!   the server.
//! - **Auth-start** has the server return `s` to the client, which re-derives
//!   `MK → AuthKey → x` and runs the handshake.
//! - `s` is still mixed into `M1` per RFC 5054 to bind the transcript.
//!
//! Callers MUST pass this same Argon2id salt as the `salt` argument to
//! [`ClientHandshake::process`] / [`ServerHandshake::process`], and MUST use it
//! to derive the [`AuthKey`] they pass to [`compute_verifier`] /
//! [`ClientHandshake::process`].
//!
//! # ⚠️ Constant-time NOTE
//!
//! [`num_bigint::BigUint`] modular exponentiation is **not constant-time**, and
//! `BigUint` does not implement [`Zeroize`], so intermediate big-integer secrets
//! (e.g. `x`, the shared secret `S`) cannot be reliably wiped from memory.
//! Public-facing secret byte material (`a`, `b`, and the session key `K`) is held
//! in zeroizing wrappers, but full side-channel hardening — likely a migration to
//! `crypto-bigint` — is a Phase 2 follow-up, not part of this spike.

// SRP-6a is conventionally written with single-letter variables (N, g, k, a, A,
// b, B, u, x, v, s, S, K); this module mirrors that notation deliberately.
#![allow(clippy::many_single_char_names)]

use std::sync::OnceLock;

use num_bigint::BigUint;
use num_traits::Zero;
use rand::RngCore;
use rand::rngs::OsRng;
use sha2::{Digest, Sha256};
use zeroize::{Zeroize, ZeroizeOnDrop};

use crate::error::{CryptoError, Result};
use crate::key_hierarchy::AuthKey;

/// Byte length of the 3072-bit group modulus `N` (3072 / 8).
const N_LEN: usize = 384;

/// Byte length of the random client/server ephemeral secrets (`a`, `b`).
const SCALAR_LEN: usize = 32;

/// RFC 5054 Appendix A 3072-bit group modulus `N` (identical to the RFC 3526
/// MODP group 15), big-endian hex.
const N_HEX: &str = concat!(
    "FFFFFFFFFFFFFFFFC90FDAA22168C234C4C6628B80DC1CD1",
    "29024E088A67CC74020BBEA63B139B22514A08798E3404DD",
    "EF9519B3CD3A431B302B0A6DF25F14374FE1356D6D51C245",
    "E485B576625E7EC6F44C42E9A637ED6B0BFF5CB6F406B7ED",
    "EE386BFB5A899FA5AE9F24117C4B1FE649286651ECE45B3D",
    "C2007CB8A163BF0598DA48361C55D39A69163FA8FD24CF5F",
    "83655D23DCA3AD961C62F356208552BB9ED529077096966D",
    "670C354E4ABC9804F1746C08CA18217C32905E462E36CE3B",
    "E39E772C180E86039B2783A2EC07A28FB5C55DF06F4C52C9",
    "DE2BCBF6955817183995497CEA956AE515D2261898FA0510",
    "15728E5A8AAAC42DAD33170D04507A33A85521ABDF1CBA64",
    "ECFB850458DBEF0A8AEA71575D060C7DB3970F85A6E1E4C7",
    "ABF5AE8CDB0933D71E8C94E04A25619DCEE3D2261AD2EE6B",
    "F12FFA06D98A0864D87602733EC86A64521F2B18177B200C",
    "BBE117577A615D6C770988C0BAD946E208E24FA074E5AB31",
    "43DB5BFCE0FD108E4B82D120A93AD2CAFFFFFFFFFFFFFFFF",
);

/// The 3072-bit group generator `g`.
const G: u32 = 5;

// ── Secret wrappers ──────────────────────────────────────────────────────────

/// A random ephemeral secret scalar (`a` or `b`), zeroized on drop.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
struct SecretScalar([u8; SCALAR_LEN]);

impl std::fmt::Debug for SecretScalar {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SecretScalar([REDACTED])")
    }
}

/// The SRP shared session key `K = H(PAD(S))`. Zeroized on drop.
#[derive(Clone, Zeroize, ZeroizeOnDrop)]
pub struct SessionKey([u8; 32]);

impl SessionKey {
    /// The raw 32-byte session key.
    ///
    /// Callers must not persist or log this value.
    #[must_use]
    pub fn as_bytes(&self) -> &[u8; 32] {
        &self.0
    }
}

impl std::fmt::Debug for SessionKey {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str("SessionKey([REDACTED])")
    }
}

// ── Group ────────────────────────────────────────────────────────────────────

/// An SRP-6a discrete-log group: a safe-prime modulus `N`, generator `g`, and
/// the SRP-6a multiplier `k = H(N | PAD(g))`.
pub struct SrpGroup {
    n: BigUint,
    g: BigUint,
    k: BigUint,
}

impl SrpGroup {
    /// The RFC 5054 3072-bit group with `g = 5` and SHA-256 hashing.
    ///
    /// The group is parsed and the multiplier `k` computed once, then cached.
    #[must_use]
    pub fn rfc5054_3072() -> &'static SrpGroup {
        static GROUP: OnceLock<SrpGroup> = OnceLock::new();
        GROUP.get_or_init(|| {
            let n_bytes = hex::decode(N_HEX).expect("static N hex is valid");
            let n = BigUint::from_bytes_be(&n_bytes);
            let g = BigUint::from(G);
            let k = compute_k(&n, &g);
            SrpGroup { n, g, k }
        })
    }
}

// ── Verifier (registration) ──────────────────────────────────────────────────

/// The SRP verifier `v = g^x mod N`. The server stores this; it never sees the
/// password, the master key, or `x`.
///
/// The verifier is password-equivalent for the purposes of an *offline*
/// dictionary attack, so the server must protect it accordingly — but it cannot
/// be used to impersonate the client during an online handshake.
#[derive(Clone)]
pub struct Verifier(BigUint);

impl Verifier {
    /// Serialize the verifier as a fixed-width `N_LEN` big-endian byte string.
    #[must_use]
    pub fn to_bytes_be(&self) -> Vec<u8> {
        pad(&self.0)
    }

    /// Reconstruct a verifier from its big-endian byte representation.
    #[must_use]
    pub fn from_bytes_be(bytes: &[u8]) -> Self {
        Self(BigUint::from_bytes_be(bytes))
    }
}

/// Compute the SRP verifier `v = g^x mod N` from the account's [`AuthKey`].
///
/// Run once at registration. The server stores the resulting verifier alongside
/// the identity and the account's Argon2id salt (`s`); see the module-level
/// "Salt semantics" docs. The server never receives `x`, `MK`, or the password.
#[must_use]
pub fn compute_verifier(group: &SrpGroup, auth_key: &AuthKey) -> Verifier {
    let x = derive_x(group, auth_key);
    Verifier(group.g.modpow(&x, &group.n))
}

/// Derive the SRP private exponent `x = OS2IP(AuthKey) mod N`.
///
/// See the module-level docs for the divergence from RFC 5054.
fn derive_x(group: &SrpGroup, auth_key: &AuthKey) -> BigUint {
    BigUint::from_bytes_be(auth_key.as_bytes()) % &group.n
}

// ── Client ───────────────────────────────────────────────────────────────────

/// Client-side authentication state holding the ephemeral secret `a` and the
/// public value `A = g^a mod N`.
pub struct ClientHandshake {
    a: SecretScalar,
    big_a: BigUint,
}

impl ClientHandshake {
    /// Begin a client handshake with a freshly generated random `a`.
    #[must_use]
    pub fn start(group: &SrpGroup) -> Self {
        let mut a = [0u8; SCALAR_LEN];
        OsRng.fill_bytes(&mut a);
        Self::from_secret(group, a)
    }

    /// Begin a client handshake with a caller-supplied `a`.
    ///
    /// Used by test vectors for reproducibility. Production code should use
    /// [`ClientHandshake::start`].
    #[must_use]
    pub fn start_with_secret(group: &SrpGroup, a: [u8; SCALAR_LEN]) -> Self {
        Self::from_secret(group, a)
    }

    fn from_secret(group: &SrpGroup, a: [u8; SCALAR_LEN]) -> Self {
        let exp = BigUint::from_bytes_be(&a);
        let big_a = group.g.modpow(&exp, &group.n);
        Self {
            a: SecretScalar(a),
            big_a,
        }
    }

    /// The client's public ephemeral `A`, fixed-width big-endian, to send to the
    /// server.
    #[must_use]
    pub fn public_a(&self) -> Vec<u8> {
        pad(&self.big_a)
    }

    /// Process the server's ephemeral `B`, compute the shared key, and produce
    /// the client proof `M1`.
    ///
    /// `salt` must be the account's Argon2id salt returned by the server at
    /// auth-start; it is the same salt used to derive `auth_key` (see the
    /// module-level "Salt semantics" docs).
    ///
    /// # Errors
    ///
    /// Returns [`CryptoError::Srp`] if `B mod N == 0` or `u == 0` (both abort the
    /// protocol per RFC 5054).
    pub fn process(
        &self,
        group: &SrpGroup,
        identity: &[u8],
        salt: &[u8],
        auth_key: &AuthKey,
        server_b: &[u8],
    ) -> Result<ClientSession> {
        let big_b = BigUint::from_bytes_be(server_b) % &group.n;
        if big_b.is_zero() {
            return Err(CryptoError::Srp("server value B mod N == 0".into()));
        }

        let u = compute_u(&self.big_a, &big_b);
        if u.is_zero() {
            return Err(CryptoError::Srp("scrambling parameter u == 0".into()));
        }

        let x = derive_x(group, auth_key);
        let a = BigUint::from_bytes_be(&self.a.0);

        // S = (B - k*g^x)^(a + u*x) mod N
        let g_x = group.g.modpow(&x, &group.n);
        let kgx = (&group.k * &g_x) % &group.n;
        let base = (&big_b + &group.n - kgx) % &group.n;
        let exp = a + &u * &x;
        let s = base.modpow(&exp, &group.n);

        let key = session_key_from_s(&s);
        let m1 = compute_m1(group, identity, salt, &self.big_a, &big_b, &key);
        let expected_m2 = compute_m2(&self.big_a, &m1, &key);

        Ok(ClientSession {
            key,
            m1,
            expected_m2,
        })
    }
}

/// Completed client-side handshake: the session key, the client proof `M1`, and
/// the expected server proof `M2`.
pub struct ClientSession {
    key: SessionKey,
    m1: [u8; 32],
    expected_m2: [u8; 32],
}

impl ClientSession {
    /// The client proof `M1` to send to the server.
    #[must_use]
    pub fn proof_m1(&self) -> &[u8; 32] {
        &self.m1
    }

    /// The negotiated shared session key `K`.
    #[must_use]
    pub fn session_key(&self) -> &SessionKey {
        &self.key
    }

    /// Verify the server's proof `M2`, completing mutual authentication.
    #[must_use]
    pub fn verify_server(&self, server_m2: &[u8]) -> bool {
        ct_eq(&self.expected_m2, server_m2)
    }
}

// ── Server ───────────────────────────────────────────────────────────────────

/// Server-side authentication state holding the ephemeral secret `b`, the
/// public value `B`, and the client's verifier `v`.
pub struct ServerHandshake {
    b: SecretScalar,
    big_b: BigUint,
    v: BigUint,
}

impl ServerHandshake {
    /// Begin a server handshake with a freshly generated random `b`.
    #[must_use]
    pub fn start(group: &SrpGroup, verifier: &Verifier) -> Self {
        let mut b = [0u8; SCALAR_LEN];
        OsRng.fill_bytes(&mut b);
        Self::from_secret(group, verifier, b)
    }

    /// Begin a server handshake with a caller-supplied `b`.
    ///
    /// Used by test vectors for reproducibility. Production code should use
    /// [`ServerHandshake::start`].
    #[must_use]
    pub fn start_with_secret(group: &SrpGroup, verifier: &Verifier, b: [u8; SCALAR_LEN]) -> Self {
        Self::from_secret(group, verifier, b)
    }

    fn from_secret(group: &SrpGroup, verifier: &Verifier, b: [u8; SCALAR_LEN]) -> Self {
        let exp = BigUint::from_bytes_be(&b);
        let g_b = group.g.modpow(&exp, &group.n);
        let kv = (&group.k * &verifier.0) % &group.n;
        let big_b = (kv + g_b) % &group.n;
        Self {
            b: SecretScalar(b),
            big_b,
            v: verifier.0.clone(),
        }
    }

    /// The server's public ephemeral `B`, fixed-width big-endian, to send to the
    /// client.
    #[must_use]
    pub fn public_b(&self) -> Vec<u8> {
        pad(&self.big_b)
    }

    /// Process the client's ephemeral `A` and proof `M1`, compute the shared
    /// key, verify `M1`, and produce the server proof `M2`.
    ///
    /// `salt` must be the account's stored Argon2id salt (the one the server
    /// sent the client at auth-start); see the module-level "Salt semantics"
    /// docs.
    ///
    /// # Errors
    ///
    /// Returns [`CryptoError::Srp`] if `A mod N == 0`, `u == 0`, or the client
    /// proof `M1` does not verify (wrong password / verifier mismatch).
    pub fn process(
        &self,
        group: &SrpGroup,
        identity: &[u8],
        salt: &[u8],
        client_a: &[u8],
        client_m1: &[u8],
    ) -> Result<ServerSession> {
        let big_a = BigUint::from_bytes_be(client_a) % &group.n;
        if big_a.is_zero() {
            return Err(CryptoError::Srp("client value A mod N == 0".into()));
        }

        let u = compute_u(&big_a, &self.big_b);
        if u.is_zero() {
            return Err(CryptoError::Srp("scrambling parameter u == 0".into()));
        }

        // S = (A * v^u)^b mod N
        let v_u = self.v.modpow(&u, &group.n);
        let base = (&big_a * &v_u) % &group.n;
        let b = BigUint::from_bytes_be(&self.b.0);
        let s = base.modpow(&b, &group.n);

        let key = session_key_from_s(&s);
        let expected_m1 = compute_m1(group, identity, salt, &big_a, &self.big_b, &key);
        if !ct_eq(&expected_m1, client_m1) {
            return Err(CryptoError::Srp(
                "client proof M1 verification failed".into(),
            ));
        }

        let m2 = compute_m2(&big_a, &expected_m1, &key);
        Ok(ServerSession { key, m2 })
    }
}

/// Completed server-side handshake: the session key and the server proof `M2`.
pub struct ServerSession {
    key: SessionKey,
    m2: [u8; 32],
}

impl ServerSession {
    /// The server proof `M2` to send back to the client.
    #[must_use]
    pub fn proof_m2(&self) -> &[u8; 32] {
        &self.m2
    }

    /// The negotiated shared session key `K`.
    #[must_use]
    pub fn session_key(&self) -> &SessionKey {
        &self.key
    }
}

// ── Known-answer test support ────────────────────────────────────────────────

/// Per-step intermediate values of a single SRP-6a exchange.
///
/// Exposed for known-answer testing and cross-platform (Swift/WASM) vector
/// validation. All big-integer fields are big-endian.
///
/// This deliberately surfaces secret intermediates (`x`, `a`, `b`, `s`) so ports
/// can validate every protocol step. **Do not** use this in production auth
/// flows — use [`ClientHandshake`] / [`ServerHandshake`].
#[doc(hidden)]
pub struct KnownAnswer {
    pub k: Vec<u8>,
    pub x: Vec<u8>,
    pub v: Vec<u8>,
    pub a: Vec<u8>,
    pub big_a: Vec<u8>,
    pub b: Vec<u8>,
    pub big_b: Vec<u8>,
    pub u: Vec<u8>,
    pub s: Vec<u8>,
    pub session_key: Vec<u8>,
    pub m1: Vec<u8>,
    pub m2: Vec<u8>,
}

/// Compute every intermediate of one SRP-6a exchange from fixed inputs.
///
/// Used to generate and verify deterministic known-answer test vectors.
#[doc(hidden)]
#[must_use]
pub fn known_answer(
    group: &SrpGroup,
    auth_key: &AuthKey,
    identity: &[u8],
    salt: &[u8],
    a_secret: [u8; SCALAR_LEN],
    b_secret: [u8; SCALAR_LEN],
) -> KnownAnswer {
    let x = derive_x(group, auth_key);
    let v = group.g.modpow(&x, &group.n);

    let a = BigUint::from_bytes_be(&a_secret);
    let big_a = group.g.modpow(&a, &group.n);

    let b = BigUint::from_bytes_be(&b_secret);
    let kv = (&group.k * &v) % &group.n;
    let big_b = (kv + group.g.modpow(&b, &group.n)) % &group.n;

    let u = compute_u(&big_a, &big_b);

    // Client-side shared secret: S = (B - k*g^x)^(a + u*x) mod N.
    let g_x = group.g.modpow(&x, &group.n);
    let kgx = (&group.k * &g_x) % &group.n;
    let base = (&big_b + &group.n - kgx) % &group.n;
    let exp = &a + &u * &x;
    let s = base.modpow(&exp, &group.n);

    let key = session_key_from_s(&s);
    let m1 = compute_m1(group, identity, salt, &big_a, &big_b, &key);
    let m2 = compute_m2(&big_a, &m1, &key);

    KnownAnswer {
        k: group.k.to_bytes_be(),
        x: x.to_bytes_be(),
        v: v.to_bytes_be(),
        a: a_secret.to_vec(),
        big_a: big_a.to_bytes_be(),
        b: b_secret.to_vec(),
        big_b: big_b.to_bytes_be(),
        u: u.to_bytes_be(),
        s: s.to_bytes_be(),
        session_key: key.as_bytes().to_vec(),
        m1: m1.to_vec(),
        m2: m2.to_vec(),
    }
}

/// The big-endian modulus `N` of a group, for vector emission.
#[doc(hidden)]
#[must_use]
pub fn group_modulus_be(group: &SrpGroup) -> Vec<u8> {
    group.n.to_bytes_be()
}

// ── Internal helpers ─────────────────────────────────────────────────────────

/// Left-zero-pad a value's big-endian representation to `N_LEN` bytes
/// (RFC 5054 `PAD`).
fn pad(value: &BigUint) -> Vec<u8> {
    let bytes = value.to_bytes_be();
    if bytes.len() >= N_LEN {
        return bytes;
    }
    let mut out = vec![0u8; N_LEN - bytes.len()];
    out.extend_from_slice(&bytes);
    out
}

/// SHA-256 over the concatenation of `parts`.
fn sha256(parts: &[&[u8]]) -> [u8; 32] {
    let mut hasher = Sha256::new();
    for part in parts {
        hasher.update(part);
    }
    hasher.finalize().into()
}

/// `k = H(N | PAD(g))` (SRP-6a multiplier).
fn compute_k(n: &BigUint, g: &BigUint) -> BigUint {
    let h = sha256(&[&pad(n), &pad(g)]);
    BigUint::from_bytes_be(&h)
}

/// `u = H(PAD(A) | PAD(B))` (random scrambling parameter).
fn compute_u(big_a: &BigUint, big_b: &BigUint) -> BigUint {
    let h = sha256(&[&pad(big_a), &pad(big_b)]);
    BigUint::from_bytes_be(&h)
}

/// `K = H(PAD(S))` (session key).
fn session_key_from_s(s: &BigUint) -> SessionKey {
    SessionKey(sha256(&[&pad(s)]))
}

/// `M1 = H(H(N) XOR H(PAD(g)) | H(I) | s | PAD(A) | PAD(B) | K)` (client proof).
fn compute_m1(
    group: &SrpGroup,
    identity: &[u8],
    salt: &[u8],
    big_a: &BigUint,
    big_b: &BigUint,
    key: &SessionKey,
) -> [u8; 32] {
    let h_n = sha256(&[&pad(&group.n)]);
    let h_g = sha256(&[&pad(&group.g)]);
    let mut h_xor = [0u8; 32];
    for i in 0..32 {
        h_xor[i] = h_n[i] ^ h_g[i];
    }
    let h_i = sha256(&[identity]);
    sha256(&[&h_xor, &h_i, salt, &pad(big_a), &pad(big_b), key.as_bytes()])
}

/// `M2 = H(PAD(A) | M1 | K)` (server proof).
fn compute_m2(big_a: &BigUint, m1: &[u8; 32], key: &SessionKey) -> [u8; 32] {
    sha256(&[&pad(big_a), m1, key.as_bytes()])
}

/// Constant-time-ish byte comparison for proof verification.
fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    let mut diff = 0u8;
    for (x, y) in a.iter().zip(b) {
        diff |= x ^ y;
    }
    diff == 0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::key_hierarchy;

    fn auth_key(password: &[u8], salt: &[u8]) -> AuthKey {
        let mk = key_hierarchy::derive_master_key(password, salt).unwrap();
        key_hierarchy::derive_sub_keys(&mk).unwrap().0
    }

    #[test]
    fn group_modulus_is_3072_bit() {
        let group = SrpGroup::rfc5054_3072();
        assert_eq!(pad(&group.n).len(), N_LEN);
        assert_eq!(group.g, BigUint::from(5u32));
    }

    #[test]
    fn full_handshake_roundtrip() {
        let group = SrpGroup::rfc5054_3072();
        let ak = auth_key(b"correct horse battery staple", b"saltsaltsaltsalt");
        let verifier = compute_verifier(group, &ak);

        let client = ClientHandshake::start(group);
        let server = ServerHandshake::start(group, &verifier);

        let client_session = client
            .process(
                group,
                b"alice",
                b"saltsaltsaltsalt",
                &ak,
                &server.public_b(),
            )
            .unwrap();

        let server_session = server
            .process(
                group,
                b"alice",
                b"saltsaltsaltsalt",
                &client.public_a(),
                client_session.proof_m1(),
            )
            .unwrap();

        assert_eq!(
            client_session.session_key().as_bytes(),
            server_session.session_key().as_bytes()
        );
        assert!(client_session.verify_server(server_session.proof_m2()));
    }

    #[test]
    fn wrong_password_fails() {
        let group = SrpGroup::rfc5054_3072();
        let ak = auth_key(b"right", b"saltsaltsaltsalt");
        let wrong = auth_key(b"wrong", b"saltsaltsaltsalt");
        let verifier = compute_verifier(group, &ak);

        let client = ClientHandshake::start(group);
        let server = ServerHandshake::start(group, &verifier);

        let cs = client
            .process(
                group,
                b"alice",
                b"saltsaltsaltsalt",
                &wrong,
                &server.public_b(),
            )
            .unwrap();
        let result = server.process(
            group,
            b"alice",
            b"saltsaltsaltsalt",
            &client.public_a(),
            cs.proof_m1(),
        );
        assert!(result.is_err());
    }

    #[test]
    fn rejects_zero_a_and_b() {
        let group = SrpGroup::rfc5054_3072();
        let ak = auth_key(b"pw", b"saltsaltsaltsalt");
        let verifier = compute_verifier(group, &ak);

        let server = ServerHandshake::start(group, &verifier);
        let zero = vec![0u8; N_LEN];
        assert!(
            server
                .process(group, b"alice", b"salt", &zero, &[0u8; 32])
                .is_err()
        );

        let client = ClientHandshake::start(group);
        assert!(
            client
                .process(group, b"alice", b"salt", &ak, &zero)
                .is_err()
        );
    }
}
