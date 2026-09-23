//! Branch-timezone-aware timestamp formatting for DISPLAY.
//!
//! The core RECORDS timestamps in corrected UTC (`corrected_now` = device clock +
//! server skew), so the recorded instant is right regardless of the device clock.
//! But DISPLAY must use the BRANCH's timezone — a Cairo store shows Cairo time on
//! a device sitting in London — mirroring Flutter's `AppTz.local()`. Centralising
//! this in the core (chrono-tz) makes Swift + Kotlin render identically and handles
//! DST correctly, instead of each host formatting in its own device-local zone.

use serde::{Deserialize, Serialize};

use crate::checkout::KEY_BRANCH_TZ;
use crate::store::Store;

/// Display styles, mirroring Flutter's `formatting.dart` helpers + the receipt stamp.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Enum))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TimeStyle {
    /// `hh:mm a` — a clock time (Flutter `timeShort`). Order/cash rows.
    Time,
    /// `MMM d` — a short date (Flutter `dateShort`).
    DateShort,
    /// `MMM d, hh:mm a` — date + time (Flutter `dateTime`). Shift open/close.
    DateTime,
    /// `dd/MM/yyyy hh:mm a` — the receipt stamp.
    Receipt,
}

/// The branch's IANA timezone (cached at login from `get_branch`, refreshed from
/// every order/shift payload that carries `timezone`), or Cairo — the
/// product-home default, matching Flutter's fallback. Falling back is flagged
/// (once per process) so a till printing in the default zone is visible.
/// The first day of a week, everywhere (owner rule, 2026-09-17): SATURDAY. The
/// backend (`tz::WEEK_START`) and the dashboard (`lib/week.ts`) carry the same
/// rule; every week preset reads it through [`week_start`].
pub const WEEK_START: chrono::Weekday = chrono::Weekday::Sat;

/// The branch-local day the week holding `day` starts on.
pub(crate) fn week_start(day: chrono::NaiveDate) -> chrono::NaiveDate {
    use chrono::Datelike;
    let back = (7 + day.weekday().num_days_from_monday() as i64 - WEEK_START.num_days_from_monday() as i64) % 7;
    day - chrono::Duration::days(back)
}

/// A branch-local calendar day as UTC bounds, midnight to midnight — the
/// backend's `service_day_bounds` (bookings/handlers.rs), gap rule included:
/// when a DST change swallows midnight (Cairo, Beirut) the day starts at the
/// first wall-clock time that exists, stepping forward 30 minutes at a time.
/// It used to read the missing midnight as UTC, which started Cairo's
/// spring-forward day two hours late.
pub(crate) fn local_day_bounds(
    tz: chrono_tz::Tz,
    date: chrono::NaiveDate,
) -> (chrono::DateTime<chrono::FixedOffset>, chrono::DateTime<chrono::FixedOffset>) {
    use chrono::TimeZone;
    let midnight = |d: chrono::NaiveDate| {
        let first = d.and_hms_opt(0, 0, 0).expect("midnight exists");
        let mut t = first;
        for _ in 0..4 {
            if let Some(at) = tz.from_local_datetime(&t).earliest() {
                return at.fixed_offset();
            }
            t += chrono::Duration::minutes(30);
        }
        // The server's last resort, kept identical.
        tz.from_utc_datetime(&first).fixed_offset()
    };
    (midnight(date), midnight(date + chrono::Duration::days(1)))
}

pub(crate) fn branch_tz(store: &Store) -> chrono_tz::Tz {
    match store
        .kv_get(KEY_BRANCH_TZ)
        .ok()
        .flatten()
        .and_then(|s| s.parse::<chrono_tz::Tz>().ok())
    {
        Some(tz) => tz,
        None => {
            flag_fallback("no cached branch timezone");
            chrono_tz::Africa::Cairo
        }
    }
}

/// Cache a server-sent effective timezone (ignored when not a valid IANA name).
pub(crate) fn remember_tz(store: &Store, iana: &str) {
    if iana.parse::<chrono_tz::Tz>().is_ok()
        && store.kv_get(KEY_BRANCH_TZ).ok().flatten().as_deref() != Some(iana)
    {
        let _ = store.kv_put(KEY_BRANCH_TZ, iana);
    }
}

