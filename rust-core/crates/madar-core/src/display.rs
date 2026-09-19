//! Display formats — THE rules for how money, an elapsed time and a timestamp
//! read on screen, in English and Arabic. `docs/design/SPEC.md` §Formats is the
//! prose; `docs/design/format_fixtures.json` is the contract.
//!
//! The Flutter design system carries a synchronous mirror of these rules
//! (`packages/design_system/lib/src/format.dart`) because a table of two hundred
//! rows cannot cross the bridge per cell, and a `Text` in the kit has no bridge
//! to call. The two are held together by ONE fixture file that both test suites
//! read: change a rule here, change the fixture, and the Dart test fails until
//! the mirror agrees. Neither side is allowed to format money any other way.
//!
//! Timezones are not this module's business. [`format_stamp`] takes wall-clock
//! times already in the branch's zone (see `timefmt`); `MadarCore::format_stamp`
//! does the conversion and supplies the corrected clock.

use chrono::{Datelike, NaiveDateTime, Timelike};

use crate::i18n::is_arabic;

/// U+2212 MINUS SIGN. A hyphen is shorter than a plus and reads as a dash in a
/// column of figures; the true minus is the width of `+`.
pub const MINUS: char = '\u{2212}';

/// U+2066 LEFT-TO-RIGHT ISOLATE / U+2069 POP DIRECTIONAL ISOLATE. A figure inside
/// Arabic text is wrapped in these so its sign, separators and digits keep their
/// order and never pull neighbouring words into the run.
pub const LRI: char = '\u{2066}';
pub const PDI: char = '\u{2069}';

/// Wrap `s` in an LTR isolate.
pub fn ltr_isolate(s: &str) -> String {
    format!("{LRI}{s}{PDI}")
}

/// Minor units to `1,234.50` — thousands grouped with `,`, always two decimals,
/// no sign. Western digits in both languages (the till's figures never change
/// script; see `timefmt::strftime_in`).
pub fn group_amount(minor: i64) -> String {
    let abs = minor.unsigned_abs();
    let whole = (abs / 100).to_string();
    let mut grouped = String::with_capacity(whole.len() + whole.len() / 3);
    for (i, ch) in whole.chars().enumerate() {
        if i > 0 && (whole.len() - i) % 3 == 0 {
            grouped.push(',');
        }
        grouped.push(ch);
    }
    format!("{grouped}.{:02}", abs % 100)
}

/// The currency as a person reads it: the ISO code in English (`EGP`), the local
/// abbreviation in Arabic (`ج.م`). An unknown code stays the code in both.
pub fn currency_label(code: &str, locale: &str) -> String {
    let upper = code.trim().to_uppercase();
    if !is_arabic(locale) {
        return upper;
    }
    match upper.as_str() {
        "EGP" => "ج.م",
        "SAR" => "ر.س",
        "AED" => "د.إ",
        "KWD" => "د.ك",
        "QAR" => "ر.ق",
        "BHD" => "د.ب",
        "OMR" => "ر.ع",
        "JOD" => "د.أ",
        _ => return upper,
    }
    .to_string()
}

/// THE money string.
///
/// * English: `EGP 1,234.50`, `−EGP 50.00`, `+EGP 20.00` (sign before the code).
/// * Arabic: `<LRI>1,234.50<PDI> ج.م`, `<LRI>−50.00<PDI> ج.م` — the figure (with its sign) in an
///   LTR isolate, the label after it, so in a right-to-left line the figure sits
///   on the reading side and the label trails it.
///
/// `signed` adds `+` to a positive amount (a ledger line); zero is never signed.
/// An empty `currency` drops the label (and, in Arabic, keeps the isolate).
pub fn format_money(minor: i64, currency: &str, locale: &str, signed: bool) -> String {
    let sign = if minor < 0 {
        MINUS.to_string()
    } else if signed && minor > 0 {
        "+".to_string()
    } else {
        String::new()
    };
    let amount = group_amount(minor);
    let label = currency_label(currency, locale);
    if is_arabic(locale) {
        let figure = ltr_isolate(&format!("{sign}{amount}"));
        if label.is_empty() {
            figure
        } else {
            format!("{figure} {label}")
        }
    } else if label.is_empty() {
        format!("{sign}{amount}")
    } else {
        format!("{sign}{label} {amount}")
    }
}

