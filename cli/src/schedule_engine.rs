use chrono::{DateTime, Datelike, Local, NaiveDate, NaiveTime, TimeZone, Utc};

use crate::models::{Schedule, SchedulePattern};

/// A computed scheduled dose occurrence.
#[derive(Debug, Clone)]
pub struct ScheduledDose {
    pub time: DateTime<Utc>,
    pub medication_id: String,
    pub medication_name: String,
}

/// Compute the next `count` scheduled dose times starting from `from`.
///
/// Returns an empty vec for PRN schedules (taken as needed).
pub fn next_doses(schedule: &Schedule, from: DateTime<Utc>, count: usize) -> Vec<ScheduledDose> {
    if matches!(schedule.pattern, SchedulePattern::Prn) || count == 0 {
        return vec![];
    }

    let local_now = from.with_timezone(&Local);
    let mut current_date = local_now.date_naive();
    let mut results = Vec::with_capacity(count);

    // Scan up to 400 days forward to handle every-N-days with large intervals.
    for _ in 0..400 {
        if date_matches_pattern(&schedule.pattern, current_date) {
            for &time in &schedule.times {
                if let Some(utc_dt) = naive_to_utc(current_date, time)
                    && utc_dt > from
                {
                    results.push(ScheduledDose {
                        time: utc_dt,
                        medication_id: schedule.medication_id.clone(),
                        medication_name: schedule.medication_name.clone(),
                    });
                    if results.len() >= count {
                        return results;
                    }
                }
            }
        }
        current_date += chrono::Duration::days(1);
    }

    results
}

/// Compute all scheduled doses for a specific date.
pub fn doses_for_date(schedule: &Schedule, date: NaiveDate) -> Vec<ScheduledDose> {
    if !date_matches_pattern(&schedule.pattern, date) {
        return vec![];
    }

    schedule
        .times
        .iter()
        .filter_map(|&time| {
            naive_to_utc(date, time).map(|utc_dt| ScheduledDose {
                time: utc_dt,
                medication_id: schedule.medication_id.clone(),
                medication_name: schedule.medication_name.clone(),
            })
        })
        .collect()
}

/// Check if a date matches the schedule pattern.
pub fn date_matches_pattern(pattern: &SchedulePattern, date: NaiveDate) -> bool {
    match pattern {
        SchedulePattern::Daily => true,
        SchedulePattern::EveryNDays {
            interval,
            start_date,
        } => {
            let days_diff = (date - *start_date).num_days();
            days_diff >= 0 && days_diff % i64::from(*interval) == 0
        }
        SchedulePattern::SpecificDays { days } => days.contains(&date.weekday()),
        SchedulePattern::Prn => false,
    }
}