/// [`remember_tz`] for a generated-client `timezone` field (absent / null skip).
pub(crate) fn remember_payload_tz(store: &Store, tz: &Option<Option<String>>) {
    if let Some(Some(name)) = tz {
        remember_tz(store, name);
    }
}

fn flag_fallback(why: &str) {
    use std::sync::atomic::{AtomicBool, Ordering};
    static FLAGGED: AtomicBool = AtomicBool::new(false);
    if !FLAGGED.swap(true, Ordering::Relaxed) {
        crate::obs::capture_bg_warning("timefmt.fallback_tz", format!("{why}; using Africa/Cairo"));
    }
}

/// Format a stored timestamp in the branch timezone for display, in `locale`.
/// Unparseable input passes through unchanged (never panics on a malformed string).
pub(crate) fn format(store: &Store, rfc3339: &str, style: TimeStyle, locale: &str) -> String {
    format_in(branch_tz(store), rfc3339, style, locale)
}

/// [`format`] in an explicit zone — what the printers use (the zone is resolved
/// once by the caller, from the payload or the cache).
pub(crate) fn format_in(
    tz: chrono_tz::Tz,
    rfc3339: &str,
    style: TimeStyle,
    locale: &str,
) -> String {
    let pat = match style {
        TimeStyle::Time => "%I:%M %p",
        TimeStyle::DateShort => "%b %-d",
        TimeStyle::DateTime => "%b %-d, %I:%M %p",
        TimeStyle::Receipt => "%d/%m/%Y %I:%M %p",
    };
    format_pat_in(tz, rfc3339, pat, locale)
}

/// The printed calendar date `dd/MM/yyyy` of an instant in `tz`.
pub(crate) fn date_in(tz: chrono_tz::Tz, rfc3339: &str) -> String {
    format_pat_in(tz, rfc3339, "%d/%m/%Y", "en")
}

/// A bare clock time of an instant in `tz`, 12-hour: `06:02 PM` (Arabic
/// `06:02 م`); `None` when unparsable. Every time of day the app SHOWS is
/// 12-hour — see `docs/design/SPEC.md` §Formats.
pub(crate) fn hhmm_in(tz: chrono_tz::Tz, rfc3339: &str, locale: &str) -> Option<String> {
    let at = chrono::DateTime::parse_from_rfc3339(rfc3339).ok()?;
    Some(strftime_in(&at.with_timezone(&tz), "%I:%M %p", locale))
}

/// `yyMMdd` of an instant in `tz` (the order-ref date segment).
pub(crate) fn yymmdd_in(tz: chrono_tz::Tz, rfc3339: &str) -> Option<String> {
    let at = chrono::DateTime::parse_from_rfc3339(rfc3339).ok()?;
    Some(at.with_timezone(&tz).format("%y%m%d").to_string())
}

fn format_pat_in(tz: chrono_tz::Tz, rfc3339: &str, pat: &str, locale: &str) -> String {
    match chrono::DateTime::parse_from_rfc3339(rfc3339) {
        Ok(d) => strftime_in(&d.with_timezone(&tz), pat, locale),
        Err(_) => rfc3339.to_string(),
    }
}

/// A table row's stamp in the branch zone, 12-hour: `06:02 PM` on the same
/// branch-local day as `now`, else `Sep 12 · 06:02 PM` (see `display::format_stamp`).
/// Unparseable input passes through unchanged.
pub(crate) fn format_stamp(
    store: &Store,
    rfc3339: &str,
    locale: &str,
    now: chrono::DateTime<chrono::Utc>,
) -> String {
    let tz = branch_tz(store);
    match chrono::DateTime::parse_from_rfc3339(rfc3339) {
        Ok(d) => crate::display::format_stamp(
            d.with_timezone(&tz).naive_local(),
            now.with_timezone(&tz).naive_local(),
            locale,
        ),
        Err(_) => rfc3339.to_string(),
    }
}

/// `strftime` with the words in `locale`: for Arabic, `%p` becomes ص / م and
/// `%b` the Arabic month. Figures stay Western, like every figure the app
/// shows and prints (money included) — only the words change. Every other
/// language keeps chrono's English.
pub(crate) fn strftime_in<Tz: chrono::TimeZone>(
    dt: &chrono::DateTime<Tz>,
    pat: &str,
    locale: &str,
) -> String
where
    Tz::Offset: std::fmt::Display,
{
    use chrono::{Datelike, Timelike};
    if !crate::i18n::is_arabic(locale) {
        return dt.format(pat).to_string();
    }
    let ampm = if dt.hour() < 12 { "ص" } else { "م" };
    let month = crate::display::AR_MONTHS[dt.month0() as usize];
    let pat = pat.replace("%p", ampm).replace("%b", month);
    dt.format(&pat).to_string()
}