/// How long something has been going: `42m`, `1h 05m`, `2d 03h`; Arabic
/// `42 د`, `1 س 05 د`, `2 ي 03 س`. Negative input (a clock that ran backwards)
/// reads `0m`. Seconds are dropped, never rounded up: a bill seated 59 seconds
/// ago has been seated `0m`, not `1m`.
///
/// Arabic output is meant to be laid out RIGHT-TO-LEFT (never force a `Text` to
/// LTR around it — that is how `د12` happened).
pub fn format_elapsed(secs: i64, locale: &str) -> String {
    let secs = secs.max(0);
    let mins = secs / 60;
    let hours = mins / 60;
    let days = hours / 24;
    let ar = is_arabic(locale);
    if hours == 0 {
        if ar {
            format!("{mins} د")
        } else {
            format!("{mins}m")
        }
    } else if days == 0 {
        let m = mins % 60;
        if ar {
            format!("{hours} س {m:02} د")
        } else {
            format!("{hours}h {m:02}m")
        }
    } else {
        let h = hours % 24;
        if ar {
            format!("{days} ي {h:02} س")
        } else {
            format!("{days}d {h:02}h")
        }
    }
}

const EN_MONTHS: [&str; 12] = [
    "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec",
];

/// Shared with `timefmt` — Egypt's transliterated Gregorian months.
pub(crate) const AR_MONTHS: [&str; 12] = [
    "يناير",
    "فبراير",
    "مارس",
    "أبريل",
    "مايو",
    "يونيو",
    "يوليو",
    "أغسطس",
    "سبتمبر",
    "أكتوبر",
    "نوفمبر",
    "ديسمبر",
];

/// The Gregorian months in full, for a calendar header (`September 2026`).
/// Arabic reuses [`AR_MONTHS`] — Egypt's transliterated months have no
/// separate short form.
pub(crate) const EN_MONTHS_LONG: [&str; 12] = [
    "January",
    "February",
    "March",
    "April",
    "May",
    "June",
    "July",
    "August",
    "September",
    "October",
    "November",
    "December",
];

/// Weekday column headings for a calendar, Sunday first (chrono's
/// `num_days_from_sunday`); a caller rotates them to [`crate::timefmt::WEEK_START`].
pub(crate) const EN_WEEKDAYS_SHORT: [&str; 7] =
    ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

/// [`EN_WEEKDAYS_SHORT`] in the everyday Egyptian short form.
pub(crate) const AR_WEEKDAYS_SHORT: [&str; 7] =
    ["حد", "اتنين", "تلات", "أربع", "خميس", "جمعة", "سبت"];

/// A clock time, 12-hour, in `locale`: `06:02 PM`, Arabic `06:02 م`. The hour
/// is zero-padded, like `timefmt`'s `%I:%M %p` — every time of day the app
/// shows reads the same shape. Figures stay Western; only the meridiem word
/// changes. `docs/design/SPEC.md` §Formats.
pub(crate) fn hhmm12(at: NaiveDateTime, locale: &str) -> String {
    let h24 = at.hour();
    let h = match h24 % 12 {
        0 => 12,
        h => h,
    };
    let meridiem = if h24 < 12 {
        if is_arabic(locale) {
            "ص"
        } else {
            "AM"
        }
    } else if is_arabic(locale) {
        "م"
    } else {
        "PM"
    };
    format!("{:02}:{:02} {}", h, at.minute(), meridiem)
}

