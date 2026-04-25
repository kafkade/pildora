# Apple Developer Program Setup

This document covers the enrollment process and configuration for publishing
Pildora on the Apple App Store.

## Developer Identity

- **Developer name:** kafkade
- **Website:** kafkade.com
- **Bundle identifier:** `com.kafkade.pildora`
- **App Store category:** Health & Fitness (not Medical — avoids clinical
  implications)

## Enrollment Type Decision

| Factor | Individual | Organization |
|---|---|---|
| Setup complexity | Simple | Requires D-U-N-S number + legal entity |
| App Store seller name | Your legal name | "Kafkade" (or LLC name) |
| Cost | $99/year | $99/year |
| Time to approve | 24-48 hours | 1-2 weeks (D-U-N-S verification) |
| Recommended when | Starting out, solo dev | When you have an LLC |

**Recommendation:** Start with **Individual** enrollment. Transition to
Organization later if you form Kafkade LLC. The app branding ("Pildora by
kafkade") is independent of the seller name.

## Enrollment Steps

### Prerequisites

1. An Apple ID (create at [appleid.apple.com](https://appleid.apple.com) if
   needed)
2. An iPhone or iPad with the
   [Apple Developer](https://apps.apple.com/app/apple-developer/id640199958)
   app installed
3. Government-issued photo ID
4. A payment method for the $99/year fee

### Process

1. Go to [developer.apple.com/enroll](https://developer.apple.com/enroll)
2. Sign in with your Apple ID
3. Select **Individual** enrollment type
4. Complete identity verification:
   - Open the Apple Developer app on your iPhone/iPad
   - Follow the prompts to scan your government ID
   - Complete the facial recognition step
5. Review and accept the Apple Developer Agreement
6. Pay $99/year (annual auto-renewal)
7. Wait for approval (typically 24-48 hours for Individual)

### Post-Enrollment Setup

1. **App Store Connect:** Access at
   [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. **Register App ID:**
   - Go to Certificates, Identifiers & Profiles
   - Create an App ID with bundle identifier `com.kafkade.pildora`
   - Enable capabilities: HealthKit, Push Notifications, App Groups
3. **Generate certificates:**
   - Development certificate (for building to device)
   - Distribution certificate (for TestFlight and App Store)
4. **Create provisioning profiles:**
   - Development profile (linked to your devices)
   - Distribution profile (for TestFlight)
5. **App Store Connect API key:**
   - Generate for Fastlane CI/CD automation
   - Store the `.p8` key file and Key ID securely

## Credential Storage

All credentials go in **1Password**:

| Credential | 1Password Item Type |
|---|---|
| Apple ID (email + password) | Login |
| Apple Developer certificates (.p12 + password) | Document + password field |
| App Store Connect API key (.p8 file) | Document |
| API Key ID + Issuer ID | Secure Note |
| Provisioning profile details | Secure Note |
| Team ID | Secure Note |

For CI/CD, credentials are referenced as **GitHub Actions secrets**:

| Secret Name | Source |
|---|---|
| `APPLE_API_KEY_ID` | App Store Connect API Key ID |
| `APPLE_API_ISSUER_ID` | App Store Connect Issuer ID |
| `APPLE_API_KEY_CONTENT` | Contents of the .p8 key file |
| `MATCH_PASSWORD` | Fastlane match encryption passphrase |

Store the actual values in 1Password and copy them to GitHub Secrets. The
1Password entries serve as the source of truth if secrets need to be rotated.

## Bundle Identifiers

| App | Bundle ID |
|---|---|
| iPhone / iPad | `com.kafkade.pildora` |
| Apple Watch | `com.kafkade.pildora.watchkitapp` |
| Widget Extension | `com.kafkade.pildora.widget` |
| Notification Extension | `com.kafkade.pildora.notification` |

## Fastlane Configuration

Fastlane will be configured in Phase 1 for automated builds and TestFlight
distribution. Key components:

- **match:** Certificate and profile management (encrypted Git storage)
- **gym:** Build automation
- **pilot:** TestFlight upload
- **deliver:** App Store submission (Phase 2+)

The match passphrase and Git repo for certificate storage should be set up
during Phase 1 CI/CD configuration.
