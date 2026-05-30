# Notification Spike — iOS 64 Limit and Rotation Strategy

**Issue:** [#23 — Local notification limits and rotation strategy](https://github.com/kafkade/pildora/issues/23)

**Status:** Strategy designed and algorithm validated. Device testing blocked by Apple Developer enrollment (#25).

## Spike Questions & Answers

### 1. 10 medications × 3 doses/day = 30 notifications/day — how many days ahead?

With the 64 pending notification limit (4 slots reserved for non-dose alerts):

| User Profile | Meds | Doses/Day | Days of Coverage |
|---|---|---|---|
| Light (Persona 1: Alex) | 5 | 6 | ~10 days |
| Moderate (Persona 2: Margaret) | 10 | 13 | ~4.6 days |
| Power (Persona 3: David) | 15 | 22 | ~2.7 days |

For the roadmap target of "10 medications × 3 daily doses = 30/day", coverage is **2 days** — replenishment must happen at least daily.

### 2. What happens when the 65th notification is scheduled?

The 65th notification is **silently dropped** — `UNUserNotificationCenter.add()` completes without error, but the notification is not persisted. Apple does not provide an error code for this.

**Mitigation:** Always call `getPendingNotificationRequests()` to check the current count before adding. The spike algorithm replaces all pending notifications on each replenishment cycle to maintain a clean slate.

### 3. How reliable is notification delivery over 48 hours?

Scheduled local notifications are **highly reliable** on iOS:

- They are persisted by the OS and survive device restarts
- They fire at the scheduled time even if the app is terminated
- Do Not Disturb silences them but they appear in Notification Center when DND ends
- Low Power Mode does not affect scheduled notification delivery

The risk is **notification exhaustion** — if the pending queue isn't replenished and all 60 scheduled notifications fire, there are no more to deliver. This is mitigated by the rotation strategy.

### 4. Best refresh strategy?

**Rolling window with priority-based scheduling**, replenished at 4 trigger points:

| Trigger | When | Reliability |
|---|---|---|
| **App foreground** | `applicationDidBecomeActive` | 100% (when user opens app) |
| **Notification action** | User taps Taken/Skip/Snooze | 100% (when user interacts) |
| **BGAppRefreshTask** | ~every 6 hours (system-managed) | ~80% (iOS may delay for battery) |
| **Medication CRUD** | After add/edit/delete | 100% (in-app action) |

For users who open the app daily, triggers 1 and 2 are sufficient. `BGAppRefreshTask` is the safety net for users who don't open the app for days.

## Rotation Algorithm

### Design

```text
replenish(medications, now):
  1. Remove ALL pending notifications
  2. For each medication, compute next N dose times
  3. Sort by: priority (critical > high > normal > low), then time (earliest first)
  4. Take the first 60 (64 limit minus 4 reserved slots)
  5. Schedule each with UNUserNotificationCenter
```

### Priority Tiers

| Tier | Description | Example |
|---|---|---|
| **Critical** | Life-sustaining medications | Insulin, immunosuppressants |
| **High** | Prescription medications | Statins, blood pressure meds |
| **Normal** | OTC medications | Aspirin, antacids |
| **Low** | Supplements/vitamins | Vitamin D, fish oil |

When space is limited, critical medications get scheduled further ahead than low-priority supplements. This ensures a power user never misses insulin because their vitamin D notification took the last slot.

### Reserved Slots

4 of the 64 slots are reserved for non-dose notifications:

- Low inventory alerts ("Only 3 pills of Metformin remaining")
- Refill reminders
- System alerts (encryption key rotation, app update)

## Edge Cases

### App not opened for days

- `BGAppRefreshTask` fires approximately every 6 hours (system-managed, not guaranteed)
- iOS deprioritizes background refresh for rarely-opened apps
- **Worst case:** Power user with 22 doses/day exhausts notifications after ~2.7 days without replenishment
- **Mitigation:** The initial replenishment schedules as far ahead as possible; even without `BGAppRefreshTask`, light users have 10+ days of coverage

### Device restart

Pending local notifications **survive device restarts**. No action needed.

### Do Not Disturb / Focus modes

Notifications are still scheduled and fire on time. They are delivered silently to Notification Center and become visible when DND/Focus ends. No action needed — the notification is not lost.

### Timezone change (travel)

`UNCalendarNotificationTrigger` fires based on the device's current timezone. If the user travels from EST to PST, an 8:00 AM dose notification fires at 8:00 AM PST. This is **correct behavior** — the user wants to take their medication at their local 8:00 AM.

### Daylight Saving Time

`UNCalendarNotificationTrigger` with `DateComponents` handles DST transitions correctly. A notification scheduled for 8:00 AM continues to fire at 8:00 AM after DST changes.

### 65th notification behavior

Silently dropped. The algorithm prevents this by always replacing the entire queue (remove all → schedule fresh set).

## Production Integration Pattern

### UNUserNotificationCenter usage

```swift
import UserNotifications

func replenishNotifications(medications: [MedicationSchedule]) async throws {
    let center = UNUserNotificationCenter.current()

    // 1. Remove all pending dose notifications
    let pending = await center.pendingNotificationRequests()
    let doseIds = pending
        .filter { $0.identifier.hasPrefix("dose-") }
        .map { $0.identifier }
    center.removePendingNotificationRequests(withIdentifiers: doseIds)

    // 2. Compute and sort future doses (see NotificationScheduler.swift)
    let scheduler = NotificationScheduler()
    let result = scheduler.replenish(medications: medications)

    // 3. Schedule each dose notification
    for dose in scheduler.pendingNotifications {
        let content = UNMutableNotificationContent()
        content.title = dose.medicationName
        content.body = "Time to take \(dose.medicationName)"
        content.categoryIdentifier = "DOSE_REMINDER"
        content.sound = .default

        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute],
            from: dose.scheduledAt
        )
        let trigger = UNCalendarNotificationTrigger(
            dateMatching: components,
            repeats: false  // One-shot — replenishment handles recurrence
        )

        let request = UNNotificationRequest(
            identifier: "dose-\(dose.notificationId)",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }
}
```

### Notification actions

```swift
// Register during app launch
let takenAction = UNNotificationAction(identifier: "TAKEN", title: "Taken ✓")
let skipAction = UNNotificationAction(identifier: "SKIP", title: "Skip")
let snoozeAction = UNNotificationAction(identifier: "SNOOZE", title: "Snooze 15m")
let category = UNNotificationCategory(
    identifier: "DOSE_REMINDER",
    actions: [takenAction, skipAction, snoozeAction],
    intentIdentifiers: []
)
UNUserNotificationCenter.current().setNotificationCategories([category])
```

### BGAppRefreshTask registration

```swift
// In application(_:didFinishLaunchingWithOptions:)
BGTaskScheduler.shared.register(
    forTaskWithIdentifier: "com.pildora.notification-refresh",
    using: nil
) { task in
    handleNotificationRefresh(task: task as! BGAppRefreshTask)
}

func scheduleBackgroundRefresh() {
    let request = BGAppRefreshTaskRequest(
        identifier: "com.pildora.notification-refresh"
    )
    request.earliestBeginDate = Date(timeIntervalSinceNow: 6 * 3600)
    try? BGTaskScheduler.shared.submit(request)
}

func handleNotificationRefresh(task: BGAppRefreshTask) {
    scheduleBackgroundRefresh()  // Schedule next refresh
    Task {
        let medications = loadMedicationSchedules()  // From SQLCipher DB
        try? await replenishNotifications(medications: medications)
        task.setTaskCompleted(success: true)
    }
}
```

## Privacy Considerations

This notification strategy preserves **zero-knowledge architecture**:

- ✅ All notifications are **local only** — no server involvement
- ✅ Notification content is computed **on-device** from local encrypted data
- ✅ No push notification service knows the user's medication schedule
- ✅ `BGAppRefreshTask` does not communicate with any server
- ✅ The server never knows when doses are scheduled or taken

## Running the Simulation

```bash
cd ios/notification-spike/PildoraNotificationSpike
swift run
```

This runs the rotation algorithm against 6 scenarios (light/moderate/power users, 48-hour simulation, degradation test, edge cases) and prints coverage analysis.

## Files

```text
ios/notification-spike/
  README.md                                              ← This file
  PildoraNotificationSpike/
    Package.swift                                        ← Swift Package
    Sources/
      main.swift                                         ← 6-scenario simulation
      DoseTimeCalculator.swift                           ← Dose time computation + priority
      NotificationScheduler.swift                        ← Rotation algorithm (platform-independent)
```

## Next Steps

1. **Device testing** (blocked by #25 Apple Developer enrollment): deploy to a physical iPhone and run a 48-hour notification delivery accuracy test
2. **Snooze implementation**: when user snoozes, schedule a one-shot notification for +N minutes (consumes 1 slot from the reserved pool temporarily)
3. **Watch mirroring**: validate that local notifications mirror to Apple Watch automatically (expected behavior for standard `UNNotificationRequest`)
