# Multi-Platform Medication & Supplement Tracker — Product Roadmap

> **Document type:** Comprehensive product roadmap
> **Author context:** Senior product strategist and technical architect
> **Scope:** Multi-platform (iOS, iPadOS, watchOS, Web, CLI) medication and supplement tracking application with zero-knowledge, end-to-end encrypted architecture

---

## SECTION 0: ASSUMPTIONS TABLE & CLARIFYING QUESTIONS

All subsequent sections use these defaults. Where a default proves wrong, the **Risk if Wrong** column guides re-planning.

| # | Question | Default | Reasoning | Risk if Wrong |
|---|----------|---------|-----------|---------------|
| 1 | Team size | Solo developer | Prompt context implies indie/small-team energy; architecture must minimize operational burden | If team is 3-5, phases compress by ~40%; parallelize platform work earlier |
| 2 | Target timeline | MVP in 4 months, full product in 18 months | Solo dev with encryption complexity needs buffer beyond typical 3-month MVP | If timeline is shorter, cut drug data enrichment from MVP and ship pure tracking first |
| 3 | Budget constraint | < $50/month infrastructure, $99/yr Apple Developer fee, $0 paid API licenses at MVP | Solo developer, no external funding assumed | If funded, accelerate by licensing DrugBank and hiring a security auditor for Phase 0 |
| 4 | MVP platform | **iOS (iPhone) first** | Largest privacy-conscious consumer health audience; HealthKit integration is a differentiator; SwiftUI maturity enables solo dev velocity; App Store is the primary distribution channel for health apps | If developer lacks Swift experience, pivot to web-first with PWA — but lose HealthKit and Watch |
| 5 | Primary persona | ADHD/forgetful user (wedge), expanding to chronic condition manager | Forgetful users have the most acute switching trigger — current reminder apps are not medication-specific enough; chronic condition managers have highest LTV | If biohacker is the wedge instead, emphasize data/correlations over reminder UX |
| 6 | Product type | Consumer product (App Store) with power-user CLI | B2B/clinical requires HIPAA BAAs and sales cycles incompatible with solo dev; consumer-first, clinical-later | If B2B is needed early, the zero-knowledge architecture actually helps — no BAA needed if server never sees PHI |
| 7 | Privacy as marketing message | **Yes — primary differentiator** | No major competitor offers true zero-knowledge encryption for medication data; post-2024 privacy awareness is at all-time high | If users don't care about privacy, the product competes on features alone — which is harder against Medisafe |
| 8 | Wedge persona switching trigger | ADHD user frustrated by generic reminder apps that don't understand medication context (PRN meds, cycling schedules, inventory) | Current apps treat meds like calendar events; medication-aware scheduling is the gap | If the wedge is wrong, user acquisition stalls — validate with landing page test in first 30 days |
| 9 | Top 3 acquisition channels | (1) App Store ASO for "medication tracker privacy," (2) Reddit/HN privacy communities, (3) Content marketing on medication management topics | Privacy-conscious users over-index on Reddit/HN; ASO captures intent-based search | If organic is too slow, consider ProductHunt launch and privacy-focused podcast sponsorships |
| 10 | HIPAA applicability | **Largely non-applicable for core product** — zero-knowledge means server never processes PHI; HIPAA applies to covered entities and business associates handling PHI in the clear | When FHIR pharmacy import is added (Phase 3+), the *import pathway* briefly handles PHI — encrypt on-device immediately | If a court or regulator disagrees, the architecture still protects users — worst case is compliance paperwork, not a data breach |
| 11 | Multi-profile vaults | Core feature, architecture from Phase 0, UX ships Phase 5 | Prompt explicitly states this is non-negotiable; vault key hierarchy must be designed upfront | If delayed, re-keying the architecture later is extremely expensive |
| 12 | Target region | United States first | FDA/RxNorm/openFDA are US-centric; expand internationally when drug data pipeline supports it | If targeting EU first, need EMA data sources and GDPR-first compliance posture |
| 13 | Disclaimer strategy | **Contextual inline disclaimers** on every interaction warning + first-launch consent + ToS | Inline disclaimers are legally stronger than buried ToS; contextual placement reduces annoyance | If legal counsel recommends modal disclaimers, add per-session acknowledgment |
| 14 | Local-only MVP acceptable? | **Yes** — local-only encrypted storage for MVP; cloud sync in Phase 2 | Reduces MVP complexity dramatically; encryption on-device is simpler than encrypted sync | If users demand multi-device from day one, prioritize Phase 2 and accept longer MVP timeline |
| 15 | Key derivation and recovery | **Master password + printed recovery key** (like 1Password Emergency Kit) | Balances security with recoverability; no server-side key escrow; iCloud Keychain backup for convenience on Apple devices | If users lose both master password and recovery key, data is unrecoverable — this is the correct trade-off |
| 16 | Self-hosted sync option | **Later (Phase 5+), not MVP** | Bitwarden model is compelling but adds ops burden; prioritize managed infrastructure first | If power users demand self-hosting early, publish a Docker image with the sync server |
| 17 | Drug reference data handling | **Locally bundled index (compressed) + periodic on-device updates** | Avoids leaking drug search queries to any server; openFDA data is ~150MB compressed for US drugs; supplements require a separate, smaller index | If index is too large for app bundle, use a CDN-served encrypted index file downloaded on first launch |
| 18 | Native Swift vs. cross-platform | **Native Swift/SwiftUI** for iOS/iPad/Watch | Apple-heavy platform list makes native the right call; SwiftUI shares code across iPhone/iPad/Watch; cross-platform (React Native/Flutter) would require native modules for HealthKit, Keychain, and Watch anyway | If web-first is chosen instead, use React/Next.js with WebCrypto API and accept no Watch/HealthKit at MVP |
| 19 | Backend language | **TypeScript (Node.js) with Hono or Fastify** | Shares language with web app and CLI; strong crypto library ecosystem (libsodium via sodium-native); familiar to most developers; deploy on Cloudflare Workers or Railway | If the developer prefers Rust or Go, either works — but TypeScript maximizes code sharing |
| 20 | CLI tool positioning | **Power-user utility** (not first-class consumer product) | Primary acquisition is App Store; CLI serves developers, data importers, and automation users | If CLI gains traction, promote to first-class with brew/npm distribution in Phase 4 |

---

## SECTION 1: USER PERSONAS

### Persona 1: Alex — The ADHD / Forgetful User (Wedge Persona)

- **Archetype:** 28-year-old software developer with ADHD, takes 3 daily medications (Adderall, Lexapro, melatonin) + 2 supplements (magnesium, vitamin D)
- **Meds tracked:** 5
- **Technical comfort:** High
- **Primary platform:** iPhone, Apple Watch
- **Pain point:** Forgets evening meds constantly; generic reminder apps don't understand PRN dosing or "already took it" confirmation; wants zero-friction logging
- **Accessibility:** Needs large tap targets for quick confirmation; Watch complications for glanceable next-dose info
- **Switching trigger:** Current phone alarm doesn't confirm doses, has no inventory tracking, and doesn't know about drug interactions
- **Roadmap phases:** Phase 1 (MVP — core tracking + notifications), Phase 6 (adherence scoring)

### Persona 2: Margaret — The Chronic Condition Manager

- **Archetype:** 67-year-old retired teacher managing Type 2 diabetes, hypertension, and arthritis; takes 12 daily medications across 4 time windows
- **Meds tracked:** 12+
- **Technical comfort:** Low-medium (uses iPhone, not comfortable with complex apps)
- **Primary platform:** iPhone (large text), iPad at home
- **Pain point:** Complex regimen with timing dependencies (take with food, take 2 hours apart from calcium); current paper system fails when traveling
- **Accessibility:** Needs Dynamic Type (large text), high contrast, VoiceOver support, simple navigation
- **Switching trigger:** Missed a critical interaction between a new prescription and existing meds; doctor asked for medication list and she couldn't produce one
- **Roadmap phases:** Phase 1 (core tracking), Phase 3 (interaction checking), Phase 6 (reporting/export for doctor visits)

### Persona 3: David — The Biohacker / Supplement Optimizer

- **Archetype:** 35-year-old product manager who takes 15 supplements, tracks sleep/HRV/workout data, wants to correlate supplements with performance
- **Meds tracked:** 15 supplements + 1 prescription (finasteride)
- **Technical comfort:** Very high (uses CLI tools, exports data to spreadsheets)
- **Primary platform:** iPhone, Apple Watch, Web dashboard, CLI
- **Pain point:** No app correlates supplement timing with health metrics; has to manually cross-reference Apple Health data with supplement log in a spreadsheet
- **Accessibility:** Standard
- **Switching trigger:** Wants data-driven supplement optimization; no current app offers on-device health signal correlation
- **Roadmap phases:** Phase 1 (tracking), Phase 4 (CLI + web), Phase 7 (health signal analysis moonshot)

### Persona 4: Sarah — The Caregiver

- **Archetype:** 45-year-old managing medications for her 72-year-old mother (10+ meds) and her own 3 medications; mother lives 30 minutes away
- **Meds tracked:** 13+ across 2 profiles
- **Technical comfort:** Medium
- **Primary platform:** iPhone
- **Pain point:** Needs to manage two separate medication regimens; wants alerts if her mother misses a dose; current apps don't support multi-profile with shared access
- **Accessibility:** Mother needs large text and simple confirmation UI
- **Switching trigger:** Mother was hospitalized after a missed blood thinner dose; needs shared visibility into adherence
- **Roadmap phases:** Phase 5 (multi-vault sharing), Phase 6 (caregiver alerts)

### Persona 5: Jennifer — The Parent

- **Archetype:** 38-year-old with two children (ages 4 and 8); tracks children's medications (seasonal allergies, antibiotics when sick) and vaccination schedules
- **Meds tracked:** 2-6 (variable), plus vaccination records
- **Technical comfort:** Medium-high
- **Primary platform:** iPhone, iPad
- **Pain point:** Loses track of which vaccinations are due; pediatrician asks for medication history and she can't remember exact dates; weight-based dosing changes as kids grow
- **Accessibility:** Standard
- **Switching trigger:** Missed a booster shot deadline; wants a single app that tracks both daily meds and vaccination schedules for multiple children
- **Roadmap phases:** Phase 3 (vaccination tracking), Phase 5 (child vaults)

### Persona 6: Mike — The Pet Owner

- **Archetype:** 52-year-old with two dogs and a cat; manages heartworm prevention (monthly), flea/tick (monthly), joint supplements (daily for older dog), and periodic vet-prescribed medications
- **Meds tracked:** 6-8 across 3 pets
- **Technical comfort:** Medium
- **Primary platform:** iPhone
- **Pain point:** Monthly pet meds are easy to forget; different pets have different schedules; current human-focused apps don't accommodate pet medication databases or vet information
- **Accessibility:** Standard
- **Switching trigger:** Missed two months of heartworm prevention; vet bill for treatment was $1,200
- **Roadmap phases:** Phase 5 (pet vaults with distinct UX)

### Persona 7: Priya — The Frequent Traveler

- **Archetype:** 31-year-old management consultant who travels internationally 2-3 weeks per month; takes 4 daily medications + melatonin as-needed for jet lag
- **Meds tracked:** 5
- **Technical comfort:** High
- **Primary platform:** iPhone, Apple Watch
- **Pain point:** Timezone changes break medication schedules; needs offline reliability (spotty international data); wants to keep medication times anchored to body clock, not wall clock
- **Accessibility:** Standard
- **Switching trigger:** Took a double dose of thyroid medication after crossing 8 time zones because the app showed the wrong schedule
- **Roadmap phases:** Phase 1 (core tracking), Phase 6 (timezone-aware scheduling feature)

---

