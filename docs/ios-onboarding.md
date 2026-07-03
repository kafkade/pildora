# iOS Onboarding Flow

Design reference for the first-run onboarding implemented in
[`ios/onboarding/PildoraOnboarding`](../ios/onboarding/PildoraOnboarding/)
(issue #53, roadmap Epic #9, Phase 1). It is the first user-facing step where
the **zero-knowledge key hierarchy** is actually created on-device: the user
sets a master password, the app derives every key, generates a recovery key,
creates the first vault, and hands an unlocked vault to the rest of the app.

> This is a tracking/information tool. Onboarding creates and secures the user's
> encrypted store; it provides **no** dosing recommendations or medical advice.

## Non-negotiable: keys are born on-device

Every key is derived and used locally. Nothing sensitive is sent to a server and
nothing sensitive is written to disk in plaintext:

```text
Master Password ──Argon2id──▶ Master Unlock Key (MUK)
                                 │
                            HKDF ├─▶ Auth Key
                                 └─▶ Master Encryption Key (MEK)
                                        │
                    random Vault Key ◀──┤ wrapped by MEK      → wrappedVaultKey
                    random Recovery Key ┴ wraps MEK           → recoveryWrappedMek
```

The persisted, **non-secret** `VaultConfig` is `{ vaultID, vaultName, salt,
wrappedVaultKey, recoveryWrappedMek }`. The live `vaultKey` is stored only in the
Keychain (optionally behind biometrics / iCloud). The master key, MEK, and
recovery key exist only transiently and are **zeroized** (`SecureBytes`, #40) as
soon as the wrapped blobs and the display string have been produced.

## Steps

The flow is an ordered `OnboardingStep` state machine driven by
`OnboardingFlowModel` (`@MainActor`, `ObservableObject`):

1. **Welcome** — zero-knowledge explainer.
2. **Password** — master password creation with a live strength meter and
   explicit requirements (see below). Submitting runs Argon2id off the main
   thread and creates the vault + recovery material.
3. **Recovery key** — the recovery key is revealed once and exported as a
   printable **Recovery Kit PDF**.
4. **Warning** — a mandatory acknowledgement that data is **unrecoverable**
   without the master password or the recovery key.
5. **Biometrics** — optional Face ID / Touch ID unlock opt-in.
6. **iCloud backup** — optional iCloud Keychain backup of the unlock key.
7. **First medication** — a skippable guided entry that seeds the vault.
8. **Done** — success screen; hands the opened vault back to the app.

## Password strength

`PasswordStrengthEvaluator` is a self-contained, dependency-free zxcvbn-style
estimator (the issue calls for "zxcvbn or similar"; a self-contained estimator
matches the repo's dependency-free slice ethos). `PasswordPolicy.standard`
requires **≥ 10 characters** and at least a **`fair`** rating; the meter and the
requirement checklist update live, and onboarding will not accept a password
below the bar.

## Recovery key & PDF

`RecoveryKeyFormatting` renders the raw recovery bytes as a **Crockford Base32**
string, in groups of five with a two-character checksum, mirroring the Rust
`recovery_key_display_string` implementation. `RecoveryDocument` is a
platform-independent content model (key, instructions, warning, generation date)
that `RecoveryKitPDFRenderer` turns into a one-page PDF (UIKit renderer, with a
plaintext fallback for non-UIKit hosts so the package still builds and tests on
macOS). Once the PDF/display string is produced, the underlying key material is
zeroized.

## Resume, safely

`OnboardingStateStore` persists progress so the flow can **resume** after the app
is closed mid-onboarding. Because **no secret material is ever persisted**, a
resumed session past the welcome step restarts at the **password** step (the user
re-enters the password; fresh keys are generated safely, since nothing was
committed) while restoring the user's opt-in toggle choices as defaults. Only on
completion is `VaultConfig` persisted and the vault key stored in the Keychain.

## Testability: protocol seams

The whole package runs under `swift test` with **no entitlements**, matching the
`notification-scheduler` / `data-layer` slices. Three seams keep it hermetic:

- `OnboardingCrypto` — the key-hierarchy operations. The app provides
  `FFIOnboardingCrypto` (real Argon2id / HKDF / wrapping via `pildora-crypto-ffi`,
  zeroizing with `SecureBytes`); tests/previews use `StubOnboardingCrypto`.
- `OnboardingStateStore` — progress + config persistence. `UserDefaults` in the
  app, in-memory in tests.
- `BiometricAuthenticating` — `LocalAuthentication` on device, a stub in tests.

The FFI-backed conformer lives in the **app target**, not the package, because
only the app has the generated `pildora_crypto_ffi` module — the same pattern the
`data-layer` uses for its `DatabaseKeyDeriving` seam.

## Crypto FFI additions

Onboarding needs the recovery-key primitives that already exist in
`crypto/src/key_hierarchy.rs` but were not previously exposed. `crypto-uniffi`
gains four functions, regenerated into the committed Swift bindings:

- `generate_recovery_key()`
- `recovery_key_display_string(recovery_key)`
- `wrap_mek_for_recovery(mek, recovery_key)`
- `unwrap_mek_from_recovery(recovery_wrapped_mek, recovery_key)`

## App wiring

`AppBootstrap` gates first launch:

- `needsOnboarding()` — true unless onboarding is complete **and** the vault key
  is present in the Keychain.
- `makeOnboardingModel(onReady:)` — builds the flow; on completion it stores the
  vault key (biometric- and/or iCloud-scoped per the user's opt-ins), seeds the
  vault + optional first medication, and hands the opened `Bootstrapped` state to
  `onReady` when the user leaves the success screen.
- `openVault()` — the returning-user path; reads the vault key from the Keychain
  (which may prompt for biometrics) and opens the encrypted database.

`ContentView` renders `.onboarding` for first run and `.ready` thereafter. The
`-uitesting` in-memory bypass is preserved, so UI tests never touch onboarding.

## Accessibility

All steps are built on the shared [design system](../ios/design-system/PildoraDesignSystem/):
VoiceOver labels/traits, Dynamic Type, and 44pt tap targets. Status is always
conveyed by icon **and** text, never color alone.

## Out of scope / follow-ups

- On-device biometric and Keychain-sync testing is gated on Apple Developer
  enrollment (#25); the seams keep the logic unit-tested in the meantime.
- Multi-vault selection UX is later; the data model is already vault-scoped, and
  onboarding creates the single default vault.
