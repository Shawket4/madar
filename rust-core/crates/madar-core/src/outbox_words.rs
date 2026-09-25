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
/// person not being an active employee.
fn op_key(op_type: &str, code: &str) -> Option<&'static str> {
    match (op_type, code) {
        ("cash_movement", "MODULE_OFF") => Some("sync.err_advance_dawam_off"),
        ("cash_movement", "EMPLOYEE_INACTIVE") => Some("sync.err_advance_inactive"),
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

    /// The lifecycle's refused move (409 TABLE_DIRTY, a code the core has no
    /// words for) reached an English till as "The server refused it": the
    /// server writes English, so an English device reads its own sentence,
    /// and only an Arabic one the sentence for the kind of refusal.
    #[test]
    fn with_no_words_of_its_own_an_english_device_reads_the_servers_sentence() {
        let dirty = r#"{"error":"Table has not been cleared since the last party","code":"TABLE_DIRTY"}"#;
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