// ── The date-range picker's chrome ───────────────────────────────────────────

/// Everything a date-range picker needs to draw a branch-local calendar: what
/// day it is IN THE BRANCH (the future-date guard), which weekday a week starts
/// on, and the month / weekday words in the till's language.
///
/// The picker lays out its own grid — pure civil-date arithmetic, which is
/// presentation — but every question that is not arithmetic (today, the week
/// start, the words) is answered here, so the POS and the dashboard cut days
/// the same way and a calendar cell never disagrees with the range label
/// beside it.
#[derive(Clone, Debug, Serialize, Deserialize, PartialEq, Eq)]
pub struct DatePickerChromeView {
    /// Today in the branch timezone, `YYYY-MM-DD`.
    pub today: String,
    /// The weekday a week starts on: 0 = Sunday … 6 = Saturday (see
    /// [`WEEK_START`] — the owner's rule is Saturday).
    pub week_start: i32,
    /// The seven column headings, already rotated so index 0 is `week_start`.
    pub weekdays: Vec<String>,
    /// The twelve months in full, January first — the calendar's own header.
    pub months: Vec<String>,
    /// The twelve months as a DATE shows them ([`TimeStyle::DateShort`]), so a
    /// day the picker labels reads exactly like the screen's range label.
    pub months_short: Vec<String>,
}

/// [`crate::MadarCore::date_picker_chrome`] with the zone, the instant and the
/// locale given — what the tests drive.
pub(crate) fn date_picker_chrome_in(
    tz: chrono_tz::Tz,
    now: chrono::DateTime<chrono::Utc>,
    locale: &str,
) -> DatePickerChromeView {
    use chrono::TimeZone;
    let arabic = crate::i18n::is_arabic(locale);
    let first = WEEK_START.num_days_from_sunday() as usize;
    let weekdays = if arabic { crate::display::AR_WEEKDAYS_SHORT } else { crate::display::EN_WEEKDAYS_SHORT };
    DatePickerChromeView {
        today: now.with_timezone(&tz).date_naive().format("%Y-%m-%d").to_string(),
        week_start: WEEK_START.num_days_from_sunday() as i32,
        weekdays: (0..7).map(|i| weekdays[(first + i) % 7].to_string()).collect(),
        months: if arabic {
            crate::display::AR_MONTHS.iter().map(|m| m.to_string()).collect()
        } else {
            crate::display::EN_MONTHS_LONG.iter().map(|m| m.to_string()).collect()
        },
        months_short: (0..12u32)
            .map(|m| {
                let d = chrono::NaiveDate::from_ymd_opt(2024, m + 1, 1).expect("a first of the month");
                strftime_in(&chrono::Utc.from_utc_datetime(&d.and_hms_opt(12, 0, 0).expect("noon")), "%b", locale)
            })
            .collect(),
    }
}