/// Convert a `NaiveDate` + `NaiveTime` to a UTC `DateTime` using the system
/// local timezone. Returns `None` if the local time is ambiguous or
/// non-existent (e.g., during a spring-forward DST gap).
fn naive_to_utc(date: NaiveDate, time: NaiveTime) -> Option<DateTime<Utc>> {
    Local
        .from_local_datetime(&date.and_time(time))
        .single()
        .map(|dt| dt.with_timezone(&Utc))
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::{NaiveDate, NaiveTime, Utc, Weekday};

    fn make_schedule(pattern: SchedulePattern, times: Vec<NaiveTime>) -> Schedule {
        Schedule {
            medication_id: "med-1".to_string(),
            medication_name: "TestMed".to_string(),
            pattern,
            times,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        }
    }

    #[test]
    fn daily_schedule_next_doses() {
        let schedule = make_schedule(
            SchedulePattern::Daily,
            vec![
                NaiveTime::from_hms_opt(8, 0, 0).unwrap(),
                NaiveTime::from_hms_opt(20, 0, 0).unwrap(),
            ],
        );

        let from = Utc::now();
        let doses = next_doses(&schedule, from, 4);
        assert_eq!(doses.len(), 4);

        // All doses should be in the future
        for dose in &doses {
            assert!(dose.time > from);
        }

        // Doses should be in chronological order
        for window in doses.windows(2) {
            assert!(window[0].time < window[1].time);
        }
    }

    #[test]
    fn every_n_days_pattern() {
        let start = NaiveDate::from_ymd_opt(2026, 4, 25).unwrap();
        let schedule = make_schedule(
            SchedulePattern::EveryNDays {
                interval: 3,
                start_date: start,
            },
            vec![NaiveTime::from_hms_opt(9, 0, 0).unwrap()],
        );

        // Day 0 (start) should match
        assert!(date_matches_pattern(&schedule.pattern, start));

        // Day 1 and Day 2 should NOT match
        let day1 = NaiveDate::from_ymd_opt(2026, 4, 26).unwrap();
        let day2 = NaiveDate::from_ymd_opt(2026, 4, 27).unwrap();
        assert!(!date_matches_pattern(&schedule.pattern, day1));
        assert!(!date_matches_pattern(&schedule.pattern, day2));

        // Day 3 should match
        let day3 = NaiveDate::from_ymd_opt(2026, 4, 28).unwrap();
        assert!(date_matches_pattern(&schedule.pattern, day3));

        // Day 6 should match
        let day6 = NaiveDate::from_ymd_opt(2026, 5, 1).unwrap();
        assert!(date_matches_pattern(&schedule.pattern, day6));

        // Day before start should NOT match
        let before = NaiveDate::from_ymd_opt(2026, 4, 24).unwrap();
        assert!(!date_matches_pattern(&schedule.pattern, before));
    }

    #[test]
    fn specific_days_pattern() {
        let pattern = SchedulePattern::SpecificDays {
            days: vec![Weekday::Mon, Weekday::Wed, Weekday::Fri],
        };

        // 2026-04-27 is a Monday
        let mon = NaiveDate::from_ymd_opt(2026, 4, 27).unwrap();
        assert_eq!(mon.weekday(), Weekday::Mon);
        assert!(date_matches_pattern(&pattern, mon));

        // Tuesday should not match
        let tue = NaiveDate::from_ymd_opt(2026, 4, 28).unwrap();
        assert!(!date_matches_pattern(&pattern, tue));

        // Wednesday should match
        let wed = NaiveDate::from_ymd_opt(2026, 4, 29).unwrap();
        assert!(date_matches_pattern(&pattern, wed));

        // Friday should match
        let fri = NaiveDate::from_ymd_opt(2026, 5, 1).unwrap();
        assert_eq!(fri.weekday(), Weekday::Fri);
        assert!(date_matches_pattern(&pattern, fri));
    }

    #[test]
    fn prn_returns_empty() {
        let schedule = make_schedule(SchedulePattern::Prn, vec![]);
        let doses = next_doses(&schedule, Utc::now(), 5);
        assert!(doses.is_empty());

        let date = NaiveDate::from_ymd_opt(2026, 4, 25).unwrap();
        assert!(!date_matches_pattern(&schedule.pattern, date));
    }

    #[test]
    fn doses_for_date_daily() {
        let schedule = make_schedule(
            SchedulePattern::Daily,
            vec![
                NaiveTime::from_hms_opt(8, 0, 0).unwrap(),
                NaiveTime::from_hms_opt(14, 0, 0).unwrap(),
                NaiveTime::from_hms_opt(20, 0, 0).unwrap(),
            ],
        );

        let date = NaiveDate::from_ymd_opt(2026, 6, 15).unwrap();
        let doses = doses_for_date(&schedule, date);
        assert_eq!(doses.len(), 3);

        for dose in &doses {
            assert_eq!(dose.medication_name, "TestMed");
        }
    }

    #[test]
    fn doses_for_date_non_matching_day() {
        let schedule = make_schedule(
            SchedulePattern::SpecificDays {
                days: vec![Weekday::Mon],
            },
            vec![NaiveTime::from_hms_opt(8, 0, 0).unwrap()],
        );

        // 2026-04-28 is Tuesday
        let tue = NaiveDate::from_ymd_opt(2026, 4, 28).unwrap();
        assert!(doses_for_date(&schedule, tue).is_empty());
    }

    #[test]
    fn next_doses_zero_count() {
        let schedule = make_schedule(
            SchedulePattern::Daily,
            vec![NaiveTime::from_hms_opt(8, 0, 0).unwrap()],
        );
        let doses = next_doses(&schedule, Utc::now(), 0);
        assert!(doses.is_empty());
    }

    #[test]
    fn midnight_crossing() {
        // Schedule at 23:59 — should still produce a dose on the correct day
        let schedule = make_schedule(
            SchedulePattern::Daily,
            vec![NaiveTime::from_hms_opt(23, 59, 0).unwrap()],
        );

        let from = Utc::now();
        let doses = next_doses(&schedule, from, 2);
        assert_eq!(doses.len(), 2);
        assert!(doses[0].time < doses[1].time);
    }
}
