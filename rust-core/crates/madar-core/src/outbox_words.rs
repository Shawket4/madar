//! A queued op the server refused, worded for the person at the till in the
//! till's language (E2E posnotif B-POS-6).
//!
//! The Sync list of an Arabic till read "the server does not have what this
//! needs yet — Not found: Employee not found", and a coded refusal (a tagged
//! pay-out with Dawam switched off) showed the server's raw JSON. The stuck
//! row now says why in the till's language: the core's words for the server's
//! code when it has them. Otherwise the server writes English: an English
//! device reads the server's own sentence ("Table has not been cleared since
//! the last party"), an Arabic one a plain sentence for the kind of refusal.
//! The same rule words a refused queued Dawam punch (`dawam_refusal`).

use crate::i18n;

/// The reason shown for a queued `op_type` the server refused with `status`
/// and `body` (its `{error, code, vars}` envelope), in `locale`.
pub(crate) fn refusal(locale: &str, op_type: &str, status: u16, body: &str) -> String {
    if let Some(code) = crate::net::extract_error_code(body) {
        if let Some(key) = op_key(op_type, &code) {
            return i18n::tr(locale, key);
        }
        // The core's words for the code itself, when it has any that need
        // no figures: `sync.err_<code>`, then the till's `err.<code>`.
        let lower = code.to_lowercase();
        for key in [format!("sync.err_{lower}"), format!("err.{lower}")] {
            let words = i18n::tr(locale, &key);
            if words != key && !words.contains('{') {
                return words;
            }
        }
    }
    if let Some(said) = crate::net::extract_error_message(body).and_then(|m| server_sentence(locale, status, &m)) {
        return said;
    }
    i18n::tr(
        locale,
        match (status, op_type) {
            (404, "void_order") => "sync.err_sale_missing",
            (404, _) => "sync.err_missing",
            (401 | 403, _) => "err.not_allowed",
            _ => "sync.refused",
        },
    )
}

/// The server's own sentence for a refusal the core has no words for, when
/// the device reads English (the server writes English), without the HTTP
/// kind it leads with ("Conflict: …"). `None` on an Arabic device, which reads
/// the core's sentence for the kind of refusal (B-POS-6); for a 404, whose text
/// names what is missing ("Not found: Employee not found") and reads better as
/// the core's "missing" sentence; and for a bare HTTP reason (a proxy's page).
pub(crate) fn server_sentence(locale: &str, status: u16, said: &str) -> Option<String> {
    if i18n::is_arabic(locale) || status == 404 {
        return None;
    }
    let said = crate::dawam::plain_sentence(said.trim());
    (!said.is_empty() && !crate::net::is_reason_phrase(&said)).then_some(said)
}