impl crate::MadarCore {
    /// The chrome a date-range picker draws itself with — see
    /// [`DatePickerChromeView`]. One cheap local read; always succeeds offline.
    pub fn date_picker_chrome(&self) -> DatePickerChromeView {
        date_picker_chrome_in(branch_tz(&self.store), self.corrected_now(), &self.current_locale())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn date_picker_chrome_is_branch_local_and_starts_the_week_on_saturday() {
        // 21:30 UTC on the 18th is already the 19th in Cairo (UTC+2) — the
        // future-date guard must use the BRANCH's day, not the device's.
        let now = chrono::DateTime::parse_from_rfc3339("2026-09-18T22:30:00+00:00")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let en = date_picker_chrome_in(chrono_tz::Africa::Cairo, now, "en");
        assert_eq!(en.today, "2026-09-19");
        assert_eq!(en.week_start, 6);
        assert_eq!(en.weekdays, ["Sat", "Sun", "Mon", "Tue", "Wed", "Thu", "Fri"]);
        assert_eq!(en.months[8], "September");
        assert_eq!(en.months_short[8], "Sep");

        // Same instant in a zone a day behind.
        let la = date_picker_chrome_in(chrono_tz::America::Los_Angeles, now, "en");
        assert_eq!(la.today, "2026-09-18");

        let ar = date_picker_chrome_in(chrono_tz::Africa::Cairo, now, "ar-EG");
        assert_eq!(ar.weekdays[0], "سبت");
        assert_eq!(ar.months[8], "سبتمبر");
        // The day label the picker composes reads like the screen's range label.
        assert_eq!(
            format!("{} {}", ar.months_short[8], 17),
            format_in(chrono_tz::Africa::Cairo, "2026-09-17T09:00:00+00:00", TimeStyle::DateShort, "ar-EG")
        );
    }

    #[test]
    fn formats_in_the_branch_timezone_not_utc() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap(); // UTC+2 (no DST since 2015)
                                                              // 10:00 UTC is 12:00 in Cairo — display must show the BRANCH wall-clock.
        let utc = "2026-01-20T10:00:00+00:00";
        assert_eq!(format(&store, utc, TimeStyle::Time, "en"), "12:00 PM");
        assert_eq!(
            format(&store, utc, TimeStyle::DateTime, "en"),
            "Jan 20, 12:00 PM"
        );
        assert_eq!(format(&store, utc, TimeStyle::DateShort, "en"), "Jan 20");
        assert_eq!(
            format(&store, utc, TimeStyle::Receipt, "en"),
            "20/01/2026 12:00 PM"
        );
    }

