//! The one canonical phone form: E.164 digits without `+` (`201001234567`).
//!
//! The rule is shared VERBATIM with the backend (Rust + SQL `phone_canonical`)
//! and the dashboard (`src/lib/phone.ts`); `phone_vectors.json` beside this
//! crate's manifest is the same file in all three repos and every
//! implementation is tested against it, so they cannot drift. Change the rule
//! in all of them or in none.

/// A raw string longer than this is not a phone number, whatever it holds.
const MAX_RAW_CHARS: usize = 32;

/// An Egyptian mobile in canonical form: `20` + `1x` + eight digits.
const EG_MOBILE_LEN: usize = 12;

/// ASCII value of an Arabic-Indic (U+0660–0669) or Extended Arabic-Indic
/// (U+06F0–06F9) digit; any other char is returned untouched.
fn ascii_digit(c: char) -> char {
    match c {
        '\u{0660}'..='\u{0669}' => char::from(b'0' + (c as u32 - 0x0660) as u8),
        '\u{06F0}'..='\u{06F9}' => char::from(b'0' + (c as u32 - 0x06F0) as u8),
        other => other,
    }
}

/// Only the digits of `raw`, Arabic numerals folded to ASCII. No validation —
/// what a search box holds while a number is still being typed.
pub fn digits(raw: &str) -> String {
    raw.chars().map(ascii_digit).filter(char::is_ascii_digit).collect()
}

/// The canonical form of `raw`, or `None` when it is not a phone number.
///
/// In order: a leading `00` is stripped; a number already starting `20` is
/// kept; a leading `0` becomes `20`; exactly ten digits starting `1` (a bare
/// Egyptian mobile) gets `20` in front; anything else is left as typed. The
/// result must be 10–15 digits, and one starting `2010`, `2011`, `2012` or
/// `2015` (an Egyptian mobile) must be exactly 12.
pub fn canonical(raw: &str) -> Option<String> {
    if raw.chars().count() > MAX_RAW_CHARS {
        return None;
    }
    let d = digits(raw);
    let out = if let Some(rest) = d.strip_prefix("00") {
        rest.to_string()
    } else if d.starts_with("20") {
        d
    } else if let Some(rest) = d.strip_prefix('0') {
        format!("20{rest}")
    } else if d.len() == 10 && d.starts_with('1') {
        format!("20{d}")
    } else {
        d
    };
    if !(10..=15).contains(&out.len()) {
        return None;
    }
    // The Egyptian mobile guard: a truncated or over-long mobile is the
    // commonest typo. Landlines (`2013…`, `202…`) are untouched.
    let mobile = ["2010", "2011", "2012", "2015"].iter().any(|p| out.starts_with(p));
    (!mobile || out.len() == EG_MOBILE_LEN).then_some(out)
}

#[cfg(test)]
mod tests {
    use super::*;

    const VECTORS: &str = include_str!("../phone_vectors.json");

    fn vectors() -> serde_json::Value {
        serde_json::from_str(VECTORS).expect("phone_vectors.json parses")
    }

    #[test]
    fn every_valid_vector_canonicalises() {
        let v = vectors();
        let valid = v["valid"].as_array().expect("valid[]");
        assert!(!valid.is_empty());
        for pair in valid {
            let (raw, want) = (pair[0].as_str().unwrap(), pair[1].as_str().unwrap());
            assert_eq!(canonical(raw).as_deref(), Some(want), "{raw:?}");
            // Canonical is a fixed point: a stored key re-canonicalises to itself.
            assert_eq!(canonical(want).as_deref(), Some(want), "{want:?} is not stable");
        }
    }

    #[test]
    fn every_invalid_vector_is_refused() {
        let v = vectors();
        let invalid = v["invalid"].as_array().expect("invalid[]");
        assert!(!invalid.is_empty());
        for raw in invalid.iter().map(|r| r.as_str().unwrap()) {
            assert_eq!(canonical(raw), None, "{raw:?}");
        }
    }

    #[test]
    fn digits_fold_arabic_numerals_without_validating() {
        assert_eq!(digits("٠١٠-۰۱"), "01001");
        assert_eq!(digits("abc"), "");
    }
}
