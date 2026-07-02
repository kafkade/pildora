# iOS Local Notifications

Design reference for the local-notification scheduler implemented in
[`ios/notification-scheduler/PildoraNotificationScheduler`](../ios/notification-scheduler/PildoraNotificationScheduler/)
(issue #49, roadmap §14.2 Epic #7, §14.1 Spike #2). It schedules dose reminders
as **local** notifications with actionable Taken / Snooze / Skip responses,
rotating them within the iOS 64-notification limit.

It promotes the validated
[`notification-spike`](../ios/notification-spike/) (issue #23) into a shippable,
tested feature slice.

> This is a reminder/tracking tool. It reminds users *when* their own doses are
> due and provides **no** dosing recommendations or medical advice.

## Non-negotiable: local only

Dose reminders are delivered exclusively through iOS `UNUserNotificationCenter`
local notifications. **There is no server-side push** — a hard constraint of the
zero-knowledge architecture (ADR-003). The server never learns a user's dose
schedule, timing, or adherence. All notification content is computed on-device
from local encrypted data, and each notification's `userInfo` carries only
opaque identifiers (`scheduleId` / `medicationId` / `vaultId`), never health
data.

## Scope

The package is a **pure-Foundation, dependency-free** slice (matching
`schedule-engine` and `today-view`). The only type that touches
`UserNotifications` is `SystemNotificationCenter`; everything else is
platform-neutral and runs under plain `swift test` in CI (the
`iOS Packages (macOS)` job) against an in-memory notification center — no
entitlements, app bundle, or live system center needed.

## Components

| Type | Responsibility |
|---|---|
| `DoseNotification` | Neutral input model (ids, name, dosage, instructions, due instant, priority). |
| `DoseOccurrenceLike` + adapter | One-line conformance seam to the schedule engine's `DoseOccurrence`. |
| `NotificationBudget` | The 64-limit budget with reserved slots (default 60 dose slots, 4 reserved). |
| `NotificationPlanner` | Pure/deterministic selection of which doses become pending notifications. |
| `NotificationScheduling` | Protocol seam over the `UNUserNotificationCenter` subset. |
| `SystemNotificationCenter` | Production `UNUserNotificationCenter` bridge (`#if canImport(UserNotifications)`). |
| `InMemoryNotificationCenter` | Test/sim double that faithfully mimics the 64-limit silent drop. |
| `DoseNotificationContentBuilder` | Rich reminder + overdue-summary content. |
| `DoseNotificationCategories` | `DOSE_REMINDER` category with Taken / Snooze / Skip actions. |
| `OverdueTracker` | Missed-dose badge count + summary. |
| `NotificationAuthorization` | Onboarding permission request (prompts only when undetermined). |
| `NotificationScheduler` | Orchestrator: `replenish`, `apply`/`handle`, `refreshOverdue`, `requestAuthorization`. |

## Rotation strategy

iOS allows at most **64 pending** local notifications per app; the 65th is
silently dropped (no error). A power user (15+ meds × 3 doses/day = 45+/day)
can exceed this, so the queue is rotated:

```text
replenish(candidates, now):
  1. Remove all pending *dose* notifications (identifier prefix "dose-")
  2. Drop past/duplicate candidates
  3. Sort by soonest due time (priority breaks ties)
  4. Take the first 60 (64 limit − 4 reserved) and schedule them
```

Replenishment is triggered on app foreground, after every notification action,
after medication CRUD, and by a `BGAppRefreshTask` safety net (~every 6 hours).

### Time-first ordering (refinement over the spike)

The spike sorted **priority-first**, which can starve a near-term low-priority
dose behind far-future critical ones under heavy load. The production planner
sorts **soonest-first**, keeping the imminent doses always pending so continuous
replenishment delivers everything within the coverage horizon on time. Priority
is retained as a tiebreaker for doses at the same instant and to decide which
doses are dropped at the **horizon boundary** (the furthest-out ones) — the
correct place to prefer a critical medication over a vitamin. The stress test
asserts the invariant that the soonest undelivered dose is always pending.

### Reserved slots and snooze

Four slots are reserved for non-dose notifications (low-inventory alerts, refill
reminders, one-shot snoozes, system alerts). A **snooze** schedules a one-shot
re-reminder (`snooze-` prefix) at `now + 10/15/30 min`; because it does not carry
the `dose-` prefix, it survives the remove-all-then-add rotation.

## Actions

The `DOSE_REMINDER` category registers three actions:

| Action | Effect |
|---|---|
| **Taken** | Returns a `DoseActionResult` the app logs as `taken`; clears the reminder. |
| **Skip** | Returns a `DoseActionResult` the app logs as `skipped`; clears the reminder. |
| **Snooze** | Schedules a one-shot re-reminder and returns the snoozed-until instant. |

The app resolves the tapped notification's `DoseNotification` from its store
(via the identifiers in `userInfo`) and calls
`handle(action:for:candidates:)`, which applies the action and immediately
replenishes so a freed slot is backfilled. This package deliberately does **not**
own the encrypted dose log — it returns the outcome for the app to persist.

## Overdue doses

On launch/foreground the app passes the doses that are past-due and still
unresolved to `refreshOverdue(unresolvedDoses:)`. After a grace period
(30 min, matching the Today view), each becomes a missed dose: the app-icon
badge is set to the missed count and a single summary notification is posted.
When nothing remains overdue, both the badge and summary are cleared.

## Timezone travel & DST

`SystemNotificationCenter` schedules with a non-repeating
`UNCalendarNotificationTrigger` on year/month/day/hour/minute components, which
fires in the device's **current** timezone. An 8:00 AM dose fires at local
8:00 AM after travel, and continues to fire at 8:00 AM across DST transitions —
matching the schedule engine's wall-clock semantics.

## Apple Watch mirroring

Standard `UNNotificationRequest`s mirror to a paired Apple Watch automatically
when the iPhone is locked/inactive; no extra work is required. Dose reminders
share a `threadIdentifier` so they group together on both devices.

## Testing

`swift test` runs the full suite against `InMemoryNotificationCenter`, including
a deterministic **48-hour / 24-medication stress simulation** that asserts the
budget is never exceeded and that every in-window dose is delivered exactly once,
in order, under continuous rotation. On-device delivery-accuracy testing is the
remaining step, gated on Apple Developer enrollment
([#25](https://github.com/kafkade/pildora/issues/25)).