    #[test]
    fn honors_a_different_branch_timezone() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "America/New_York").unwrap(); // UTC-5 in January
                                                                  // 10:00 UTC is 05:00 in New York.
        assert_eq!(
            format(&store, "2026-01-20T10:00:00+00:00", TimeStyle::Time, "en"),
            "05:00 AM"
        );
    }

    #[test]
    fn clock_and_dates_read_the_next_calendar_day_after_a_late_utc_instant() {
        let cairo = chrono_tz::Africa::Cairo;
        let late = "2026-09-12T23:30:00Z"; // 02:30 on Sep 13, Cairo summer (UTC+3)
        assert_eq!(hhmm_in(cairo, late, "en").as_deref(), Some("02:30 AM"));
        assert_eq!(date_in(cairo, late), "13/09/2026");
        assert_eq!(yymmdd_in(cairo, late).as_deref(), Some("260913"));
        assert_eq!(format_in(cairo, late, TimeStyle::Time, "en"), "02:30 AM");
    }

    #[test]
    fn a_payload_zone_refreshes_the_cache_and_garbage_does_not() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap();
        remember_payload_tz(&store, &Some(Some("Asia/Dubai".into())));
        assert_eq!(branch_tz(&store), chrono_tz::Asia::Dubai);
        remember_payload_tz(&store, &Some(Some("Not/AZone".into())));
        remember_payload_tz(&store, &Some(None));
        remember_payload_tz(&store, &None);
        assert_eq!(branch_tz(&store), chrono_tz::Asia::Dubai);
    }

    #[test]
    fn falls_back_to_cairo_and_passes_through_garbage() {
        let store = Store::open("").unwrap();
        // No cached tz → Cairo (UTC+2): 10:00 UTC → 12:00.
        assert_eq!(branch_tz(&store), chrono_tz::Africa::Cairo);
        assert_eq!(
            format(&store, "2026-01-20T10:00:00+00:00", TimeStyle::Time, "en"),
            "12:00 PM"
        );
        // Unparseable input is returned as-is, never panics.
        assert_eq!(
            format(&store, "not-a-date", TimeStyle::Time, "ar"),
            "not-a-date"
        );
    }

    #[test]
    fn arabic_says_the_words_in_arabic_and_keeps_the_figures() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap();
        let morning = "2026-01-20T08:05:00+00:00"; // 10:05 Cairo
        let evening = "2026-09-12T17:30:00+00:00"; // 20:30 Cairo (UTC+3 in summer)
        assert_eq!(format(&store, morning, TimeStyle::Time, "ar"), "10:05 ص");
        assert_eq!(
            format(&store, morning, TimeStyle::DateShort, "ar-EG"),
            "يناير 20"
        );
        assert_eq!(
            format(&store, evening, TimeStyle::Receipt, "ar"),
            "12/09/2026 08:30 م"
        );
        assert_eq!(
            format(&store, evening, TimeStyle::DateTime, "ar"),
            "سبتمبر 12, 08:30 م"
        );
        // English is untouched.
        assert_eq!(format(&store, morning, TimeStyle::Time, "en"), "10:05 AM");
    }

    #[test]
    fn stamp_reads_today_in_the_branch_zone() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap();
        // 22:30 UTC on the 12th is 01:30 on the 13th in Cairo (UTC+3 in Sept).
        let now = chrono::DateTime::parse_from_rfc3339("2026-09-12T22:30:00+00:00")
            .unwrap()
            .with_timezone(&chrono::Utc);
        let at = "2026-09-12T22:05:00+00:00"; // 01:05 on the 13th, Cairo
        assert_eq!(format_stamp(&store, at, "en", now), "01:05 AM");
        let yesterday = "2026-09-12T15:02:00+00:00"; // 18:02 on the 12th, Cairo
        assert_eq!(
            format_stamp(&store, yesterday, "en", now),
            "Sep 12 · 06:02 PM"
        );
        assert_eq!(
            format_stamp(&store, yesterday, "ar", now),
            "12 سبتمبر · 06:02 م"
        );
    }

    /// Guardrail: every date/time is formatted HERE, in an explicit zone. Any
    /// other source file that formats a chrono value (`.format(`) or reads the
    /// device zone (`Local::now` / `chrono::Local`) fails this test.
    #[test]
    fn no_date_formatting_or_device_zone_outside_timefmt() {
        let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
        let mut bad = Vec::new();
        let mut stack = vec![dir];
        while let Some(d) = stack.pop() {
            for e in std::fs::read_dir(&d).unwrap().flatten() {
                let p = e.path();
                if p.is_dir() {
                    stack.push(p);
                    continue;
                }
                if p.extension().is_none_or(|x| x != "rs") || p.ends_with("timefmt.rs") {
                    continue;
                }
                let src = std::fs::read_to_string(&p).unwrap();
                for (n, line) in src.lines().enumerate() {
                    let code = line.split("//").next().unwrap_or("");
                    if code.contains(".format(")
                        || code.contains("Local::now")
                        || code.contains("chrono::Local")
                    {
                        bad.push(format!("{}:{}: {}", p.display(), n + 1, line.trim()));
                    }
                }
            }
        }
        assert!(
            bad.is_empty(),
            "format dates via timefmt only:\n{}",
            bad.join("\n")
        );
    }

    /// X1 (madar-shared discovery): on a DST gap that swallows midnight the day
    /// starts at the first wall-clock time that exists — the backend's
    /// `service_day_bounds` (bookings/handlers.rs) — never at midnight read as
    /// UTC, which started Cairo's spring-forward day two hours late.
    #[test]
    fn a_dst_gap_day_starts_at_the_first_real_local_time_like_the_server() {
        let d = |s: &str| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
        let utc = |s: &str| chrono::DateTime::parse_from_rfc3339(s).unwrap().with_timezone(&chrono::Utc);
        let cairo = chrono_tz::Africa::Cairo;
        for (day, start) in [
            ("2026-04-24", "2026-04-23T22:00:00Z"),
            ("2024-04-26", "2024-04-25T22:00:00Z"),
            ("2025-04-25", "2025-04-24T22:00:00Z"),
        ] {
            let (from, _) = local_day_bounds(cairo, d(day));
            assert_eq!(from.with_timezone(&chrono::Utc), utc(start), "Cairo {day}");
            // …and the day before ends exactly there: no gap, no overlap.
            let (_, prev_end) = local_day_bounds(cairo, d(day).pred_opt().unwrap());
            assert_eq!(prev_end, from, "Cairo {day}: contiguous days");
        }
        // Beirut springs forward at midnight too (last Sunday of March).
        let (from, to) = local_day_bounds(chrono_tz::Asia::Beirut, d("2026-03-29"));
        assert_eq!(from.with_timezone(&chrono::Utc), utc("2026-03-28T22:00:00Z"));
        assert_eq!(to.with_timezone(&chrono::Utc), utc("2026-03-29T21:00:00Z"), "a 23-hour day");
        // An ordinary day is untouched.
        let (from, to) = local_day_bounds(cairo, d("2026-09-17"));
        assert_eq!(from.with_timezone(&chrono::Utc), utc("2026-09-16T21:00:00Z"));
        assert_eq!(to.with_timezone(&chrono::Utc), utc("2026-09-17T21:00:00Z"));
    }
}
