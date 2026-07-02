# PildoraScheduleEngine

The **schedule engine** (issue #46, roadmap Epic #6): a pure-Swift computation
layer that turns a medication's recurrence rule into concrete dose times. It is
the source of truth that drives local notifications, the Today view, and
adherence tracking.

> **Informational only.** This package computes *timing*. It provides no dosing
> recommendations or medical advice.

## Design

- **Pure Foundation, no dependencies.** No GRDB/SQLCipher/FFI — the engine is
  deterministic and testable with plain `swift test`.
- **Independent input model.** The engine defines its own `ScheduleRule` /
  `SchedulePattern` rather than consuming the persisted data-layer `Schedule`
  (#44), which can't yet express cycling or time windows. Mapping stored rows
  onto `ScheduleRule` is a future persistence-wiring step.
- **Wall-clock semantics.** A `TimeOfDay` of `08:00` means 8am in the *current*
  calendar/timezone. Every query takes an explicit `Calendar`, so travel and DST
  are handled by calendar arithmetic. See
  [`docs/ios-schedule-engine.md`](../../../docs/ios-schedule-engine.md).

## Scheduling patterns

| Pattern | Meaning |
| --- | --- |
| `daily(anchors:)` | Fixed times every day. One anchor = once daily; many = multi-daily (e.g. 3×/day). |
| `specificDays(weekdays:anchors:)` | Fixed times, only on the listed weekdays. |
| `everyNDays(interval:anchors:)` | Fixed times once every N days, counted from `startDate`. |
| `cycling(daysOn:daysOff:anchors:)` | N active days then M inactive days, repeating (e.g. 21-on/7-off). |
| `asNeeded` | PRN — produces **no** computed doses; logged manually. |

A dose `DoseAnchor` is either an explicit `.time("HH:mm")` or a `.window(...)`
(morning/afternoon/evening/bedtime) resolved through a user-configurable
`TimeWindowConfiguration`.

## Usage

```swift
import PildoraScheduleEngine

let rule = ScheduleRule(
    scheduleId: schedule.id,
    medicationId: schedule.medicationId,
    vaultId: schedule.vaultId,
    pattern: .cycling(daysOn: 21, daysOff: 7, anchors: [.time(TimeOfDay("08:00")!)]),
    startDate: schedule.startDate
)

// Validate before scheduling notifications or persisting.
guard rule.isValid else { /* surface rule.validate() errors */ return }

let engine = ScheduleEngine(rule: rule)

// Next 64 doses for the local-notification budget:
let upcoming = engine.nextDoses(count: 64, after: Date(), calendar: .current)

// Everything due today, for the Today timeline:
let today = engine.occurrences(
    in: DateInterval(start: startOfDay, end: endOfDay),
    calendar: .current
)
```

## Timezone / DST policy

- **Travel:** query with the destination's `Calendar`/`TimeZone`; doses fire at
  local wall time there.
- **Spring-forward** (nonexistent wall time, e.g. `02:30`): advance to the next
  valid instant.
- **Fall-back** (ambiguous wall time): use the earlier occurrence.

## Testing

```sh
cd ios/schedule-engine/PildoraScheduleEngine
swift test
```

Covers every pattern plus edge cases: DST spring-forward/fall-back
(America/New_York), multi-timezone travel, midnight/`endDate` boundaries, and
all validation errors.

## Status

🚧 Standalone package. Not yet wired to persistence (data layer #44) or the
notification scheduler (#... local notifications epic); those integrations land
in follow-up issues.
