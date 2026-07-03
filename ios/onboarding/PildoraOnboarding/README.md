# PildoraOnboarding

Production first-run onboarding — master password, recovery key, first vault —
**issue #53** (Phase 1, Epic #9). It's the first user-facing step where the
zero-knowledge key hierarchy is created on-device.

## Status

🚧 Self-contained feature slice. Like the other iOS slices, this package builds
on the shared `PildoraDesignSystem` and runs entirely under `swift test` on the
macOS toolchain — no entitlements, app bundle, Keychain, or `LocalAuthentication`
required. Crypto, keychain/biometrics, and persistence sit behind protocol seams;
the **app** supplies the FFI-backed `OnboardingCrypto`.

On-device biometric / Keychain-sync testing remains blocked by Apple Developer
enrollment ([#25](https://github.com/kafkade/pildora/issues/25)); the seams keep
the flow logic fully unit-tested in the meantime.

## What it does

- **Master password** creation with a live zxcvbn-style **strength meter**
  (`PasswordStrengthEvaluator`) and explicit requirements (`PasswordPolicy`:
  ≥ 10 chars, ≥ `fair`).
- **Key derivation** on submit: Argon2id → MUK → HKDF (auth key + MEK) → random
  vault key wrapped by the MEK; a random **recovery key** wraps the MEK for
  offline recovery. Sensitive material is zeroized via `SecureBytes` (#40).
- **Recovery key** reveal + printable **Recovery Kit PDF** (Crockford Base32,
  grouped + checksummed, mirroring the Rust display format).
- Mandatory **unrecoverable-data** acknowledgement.
- First **vault** creation + optional **biometric unlock** and **iCloud Keychain
  backup** opt-ins.
- Skippable **guided first medication** that seeds the vault.
- **Resume** after interruption — without ever persisting secret material.

## Architecture

```text
OnboardingFlowView ──▶ OnboardingFlowModel (@MainActor state machine)
                              │
        ┌─────────────────────┼─────────────────────┐
        ▼                     ▼                     ▼
 OnboardingCrypto      OnboardingStateStore   BiometricAuthenticating
   (seam)                 (seam)                  (seam)
   ├─ FFIOnboardingCrypto (app: real Argon2id/HKDF/wrapping + SecureBytes)
   └─ StubOnboardingCrypto (tests/previews)
```

The FFI-backed `OnboardingCrypto` lives in the **app target**, not this package,
because only the app has the generated `pildora_crypto_ffi` module — the same
pattern `PildoraDataLayer` uses for its `DatabaseKeyDeriving` seam.

## Resume, safely

Progress is persisted so the flow resumes after the app is closed, but **no
secret material is ever written to disk**. A resumed session past the welcome
step therefore restarts at the **password** step (the user re-enters it; fresh
keys are generated safely) while restoring the user's opt-in choices as defaults.
Only on completion is the non-secret `VaultConfig` persisted and the vault key
stored in the Keychain.

## Tests

`swift test` covers the strength estimator + policy, recovery-key formatting +
PDF/plaintext content, the persistence/resume store, and the flow state machine
(including crypto-failure surfacing and the resume clamp).

Design reference: [`docs/ios-onboarding.md`](../../../docs/ios-onboarding.md).