## SECTION 2: PRIVACY, DATA SOVEREIGNTY & ZERO-KNOWLEDGE ARCHITECTURE

### 2.1 — Zero-Knowledge Design

**Encryption boundary — what is encrypted vs. plaintext:**

| Data Category | Encrypted? | Rationale |
|---|---|---|
| Medication names, dosages, schedules | Yes — Encrypted (AES-256-GCM) | Core health data — user-owned |
| Dose logs (taken/skipped/missed) | Yes — Encrypted | Adherence patterns are sensitive |
| Inventory counts, refill dates | Yes — Encrypted | Reveals medication usage |
| Vaccination records | Yes — Encrypted | Sensitive PII |
| Health signal snapshots (from HealthKit) | Yes — Encrypted | Protected health data |
| Notes, photos of pills/labels | Yes — Encrypted | Could contain prescription details |
| Vault names, icons, colors | Yes — Encrypted (lightweight) | Vault name could reveal condition (e.g., "Diabetes Meds") |
| Drug reference data (FDA, RxNorm) | No — Plaintext | Public data, no privacy concern |
| Interaction rule database | No — Plaintext | Public reference data |
| Account email address | No — Plaintext (minimized) | Required for account recovery and communication |
| Subscription/billing status | No — Plaintext | Required for entitlement checking |
| Encrypted blob timestamps | No — Plaintext | Required for sync protocol ordering |

**Key derivation model:**

1. User creates a **master password** during onboarding
2. Master password is processed through **Argon2id** (memory-hard KDF) with a unique salt to produce the **Master Key (MK)**
3. MK never leaves the device and is never transmitted to the server
4. Authentication uses **SRP (Secure Remote Password)** protocol — the server stores an SRP verifier derived from the password, never the password or MK itself
5. A **Master Unlock Key (MUK)** is derived separately for local device unlock (backed by iOS Keychain + biometrics)

**Key hierarchy:**

```text
Master Password
    -> [Argon2id + salt] -> Master Key (MK)
        -> [HKDF] -> Authentication Key (for SRP)
        -> [HKDF] -> Master Encryption Key (MEK)
            -> wraps -> Vault Key (VK) per vault [AES-256-GCM keywrap]
                -> wraps -> Item Key (IK) per item [AES-256-GCM keywrap]
```

Each vault has its own symmetric key (VK). Each item (medication, dose log, vaccination) has its own item key (IK) wrapped by the VK. This enables granular sharing — share a vault by sharing its VK, encrypted to the recipient's public key.

**Per-platform key storage:**

| Platform | Key Storage | Biometric Unlock |
|---|---|---|
| iOS/iPadOS | iOS Keychain (kSecAttrAccessibleWhenUnlockedThisDeviceOnly) | Face ID / Touch ID via LAContext |
| watchOS | watchOS Keychain (synced from paired iPhone) | Wrist detection |
| Web | WebCrypto API + IndexedDB (non-extractable CryptoKey) | WebAuthn / passkey |
| CLI | OS keyring (macOS Keychain, Linux secret-service, Windows Credential Manager) | None (master password or environment variable) |

### 2.2 — Vault Architecture

Each user starts with one default vault ("My Meds"). Additional vaults are created for dependents, pets, or organizational grouping.

