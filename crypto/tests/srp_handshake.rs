//! Integration tests for the SRP-6a client ↔ server handshake.
//!
//! These exercise the public [`pildora_crypto::srp`] API end to end: a pure-Rust
//! client and server derive the same session key `K` and mutually verify each
//! other's proofs, plus negative cases that must be rejected.
//!
//! NOTE: exposing this handshake over Axum HTTP endpoints (the sync server) is
//! Phase 2 work — this spike only validates the protocol in-process.

use pildora_crypto::key_hierarchy;
use pildora_crypto::srp::{ClientHandshake, ServerHandshake, SrpGroup, compute_verifier};

const N_LEN: usize = 384;

fn auth_key(password: &[u8], salt: &[u8]) -> key_hierarchy::AuthKey {
    let mk = key_hierarchy::derive_master_key(password, salt).expect("master key derivation");
    key_hierarchy::derive_sub_keys(&mk)
        .expect("sub-key derivation")
        .0
}

// In every test below, `salt` is the account's Argon2id salt: it is used both to
// derive the AuthKey (MK = Argon2id(password, salt)) and as the SRP salt `s`
// passed to `process`. The two are intentionally the same value (see ADR-008).

/// A full registration + authentication roundtrip with random ephemerals: both
/// sides must agree on `K` and both proofs must verify.
#[test]
fn handshake_roundtrip_derives_shared_key() {
    let group = SrpGroup::rfc5054_3072();
    let identity = b"alice@example.test";
    let salt = b"saltsaltsaltsalt";

    // Registration: derive verifier from the AuthKey, upload to "server".
    let ak = auth_key(b"correct horse battery staple", salt);
    let verifier = compute_verifier(group, &ak);

    // Authentication.
    let client = ClientHandshake::start(group);
    let server = ServerHandshake::start(group, &verifier);

    let client_session = client
        .process(group, identity, salt, &ak, &server.public_b())
        .expect("client process");
    let server_session = server
        .process(
            group,
            identity,
            salt,
            &client.public_a(),
            client_session.proof_m1(),
        )
        .expect("server process");

    // Zero-knowledge property: both sides derived the same key without the
    // server ever seeing the password, MK, or x.
    assert_eq!(
        client_session.session_key().as_bytes(),
        server_session.session_key().as_bytes(),
        "client and server session keys must match"
    );
    // Mutual authentication.
    assert!(
        client_session.verify_server(server_session.proof_m2()),
        "client must accept the server proof M2"
    );
}

/// A client authenticating with the wrong password must fail server-side M1
/// verification.
#[test]
fn wrong_password_is_rejected() {
    let group = SrpGroup::rfc5054_3072();
    let identity = b"alice@example.test";
    let salt = b"saltsaltsaltsalt";

    let registered = auth_key(b"the real password", salt);
    let attacker = auth_key(b"a guessed password", salt);
    let verifier = compute_verifier(group, &registered);

    let client = ClientHandshake::start(group);
    let server = ServerHandshake::start(group, &verifier);

    let client_session = client
        .process(group, identity, salt, &attacker, &server.public_b())
        .expect("client process still succeeds locally");

    let result = server.process(
        group,
        identity,
        salt,
        &client.public_a(),
        client_session.proof_m1(),
    );
    assert!(
        result.is_err(),
        "server must reject a proof from the wrong password"
    );
}

/// The server must reject a client public value `A` with `A mod N == 0`.
#[test]
fn server_rejects_zero_a() {
    let group = SrpGroup::rfc5054_3072();
    let salt = b"saltsaltsaltsalt";
    let verifier = compute_verifier(group, &auth_key(b"pw", salt));

    let server = ServerHandshake::start(group, &verifier);
    let zero_a = vec![0u8; N_LEN];

    let result = server.process(group, b"alice@example.test", salt, &zero_a, &[0u8; 32]);
    assert!(result.is_err(), "A mod N == 0 must be rejected");
}

/// The client must reject a server public value `B` with `B mod N == 0`.
#[test]
fn client_rejects_zero_b() {
    let group = SrpGroup::rfc5054_3072();
    let salt = b"saltsaltsaltsalt";
    let ak = auth_key(b"pw", salt);

    let client = ClientHandshake::start(group);
    let zero_b = vec![0u8; N_LEN];

    let result = client.process(group, b"alice@example.test", salt, &ak, &zero_b);
    assert!(result.is_err(), "B mod N == 0 must be rejected");
}
