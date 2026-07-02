# PildoraNotificationScheduler

Production local-notification scheduling for dose reminders with actionable
responses — **issue #49** (Phase 1 / S13; promotes the `notification-spike`
strategy, issue #23).

## Status

🚧 Self-contained feature slice. Like the other iOS slices, this package is
pure-Foundation and dependency-free, and runs against an in-memory notification
center until shared wiring (schedule engine + persistence) lands. All logic is
testable with `swift test` on the macOS toolchain — no entitlements, app bundle,
or live `UNUserNotificationCenter` required.

Physical-device delivery testing remains blocked by Apple Developer enrollment
([#25](https://github.com/kafkade/pildora/issues/25)); the 48-hour stress test
here is a deterministic simulation of the rotation invariants that test will
ultimately confirm on-device.

## What it does

- **Rotation within the iOS 64-notification limit.** `NotificationPlanner` keeps
  the soonest doses pending (priority breaks ties / decides horizon drops), and
  `NotificationScheduler.replenish(candidates:)` applies them with a
  remove-all-then-add rotation so the 65th-notification silent drop can never
  occur. Replenish on launch, after medication CRUD, and after every action.
- **Actionable reminders.** Taken / Snooze / Skip notification actions, mapped to
  a `DoseActionResult` the app persists to the encrypted dose log. Snooze
  schedules a one-shot re-reminder (+10/15/30 min) that survives rotation.
- **Overdue handling.** `OverdueTracker` turns unresolved past doses into a badge
  count and a single summary notification (posted/cleared idempotently).
- **Rich content.** Medication name, dosage, and any special instructions, on a
  shared thread that mirrors to the Apple Watch automatically.
- **Permission handling.** `NotificationAuthorization` performs the onboarding
  prompt, prompting only when undetermined.

## Architecture

```text
DoseNotification (neutral input) ──► NotificationPlanner ──► NotificationPlan
        ▲                                                          │
        │ adapter                                                  ▼
  DoseOccurrenceLike                              NotificationScheduler (orchestrator)
  (schedule engine)                                     │        │        │
                                     DoseNotificationContentBuilder  OverdueTracker
                                                        │        │        │
                                                        ▼        ▼        ▼
                                            NotificationScheduling (seam)
                                             ├── SystemNotificationCenter (UNUserNotificationCenter)
                                             └── InMemoryNotificationCenter (tests/sim)
```

The only type that imports `UserNotifications` is `SystemNotificationCenter`;
everything else is platform-neutral and unit-tested against the in-memory center.

### Wiring to the schedule engine

The package does not depend on `PildoraScheduleEngine`. The app conforms the
engine's `DoseOccurrence` to `DoseOccurrenceLike` in one line and builds
notifications from it:

```swift
import PildoraScheduleEngine
import PildoraNotificationScheduler

extension DoseOccurrence: DoseOccurrenceLike {}

let doses = DoseNotification.from(
    occurrences: engine.nextDoses(count: 80),
    medicationName: med.name,
    dosage: med.dosage,
    instructions: med.instructions,
    priority: med.priority
)
try await scheduler.replenish(candidates: doses)
```

## Build & test

```sh
cd ios/notification-scheduler/PildoraNotificationScheduler
swift build
swift test
```

## Privacy / compliance notes

- **Zero-knowledge / local-first:** notifications are **local-only** — no server
  push. Content is computed on-device from local encrypted data; the server
  never learns when doses are scheduled or taken. Notification `userInfo`
  carries only opaque identifiers (`scheduleId`/`medicationId`/`vaultId`), never
  health data.
- **No medical advice:** reminders state what/how-much/when plus the user's own
  instructions verbatim; no dosing guidance or interpretation is added.
- **Multi-vault readiness:** `DoseNotification` carries `vaultId`.
