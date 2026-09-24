//! A queued op the server refused, worded for the person at the till in the
//! till's language (E2E posnotif B-POS-6).
//!
//! The Sync list of an Arabic till read "the server does not have what this
//! needs yet — Not found: Employee not found", and a coded refusal (a tagged
//! pay-out with Dawam switched off) showed the server's raw JSON. The stuck
//! row now says why in the till's language: the core's words for the server's
//! code when it has them, otherwise a plain sentence for the kind of refusal.
//! The server's own text is kept for the diagnostics, never shown here.

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
}
