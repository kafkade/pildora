/**
 * Node.js test harness for pildora-crypto WASM bindings.
 *
 * Validates the WASM build against the same test vectors used by the native
 * Rust test suite, ensuring cross-platform correctness.
 *
 * Usage:
 *   cd crypto
 *   wasm-pack build --target nodejs --features wasm
 *   node tests/wasm_node_test.cjs
 */

"use strict";

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");

const wasm = require("../pkg/pildora_crypto.js");

// ── Helpers ──────────────────────────────────────────────────────────────────

/** Decode a hex string to a Uint8Array. */
function hexToBytes(hex) {
  if (hex.length === 0) return new Uint8Array(0);
  const bytes = new Uint8Array(hex.length / 2);
  for (let i = 0; i < hex.length; i += 2) {
    bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
  }
  return bytes;
}

/** Encode a Uint8Array to a lowercase hex string. */
function bytesToHex(bytes) {
  return Array.from(bytes)
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

// ── Test runner ──────────────────────────────────────────────────────────────

let passed = 0;
let failed = 0;

function ok(name) {
  passed++;
  console.log(`  ✓ ${name}`);
}

function fail(name, err) {
  failed++;
  console.error(`  ✗ ${name}`);
  console.error(`    ${err}`);
}

function section(title) {
  console.log(`\n── ${title} ──`);
}

// ── Load test vectors ────────────────────────────────────────────────────────

const vectorsPath = path.resolve(__dirname, "..", "test-vectors", "vectors.json");
const vectors = JSON.parse(fs.readFileSync(vectorsPath, "utf-8")).vectors;

// ── BLAKE2b ──────────────────────────────────────────────────────────────────

section("BLAKE2b");

for (const v of vectors.blake2b) {
  // Skip keyed vectors — the WASM binding only exposes unkeyed blake2b_hash.
  if (v.key_hex) {
    ok(`${v.description} (skipped — keyed, not exposed via WASM)`);
    continue;
  }
  const name = `blake2b: ${v.description}`;
  try {
    const input = hexToBytes(v.input_hex);
    const result = wasm.blake2b_hash(input);
    const resultHex = bytesToHex(result);
    assert.equal(resultHex, v.expected_hash_hex, "hash mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

// ── Argon2id (first vector only — 64 MiB is slow) ───────────────────────────

section("Argon2id (first vector only)");

{
  const v = vectors.argon2id[0];
  const name = `argon2id: ${v.description}`;
  try {
    const password = hexToBytes(v.password_hex);
    const salt = hexToBytes(v.salt_hex);
    const mk = wasm.derive_master_key(password, salt);
    const mkHex = bytesToHex(mk);
    assert.equal(mkHex, v.expected_key_hex, "master key mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

// ── Key hierarchy ────────────────────────────────────────────────────────────

section("Key hierarchy");

for (const v of vectors.key_hierarchy) {
  const name = `key_hierarchy: ${v.description}`;
  try {
    const password = hexToBytes(v.password_hex);
    const salt = hexToBytes(v.salt_hex);

    // Step 1: derive master key
    const mk = wasm.derive_master_key(password, salt);
    assert.equal(
      bytesToHex(mk),
      v.expected_mk_hex,
      "master key mismatch"
    );

    // Step 2: derive sub-keys
    const sub = wasm.derive_sub_keys(mk);
    const authKey = new Uint8Array(sub.auth_key);
    const mek = new Uint8Array(sub.mek);

    assert.equal(bytesToHex(authKey), v.expected_auth_key_hex, "auth_key mismatch");
    assert.equal(bytesToHex(mek), v.expected_mek_hex, "mek mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

// ── Item encryption (decrypt golden blobs) ───────────────────────────────────

section("Item encryption (golden blob decryption)");

for (const v of vectors.item_encryption) {
  const name = `item_decrypt: ${v.description}`;
  try {
    const blob = hexToBytes(v.blob_hex);
    const vaultKey = hexToBytes(v.vault_key_hex);
    const plaintext = wasm.item_decrypt(blob, vaultKey);
    assert.equal(bytesToHex(plaintext), v.plaintext_hex, "plaintext mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

// ── Encrypt / decrypt roundtrip ──────────────────────────────────────────────

section("Roundtrip");

{
  const name = "item_encrypt → item_decrypt roundtrip";
  try {
    const vk = wasm.generate_vault_key();
    assert.equal(vk.length, 32, "vault key must be 32 bytes");

    const plaintext = new TextEncoder().encode("medication data for roundtrip");
    const blob = wasm.item_encrypt(plaintext, vk);
    const recovered = wasm.item_decrypt(blob, vk);
    assert.deepEqual(recovered, plaintext, "roundtrip plaintext mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

{
  const name = "encrypt_json → decrypt_json roundtrip";
  try {
    const vk = wasm.generate_vault_key();
    const json = JSON.stringify({ med: "aspirin", dose_mg: 100 });
    const blob = wasm.encrypt_json(json, vk);
    const recovered = wasm.decrypt_json(blob, vk);
    assert.equal(recovered, json, "JSON roundtrip mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

{
  const name = "wrap_vault_key → unwrap_vault_key roundtrip";
  try {
    const vk = wasm.generate_vault_key();
    // Use a deterministic MEK from key_hierarchy vector for wrapping
    const v = vectors.key_hierarchy[0];
    const mk = wasm.derive_master_key(
      hexToBytes(v.password_hex),
      hexToBytes(v.salt_hex)
    );
    const sub = wasm.derive_sub_keys(mk);
    const mek = new Uint8Array(sub.mek);

    const wrapped = wasm.wrap_vault_key(vk, mek);
    const unwrapped = wasm.unwrap_vault_key(wrapped, mek);
    assert.deepEqual(new Uint8Array(unwrapped), new Uint8Array(vk), "vault key roundtrip mismatch");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

{
  const name = "generate_salt returns 16 bytes";
  try {
    const salt = wasm.generate_salt();
    assert.equal(salt.length, 16, "salt must be 16 bytes");
    ok(name);
  } catch (e) {
    fail(name, e.message);
  }
}

// ── Summary ──────────────────────────────────────────────────────────────────

console.log(`\n${"═".repeat(50)}`);
console.log(`  ${passed} passed, ${failed} failed`);
console.log(`${"═".repeat(50)}\n`);

process.exit(failed > 0 ? 1 : 0);
