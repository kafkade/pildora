# ADR-003: Notification Architecture

**Status:** Accepted
**Date:** 2026-04-24

## Context

Dose reminders are a core feature. However, the zero-knowledge architecture
means the server cannot read medication schedules, so it cannot trigger
server-side push notifications at the right time. We need a notification
strategy that is reliable, timely, and compatible with zero-knowledge.

## Decision

**Local notifications only for MVP (and default for all phases).**

- iOS/iPadOS: `UNUserNotificationCenter` scheduled on-device
- watchOS: Mirrored from iPhone + haptic alerts
- CLI: OS-native notifications (macOS Notification Center, Linux notify-send)
- Web: Browser Notification API (requires browser open — unreliable)

No server-side push, no email reminders, no SMS reminders.

## Rationale

### Why local-only works

- iOS supports **64 pending local notifications**. For a user with 10
  medications × 3 times/day = 30 notifications/day, the system can schedule
  ~2 days ahead.
- The app refreshes the notification schedule each time it's opened (foreground
  or background app refresh).
- For 99%+ of users, 64 notifications is sufficient.

### Privacy analysis by channel

| Channel | Privacy Impact | Decision |
|---|---|---|
| Local notifications | Zero — entirely on-device | ✅ Use |
| watchOS haptic | Zero — mirrors iPhone locally | ✅ Use |
| APNs server push (opaque timers) | Timing patterns visible to Apple and server | ⏳ Defer to Phase 2+ as fallback only |
| Email reminders | Email, timing, and content visible to email provider | ❌ Do not implement |
| SMS reminders | Phone, timing, and content visible to carrier | ❌ Do not implement |

Email and SMS reminders **break zero-knowledge entirely** — a third party
(email provider, carrier) can see when the user takes medication and
potentially what they take. These will not be implemented.

### Fallback for the 64-notification limit

If a future user exceeds 64 scheduled notifications (unlikely but possible with
20+ medications at multiple daily times), the fallback is **opaque server
timers**: the client registers periodic wake-up signals with the server ("ping
me every 15 minutes") without revealing why. The client decrypts locally and
decides whether a dose is due. This preserves zero-knowledge at the cost of
battery and timing precision.

## Alternatives Considered

**Server-side push via APNs:** The server would need to know when to send
notifications, which means knowing the schedule, which breaks zero-knowledge.
The "opaque timer" variant avoids this but adds complexity and battery cost.
Deferred as a Phase 2+ fallback.

**Encrypted push payloads:** The server sends an encrypted payload that the
client decrypts to determine if a dose is due. Technically feasible but complex
to implement, and Apple's push notification system isn't designed for
high-frequency decryption-on-receive. Deferred.

## Consequences

- Users must open the app periodically (at least every ~2 days) for the
  notification schedule to refresh. Background app refresh helps.
- Power users with 20+ medications and complex schedules may hit the
  64-notification limit. This needs monitoring and the opaque timer fallback
  needs to be ready by Phase 2.
- No cross-device notification sync — each device schedules its own
  notifications based on its local copy of the schedule.
- Notification reliability depends on iOS not aggressively killing the app —
  this must be validated in Phase 0 technical spikes.