- **Vault = encryption boundary.** All items within a vault are encrypted under that vault's key
- **Vault key (VK)** is a random 256-bit AES key, generated on vault creation
- **VK is wrapped** by the owner's Master Encryption Key (MEK) and stored as an encrypted blob
- **Vault metadata** (name, icon, color, profile type) is encrypted under the VK — because vault names like "Mom's Heart Meds" leak health information
- **Profile types:** Personal, Dependent (Human), Pet — each type configures available features (e.g., pet vaults don't show HealthKit integration)

### 2.3 — Vault Sharing Model

**Access roles:**

| Role | Can View Items | Can Add/Edit Items | Can Delete Items | Can Manage Members | Can Delete Vault | Can Re-key Vault |
|---|---|---|---|---|---|---|
| Owner | Yes | Yes | Yes | Yes | Yes | Yes |
| Editor | Yes | Yes | No | No | No | No |
| Viewer | Yes | No | No | No | No | No |

**Invitation flow:**

1. Owner generates an invite containing the vault key (VK) encrypted to the recipient's public key (X25519)
2. If the recipient doesn't have an account yet, the invite link contains a one-time token; VK is encrypted to a temporary key derived from a shared secret (e.g., a 6-digit code communicated out-of-band)
3. Once the recipient creates an account and registers their public key, the VK is re-wrapped to their permanent public key
4. Server stores only encrypted key blobs — it never sees the VK in plaintext

**Revocation:** When a member is removed, the vault must be **re-keyed**:

1. Generate a new VK
2. Re-encrypt all vault items under the new VK (on the owner's device)
3. Re-wrap the new VK to all remaining members' public keys
4. Upload re-encrypted blobs to the server
5. **UX cost:** For a vault with 50 medications and 2,000 dose logs, re-encryption takes ~2-5 seconds on a modern iPhone. Display a progress indicator: "Securing your vault..."
6. **Performance mitigation:** Lazy re-encryption — re-encrypt item keys immediately (fast), re-encrypt item bodies in background

**Emergency / break-glass access:**

Implement a **time-delayed emergency access** model (similar to Bitwarden):

1. A trusted contact is designated as an emergency contact
2. They can request access to a vault
3. The owner receives a notification and has a configurable waiting period (e.g., 48 hours) to deny the request
4. If not denied, the vault key is released to the emergency contact (encrypted to their public key)
5. This is opt-in and configured per vault

### Temporary access (doctor visit) — On-device PDF export

- **Recommendation:** Generate a formatted PDF/printable medication list on-device. No server involvement, no sharing protocol complexity, works offline, doctor doesn't need to install anything.
- Rejected alternatives:
  - Time-limited sharing link: requires server infrastructure, recipient needs an account or web access, over-engineered for a 15-minute appointment
  - QR code for temporary view: requires a web service to host the decrypted view, breaks zero-knowledge for the duration
  - Persistent vault sharing: far too heavy for temporary access

**Child-to-adult transition:**

1. When a child turns 18 (or at the parent's discretion), the parent initiates a "transfer ownership" flow
2. The child creates their own account with a master password
3. The vault key is re-wrapped to the child's new MEK
4. The parent's access is either revoked or downgraded to Viewer (child's choice)
5. All vault data transfers seamlessly — no re-entry required

**Audit trail:** All vault sharing events (member added, removed, role changed, emergency access requested/granted/denied) are logged in an encrypted audit log within the vault. The audit log is itself encrypted under the VK.

**Legal authority disclaimer:** The app does not verify guardianship, power of attorney, parental authority, or any legal relationship between vault owner and dependent. A clear disclaimer is presented during vault creation for dependents: "You represent that you have legal authority to manage health information for this individual."

### 2.4 — Sync Architecture Under E2E Encryption

**Phase 1 (MVP):** Local-only. All data in an encrypted SQLite database (SQLCipher) on-device. No sync.

**Phase 2+:** Encrypted cloud sync using the following model:

1. Each item is encrypted on-device, producing an encrypted blob + encrypted metadata envelope
2. Blobs are uploaded to the server with a monotonically increasing version counter per vault
3. Server stores: `{vault_id, item_id, encrypted_blob, version, updated_at}` — it cannot read any content
4. **Conflict resolution:** Last-write-wins (LWW) at the item level, using Lamport timestamps embedded in the encrypted envelope. The client decrypts both versions and presents a merge UI if the same item was edited on two devices within the sync window.
5. **Rejected alternatives:**
   - CRDTs: Elegant but require the merge logic to operate on plaintext fields, which means the server would need to understand the data structure. Incompatible with encrypted blobs. [Validated]
   - Full vault re-download: Too expensive at scale; item-level sync is necessary

**Reference architectures studied:** 1Password (SRP + encrypted vaults), Bitwarden (AES-CBC encrypted items with RSA-OAEP key wrapping), Signal Protocol (double ratchet — overkill for non-real-time sync).

### 2.5 — Metadata Exposure Matrix

| Metadata Type | Who Can See It | Risk Level | Mitigation |
|---|---|---|---|
| Email address | Operator, email provider | Medium | Offer anonymous sign-up with recovery key only (no email); make email optional |
| Push notification timing | Apple (APNs) | Medium | Use **local notifications only** for MVP; if server push is added, use opaque periodic timers (fire every 15 min, client decides if a dose is due) |
| Drug autocomplete queries | Nobody (local index) | None | **Bundled local drug index** — no server queries for drug search |
| Encrypted blob sizes | Operator (sync server) | Low | Pad encrypted blobs to fixed size buckets (512B, 2KB, 8KB, 32KB) to prevent inference |
| IP addresses | Operator, ISP | Medium | Minimize server logs (retain 24h max); document Tor/VPN compatibility; no IP-based analytics |
| Sync timing patterns | Operator | Low | Batch sync on a timer (every 15 min) rather than on each action — prevents real-time behavioral inference |
| Billing records | Payment processor (Stripe) | Low | No health data in billing; use generic product names |
| App Store review metadata | Apple | Low | Standard; no mitigation needed |

### 2.6 — Threat Model & Guarantees

**User guarantees (precisely scoped):**

1. "Even if our servers are fully compromised, your encrypted health data cannot be decrypted without your master password."
2. "We cannot view, access, or disclose the content of your health data in response to any request — legal or otherwise — because we do not possess the decryption keys. Note: account metadata (email address, encrypted blob timestamps, subscription status) may be subject to legal process."
3. "Your data is yours. We will never sell, monetize, analyze, or share it. This is architecturally enforced, not just a policy promise."
4. "You can export all your data in a portable, decrypted format at any time from any device."

**Limits:**

- If the user loses their master password AND printed recovery key, their data is **permanently unrecoverable**. This is a feature, not a bug. The app communicates this clearly during onboarding.
- Metadata (see Section 2.5) is not protected by E2E encryption. The operator can see *that* you use the app and *when* you sync, but not *what* medications you take.

**Auditability:** The encryption layer (crypto primitives, key derivation, vault protocol) will be **open-sourced** under MIT license as a standalone library, even if the application code is not fully open source. This enables third-party security audits and community review. Target: publish before Phase 2 (cloud sync) ships.

### 2.7 — Liability & Disclaimers

- The product is an **informational tracking tool**, not a medical device and not a source of medical advice
- **Interaction warnings** always display: "This is informational only, sourced from [database name, date]. Consult your healthcare provider before making any medication decisions."
- **First-launch consent:** User acknowledges that the app does not provide medical advice and they are solely responsible for their health decisions
- **Terms of Service:** User accepts full responsibility; the project provides data and tools, not guidance
- **Data provenance indicator:** Every piece of drug reference data shows its source (e.g., "Source: openFDA DailyMed, last updated 2025-01-15") and staleness warning if data is >90 days old
- **UX pattern for disclaimers:** Subtle but persistent — a small "Informational only" tag on every interaction warning, expandable to full disclaimer text. Not a modal that blocks workflow.

---

## SECTION 3: REGULATORY, LEGAL & TRUST BOUNDARIES

### 3.1 — Regulatory Landscape

| Domain | Applies? | Why / Why Not | Recommended Posture | Phase |
|---|---|---|---|---|
| **FDA SaMD / Clinical Decision Support (CDS)** | Partially | Pure tracking is exempt. Interaction warnings that display severity levels *may* qualify as CDS under 21st Century Cures Act criteria. Health signal correlation (Phase 7) is highest risk. | Ship Phase 1-2 features under the tracking/informational exemption. Before shipping interaction checking (Phase 3), obtain legal opinion on CDS classification. Defer health correlation until legal clearance. `[Validation Required]` | Phase 3+ |
| **FTC Health Claims** | Yes, for marketing | Marketing language must not imply the app improves health outcomes ("manage your health better" is risky; "track your medications" is safe) | Review all marketing copy with FTC health claims guidelines. Never state or imply clinical efficacy. | All phases |
| **HIPAA** | Largely no | HIPAA applies to covered entities and business associates. A consumer app where the server never sees plaintext PHI is not a covered entity. The zero-knowledge architecture is the strongest possible defense. | Do not pursue HIPAA certification for MVP. When FHIR pharmacy import is added, the brief plaintext-to-encrypted pipeline on-device does not create a covered entity relationship. Document this analysis for legal review. `[Validation Required]` | Phase 3+ |
| **COPPA** | Yes, for child profiles | If a parent creates a vault for a child under 13, COPPA may apply. The app collects health data about children. | Do not collect identifying data about children on the server (the vault is encrypted and the server can't read it). The parent is the account holder. Obtain legal opinion on whether encrypted-on-device child health data triggers COPPA. `[Validation Required]` | Phase 5 |
| **State Health Privacy Laws (WA My Health My Data Act, etc.)** | Yes | These laws apply to consumer health data broadly, regardless of HIPAA status. Washington's law specifically covers "consumer health data" including medication records. | Comply proactively: provide data deletion on request (straightforward — delete encrypted blobs), data export (on-device decryption), and clear privacy disclosures. The zero-knowledge architecture makes compliance easier. `[Validation Required]` | Phase 2+ |
| **GDPR / International Privacy** | Later | Not applicable for US-only launch. Required before any EU expansion. | Defer until international expansion. Architecture is GDPR-friendly by design (data minimization, encryption, right to erasure). | Phase 8+ |
| **TCPA / CAN-SPAM** | Minimal | Only relevant if email/SMS reminders are implemented. | **Do not implement email or SMS reminders.** Use local notifications only. If push notifications are added, they are device-to-device via APNs, not marketing communications. | All phases |
| **Apple App Store Health Guidelines** | Yes | Health apps must not make medical claims, must handle HealthKit data per Apple guidelines, must have a privacy policy. | Follow Apple HIG for health apps. Ensure HealthKit usage descriptions are accurate. Submit for App Review with clear "informational only" positioning. `[Validation Required]` | Phase 1+ |

### 3.2 — Feature Risk Classification

| Feature | Risk | Rationale |
|---|---|---|
| Manual medication entry and tracking | 🟢 Low risk | Pure data entry and logging |
| Scheduling and local notifications | 🟢 Low risk | Reminder tool, no clinical content |
| Dose logging (taken/skipped/missed) | 🟢 Low risk | Personal record-keeping |
| Inventory and supply tracking | 🟢 Low risk | Quantity tracking, no clinical interpretation |
| Drug reference data display (side effects, storage) | 🟡 Informational | Displays published reference data with source attribution |
| Drug-drug interaction checking | 🟡 Informational to 🔴 if severity influences behavior | Displaying "Major interaction" between two drugs could influence dosing decisions. **Legal review required before Phase 3 ships.** |
| Supplement-supplement interaction checking | 🟡 Informational | Less regulated than drug interactions, but same disclaimers apply |
| Vaccination schedule display (CDC schedules) | 🟡 Informational | Displaying standard public health schedules with source attribution |
| Vaccination recommendations ("your child is due for...") | 🔴 Medically sensitive | Could be interpreted as medical advice; needs contextual disclaimer and legal review |
| Health signal correlation (Phase 7) | 🔴 Medically sensitive | Correlating meds with health outcomes approaches CDS territory; **FDA legal review required** |
| Medication tapering schedules | 🔴 Medically sensitive | Tapering guidance (especially for SSRIs, steroids, benzodiazepines) is clinical guidance; user must enter taper schedule from their doctor, app must not generate taper plans |
| Pediatric dosing calculations | ⛔ Not recommended | Weight-based dosing calculations carry direct patient safety risk; liability exposure is extreme. **Do not implement.** Allow parents to enter doctor-prescribed doses, but never calculate doses. |
| Dosing recommendations/adjustments | ⛔ Not recommended | Clinical decision-making; FDA SaMD territory; unacceptable liability |
| Diagnostic suggestions | ⛔ Not recommended | Out of scope; medical device territory |

### 3.3 — Trust Boundaries & External Dependencies

| External System | Data Exposed | Trust Level | Mitigation |
|---|---|---|---|
| Apple Health (HealthKit) | Health signals, medication records | High | On-device only; Apple's own encryption; data encrypted under vault key before any sync |
| APNs (Push Notifications) | Push timing, opaque payload | Medium | Use local notifications for MVP; if server push is added, use opaque timers with no health content in payload |
| openFDA / DailyMed / RxNorm APIs | Drug search queries | Low (if server-side) | **Mitigated: use locally bundled drug index.** No server queries for drug search. |
| App Store / TestFlight | App binary, metadata | Medium | Standard; no health data exposure |
| Payment processor (Stripe) | Billing info, subscription status | Medium | No health data; generic product names in billing |
| Apple Vision (OCR) | Prescription label images | High (on-device) | **On-device only** — use Apple's Vision framework, never cloud OCR |
| Pharmacy FHIR APIs | Medication records | Low | Data enters device and is encrypted immediately; brief plaintext window is on-device only `[Validation Required]` |
| State IIS (Immunizations) | Vaccination records | Low | Same as FHIR — encrypt immediately on-device `[Validation Required]` |

### 3.4 — Non-Goals & Red Lines

The following are explicitly **out of scope** and will not be built:

1. **No dosing recommendations or adjustments** — the app tracks user-entered doses, never calculates or suggests doses
2. **No diagnostic suggestions** based on symptoms or health data
3. **No direct-to-pharmacy prescription ordering** — unacceptable liability and regulatory complexity
4. **No sharing of user data with insurance companies, employers, or data brokers** — architecturally impossible due to E2E encryption
5. **No server-side analytics on user health patterns** — server cannot read encrypted data
6. **No pediatric dose calculations** — weight/age-based dosing is clinical decision-making (⛔)
7. **No medication recommendations** ("you should take X for Y condition")
8. **No integration with telemedicine platforms** that would require plaintext data sharing
9. **No advertising or third-party tracking SDKs** — zero analytics SDKs that phone home with user data

---

## SECTION 4: CORE FEATURE SET

### 4.1 — Medication & Supplement Input 🟢

**MVP (Phase 1):** Manual entry with fields: name (free text + autocomplete from local index), dosage (amount + unit), form (pill/capsule/liquid/topical/injection/other), frequency, time(s) of day, optional notes. Encrypted on-device via SQLCipher.

**Full feature:** Add prescriber, pharmacy, reason/condition, start/end dates, refill info, photo of pill/bottle (stored encrypted), barcode scanning.

**E2E implementation:** Autocomplete uses a **locally bundled drug index** (compressed openFDA + RxNorm data, ~80-120MB on disk). The index is shipped with the app and updated via app updates or a background delta-download. **No server queries for drug search — this is the recommended approach.**

- Rejected: Server-side search (leaks medication interest), k-anonymity batch queries (complex, partial privacy)

### 4.2 — Bulk Import & External Sources 🟢

**MVP (Phase 1):** CSV import via CLI tool. Manual entry on iOS.

**Full feature:**

- CSV/JSON import (CLI + web)
- Apple Health medication import (Phase 3) — reads HealthKit medication records, encrypts into vault
- FHIR pharmacy import (Phase 3+) — `[Validation Required]` — availability varies by pharmacy chain; Walgreens, CVS have patient-facing APIs but access requires partnership
- OCR of prescription labels (Phase 4) — Apple Vision framework on-device only; not available on web/CLI
- Import from other apps: Export/import via standard formats (JSON, CSV); direct integration unlikely due to closed ecosystems

**E2E note:** All imported data is encrypted on-device immediately. OCR uses Apple's on-device Vision framework — image data never leaves the device.

### 4.3 — Scheduling & Notifications 🟢

**Recommended primary notification architecture: iOS/iPadOS local notifications + watchOS haptic alerts.**

This is the **only architecture that maintains full zero-knowledge guarantees** with high reliability.

**Channel feasibility matrix:**

| Channel | Privacy Leakage | Reliability | E2E Compatible? | Cost | MVP? | Recommendation |
|---|---|---|---|---|---|---|
| iOS/iPadOS local notifications | None (on-device) | High (up to 64 pending) | Yes | Free | Yes | **Primary channel — use this** |
| watchOS haptic alerts | None (on-device) | High | Yes | Free | Yes | **Secondary channel — companion to iOS** |
| Push via APNs (opaque timers) | Timing pattern visible to Apple | Medium | Partial | Free | No | Defer to Phase 2+ only if local notification limits are hit; use opaque periodic heartbeat, not per-dose pushes |
| Email reminders | Email + timing + content visible | Low | No | Low | No | **Do not implement.** Breaks zero-knowledge entirely. |
| SMS reminders | Phone + timing + content visible | Low | No | $$$+ | No | **Do not implement.** Breaks zero-knowledge and is expensive. |
| CLI system notifications | None (local) | Medium | Yes | Free | Later | Phase 4 with CLI tool |

**Scheduling capabilities (Phase 1):** Daily, multiple times/day, every N days, specific days of week, as-needed (PRN with logging only, no auto-schedule), cycling schedules (e.g., "5 on / 2 off").

**Snooze/skip/confirm flow:** Notification action buttons: "Taken" / "Snooze 15m" / "Skip". Tapping opens the app pre-filled on the dose confirmation screen.

**Escalating reminders (Phase 6):** If a dose isn't confirmed within 30 minutes, send a second notification. If still unconfirmed after 1 hour, alert a caregiver (if configured in a shared vault).

### 4.4 — Authoritative Drug & Supplement Data 🟡

**Data source validation table:**

| Source | Availability | License / Cost | Coverage | API Maturity | MVP Suitable? | Validation Status |
|---|---|---|---|---|---|---|
| openFDA / DailyMed | Public | Free (public domain) | US prescription drugs, OTC | Mature REST API | Yes | [Validated] |
| RxNorm (NLM) | Public | Free (UMLS license, no cost) | US drug naming normalization | Mature REST API | Yes | [Validated] |
| NIH ODS (Office of Dietary Supplements) | Public | Free | US supplements — limited to ~100 fact sheets | No structured API | Partial | [Validation Required] — may need scraping/manual curation |
| Natural Medicines Database (TRC) | Licensed | $$$+ (institutional pricing) | Comprehensive supplement interactions | Unknown API availability | No (MVP) | [Validation Required] — licensing inquiry needed |
| DrugBank | Licensed | $2,500+/yr (academic), more for commercial | Drug interactions, comprehensive | Good REST API | No (MVP) | [Validation Required] — licensing inquiry needed |
| State IIS (immunization registries) | Varies by state | Free (government) | Vaccination records | [Validation Required] | No | State-by-state API research needed |
| Pharmacy FHIR (CVS, Walgreens) | [Validation Required] | Free? | Medication fill history | [Validation Required] | No | Partnership/API access inquiry needed |

**MVP data strategy:** Bundle openFDA + RxNorm data as a local SQLite index. For supplements, curate a manual index of the top 200 supplements with basic interaction data from public NIH sources. Expand to licensed databases post-revenue.

**Data freshness:** Update the bundled drug index with each app release (monthly cadence). Implement a background delta-update mechanism in Phase 3 so the index can refresh without a full app update.

### 4.5 — Inventory & Supply Tracking 🟢

**MVP (Phase 6):** Not in MVP — deferred to reduce Phase 1 scope.

**Full feature:** Track pills remaining per medication. Auto-decrement on dose confirmation. Low-supply alert at configurable threshold (default: 7 days remaining). Manual refill logging (date, quantity, pharmacy, cost). Monthly cost summary.

**E2E note:** All inventory data is encrypted within the vault. No server-side analytics on refill patterns.

### 4.6 — Interaction Checking 🟡 (potentially 🔴)

**Implementation:** On-device interaction checking using a locally cached interaction database. When a user adds a new medication, the app checks it against all other medications/supplements in the vault on-device.

**Severity display:** Minor (informational note) | Moderate (yellow warning) | Major (red warning with prominent disclaimer) | Contraindicated (red alert with strong disclaimer and recommendation to contact healthcare provider immediately).

**Disclaimer on every interaction result:** "Informational only. Source: [database], updated [date]. This is not medical advice. Consult your healthcare provider."

**Legal review gate:** Before shipping interaction checking in Phase 3, obtain a legal opinion on whether severity-classified interaction warnings constitute Clinical Decision Support under FDA's 21st Century Cures Act criteria. `[Validation Required]`

**E2E note:** Interaction database is public reference data (plaintext, cached locally). The user's medication list never leaves the device — all checking is client-side.

### 4.7 — Apple Health Integration 🟢 (read) / 🟡 (correlation analysis)

**Phase 1:** Request HealthKit permissions for medication records (read/write). Write dose logs to HealthKit as HKMedicationDoseEvent.

**Phase 6:** Read health signals: heart rate, HRV, sleep analysis, blood oxygen, activity, blood pressure, blood glucose. Store encrypted snapshots for future correlation analysis.

**Phase 7 (moonshot):** On-device correlation analysis between medication adherence and health signal trends. Risk classification: 🔴 — requires legal review.

**E2E note:** HealthKit data stays on-device (Apple's own security model). Any data pulled into the app for storage/sync is encrypted under the vault key before leaving the device.

---

## SECTION 5: MULTI-PROFILE VAULTS, VACCINATION TRACKER & SHARING

### 5.1 — Multi-Profile Vaults 🟢

**Architecture (Phase 0):** Design the vault key hierarchy from day one. Even the MVP single-vault experience is built on the vault architecture — the default "My Meds" vault is a real vault with its own VK.

**UX (Phase 5):**

- Vault switcher in the navigation (sidebar on iPad, tab bar long-press or dedicated screen on iPhone)
- Each vault has a profile type: Personal | Dependent (Human) | Pet
- **Pet vault UX differences:** Medication databases shift to veterinary sources (initially manual entry only); "Doctor" field becomes "Veterinarian"; scheduling patterns include monthly preventatives; weight tracking for dosing reference (display only, no calculations)
- Vault creation flow: Name, profile type, icon/color, optional profile photo (encrypted)

**E2E note:** Each vault has its own symmetric key. The vault architecture must be designed in Phase 0 even if multi-vault UX ships later. This is non-negotiable — retrofitting vault encryption is architecturally expensive.

### 5.2 — Vaccination Tracker 🟡

**Phase 3 feature:** Track vaccination records per vault (date, vaccine name, lot number, provider, site/location, next due date).

- Display CDC recommended schedules for children and adults as reference data 🟡
- Upcoming vaccination reminders based on standard schedules or user-entered dates
- Store photos/scans of vaccination cards (encrypted, on-device storage)
- **Import from state IIS:** `[Validation Required]` — defer to Phase 5+ pending API availability research

**Risk notes:** Displaying standard CDC schedules with source attribution is 🟡 Informational. Generating personalized vaccination recommendations ("your child should get MMR now") is 🔴 and requires legal review. **Recommendation:** Display the standard schedule and let the user mark vaccinations as received. Do not generate personalized recommendations.

**E2E note:** Vaccination records are highly sensitive PII — same encryption guarantees as medication data. On-device storage with encrypted sync.

---

## SECTION 6: FEATURES THE USER MAY HAVE MISSED

### 6.1 — Medication Adherence Scoring & Streaks 🟢

**What:** Calculate a simple adherence percentage (doses taken / doses scheduled) per medication and overall. Display streaks ("14 days in a row!") for motivation.
**Why:** Gamification drives consistent behavior; adherence data is valuable for doctor conversations.
**Milestone:** Phase 6 (Intelligence Layer)
**E2E note:** All calculations on-device. Adherence data encrypted in vault.

### 6.2 — On-Device PDF Export ("Doctor Mode") 🟢

**What:** Generate a formatted PDF listing all medications, dosages, schedules, and recent adherence — designed to hand to a healthcare provider.
**Why:** Solves the number one real-world scenario: "What medications are you taking?" at a doctor visit.
**Milestone:** Phase 3 (Data Enrichment) — ship early, high user value
**E2E note:** PDF generated on-device, never touches a server. User can AirDrop, print, or share manually.

### 6.3 — Timezone-Aware Scheduling 🟢

**What:** Detect timezone changes and offer to adjust medication schedules: "anchor to body clock" (keep 8-hour intervals regardless of wall clock) vs. "anchor to local time" (take at 8am local).
**Why:** Priya (frequent traveler persona) — critical for medications where timing matters (thyroid, birth control).
**Milestone:** Phase 6 (Intelligence Layer)
**E2E note:** Timezone detection is on-device (Core Location); no server involvement.

### 6.4 — Drug Recall Alerts 🟡

**What:** Monitor FDA recall RSS feeds. Push recall alerts for drugs matching the user's medications.
**Why:** Safety feature with high trust-building value.
**Milestone:** Phase 6
**E2E note:** The server checks FDA recalls and pushes a generic notification with the recall notice (public data). The **client** then checks locally whether the recalled drug matches any medication in the user's encrypted vault. The server never learns which medications the user takes. The notification payload contains the recall data, not the user's medication match.

### 6.5 — Generic/Brand Name Equivalence 🟢

**What:** Map generic to brand names (e.g., "atorvastatin" to "Lipitor") using RxNorm data.
**Why:** Users enter medications inconsistently; interaction checking requires normalized names.
**Milestone:** Phase 3 (built into drug data pipeline)
**E2E note:** RxNorm mapping is public reference data; the user's selected medication is encrypted.

### 6.6 — Medication Tapering Schedule Tracker 🔴

**What:** Allow users to enter a doctor-prescribed tapering schedule (e.g., "reduce by 25mg every 2 weeks") and track progress through the taper.
**Why:** Common need for SSRIs, steroids, benzodiazepines. Currently tracked on paper or not at all.
**Milestone:** Phase 6 — **with legal review gate**
**E2E note:** User-entered taper plans encrypted in vault. **The app never generates or suggests a taper schedule — only tracks a doctor-prescribed plan.**
**Risk:** 🔴 because displaying a taper schedule with declining doses could be interpreted as dosing guidance. Mitigate with prominent disclaimer: "This taper schedule was entered by you based on your healthcare provider's instructions."

### 6.7 — Accessibility Suite 🟢

**What:** Full VoiceOver support, Dynamic Type up to xxxLarge, high-contrast mode, reduced-motion mode, large tap targets (minimum 44pt), haptic feedback for confirmations.
**Why:** Margaret (chronic condition manager persona) and aging users are a primary audience.
**Milestone:** Phase 1 (baseline accessibility from day one), Phase 8 (formal accessibility audit)
**E2E note:** No encryption impact — accessibility is a presentation-layer concern.

### 6.8 — Offline-First Architecture 🟢

**What:** The app works fully offline. Sync is a background enhancement, not a requirement.
**Why:** Aligns with local-first encryption model; critical for Priya (traveler) and any user in low-connectivity situations.
**Milestone:** Phase 1 (inherent in local-only MVP); Phase 2 (maintained through sync layer)
**E2E note:** Offline-first is a natural consequence of the local-encrypted architecture. The app is fully functional with zero network access.

### 6.9 — iOS Widgets & Watch Complications 🟢

**What:** Home screen widget showing next upcoming dose; Lock Screen widget with dose count remaining today; Watch complication with next dose time and medication name.
**Why:** Reduces friction for Alex (ADHD user) — glanceable information without opening the app.
**Milestone:** Phase 4 (multi-platform expansion)
**E2E note:** Widget data is decrypted on-device for display. iOS widget data is stored in a shared App Group container, encrypted at rest by iOS data protection. Minimize data in widget storage — only next 3 upcoming doses.

### 6.10 — Siri Shortcuts & Voice Dose Logging 🟢

**What:** "Hey Siri, log my morning meds" confirms all scheduled morning medications as taken.
**Why:** Zero-friction logging for Alex (ADHD persona); accessibility for Margaret (motor challenges).
**Milestone:** Phase 4
**E2E note:** Siri Shortcuts run on-device. The shortcut interacts with the app's encrypted database locally. No data is sent to Apple's servers beyond the voice transcription (which Apple processes under their own privacy policy and does not contain medication data — only the command).

### 6.11 — Full Data Export 🟢

**What:** Export all vault data as decrypted JSON, CSV, or PDF at any time. "Your data is yours" — enforced by architecture, demonstrated by export.
**Why:** Reinforces the data ownership promise. Reduces lock-in anxiety. Required by some state privacy laws.
**Milestone:** Phase 3 (JSON/CSV via CLI + iOS), Phase 4 (web)
**E2E note:** Export happens entirely on-device. The app decrypts vault data using the user's key, formats it, and saves/shares the plaintext file locally. The server is never involved.

### 6.12 — Dark Mode 🟢

**What:** Full dark mode support following system preference, with manual override.
**Why:** Standard user expectation; reduces eye strain for evening medication logging.
**Milestone:** Phase 1 (built into design system from day one)
**E2E note:** No encryption impact.

---

## SECTION 7: MOONSHOT FEATURES

### 7.1 — Health Signal Impact Analysis 🔴

**What:** Correlate medication/supplement adherence with Apple Health data trends over time. Example insight: "Since starting Magnesium Glycinate 30 days ago, your average sleep duration increased by 22 minutes (7h12m to 7h34m) and HRV improved by 8% (42ms to 45ms)."

**Data needed:** Daily HealthKit snapshots (sleep, HRV, resting HR, blood pressure, blood glucose, SpO2, step count) + medication adherence log from the app.

**Statistical approach:** Rolling 30-day averages with before/after comparison against supplement start dates. Display confidence indicators ("based on 30 days of data" vs. "based on 7 days — needs more data"). Always include a confounding variables disclaimer: "Many factors affect these health signals. This correlation does not imply causation."

**UX:** A "Health Insights" tab (Phase 7) showing trend cards per medication/supplement with sparkline charts. Each card has a data provenance footer and disclaimer.

**Regulatory risk:** 🔴 Medically sensitive. Correlating medications with health outcomes may qualify as Clinical Decision Support under FDA criteria. **Mandatory legal review before development begins.** If CDS classification is triggered, either (a) pursue FDA pre-certification (expensive, slow) or (b) redesign as raw data visualization without interpretive language (show the chart, don't say "improved").

**E2E note:** All analysis runs on-device using Core ML or simple statistical functions in Swift. No health data is transmitted to any server. The analysis model itself is public (shipped with the app), but the user's data never leaves the device.

### 7.2 — Performance Signal Analysis 🔴

**What:** Extend health signal analysis to athletic/cognitive performance: VO2 max trends, workout recovery metrics, self-reported mood/energy scores correlated with supplement regimen changes.

**Data needed:** HealthKit workout data + VO2 max + user self-reported mood/energy (1-5 scale daily check-in) + supplement adherence log.

**UX:** Longitudinal dashboard with exportable PDF reports. David (biohacker persona) is the primary user.

**Regulatory risk:** 🔴 — same CDS concerns as Section 7.1. Additionally, mood tracking correlated with medication adherence creates risk of being interpreted as mental health treatment support.

**E2E note:** Entirely on-device. Self-reported mood data is encrypted in the vault like all other health data.

---

## SECTION 8: TECH STACK RECOMMENDATIONS

> **Note:** This section's original recommendations have been superseded by
> [ADR-006: Tech Stack Consolidation](adr/006-tech-stack-consolidation.md),
> which consolidates the stack to 3 primary languages (Rust, Swift, TypeScript)
> plus Python for ETL. The table below reflects the updated decisions.

| Component | Recommendation | Justification |
|---|---|---|
| **Crypto Library** | **Rust** (`pildora-crypto`), compiled to native (FFI) + WASM | Single implementation = single audit target. Shared by CLI, server (as crate), iOS (via FFI), and web (via WASM). See ADR-001. |
| **CLI Tool** | **Rust + clap**, shares `pildora-crypto` crate directly | Same language as crypto — no FFI bridge needed. clap for CLI parsing, ratatui for optional TUI. Distributed via GitHub Releases and cargo install. |
| **Backend API / Sync Server** | **Rust + Axum**, deployed as a single static binary | Replaces the original Go recommendation. Shares crypto crate directly for SRP-6a auth. Thin server — stores/retrieves encrypted blobs only. Deploy on Fly.io, Railway, Docker, or bare metal. |
| **iOS / iPad App** | **Native Swift/SwiftUI**, minimum iOS 17 | Non-negotiable for HealthKit, Keychain, Secure Enclave, Watch, and local notifications. pildora-crypto bridged via FFI (UniFFI or cbindgen). |
| **watchOS App** | **Companion app (shared Swift package)**, watchOS 10+ | Share data model and crypto layer via Swift Package; complications for next dose; haptic dose confirmation |
| **Website / Web App** | **Next.js (App Router) + React + TypeScript**, pildora-crypto via WASM | SSR for marketing/SEO pages, SPA for dashboard. Crypto operations run in Rust WASM — no JS crypto reimplementation. Rust WASM UI frameworks (Leptos, Yew) were evaluated and rejected for maturity reasons (see ADR-006). |
| **Database** | **SQLite (on-device)** for encrypted blob storage; **PostgreSQL or SQLite** (server-side) for encrypted blob metadata | On-device: plain SQLite storing pre-encrypted blobs (CLI) or SQLCipher (iOS). Server: Axum + SQLx with PostgreSQL or SQLite. |
| **Auth & Key Exchange** | **SRP-6a** for zero-knowledge auth; **Argon2id** for key derivation; **X25519** for public-key key exchange | SRP prevents server from ever seeing the password; Argon2id is the current best-practice memory-hard KDF; X25519 for efficient vault sharing key wrapping |
| **E2E Encryption Layer** | **Single Rust library** (`pildora-crypto`) using RustCrypto crates or ring | One implementation across all platforms. Swift access via FFI, web access via WASM. Eliminates the multi-library divergence risk of per-platform libsodium bindings. |
| **Drug Data Pipeline** | **Python ETL scripts** into SQLite index, bundled with app releases | Python for batch data processing (openFDA bulk download, RxNorm normalization); output is a compressed SQLite file shipped as an app asset |
| **Notifications** | **iOS UNUserNotificationCenter (local)** + watchOS mirroring | Local notifications are E2E compatible and highly reliable; no server involvement |
| **CI/CD** | **GitHub Actions** | Matrix builds for Rust (Linux, macOS, Windows), iOS/Watch (Xcode on macOS runners), web (Node), data pipeline (Python). Fastlane for iOS builds and TestFlight distribution. |
| **Monitoring** | **Sentry (self-hosted or cloud with PII scrubbing)** for crash reporting; **no analytics SDK** | Sentry can be configured to strip PII; no third-party analytics (Mixpanel, Amplitude, etc.) — those require user data the project refuses to collect |

**Cross-platform crypto parity:** Use a **single shared Rust library** (`pildora-crypto`) as the crypto implementation across all platforms. Swift accesses it via FFI (UniFFI or cbindgen), the web app via WASM (wasm-bindgen), and the CLI + server import it as a Cargo workspace crate. One implementation = one audit target = zero divergence risk. This supersedes the earlier recommendation to use per-platform libsodium bindings.

**Open-source crypto module:** The `pildora-crypto` crate is the auditable encryption module. Published with cross-platform test vectors that Swift FFI and WASM builds validate against.

**Monorepo strategy:** Use a **Cargo workspace** for Rust components and **Swift Package Manager** for Apple platforms. Structure:

```text
pildora/
  crypto/          — pildora-crypto Rust crate (lib)
  cli/             — CLI binary crate (depends on crypto)
  server/          — Sync server binary crate (depends on crypto)
  ios/             — SwiftUI app (crypto via FFI)
  web/             — Next.js app (crypto via WASM npm package)
  data/            — Python ETL pipeline
  docs/            — Documentation, ADRs
```

**Estimated infrastructure costs:**

| Users | Sync Server (Cloudflare) | Storage (R2) | Total/month |
|---|---|---|---|
| 0 (development) | $0 (free tier) | $0 | $0 |
| 1,000 | ~$5 | ~$2 | ~$7 |
| 10,000 | ~$25 | ~$15 | ~$40 |
| 100,000 | ~$150 | ~$100 | ~$250 |

**Crypto-specific primitives:**

| Primitive | Algorithm | Purpose |
|---|---|---|
| Symmetric encryption | AES-256-GCM (via libsodium secretbox/AEAD) | Item encryption, vault metadata encryption |
| Key derivation | Argon2id (memory: 64MB, iterations: 3, parallelism: 1) | Master password to master key |
| Key wrapping | AES-256-GCM keywrap | Wrapping vault keys with master key, item keys with vault key |
| Asymmetric key exchange | X25519 (Curve25519 Diffie-Hellman) | Vault sharing — encrypt vault key to recipient's public key |
| Key derivation (sub-keys) | HKDF-SHA-256 | Deriving authentication key and encryption key from master key |
| Authentication | SRP-6a (3072-bit group) | Zero-knowledge password authentication with server |
| Hashing | BLAKE2b | Integrity checks, content addressing |

---

## SECTION 9: DATA MODEL

### Entity-Relationship Diagram (Text)

```text
User (1) ---- (N) VaultMember (N) ---- (1) Vault
                                            |
                        +-------------------+-------------------+
                        |                   |                   |
                   Medication (N)      Vaccination (N)     AuditLog (N)
                        |
              +---------+---------+
              |         |         |
         Schedule (N)  DoseLog (N)  Inventory (1)

                                   HealthSignal (N)

--- Reference Data (Plaintext, Shared) ---

DrugReference (1) ---- (N) InteractionRule
```

### Entity Details

| Entity | Key Attributes | Encrypted? | Vault-Scoped? |
|---|---|---|---|
| **User** | id, email (optional), srp_verifier, public_key (X25519), created_at | email: plaintext; srp_verifier: plaintext (not sensitive); public_key: plaintext | No (account-level) |
| **Vault** | id, owner_user_id, encrypted_metadata (name, icon, color, profile_type), wrapped_vault_key | Metadata: encrypted; wrapped key: encrypted | Self-contained |
| **VaultMember** | vault_id, user_id, role (owner/editor/viewer), wrapped_vault_key (encrypted to member's public key) | wrapped_vault_key: encrypted | Links User to Vault |
| **Medication** | id, vault_id, encrypted_blob (name, dosage, form, frequency, prescriber, pharmacy, notes, photo_refs, rxnorm_id, start_date, end_date) | Entire blob encrypted under vault key | Yes |
| **Schedule** | id, medication_id, vault_id, encrypted_blob (times, days, cycle_pattern, timezone_mode) | Encrypted | Yes |
| **DoseLog** | id, medication_id, vault_id, encrypted_blob (timestamp, status: taken/skipped/missed, notes) | Encrypted | Yes |
| **Inventory** | id, medication_id, vault_id, encrypted_blob (quantity_remaining, refill_date, cost, pharmacy) | Encrypted | Yes |
| **Vaccination** | id, vault_id, encrypted_blob (vaccine_name, date, lot_number, provider, location, next_due, photo_refs) | Encrypted | Yes |
| **HealthSignal** | id, vault_id, encrypted_blob (signal_type, value, date, source) | Encrypted | Yes |
| **NotificationPref** | id, vault_id, encrypted_blob (channels, snooze_duration, escalation_rules) | Encrypted | Yes |
| **AuditLog** | id, vault_id, encrypted_blob (event_type, actor_user_id, timestamp, details) | Encrypted | Yes |
| **DrugReference** | rxnorm_id, name, brand_names, form, drug_class, side_effects, storage, source, updated_at | Plaintext | No (reference data) |
| **InteractionRule** | drug_a_rxnorm_id, drug_b_rxnorm_id, severity, description, source, updated_at | Plaintext | No (reference data) |

**Server-side storage model:** Encrypted entities are stored as opaque blobs. The server schema is:

```sql
-- Server only sees this
CREATE TABLE encrypted_items (
    id TEXT PRIMARY KEY,
    vault_id TEXT NOT NULL,
    item_type TEXT NOT NULL,  -- 'medication', 'dose_log', etc.
    encrypted_blob BLOB NOT NULL,
    version INTEGER NOT NULL,
    updated_at TIMESTAMP NOT NULL
);
```

The server cannot query, filter, or index any encrypted content. All querying happens on-device after decryption.

**Migration strategy:** Schema versioning is embedded in the encrypted blob format. Each blob starts with a version byte. Client-side migration runs on decryption: if the blob version is older than current, the client re-encrypts with the updated schema. This avoids server-side migrations of encrypted data.

**Vault sharing support:** The VaultMember entity stores wrapped_vault_key — the vault's symmetric key encrypted to each member's X25519 public key. When a member opens a shared vault, they decrypt the wrapped_vault_key with their private key, then use the resulting VK to decrypt all items in the vault.

---

## SECTION 10: DESIGN BRIEF

### 10.1 — Design Principles

1. **Calm & Trustworthy** — The app should feel like a reliable, quiet assistant — not an anxious health dashboard. Muted color palette, generous whitespace, no aggressive gamification.
2. **Glanceable** — The most common action (confirming a dose) must take < 3 seconds and < 2 taps. Information hierarchy optimizes for "what's next?"
3. **Privacy-Visible** — The zero-knowledge promise is not hidden in settings. A subtle lock icon and "Encrypted" badge are persistently visible, reinforcing trust. The vault metaphor is used throughout the UI.
4. **Accessible by Default** — Dynamic Type, VoiceOver, high contrast, and large tap targets are not afterthoughts. The app must be usable by Margaret (67, low vision) as comfortably as by Alex (28, tech-savvy).
5. **Honest & Transparent** — Disclaimers are visible but not obstructive. Data sources are always attributed. The app never overstates its capabilities.

**Design system:** Follow **Apple Human Interface Guidelines (HIG)** as the foundation. Build a lightweight custom design token layer on top (color palette, typography scale, spacing scale, component library) using SwiftUI's native styling capabilities. No third-party UI framework.

### 10.2 — Key Screens Per Platform

**iPhone (8 key screens):**

1. **Today View (Home)** — Timeline of upcoming doses today, with quick-confirm buttons. Shows adherence for today ("4 of 6 taken"). Vault indicator at top.
2. **Medication List** — All medications in the active vault, sorted by next dose time. Search/filter. Each row shows name, dosage, next dose, and inventory status.
3. **Add Medication Flow** — Multi-step: Name (with local autocomplete) then Dosage then Schedule then Optional details. Progressive disclosure — get to "done" in 3 steps, add details later.
4. **Dose Confirmation** — Large, prominent "Take" button with medication name and dosage. Swipe actions for snooze/skip. Haptic feedback on confirmation.
5. **Medication Detail** — Full detail view: schedule, inventory, interaction warnings, dose history, notes, photos. Edit capability.
6. **Vault Switcher** — List of vaults with profile icons. Quick switch without leaving context. "+ New Vault" action.
7. **Interaction Warnings** — Displayed inline on medication detail and proactively when adding a new med. Severity color-coded. Disclaimer always visible.
8. **Settings & Security** — Encryption status, master password change, recovery key, biometric unlock toggle, export data, about/legal.

**iPad (5 key screens):**

1. **Split View Dashboard** — Sidebar (vault list + medication list) + main content (today view or medication detail). NavigationSplitView.
2. **Multi-Column Schedule** — Full week view with all medications across time slots.
3. **Reporting Dashboard** — Adherence charts, inventory status, interaction summary.
4. **Vault Management** — Full sharing controls, member management, audit log.
5. **Data Import** — Drag-and-drop CSV import, photo capture, FHIR connection setup.

**Apple Watch (4 key views):**

1. **Complication** — Next dose: medication name + time. Circular gauge showing today's progress (4/6).
2. **Today List** — Scrollable list of today's doses with status (taken, upcoming, missed).
3. **Dose Confirmation** — Large tap target: "Take [Medication Name] [Dosage]?" with Confirm / Skip buttons. Haptic success feedback.
4. **Quick Glance** — Summary card: doses remaining today, any overdue doses, next dose time.

**Web App (6 key screens):**

1. **Dashboard** — Full-featured today view with sidebar navigation.
2. **Medication Management** — Add/edit/delete medications with full form fields.
3. **Reports & Export** — Adherence reports, PDF generation, CSV/JSON export.
4. **Vault & Sharing Management** — Create vaults, invite members, manage roles, revoke access.
5. **Account & Security** — Master password, recovery key, connected devices, encryption status.
6. **Drug Reference Browser** — Search and browse drug/supplement information.

**CLI (command structure):**

`
medtrack add <name>          # Interactive medication entry
medtrack list                # List all medications in active vault
medtrack dose [medication]   # Log a dose (interactive selection if no arg)
medtrack today               # Show today's schedule and status
medtrack export [format]     # Export vault data (json, csv, pdf)
medtrack vault list          # List vaults
medtrack vault switch <name> # Switch active vault
medtrack import <file>       # Import from CSV/JSON
medtrack status              # Encryption status, sync status, vault info
`

### 10.3 — Information Architecture

**Navigation model (iPhone):** Tab bar with 4 tabs: Today | Medications | Health (Phase 6+) | Settings. Vault switcher accessible via long-press on the app icon or a header button on any tab.

**Vault UX:** Vaults are presented as "profiles" to non-technical users. The word "vault" appears in settings/security contexts. In daily use, it's "Switch Profile" with the person/pet's name and avatar.

**Disclaimer integration:** Interaction warnings use a collapsible card pattern — headline ("Moderate Interaction"), one-line summary, expandable detail with full disclaimer and source attribution. The disclaimer is always present but doesn't block the workflow.

**Onboarding flow (4 steps):**

1. Welcome screen explaining the privacy promise ("Your data is encrypted on your device. We can never see it.")
2. Master password creation with strength indicator + recovery key generation (printable PDF)
3. Create first vault ("My Meds" pre-filled)
4. Add first medication (guided flow)

---

## SECTION 11: COMPETITIVE ANALYSIS

| Competitor | Core Strengths | Privacy Model | Platforms | Monetization | Key Weakness |
|---|---|---|---|---|---|
| **Medisafe** | Feature-rich, caregiver features, large user base | `[Validation Required]` — collects and shares anonymized data with pharma partners; not zero-knowledge | iOS, Android, Web | Freemium + B2B pharma data licensing | **Privacy: monetizes user medication data** (anonymized but still shared); no encryption |
| **MyTherapy** | Good UX, health diary, simple tracking | `[Validation Required]` — standard cloud storage; likely server-readable | iOS, Android | Free (pharma-sponsored) | Pharma sponsorship model creates conflicts of interest; no E2E encryption |
| **Pill Reminder & Med Tracker** | Simple, lightweight | `[Validation Required]` — unclear privacy model | iOS | Ads + premium | Ad-supported model in a health context is questionable; limited features |
| **Dosecast** | Flexible scheduling, timezone support | `[Validation Required]` — local storage option available | iOS | Premium purchase | Limited sharing/caregiver features; aging UI; no supplement interaction data |
| **CareZone** | Medication list management, pharmacy integration | `[Validation Required]` — **CareZone was acquired and its medication features were discontinued** | iOS (limited) | Was free | **Effectively dead as a medication tracker** — demonstrates market risk |
| **Round Health** | Beautiful minimal UI, simple reminders | `[Validation Required]` — likely local-first | iOS | Free / Premium | Very simple — no interactions, no sharing, no supplement support |
| **Apple Health (native)** | Integrated with iOS, medications tracking in iOS 16+ | High (Apple's privacy model, on-device) | iOS only | Free (bundled) | Very basic medication tracking; no interaction checking, no scheduling, no sharing, no supplement focus, no Watch complications for meds |

### Differentiation Analysis

**2x2 Positioning Matrix:**

```text
                    High Feature Richness
                          |
         Medisafe *       |       * THIS PROJECT (goal)
                          |
   Low Privacy -----------+------------ High Privacy
                          |
         MyTherapy *      |       * Apple Health (native)
                          |
                    Low Feature Richness
```

**Core differentiators:**

1. **"True zero-knowledge encryption — we can never see your health data"** — No major competitor offers this. Medisafe monetizes data. MyTherapy is pharma-sponsored. This is a clear, marketable differentiator that resonates with privacy-conscious users.

2. **Data ownership and portability** — Full data export at any time in portable formats. No lock-in. Competitors either make export difficult or don't offer it.

3. **Multi-profile vault model** — Family members, dependents, and pets with encrypted sharing is entirely unique. No competitor offers encrypted multi-profile with role-based access.

4. **Multi-platform coverage** — iOS + iPad + Watch + Web + CLI covers use cases competitors miss. CLI is unique in this market.

5. **Open-source encryption layer** — Auditable trust that closed-source competitors cannot match. "Don't trust us — verify."

**Why this wins now:**

1. **Post-2024 privacy awareness** — Users increasingly distrust apps with their health data after high-profile FTC actions against health data sharing (Flo Health, BetterHelp, GoodRx consent orders)
2. **Medisafe's pharma data model** is a recognized liability — privacy-conscious users actively seek alternatives `[Validation Required]`
3. **Apple Health validated the market** with iOS 16+ medication tracking, but it's too basic — users want more features with the same privacy ethos
4. **The "1Password for health data" positioning** is intuitive and immediately communicable
5. **No current app** combines medication tracking + supplement tracking + interaction checking + vaccination tracking + encrypted sharing in one product

---

## SECTION 12: MONETIZATION STRATEGY

### 12.1 — Open Source vs. Closed Source

| Model | Pros | Cons | Recommendation |
|---|---|---|---|
| Fully open source | Maximum trust; community contributions; security audits | Revenue challenge; competitors fork freely | Not recommended for full product |
| **Open core** | Trust where it matters (crypto layer); protectable app IP; community audits crypto | Dual licensing complexity | **Recommended** |
| Source-available | Transparency without forking risk | Community may not contribute; license confusion | Acceptable alternative |
| Closed source | Full IP control | Less trust; harder to prove privacy claims | Undermines the zero-knowledge story |

**Recommendation: Open Core.** Open-source the encryption/vault protocol library (MIT license). Keep the application code (iOS app, web app, backend) as proprietary source-available (visible on GitHub, not OSS-licensed). This lets anyone audit the crypto (building trust), while protecting the product investment.

### 12.2 — Revenue Model: Freemium Subscription

**Recommendation: Freemium with annual subscription for cloud features.**

| Tier | Price | Features |
|---|---|---|
| **Free** | $0 | Single vault, unlimited medications, local-only storage, local notifications, drug reference data, interaction checking, full data export |
| **Premium** | $2.99/month or $24.99/year | Unlimited vaults, encrypted cloud sync, multi-device support, vault sharing, priority drug data updates, Apple Watch complications, widgets |
| **Family** | $4.99/month or $39.99/year | Premium for up to 6 family members (shared subscription, individual encrypted accounts) |

**Why this works:**

- **Free tier is genuinely useful** — a single-device medication tracker with interaction checking. This is not a crippled demo.
- **Paid tier adds sync and sharing** — the features that cost money to operate (server, storage)
- **Aligns with zero-knowledge philosophy** — payment is for infrastructure, not data access
- **Sustainable for solo developer** — 1,000 premium subscribers = ~$25K ARR, covering infrastructure and development time
- **No perverse incentives** — the free tier doesn't push users toward data-compromising features

### 12.3 — Pricing Evolution

- **Phase 1 (MVP):** Entirely free. No payment infrastructure. Build the user base.
- **Phase 2 (Cloud Sync):** Introduce Premium tier. Cloud sync is the natural monetization trigger.
- **Phase 5 (Vaults & Sharing):** Introduce Family tier.
- **Consider:** GitHub Sponsors / Open Collective for the open-source crypto library — supplemental revenue from the developer community.

---

## SECTION 13: PHASED ROADMAP WITH MILESTONES

### Phase 0: Architecture & Cryptographic Foundation

**Duration:** 4-6 weeks | **Theme:** "Build the vault before the house"

**Goal:** Establish the project infrastructure, encryption layer, data model, and development environment. No user-facing features — but the crypto foundation makes everything else possible.

**Deliverables:**

- Monorepo setup (Swift Package Manager + pnpm workspaces)
- E2E encryption library: key derivation (Argon2id), vault key management, item encryption/decryption (AES-256-GCM), using libsodium
- SQLCipher integration for on-device encrypted storage
- SRP-6a authentication protocol implementation (for Phase 2, but design now)
- Data model implementation (Vault, Medication, Schedule, DoseLog entities)
- CI/CD pipeline (GitHub Actions: Xcode builds, linting, tests)
- Design system foundation (SwiftUI tokens, color palette, typography)
- Drug data ETL: first build of local drug index from openFDA + RxNorm

**Technical spikes (must succeed):**

1. Encrypt, store, retrieve, decrypt roundtrip with SQLCipher on iOS (target: < 10ms per item)
2. Local notification scheduling with 20+ notifications (verify iOS limits and behavior)
3. Drug index: build SQLite FTS5 index from openFDA bulk data, measure size (target: < 150MB) and search latency (target: < 50ms)
4. SwiftUI + VoiceOver: verify Dynamic Type and VoiceOver work with custom components

**Cut line:** Design system polish can be minimal; focus on architecture correctness.

**Launch gate:** All encryption tests pass. Drug index builds successfully. CI/CD pipeline runs.

**Acceptance criteria (top 3):**

1. Unit tests prove encrypt-then-decrypt roundtrip preserves data integrity for all entity types
2. Local drug index returns correct results for 10 test queries in < 50ms each
3. CI/CD builds the iOS app and runs tests on every push

---

### Phase 1: Core MVP (iOS)

**Duration:** 8-10 weeks | **Theme:** "Track and remember"

**Goal:** A user can add medications, set schedules, receive local notifications, and confirm doses — all encrypted on-device. Ship to TestFlight.

**Deliverables:**

- Add/edit/delete medications (with local drug autocomplete)
- Schedule configuration (daily, multi-daily, every N days, specific days, PRN)
- Local notification scheduling and delivery
- Dose confirmation flow (taken / snooze / skip)
- Today view with upcoming and completed doses
- Medication list with search
- Onboarding: master password creation, recovery key, first vault, first medication
- Biometric unlock (Face ID / Touch ID)
- Dark mode
- Baseline accessibility (Dynamic Type, VoiceOver, minimum 44pt tap targets)

**Dependencies:** Phase 0 complete (encryption layer, data model, drug index).

**Risks:**

- iOS local notification limits (64 pending) may be insufficient for users with 10+ medications at multiple daily doses. **Mitigation:** Implement a notification rotation strategy — schedule the next 64 most urgent notifications, refresh on app open.
- Drug autocomplete index may be too large for app bundle. **Mitigation:** Ship core index (~30MB compressed) with app, download full index on first launch.

**Cut line:** PRN scheduling and cycling schedules can slip to Phase 3. Photo capture can wait.

**Launch gate:** 10 beta testers on TestFlight for 2 weeks with no critical bugs.

**Acceptance criteria (top 3):**

1. A user can add a medication, set a twice-daily schedule, and receive notifications at the correct times for 7 consecutive days
2. Dose confirmation persists correctly across app restarts (encrypted storage verified)
3. VoiceOver can navigate the entire add-medication and dose-confirmation flow without sighted assistance

---

### Phase 2: Encrypted Cloud Sync

**Duration:** 6-8 weeks | **Theme:** "Your data, everywhere"

**Goal:** Multi-device sync with zero-knowledge encryption. The server stores only encrypted blobs and can never read user data.

**Deliverables:**

- Backend API (Hono on Cloudflare Workers) with encrypted blob storage (D1 + R2)
- SRP-6a authentication (zero-knowledge login)
- Vault sync protocol: upload/download encrypted items with version tracking
- Conflict resolution (LWW at item level with client-side merge UI)
- Account recovery: recovery key restores access on a new device
- Sync status indicator in the app ("Last synced: 2 minutes ago")
- Premium subscription infrastructure (StoreKit 2 + server validation)

**Dependencies:** Phase 0 encryption layer. Phase 1 core app.

**Risks:**

- Sync conflict edge cases with encrypted data are hard to test. **Mitigation:** Extensive integration tests with simulated multi-device scenarios.
- Cloudflare D1 is relatively new. **Mitigation:** D1 is production-ready for this scale [Validated]; fallback to Turso or PlanetScale if issues arise.

**Cut line:** Conflict merge UI can be simplified to "latest wins" with notification of overwritten changes.

**Launch gate:** Sync works reliably between two iOS devices for 1 week. No data loss in testing. App Store submission.

**Acceptance criteria (top 3):**

1. A medication added on Device A appears on Device B within 60 seconds, correctly decrypted
2. If the server database is dumped, no plaintext health data is recoverable
3. Account recovery with recovery key on a new device restores all vault data

---

### Phase 3: Data Enrichment

**Duration:** 6-8 weeks | **Theme:** "Know your meds"

**Goal:** Drug reference data, interaction checking, vaccination tracking, and export capabilities.

**Deliverables:**

- Drug reference display: side effects, contraindications, storage, food interactions (from openFDA/DailyMed)
- On-device drug-drug and drug-supplement interaction checking with severity classification
- Contextual disclaimers on all interaction warnings ("Informational only. Consult your provider.")
- Vaccination tracker: add/edit vaccination records, display CDC schedules as reference
- PDF export ("Doctor Mode") — generate medication list on-device
- JSON/CSV export via iOS share sheet
- Apple Health medication import
- Generic-to-brand name mapping (RxNorm)

**Dependencies:** Phase 1 core app. Drug index from Phase 0.

**Risks:**

- Interaction data quality from free sources may be incomplete. **Mitigation:** Start with major interactions only; curate a quality-reviewed subset; plan DrugBank licensing inquiry.
- Legal review of interaction warnings may delay launch. **Mitigation:** Start legal inquiry in Phase 1; have disclaimer language reviewed before Phase 3 begins. `[Validation Required]`

**Cut line:** Vaccination tracker can slip to Phase 5. Supplement interaction data (beyond basic) can defer pending database licensing.

**Launch gate:** Legal review of interaction warning presentation is complete. 100+ interaction rules verified against DrugBank or Lexicomp reference.

---

### Phase 4: Multi-Platform Expansion

**Duration:** 10-12 weeks | **Theme:** "Every device, every context"

**Goal:** Ship web app, CLI tool, Watch app, and iPad-optimized experience.

**Deliverables:**

- **Web app:** Next.js dashboard with WebCrypto-based encryption, medication management, reports, vault management
- **CLI tool:** medtrack CLI with full CRUD, import/export, and vault management
- **watchOS app:** Complications, today's schedule, dose confirmation with haptics
- **iPad app:** Multi-column layout, enhanced reporting dashboard
- iOS widgets (Home Screen + Lock Screen) showing next dose
- Siri Shortcuts for voice dose logging

**Dependencies:** Phase 2 sync infrastructure (web and CLI need cloud sync). Phase 1 iOS core.

**Risks:**

- WebCrypto API limitations (no Argon2id native — requires WASM). **Mitigation:** Use argon2-browser WASM package. [Validated]
- Watch app complexity with limited watchOS APIs. **Mitigation:** Keep Watch app simple — complications + dose confirmation only; no full medication management on Watch.

**Cut line:** CLI tool can be minimal (list + dose + export). Siri Shortcuts can defer.

**Launch gate:** All platforms can sync and decrypt the same vault. Cross-platform encryption parity verified with shared test vectors.

---

### Phase 5: Vaults & Sharing

**Duration:** 6-8 weeks | **Theme:** "Care for everyone"

**Goal:** Multi-profile vaults (family, dependents, pets) with encrypted sharing.

**Deliverables:**

- Create/manage multiple vaults with profile types (Personal, Dependent, Pet)
- Vault sharing: invite members, assign roles (Owner/Editor/Viewer)
- Vault re-keying on member revocation
- Emergency access (time-delayed break-glass)
- Child-to-adult vault ownership transfer
- Pet vault UX (veterinary context, monthly preventative scheduling)
- Encrypted audit log per vault
- Family subscription tier

**Dependencies:** Phase 2 sync. Phase 0 vault architecture.

**Cut line:** Emergency access and child-to-adult transfer can defer to Phase 6. Pet-specific drug databases (manual entry only at first).

**Launch gate:** Vault sharing works between two users with correct role enforcement. Re-keying tested with vaults containing 100+ items.

---

### Phase 6: Intelligence Layer

**Duration:** 8-10 weeks | **Theme:** "Insights from your data"

**Goal:** Adherence analytics, inventory tracking, timezone handling, and health data integration.

**Deliverables:**

- Adherence scoring and streak tracking
- Inventory management (supply tracking, auto-decrement, low-supply alerts, refill logging)
- Timezone-aware scheduling (body clock vs. local time)
- Drug recall alerts (server pushes public recall data, client matches locally)
- Apple Health read integration (HR, HRV, sleep, SpO2, BP, glucose)
- Caregiver escalation alerts (missed dose notifies shared vault members)
- Medication tapering tracker (user-entered schedules, 🔴 legal review required)

**Dependencies:** Phase 3 (data enrichment), Phase 5 (vaults for caregiver alerts).

**Cut line:** Tapering tracker defers if legal review is incomplete. Health signal read can defer to Phase 7.

**Launch gate:** Adherence scoring matches manual calculation for 5 test scenarios. Inventory auto-decrement works for 30-day test period.

---

### Phase 7: Moonshots

**Duration:** 12+ weeks | **Theme:** "Intelligence on your device"

**Goal:** Health signal correlation, performance analysis — all on-device.

**Deliverables:**

- Health signal impact analysis (correlate meds/supplements with HealthKit trends)
- On-device statistical analysis (rolling averages, before/after comparisons)
- Performance signal dashboards
- Self-reported mood/energy tracking
- Exportable health insight reports (PDF)

**Dependencies:** Phase 6 (Apple Health integration, adherence data). Legal review of CDS classification.

**Launch gate:** FDA CDS legal review is complete and cleared. `[Validation Required]`

---

### Phase 8: Scale & Polish

**Duration:** 8-10 weeks | **Theme:** "Production-grade"

**Goal:** Performance optimization, accessibility audit, localization, security audit.

**Deliverables:**

- Independent third-party security audit of the encryption layer
- Formal accessibility audit (WCAG 2.1 AA compliance)
- Localization (Spanish, French, German as first wave)
- Performance optimization (app launch time < 1s, sync < 5s)
- App Store Optimization (screenshots, descriptions, keywords)
- Self-hosted sync server Docker image (for power users)

**Launch gate:** Security audit report with no critical findings. Accessibility audit passes.

---

## SECTION 14: FIRST 90 DAYS — EXECUTION PLAN

### 14.1 — Technical Spikes (Weeks 1-3)

| # | Spike | Success Criteria | Effort | Risk if Fails |
|---|---|---|---|---|
| 1 | **E2E encryption roundtrip** | Encrypt a Medication entity with libsodium (swift-sodium), store in SQLCipher, retrieve and decrypt. < 10ms per operation. | S | Architecture is blocked — must succeed |
| 2 | **Local notification stress test** | Schedule 64 notifications for 10 medications with 3 daily doses. Verify delivery accuracy over 48 hours on a physical device. | S | Notification rotation strategy required if limits are hit |
| 3 | **Drug index build** | ETL openFDA NDC + DailyMed + RxNorm into SQLite FTS5 index. Measure: final size (target < 150MB), search latency (target < 50ms for autocomplete). | M | If index is too large, implement tiered loading (core drugs bundled, full index downloaded) |
| 4 | **SRP-6a proof of concept** | Implement SRP-6a handshake between a Swift client and TypeScript server. Verify zero-knowledge property (server never sees password). | M | If SRP proves too complex, fall back to standard password auth with server-side Argon2 — but this weakens the zero-knowledge story |
| 5 | **SwiftUI accessibility audit** | Build a prototype medication list + dose confirmation screen with Dynamic Type (xxxLarge) and VoiceOver. Verify all interactive elements are accessible. | S | UI architecture may need adjustment for accessibility |

### 14.2 — First 10 Epics

| # | Epic | Acceptance Criteria | Effort | Dependencies | Risk |
|---|---|---|---|---|---|
| 1 | **Project bootstrap & CI/CD** | Monorepo created, Xcode project builds, GitHub Actions runs tests on push, Fastlane configured for TestFlight | M | None | Low |
| 2 | **Encryption library** | libsodium integrated; Vault create/unlock, item encrypt/decrypt functions pass unit tests with test vectors | L | None | Medium — crypto code must be correct |
| 3 | **SQLCipher data layer** | Encrypted local database stores and retrieves Medication, Schedule, DoseLog entities; migration framework in place | M | Epic 2 | Low |
| 4 | **Drug index pipeline** | Python ETL produces SQLite FTS5 index from openFDA + RxNorm; index is < 150MB; search returns results in < 50ms | M | None (parallel) | Medium |
| 5 | **Medication CRUD** | Add, edit, delete medications with name autocomplete from local index; data persists encrypted across app restarts | L | Epics 2, 3, 4 | Low |
| 6 | **Schedule engine** | Create schedules (daily, multi-daily, every-N-days, specific days); engine correctly computes next N dose times | M | Epic 3 | Low |
| 7 | **Local notifications** | Schedule engine triggers iOS local notifications at correct times; notification actions (Taken, Snooze, Skip) update dose log | L | Epics 5, 6 | Medium — iOS notification edge cases |
| 8 | **Today view + dose confirmation** | Today screen shows upcoming/completed doses; tap to confirm; state persists; VoiceOver accessible | L | Epics 5, 6, 7 | Low |
| 9 | **Onboarding flow** | Master password creation with strength meter, recovery key generation (PDF), first vault creation, first medication entry | M | Epics 2, 5 | Low |
| 10 | **Design system + dark mode** | Color tokens, typography scale, component library (buttons, cards, forms); dark mode support; Dynamic Type up to xxxLarge | M | None (parallel) | Low |

### 14.3 — Due Diligence Backlog (Parallel with Development)

| # | Task | Owner | Deadline | Status |
|---|---|---|---|---|
| 1 | DrugBank licensing inquiry — email sales, get pricing for indie developer | Developer | Week 4 | Open |
| 2 | Natural Medicines Database licensing inquiry | Developer | Week 4 | Open |
| 3 | Legal review of interaction warning disclaimer language | Legal counsel | Week 8 (before Phase 3) | Open |
| 4 | Apple App Store health app guidelines review — document requirements | Developer | Week 2 | Open |
| 5 | State immunization registry (IIS) API availability — research top 10 states | Developer | Week 6 | Open |
| 6 | COPPA analysis for child vault profiles — consult attorney | Legal counsel | Week 10 (before Phase 5) | Open |
| 7 | FDA CDS classification analysis — is interaction checking CDS? | Legal counsel | Week 8 (before Phase 3) | Open |
| 8 | Washington My Health My Data Act compliance review | Legal counsel | Week 6 | Open |
| 9 | Competitor privacy policy audit — verify Medisafe, MyTherapy data practices | Developer | Week 3 | Open |
| 10 | Security researcher outreach — identify candidates for Phase 8 crypto audit | Developer | Week 12 | Open |

### 14.4 — Architecture Decision Records (ADRs)

| ADR | Title | Decision Scope | Decide By |
|---|---|---|---|
| ADR-001 | **Encryption Architecture** | Key hierarchy (master to vault to item), primitives (AES-256-GCM, X25519, Argon2id), libsodium as library, key storage per platform | Week 2 |
| ADR-002 | **MVP Platform Choice** | iOS-first with native SwiftUI. Justification: HealthKit, Keychain, Watch integration, App Store distribution. | Week 1 |
| ADR-003 | **Notification Architecture** | Local notifications only for MVP. Opaque server timers for Phase 2+ if needed. No email/SMS. | Week 3 |
| ADR-004 | **Data Sync Protocol** | Item-level encrypted blob sync with LWW conflict resolution. Server stores opaque blobs + version counters. | Week 4 |
| ADR-005 | **Open Source Strategy** | Open core: MIT-licensed encryption/vault protocol library; proprietary application code (source-available). | Week 6 |

---

## SECTION 15: DEPENDENCY MAP

### Critical Path

`
Phase 0: Encryption Library --> Phase 1: Core MVP --> Phase 2: Cloud Sync --> Phase 3+
         Drug Index ---------> Phase 1 (autocomplete)
         Data Model ---------> Phase 1 (storage)
`

**The encryption library is the #1 critical path item.** Nearly every feature depends on it.

### Feature Dependencies

| Feature | Depends On | Can Proceed With Local-Only? | Requires Full Sync? |
|---|---|---|---|
| Medication CRUD | Encryption library, data model | Yes | No |
| Local notifications | Schedule engine, data model | Yes | No |
| Dose logging | Medication CRUD, notifications | Yes | No |
| Drug autocomplete | Drug index (Phase 0) | Yes | No |
| Multi-device sync | Encryption library, backend API, SRP auth | No | Yes |
| Interaction checking | Drug index, interaction database | Yes | No |
| Vault sharing | Sync infrastructure, X25519 key exchange | No | Yes |
| Multi-profile vaults | Vault key architecture (Phase 0 design) | Yes (local vaults) | For sharing |
| Apple Health integration | iOS HealthKit, encryption library | Yes | No |
| Web app | Sync infrastructure, WebCrypto encryption | No | Yes |
| CLI tool | Encryption library (JS), sync infrastructure | Partial (local mode) | For sync |
| Watch app | iOS companion app, shared Swift package | Yes (companion) | No |
| Health signal analysis | Apple Health integration, adherence data, legal review | Yes | No |

### Platform Dependencies

`
SharedKit (Swift Package: data model, crypto, schedule engine)
    +-- iOS App (depends on SharedKit)
    +-- iPad App (depends on SharedKit)
    +-- Watch App (depends on SharedKit)
    (No dependency on web/CLI — those use JS crypto)

Crypto Protocol Spec (documentation + test vectors)
    +-- swift-sodium implementation (SharedKit)
    +-- libsodium.js implementation (web + CLI)
    +-- Cross-platform test vectors (verify parity)
`

### Parallelization Opportunities

- **Phase 0:** Drug index ETL and encryption library can be built in parallel
- **Phase 1:** Design system and onboarding UX can be built in parallel with core data layer
- **Phase 4:** Web app and Watch app can be built in parallel (different tech stacks, no dependencies on each other)
- **Due diligence tasks** (Section 14.3) run in parallel with all development phases

---

## SECTION 16: FEASIBILITY & COMPROMISE MATRIX

| Challenge | Ideal Solution | Compromise if Ideal Fails | Privacy Impact of Compromise | Recommendation |
|---|---|---|---|---|
| **Notifications under E2E** | Local notifications only (iOS UNUserNotificationCenter) | Opaque server timers (fire every 15 min, client checks if dose is due) | Timing pattern visible to operator — reveals that the user has medications scheduled | **Start with local only.** Compromise only if iOS 64-notification limit proves insufficient for power users with 15+ meds. |
| **Drug autocomplete without leaking queries** | Bundled local SQLite FTS5 index (~80-120MB) | k-anonymity batch queries (send query prefix + 99 random prefixes) | Partial query exposure — server sees the query mixed with noise | **Bundled local index.** The size cost is acceptable for modern devices. |
| **Cross-platform crypto parity** | Shared Rust library compiled to native (Swift FFI) + WASM (web) + napi (CLI) | Per-platform libsodium bindings (swift-sodium, libsodium.js, sodium-native) | No privacy impact — risk is implementation divergence causing bugs | **Per-platform libsodium.** Shared Rust adds build complexity a solo dev cannot maintain. Mitigate divergence risk with shared test vectors. |
| **OCR on web/CLI** | On-device OCR for all platforms | OCR available on iOS/iPad only (Apple Vision); not available on web/CLI | None (feature absent on web/CLI) | **iOS/iPad only.** Do not implement cloud OCR — it breaks zero-knowledge. Web/CLI users import via CSV/JSON. |
| **Vault sharing revocation** | Re-key entire vault (new VK, re-encrypt all items) | Revoke forward access only (change VK for new items, old items remain accessible to revoked user with old key) | **High** — revoked user retains access to historical data | **Full re-key.** The privacy cost of the compromise is unacceptable. Performance cost of re-keying is manageable (lazy re-encryption). |
| **On-device health correlation** | Core ML model for trend detection | Simple rolling average comparison (no ML) | None (both are on-device) | **Simple statistics first.** Core ML adds complexity without proportional user value in early phases. |

---

## SECTION 17: OPEN QUESTIONS & DECISION LOG

| # | Decision | Options | Recommendation | Status |
|---|---|---|---|---|
| 1 | Native vs. cross-platform iOS | SwiftUI / React Native / Flutter | **SwiftUI** — best HealthKit, Keychain, Watch, widget integration | Decided (ADR-002) |
| 2 | Notification architecture | Local-only / Opaque timers / Encrypted push | **Local-only for MVP**, opaque timers for Phase 2+ if needed | Decided (ADR-003) |
| 3 | Open source strategy | Fully open / Open core / Source-available / Closed | **Open core** — MIT crypto library, proprietary app | Decided (ADR-005) |
| 4 | Self-hosted sync option | Yes / No / Later | **Later (Phase 8)** — Docker image for power users after managed service is stable | Decided |
| 5 | Key recovery mechanism | Recovery key / iCloud Keychain / Social recovery | **Printed recovery key** (1Password Emergency Kit model) + optional iCloud Keychain backup for device unlock key | Decided (ADR-001) |
| 6 | Monetization model | Freemium / Subscription / Donations / Hybrid | **Freemium subscription** — free local-only tier, paid sync + multi-vault | Decided |
| 7 | Vault sharing key management | Asymmetric wrapping / Key escrow / Link-based | **Asymmetric wrapping** (X25519) — vault key encrypted to recipient's public key | Decided (ADR-001) |
| 8 | Drug autocomplete privacy | Local index / k-anonymity / Accept leakage | **Local bundled index** — no server queries | Decided |
| 9 | Cross-platform crypto library | Shared Rust/WASM / Per-platform native | **Per-platform libsodium** with shared test vectors | Decided |
| 10 | Doctor/temporary access model | Export PDF / Time-limited link / QR code | **On-device PDF export** ("Doctor Mode") — zero server involvement | Decided |
| 11 | Interaction warning CDS classification | Ship with disclaimers / Wait for legal review / Don't ship | **Ship after legal review** — schedule review during Phase 2, resolve before Phase 3 ships | Open `[Validation Required]` |
| 12 | COPPA applicability for child vaults | Full COPPA compliance / Argue exemption / Age-gate children out | **Consult attorney** — encrypted child data on a zero-knowledge server is a novel COPPA question | Open `[Validation Required]` |
| 13 | Supplement interaction data source | NIH ODS (free, limited) / Natural Medicines DB (paid, comprehensive) / Manual curation | **Start with manual curation of top 50 supplement interactions from public sources**, plan licensing inquiry for comprehensive data | Decided for MVP, revisit post-revenue |

---

## SECTION 18: FAILURE MODE ANALYSIS

| # | Failure Mode | Likelihood | Impact | Mitigation Already in Plan? | Additional Mitigation |
|---|---|---|---|---|---|
| 1 | **E2E encryption complexity delays MVP by 3+ months** | Medium (35%) | Critical — blocks all features | Phase 0 spikes de-risk crypto early; libsodium is battle-tested | Hire a contract cryptographer for 2 weeks if stuck on key hierarchy implementation. Keep MVP local-only to avoid sync complexity. |
| 2 | **Drug/supplement data sources are too expensive or unavailable** | Medium (30%) | High — interaction checking is a key differentiator | MVP uses free sources (openFDA, RxNorm); licensing inquiry starts in parallel | Ship MVP without interaction checking if databases are unavailable. Curate a small, high-quality interaction set manually from public literature. Revisit licensing post-revenue. |
| 3 | **No user acquisition — privacy positioning is too niche** | Medium (40%) | Critical — no users means no product | Content marketing, ASO, Reddit/HN targeting in plan | Validate positioning with a landing page and waitlist before MVP ships. If privacy messaging doesn't resonate, pivot messaging to "the most complete medication tracker" with privacy as a secondary differentiator. |
| 4 | **Regulatory challenge blocks key features** | Low (15%) | High — interaction checking or health correlation features could be blocked | Legal review gates in roadmap; disclaimers on all features; non-goals exclude dosing recommendations | If interaction checking is classified as CDS, redesign as "drug information lookup" (user searches for interactions manually) rather than proactive warnings. Removes CDS trigger while preserving user value. |
| 5 | **Solo developer burnout — 18-month roadmap is too ambitious** | High (50%) | Critical — project stalls | Phased approach with clear milestones and cut lines | Ruthlessly cut scope. Phase 1 MVP is a viable product on its own. Phases 7-8 are aspirational — the product is useful without moonshots. Consider open-sourcing earlier to attract contributors. Take breaks. Ship Phase 1 and celebrate before starting Phase 2. |

---

*This roadmap was generated based on the assumptions in Section 0. As assumptions are validated or invalidated, revisit the affected sections. The first 90 days (Section 14) are immediately actionable. Start with the technical spikes — they will confirm or challenge the architectural decisions within 3 weeks.*
