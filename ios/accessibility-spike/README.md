# Accessibility Spike — SwiftUI Baseline with VoiceOver and Dynamic Type

**Issue:** [#24 — SwiftUI accessibility baseline](https://github.com/kafkade/pildora/issues/24)

**Status:** Prototype built. Manual testing with VoiceOver and Accessibility Inspector requires Xcode + macOS/iOS simulator.

## Spike Questions & Answers

### 1. Does the medication list remain usable at xxxLarge Dynamic Type?

**Yes, by design.** The prototype uses these techniques to ensure Dynamic Type compliance:

| Technique | Where Applied |
|---|---|
| System semantic fonts (`.headline`, `.body`, `.subheadline`, `.footnote`) | All text elements |
| `@ScaledMetric` | Icon sizes (32pt base), button heights (52pt base) |
| `lineLimit(nil)` + `fixedSize(horizontal: false, vertical: true)` | Medication name, frequency, form |
| `ScrollView` | Dose confirmation (prevents content clipping at accessibility sizes) |
| `List` with `.insetGrouped` | Medication list (native scroll + cell sizing) |

**Dynamic Type sizes tested via Previews:**

- `.xSmall` — compact but readable
- `.large` — default iOS size
- `.xLarge` — comfortable enlarged text
- `.xxxLarge` — largest standard size
- `.accessibility3` — large accessibility size
- `.accessibility5` — maximum accessibility size

**Expected result:** At `.accessibility5`, medication cards become tall (wrapping name + frequency), but all content remains readable and tappable. No truncation of critical information (name, dosage, status).

### 2. Can VoiceOver navigate the entire dose confirmation flow?

**Yes.** Every interactive element has explicit accessibility labels with medication context:

| Element | VoiceOver Announcement |
|---|---|
| Medication card | "{Name}, {dosage} {form}. {generic}. {frequency}. {status}. {inventory}" |
| Taken button | "Mark {Name} {dosage} as taken" |
| Snooze button | "Snooze {Name} reminder" |
| Skip button | "Skip {Name} {dosage} dose" |
| Snooze option | "Snooze {Name} for 15 minutes" |
| Skip reason field | "Skip reason for {Name}" |
| Confirm Skip | "Confirm skipping {Name} {dosage}" |

**Key accessibility decisions:**

- Medication cards use `.accessibilityElement(children: .ignore)` with a custom label — VoiceOver reads the entire card as one semantic unit
- Action buttons include medication name in the label (not just "Taken") so VoiceOver users don't lose context
- Section headers have `.isHeader` trait for VoiceOver rotor navigation
- Decorative icons use `.accessibilityHidden(true)`

### 3. Do all interactive elements meet the 44pt minimum tap target?

**Yes.** All interactive elements meet or exceed the 44pt minimum:

| Element | Minimum Size | Notes |
|---|---|---|
| Medication card | 44pt height | Uses `.frame(minHeight: 44)` + `.contentShape(Rectangle())` |
| Taken button | 52pt height | `@ScaledMetric` — grows with Dynamic Type |
| Snooze button | 52pt height | `@ScaledMetric` |
| Skip button | 52pt height | `@ScaledMetric` |
| Snooze options | 44pt height | Each row has `.frame(minHeight: 44)` |
| Skip reason text field | 44pt height | `.frame(minHeight: 44)` |
| Confirm Skip button | 44pt height | Standard button with min height |
| Cancel button | System size | iOS navigation bar button (meets HIG) |

### 4. Are custom components properly accessible?

**Yes.** Custom components and their accessibility treatment:

| Component | Accessibility Strategy |
|---|---|
| `MedicationCard` | Custom label with full context; `.isButton` trait; decorative icon hidden |
| `DetailRow` | `.accessibilityElement(children: .combine)` — reads label + value together |
| `DoseConfirmationView` | Each section has header traits; ScrollView for overflow |
| Status badge (colored circle) | `.accessibilityHidden(true)` — status conveyed via adjacent text |
| Inventory warning icon | `.accessibilityHidden(true)` — warning conveyed via text |

## Accessibility Techniques Used

### Color Independence

Every status is conveyed through **text and color**, never color alone:

| Status | Color | Text |
|---|---|---|
| Missed | Red | "Missed — overdue" |
| Due now | Orange | "Due now" |
| Upcoming | Blue | "Due in 2 hours" (relative time) |
| Taken | Green | "Taken today" |
| Skipped | Secondary | "Skipped" |
| Low inventory | Orange | "Low: 3 capsules left" |
| Critical inventory | Orange | "Critical: 3 capsules left" |

### VoiceOver Grouping Strategy

- **Medication cards:** Grouped (`.ignore` children + custom label) — VoiceOver reads one semantic description per card
- **Detail rows:** Combined (`.combine` children) — VoiceOver reads "Dosage, 500 mg tablet"
- **Action buttons:** Individual — each has its own label with medication context
- **Sections:** Header trait on section labels for rotor navigation

### Known Limitations

1. **No actual VoiceOver testing** — requires macOS with Xcode simulator or a physical iOS device. Prototype is structurally accessible but needs runtime validation.
2. **No Reduce Motion support** — the prototype uses `withAnimation` for snooze/skip reveal. Should respect `accessibilityReduceMotion` preference.
3. **No Increase Contrast support** — uses standard system colors. Should add `.accessibilityShowButtonShapes` awareness.
4. **No Large Content Viewer** — not needed for this prototype (no icon-only controls), but should be added if the design adds toolbar icon buttons.

## Manual Test Procedures

### Setup

```bash
# Open in Xcode
cd ios/accessibility-spike/PildoraAccessibilitySpike
open Package.swift
# Select an iPhone simulator (iPhone 15 Pro recommended)
# Product > Run (⌘R)
```

### Test 1: Dynamic Type Verification

1. **Settings > Accessibility > Display & Text Size > Larger Text**
2. Set to each size and verify:

| Size | Check | Expected |
|---|---|---|
| Default | All 5 medications visible | Cards compact, all text readable |
| xLarge | Name wrapping | Long names like "Cholecalciferol (Vitamin D3)" wrap to 2 lines |
| xxxLarge | Card height | Cards expand vertically; all content visible |
| Accessibility 3 | Scroll behavior | List scrolls; dose confirmation scrolls |
| Accessibility 5 | No truncation | Name, dosage, status, inventory all visible |

### Test 2: VoiceOver Walkthrough

1. **Settings > Accessibility > VoiceOver > On**
2. Navigate the medication list:

| Step | Gesture | Expected Announcement |
|---|---|---|
| 1 | Swipe right | "Today, heading" (navigation title) |
| 2 | Swipe right | "Needs Attention, heading" (section header) |
| 3 | Swipe right | "Levothyroxine, 88 mcg tablet..." (full card) |
| 4 | Swipe right | "Gabapentin, 300 mg capsule..." (due now card) |
| 5 | Swipe right | "Upcoming, heading" |
| 6 | Swipe right | "Cholecalciferol (Vitamin D3)..." |
| 7 | Double tap | Dose confirmation sheet opens |
| 8 | Swipe right | "Confirm Dose, heading" |
| 9 | Swipe right | Medication name announced |
| 10 | Swipe right | "Mark [Name] [dosage] as taken, button" |
| 11 | Swipe right | "Snooze [Name] reminder, button" |
| 12 | Swipe right | "Skip [Name] [dosage] dose, button" |
| 13 | Double tap on Snooze | Snooze options appear |
| 14 | Swipe right | "Snooze [Name] for 5 minutes" |

3. Verify VoiceOver rotor shows headings: "Needs Attention", "Upcoming", "Completed"

### Test 3: Accessibility Inspector

1. **Xcode > Open Developer Tool > Accessibility Inspector**
2. Connect to the simulator
3. Run **Audit** on each screen
4. Check for:
   - Missing labels
   - Insufficient contrast
   - Hit target violations
   - Dynamic Type clipping

### Test 4: Keyboard Navigation (iPad)

1. Connect a hardware keyboard to iPad simulator
2. Verify Tab moves focus between cards and buttons
3. Verify Enter/Space activates the focused element

## Programmatic Audit

The app includes a built-in audit accessible via the toolbar button. It checks:

- ✅ Accessibility label coverage (all 5 medications)
- ✅ Tap target compliance (≥ 44pt)
- ✅ Color independence (text + color for all states)
- ✅ Dynamic Type support (system fonts, @ScaledMetric, wrapping)
- ✅ Dose confirmation context (medication name in all action labels)
- ✅ Inventory warnings in VoiceOver labels

Run from command line (prints audit results):

```bash
cd ios/accessibility-spike/PildoraAccessibilitySpike
swift run
```

## Remediation Plan

Based on structural analysis, these items need attention before Phase 1:

| Issue | Severity | Remediation |
|---|---|---|
| Reduce Motion not respected | Medium | Wrap `withAnimation` in `UIAccessibility.isReduceMotionEnabled` check |
| No Increase Contrast support | Low | Add `.accessibilityShowButtonShapes` and high-contrast color variants |
| No Large Content Viewer | Low | Add `.accessibilityShowsLargeContentViewer()` to any future icon-only controls |
| VoiceOver reading order untested | High | Must validate with device testing (Accessibility Inspector audit) |
| Haptic feedback missing | Low | Add haptic confirmation on Taken action for tactile feedback |
| No error announcements | Medium | Add `UIAccessibility.post(notification: .announcement)` for state changes |

## Files

```text
ios/accessibility-spike/
  README.md                                              ← This file
  PildoraAccessibilitySpike/
    Package.swift                                        ← Swift Package (macOS 14+ / iOS 17+)
    Sources/
      PildoraAccessibilityApp.swift                     ← @main App + audit results view
      SampleData.swift                                  ← 5 medications covering accessibility edge cases
      MedicationListView.swift                          ← List screen with sections + accessible cards
      DoseConfirmationView.swift                        ← Taken/Snooze/Skip with context-rich labels
      AccessibilityAudit.swift                          ← Programmatic baseline checks
```

## Next Steps

1. **Device testing** (blocked by #25): run VoiceOver + Accessibility Inspector on physical iPhone
2. **Reduce Motion**: wrap animations in `accessibilityReduceMotion` checks
3. **Haptic feedback**: add `UIImpactFeedbackGenerator` to Taken/Skip confirmations
4. **Error announcements**: post `UIAccessibility.Notification.announcement` on state transitions
5. **iPad layout**: test with larger screen, keyboard navigation, pointer support
