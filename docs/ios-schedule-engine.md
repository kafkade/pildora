# iOS Schedule Engine

Design reference for the schedule engine implemented in
[`ios/schedule-engine/PildoraScheduleEngine`](../ios/schedule-engine/PildoraScheduleEngine/)
(issue #46, roadmap §14.2 Epic #6). The engine computes concrete dose times
from a recurrence rule and is the timing source for local notifications, the
Today view, and adherence tracking.

> This is a tracking/timing tool. It computes *when* doses recur and provides
> **no** dosing recommendations or medical advice.

## Scope

The engine is a **pure, deterministic computation layer**:

- Foundation only — no GRDB, SQLCipher, or FFI. It runs and tests under plain
  `swift test`, on the command line and in CI.
- No I/O and no global state: every query takes an explicit `Calendar` (which
  carries the `TimeZone`), so results are fully reproducible.

## Model boundary: engine vs. persistence

The engine deliberately defines its **own** input model rather than consuming
the persisted `Schedule` record from the data layer
([`docs/ios-data-model.md`](ios-data-model.md), #44). Two reasons:

1. **Capability gap.** The shipped `Schedule`/`SchedulePattern` supports only
   `daily` / `specific_days` / `every_n_days` / `prn` with concrete `"HH:mm"`
   times. This issue additionally requires **cycling** schedules and
   **time windows** (morning/afternoon/evening/bedtime), which the persisted
   model can't yet express.
2. **Staging.** Extending the persisted schema (new columns, a `.cycling`
   pattern, a migration) is a separate change with its own review surface.
   Keeping the engine's model independent lets the computation land now; a
   later persistence-wiring issue maps stored rows onto `ScheduleRule` (and, if
   desired, extends the schema to round-trip cycling/windows).

This mirrors how the Today view (#47) ships "self-contained until the schedule
engine and persistence wiring land".

### Engine model

| Type | Role |
| --- | --- |
| `TimeOfDay` | Wall-clock `HH:mm`, calendar/timezone-independent. |
| `Weekday` | `mon…sun` tokens matching the persisted `daysJson`. |
| `DoseTimeWindow` | morning/afternoon/evening/bedtime (mirrors the Today view). |
| `TimeWindowConfiguration` | User-configurable window → `TimeOfDay` map (defaults 08:00/13:00/18:00/22:00). |
| `DoseAnchor` | `.time(TimeOfDay)` or `.window(DoseTimeWindow)` — where a dose is pinned. |
| `SchedulePattern` | `daily` / `specificDays` / `everyNDays` / `cycling` / `asNeeded`. |
| `ScheduleRule` | Engine input: pattern + `startDate`/`endDate` + window config + ids. |
| `DoseOccurrence` | Engine output: absolute `scheduledAt` + `time` + `window` + ids. |

## Patterns

- **daily** — fire at each anchor every day. One anchor is once-daily; multiple
  anchors give multi-daily (e.g. 3×/day).
- **specificDays** — like daily, restricted to the listed weekdays.
- **everyNDays** — fire once every `interval` days, counted from `startDate`
  (day granularity). Querying mid-stream stays on the original cadence.
- **cycling** — `daysOn` active days followed by `daysOff` inactive days,
  repeating from `startDate`. Covers 21-on/7-off contraceptive packs and
  N-on/M-off dosing. Cycle position is `dayIndex % (daysOn + daysOff)`.
- **asNeeded (PRN)** — no computed occurrences; doses are logged manually.

`startDate` is inclusive at day granularity (all of that day's doses count).
`endDate`, when set, is inclusive of that day's doses.

## Public API

```swift
ScheduleEngine(rule:).nextDoses(count:after:calendar:maxLookaheadDays:) -> [DoseOccurrence]
ScheduleEngine(rule:).occurrences(in:calendar:)                         -> [DoseOccurrence]
ScheduleRule.validate()                                                 -> [ScheduleValidationError]
```

- `nextDoses` returns the next `count` doses **strictly after** the given
  instant, in chronological order — the API the notification scheduler and Today
  view consume. `maxLookaheadDays` bounds the search for sparse schedules.
- `occurrences(in:)` returns everything within a `DateInterval` (both ends
  inclusive).

## Timezone & DST policy

Doses use **wall-clock local time**: `08:00` means 8am wherever the user is. The
engine builds each occurrence by combining a calendar day with a `TimeOfDay` in
the supplied `Calendar`, so timezone and DST behavior come from Foundation's
calendar arithmetic rather than special cases.

- **Timezone travel.** Query with the destination's `Calendar`/`TimeZone`; the
  same rule yields doses at local 08:00 there (a different absolute instant than
  at the origin).
- **DST spring-forward.** A nonexistent wall time (e.g. `02:30` on a
  spring-forward day) resolves to the **next valid instant** (`03:30`).
- **DST fall-back.** An ambiguous wall time (occurs twice) resolves to its
  **earlier** occurrence.
- **Day length.** A daily noon dose spans 23h across spring-forward and 25h
  across fall-back — the wall time is preserved, the absolute gap changes. This
  is verified in `DSTTransitionTests`.

## Validation

`ScheduleRule.validate()` returns an empty array only when the rule is safe.
It rejects impossible or overlapping configurations:

- Scheduled patterns with no dose anchors (`missingDoseTimes`).
- `everyNDays` interval `< 1` (`invalidInterval`).
- `specificDays` with no weekdays (`noWeekdaysSelected`).
- `cycling` with `daysOn < 1` / non-positive cycle (`invalidCycle`).
- `endDate` earlier than `startDate` (`endBeforeStart`).
- Two anchors resolving to the same time-of-day (`duplicateDoseTimes`).

PRN carries no anchors or cadence by construction and is always valid.

## Testing

`swift test` runs the full XCTest suite with fixed `Calendar` + `TimeZone`
fixtures: every pattern, time windows, PRN, `nextDoses` ordering/count/`endDate`
truncation, DST spring-forward and fall-back (America/New_York), multi-timezone
travel (Tokyo/London, LA/NY), and all validation errors.

## Not yet wired

- **Persistence** — mapping data-layer `Schedule` rows onto `ScheduleRule` (and
  any schema extension for cycling/windows) is a follow-up.
- **Local notifications** — the notification scheduler (roadmap Epic #7) will
  call `nextDoses(count:)` against the iOS 64-notification budget.