/// A row's timestamp, 12-hour. Today: `06:02 PM`. This year:
/// `Sep 12 · 06:02 PM` (Arabic `12 سبتمبر · 06:02 م`). Another year:
/// `Sep 12, 2025 · 06:02 PM` (`12 سبتمبر 2025 · 06:02 م`). Both arguments are
/// wall-clock in the SAME zone.
pub fn format_stamp(at: NaiveDateTime, now: NaiveDateTime, locale: &str) -> String {
    let time = hhmm12(at, locale);
    if at.date() == now.date() {
        return time;
    }
    let m = at.month0() as usize;
    let d = at.day();
    let same_year = at.year() == now.year();
    if is_arabic(locale) {
        let month = AR_MONTHS[m];
        if same_year {
            format!("{d} {month} · {time}")
        } else {
            format!("{d} {month} {} · {time}", at.year())
        }
    } else {
        let month = EN_MONTHS[m];
        if same_year {
            format!("{month} {d} · {time}")
        } else {
            format!("{month} {d}, {} · {time}", at.year())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    const FIXTURES: &str = include_str!("../../../../docs/design/format_fixtures.json");

    fn fixtures() -> serde_json::Value {
        serde_json::from_str(FIXTURES).expect("format_fixtures.json parses")
    }

    fn naive(s: &str) -> NaiveDateTime {
        NaiveDateTime::parse_from_str(s, "%Y-%m-%dT%H:%M:%S").expect("fixture datetime")
    }

    #[test]
    fn a_clock_time_is_twelve_hour_midnight_and_noon_included() {
        let at = |h: u32, m: u32| {
            NaiveDateTime::parse_from_str(
                &format!("2026-09-12T{h:02}:{m:02}:00"),
                "%Y-%m-%dT%H:%M:%S",
            )
            .unwrap()
        };
        assert_eq!(hhmm12(at(0, 5), "en"), "12:05 AM");
        assert_eq!(hhmm12(at(9, 0), "en"), "09:00 AM");
        assert_eq!(hhmm12(at(11, 59), "en"), "11:59 AM");
        assert_eq!(hhmm12(at(12, 0), "en"), "12:00 PM");
        assert_eq!(hhmm12(at(18, 2), "en"), "06:02 PM");
        assert_eq!(hhmm12(at(23, 30), "en"), "11:30 PM");
        assert_eq!(hhmm12(at(0, 5), "ar"), "12:05 ص");
        assert_eq!(hhmm12(at(18, 2), "ar"), "06:02 م");
        // Never a 24-hour hour, in either language.
        for h in 0..24 {
            for locale in ["en", "ar"] {
                let out = hhmm12(at(h, 0), locale);
                let hour: u32 = out[..2].parse().unwrap();
                assert!((1..=12).contains(&hour), "{locale} {h} -> {out}");
            }
        }
    }

    #[test]
    fn money_matches_the_shared_fixtures() {
        for case in fixtures()["money"].as_array().unwrap() {
            let got = format_money(
                case["minor"].as_i64().unwrap(),
                case["currency"].as_str().unwrap(),
                case["locale"].as_str().unwrap(),
                case["signed"].as_bool().unwrap_or(false),
            );
            assert_eq!(got, case["out"].as_str().unwrap(), "money case {case}");
        }
    }

    #[test]
    fn currency_labels_match_the_shared_fixtures() {
        for case in fixtures()["currency"].as_array().unwrap() {
            let got = currency_label(
                case["code"].as_str().unwrap(),
                case["locale"].as_str().unwrap(),
            );
            assert_eq!(got, case["out"].as_str().unwrap(), "currency case {case}");
        }
    }

    #[test]
    fn elapsed_matches_the_shared_fixtures() {
        for case in fixtures()["elapsed"].as_array().unwrap() {
            let got = format_elapsed(
                case["secs"].as_i64().unwrap(),
                case["locale"].as_str().unwrap(),
            );
            assert_eq!(got, case["out"].as_str().unwrap(), "elapsed case {case}");
        }
    }

    #[test]
    fn stamps_match_the_shared_fixtures() {
        for case in fixtures()["stamp"].as_array().unwrap() {
            let got = format_stamp(
                naive(case["at"].as_str().unwrap()),
                naive(case["now"].as_str().unwrap()),
                case["locale"].as_str().unwrap(),
            );
            assert_eq!(got, case["out"].as_str().unwrap(), "stamp case {case}");
        }
    }

    #[test]
    fn i64_min_does_not_panic() {
        let s = format_money(i64::MIN, "EGP", "en", false);
        assert!(s.starts_with('\u{2212}'));
    }
}
