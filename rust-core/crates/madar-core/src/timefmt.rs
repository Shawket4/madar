//! Branch-timezone-aware timestamp formatting for DISPLAY.
//!
//! The core RECORDS timestamps in corrected UTC (`corrected_now` = device clock +
//! server skew), so the recorded instant is right regardless of the device clock.
//! But DISPLAY must use the BRANCH's timezone — a Cairo store shows Cairo time on
//! a device sitting in London — mirroring Flutter's `AppTz.local()`. Centralising
//! this in the core (chrono-tz) makes Swift + Kotlin render identically and handles
//! DST correctly, instead of each host formatting in its own device-local zone.

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

/// The branch's IANA timezone (cached at login from `get_branch`), or Cairo — the
/// product-home default, matching Flutter's fallback. The cached value is present
/// after any online login, so the fallback only applies before first setup.
pub(crate) fn branch_tz(store: &Store) -> chrono_tz::Tz {
    store
        .kv_get(KEY_BRANCH_TZ)
        .ok()
        .flatten()
        .and_then(|s| s.parse::<chrono_tz::Tz>().ok())
        .unwrap_or(chrono_tz::Africa::Cairo)
}

/// Re-emit an RFC3339 timestamp converted to the branch timezone (same instant, the
/// branch's wall-clock + offset). Unparseable input passes through unchanged.
pub(crate) fn to_branch_local(store: &Store, rfc3339: &str) -> String {
    match chrono::DateTime::parse_from_rfc3339(rfc3339) {
        Ok(dt) => dt.with_timezone(&branch_tz(store)).to_rfc3339(),
        Err(_) => rfc3339.to_string(),
    }
}

/// Format a stored timestamp in the branch timezone for display, in `locale`.
/// Unparseable input passes through unchanged (never panics on a malformed string).
pub(crate) fn format(store: &Store, rfc3339: &str, style: TimeStyle, locale: &str) -> String {
    let dt = match chrono::DateTime::parse_from_rfc3339(rfc3339) {
        Ok(d) => d.with_timezone(&branch_tz(store)),
        Err(_) => return rfc3339.to_string(),
    };
    let pat = match style {
        TimeStyle::Time => "%I:%M %p",
        TimeStyle::DateShort => "%b %-d",
        TimeStyle::DateTime => "%b %-d, %I:%M %p",
        TimeStyle::Receipt => "%d/%m/%Y %I:%M %p",
    };
    strftime_in(&dt, pat, locale)
}

/// Arabic month names as written in Egypt and most of the region's shops
/// (the transliterated Gregorian set, not the Levantine كانون/شباط one).
const AR_MONTHS: [&str; 12] = [
    "يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر",
    "نوفمبر", "ديسمبر",
];

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
    let month = AR_MONTHS[dt.month0() as usize];
    let pat = pat.replace("%p", ampm).replace("%b", month);
    dt.format(&pat).to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn formats_in_the_branch_timezone_not_utc() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap(); // UTC+2 (no DST since 2015)
                                                              // 10:00 UTC is 12:00 in Cairo — display must show the BRANCH wall-clock.
        let utc = "2026-01-20T10:00:00+00:00";
        assert_eq!(format(&store, utc, TimeStyle::Time, "en"), "12:00 PM");
        assert_eq!(format(&store, utc, TimeStyle::DateTime, "en"), "Jan 20, 12:00 PM");
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
    fn falls_back_to_cairo_and_passes_through_garbage() {
        let store = Store::open("").unwrap();
        // No cached tz → Cairo (UTC+2): 10:00 UTC → 12:00.
        assert_eq!(branch_tz(&store), chrono_tz::Africa::Cairo);
        assert_eq!(
            format(&store, "2026-01-20T10:00:00+00:00", TimeStyle::Time, "en"),
            "12:00 PM"
        );
        // Unparseable input is returned as-is, never panics.
        assert_eq!(format(&store, "not-a-date", TimeStyle::Time, "ar"), "not-a-date");
    }

    #[test]
    fn arabic_says_the_words_in_arabic_and_keeps_the_figures() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap();
        let morning = "2026-01-20T08:05:00+00:00"; // 10:05 Cairo
        let evening = "2026-09-12T17:30:00+00:00"; // 20:30 Cairo (UTC+3 in summer)
        assert_eq!(format(&store, morning, TimeStyle::Time, "ar"), "10:05 ص");
        assert_eq!(format(&store, morning, TimeStyle::DateShort, "ar-EG"), "يناير 20");
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
    fn to_branch_local_shifts_the_offset_to_the_branch() {
        let store = Store::open("").unwrap();
        store.kv_put(KEY_BRANCH_TZ, "Africa/Cairo").unwrap();
        let out = to_branch_local(&store, "2026-01-20T10:00:00+00:00");
        // Same instant, Cairo offset (+02:00), 12:00 wall-clock.
        assert!(out.starts_with("2026-01-20T12:00:00+02:00"), "got {out}");
    }
}