/// A code whose words depend on what was queued: the till's pay-out tagged
/// as someone's expense advance is refused for Dawam being off or for the
/// person not being an active employee; a paid bill refuses a line void
/// differently from a void of the whole bill; a bill fired under a booking
/// that is no longer active is the bill that did not land.
fn op_key(op_type: &str, code: &str) -> Option<&'static str> {
    match (op_type, code) {
        ("cash_movement", "MODULE_OFF") => Some("sync.err_advance_dawam_off"),
        ("cash_movement", "EMPLOYEE_INACTIVE") => Some("sync.err_advance_inactive"),
        ("void_ticket_line", "TICKET_SETTLED") => Some("sync.err_line_bill_settled"),
        ("open_ticket", "BOOKING_NOT_ACTIVE") => Some("sync.err_fire_booking_not_active"),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::refusal;
    use crate::i18n::tr;

    #[test]
    fn a_code_the_core_has_words_for_is_said_in_them() {
        let body = r#"{"error":"Cash movements can only be added to an open till","code":"TILL_NOT_OPEN"}"#;
        for locale in ["en", "ar"] {
            assert_eq!(
                refusal(locale, "cash_movement", 400, body),
                tr(locale, "sync.err_till_not_open")
            );
        }
        let body = r#"{"error":"Pick another method","code":"PAYMENT_METHOD_UNAVAILABLE"}"#;
        assert_eq!(
            refusal("ar", "create_order", 422, body),
            tr("ar", "err.payment_method_unavailable")
        );
    }

    #[test]
    fn a_refusal_without_words_is_a_plain_sentence_in_the_tills_language() {
        let conflict = r#"{"error":"Conflict: something English","code":"SOMETHING_NEW"}"#;
        assert_eq!(
            refusal("ar", "create_order", 409, conflict),
            tr("ar", "sync.refused")
        );
        assert_eq!(
            refusal("ar", "void_order", 404, r#"{"error":"Not found: Order"}"#),
            tr("ar", "sync.err_sale_missing")
        );
        assert_eq!(
            refusal("ar", "record_waste", 403, r#"{"error":"Forbidden"}"#),
            tr("ar", "err.not_allowed")
        );
        // A proxy's HTML page is not our server's words either.
        assert_eq!(
            refusal("en", "cash_movement", 404, "<html>nope</html>"),
            tr("en", "sync.err_missing")
        );
    }

    /// Every loyalty award code is worded for a stuck row, in both languages,
    /// from the same keys the teller who pressed the button was shown.
    #[test]
    fn a_stuck_award_says_why_in_both_languages() {
        for (code, key) in crate::loyalty::AWARD_REFUSAL_CODES {
            let body = format!(r#"{{"error":"Conflict: x","code":"{code}"}}"#);
            for (status, locale) in [(409, "en"), (404, "en"), (409, "ar"), (404, "ar")] {
                let said = refusal(locale, "award_loyalty_points", status, &body);
                assert_eq!(said, tr(locale, key), "{code} {locale}");
                assert!(!said.starts_with("sync."), "{code} {locale}: {said}");
            }
        }
        // An older server sends no code: today's wording.
        let old = r#"{"error":"Conflict: That sale was voided — it earns no points"}"#;
        assert_eq!(
            refusal("en", "award_loyalty_points", 409, old),
            "That sale was voided — it earns no points"
        );
        assert_eq!(refusal("ar", "award_loyalty_points", 409, old), tr("ar", "sync.refused"));
    }

    /// The birthday-gift and stamp-track refusals a sale can meet are worded
    /// in both languages (the server's 409 codes).
    #[test]
    fn a_gift_or_track_refusal_says_why_in_both_languages() {
        for code in [
            "LOYALTY_GIFT_NONE",
            "LOYALTY_GIFT_NOT_A_REWARD",
            "LOYALTY_GIFT_LINE",
            "LOYALTY_TRACK_UNKNOWN",
            "LOYALTY_TRACK_BALANCE_SHORT",
            "LOYALTY_TRACK_NOT_ON_OFFER",
        ] {
            let body = format!(r#"{{"error":"Conflict: x","code":"{code}"}}"#);
            let key = format!("sync.err_{}", code.to_lowercase());
            for locale in ["en", "ar"] {
                let said = refusal(locale, "create_order", 409, &body);
                assert_eq!(said, tr(locale, &key), "{code} {locale}");
                assert!(!said.starts_with("sync."), "{code} {locale}: {said}");
            }
        }
    }

    /// Every coded refusal a queued op can meet through `/sync/replay` is
    /// worded in both languages, and an older server's uncoded 409 keeps
    /// today's wording: its own sentence in English, the plain one in Arabic.
    #[test]
    fn a_coded_replay_refusal_says_why_in_both_languages() {
        let cases = [
            ("refund_order", "ORDER_FULLY_REFUNDED", "sync.err_order_fully_refunded"),
            ("void_order", "ORDER_REFUNDED", "sync.err_order_refunded"),
            ("cash_movement", "CASH_ALREADY_CORRECTED", "sync.err_cash_already_corrected"),
            ("void_ticket", "TICKET_SETTLED", "sync.err_ticket_settled"),
            ("void_ticket_line", "TICKET_SETTLED", "sync.err_line_bill_settled"),
            ("open_ticket", "BOOKING_NOT_ACTIVE", "sync.err_fire_booking_not_active"),
            ("open_ticket", "BOOKING_OTHER_BRANCH", "sync.err_booking_other_branch"),
            ("seat_booking", "BOOKING_NOT_ACTIVE", "sync.err_booking_not_active"),
            ("seat_booking", "BOOKING_SEATED_ELSEWHERE", "sync.err_booking_seated_elsewhere"),
            ("no_show_booking", "BOOKING_SEATED", "sync.err_booking_seated"),
            ("hold_table", "TABLE_HELD", "sync.err_table_held"),
            ("hold_table", "TABLE_DIRTY", "sync.err_table_dirty"),
            ("clear_table", "TABLE_OCCUPIED", "sync.err_table_occupied"),
            ("fulfill_table_transfer", "TICKET_NOT_LIVE", "sync.err_ticket_not_live"),
            ("create_table_transfer", "TRANSFER_EXISTS", "sync.err_transfer_exists"),
            ("fulfill_table_transfer", "TRANSFER_CANCELLED", "sync.err_transfer_cancelled"),
            ("cancel_table_transfer", "TRANSFER_FULFILLED", "sync.err_transfer_fulfilled"),
        ];
        for (op, code, key) in cases {
            let body = format!(r#"{{"error":"Conflict: x","code":"{code}"}}"#);
            for locale in ["en", "ar"] {
                let said = refusal(locale, op, 409, &body);
                assert_eq!(said, tr(locale, key), "{op} {code} {locale}");
                assert!(!said.starts_with("sync."), "{op} {code} {locale}: {said}");
            }
        }
        let old = r#"{"error":"Conflict: This order has already been refunded in full"}"#;
        assert_eq!(
            refusal("en", "refund_order", 409, old),
            "This order has already been refunded in full"
        );
        assert_eq!(refusal("ar", "refund_order", 409, old), tr("ar", "sync.refused"));
    }

    /// The lifecycle's refused move (409 with a code the core had no words
    /// for, as TABLE_DIRTY once was) reached an English till as "The server
    /// refused it": the server writes English, so an English device reads its
    /// own sentence, and only an Arabic one the sentence for the kind of
    /// refusal.
    #[test]
    fn with_no_words_of_its_own_an_english_device_reads_the_servers_sentence() {
        let dirty = r#"{"error":"Table has not been cleared since the last party","code":"TABLE_SOMETHING_NEW"}"#;
        assert_eq!(
            refusal("en", "move_party", 409, dirty),
            "Table has not been cleared since the last party"
        );
        assert_eq!(refusal("ar", "move_party", 409, dirty), tr("ar", "sync.refused"));
        // Uncoded: the server's kind in front is not part of the sentence.
        let closed = r#"{"error":"Conflict: The till is already closed"}"#;
        assert_eq!(refusal("en", "cash_movement", 409, closed), "The till is already closed");
        assert_eq!(refusal("ar", "cash_movement", 409, closed), tr("ar", "sync.refused"));
        // A 404 names what is missing: the core's sentence, in English too.
        let gone = r#"{"error":"Not found: Employee not found"}"#;
        assert_eq!(refusal("en", "cash_movement", 404, gone), tr("en", "sync.err_missing"));
        // Not our envelope, or nothing but an HTTP reason: no sentence of the server's.
        assert_eq!(refusal("en", "cash_movement", 400, "<html>nope</html>"), tr("en", "sync.refused"));
        assert_eq!(refusal("en", "cash_movement", 409, r#"{"error":"Conflict"}"#), tr("en", "sync.refused"));
    }
}
