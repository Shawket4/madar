//! What the till's drawer and Orders screens DECIDE, kept out of Dart.
//!
//! A payment method's name in the teller's language, which methods a refund
//! may go back by (and whether the sale's own method is one of them), whether
//! a refund lands in a later shift than its sale, what a close count means
//! against the expected drawer, the cash-sales line of the drawer arithmetic,
//! and whether an old sale's tax was inclusive — each of these used to be
//! worked out on the screen, from today's settings or from raw codes.

use crate::menu::{self, CachedPaymentMethod};
use crate::{i18n, till, CoreError, MadarCore};

/// One way money can go back: the wire code the server checks, and its name.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct PaymentMethodChoice {
    /// The org's method name as the server knows it (`cash`, `card`, …).
    pub code: String,
    /// The name in the till's language.
    pub label: String,
    pub is_cash: bool,
}

/// How a refund of one sale may be paid back.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct RefundMethodPlan {
    /// The org's active methods — what the server will accept.
    pub options: Vec<PaymentMethodChoice>,
    /// The sale's own method when it is one of [options]; `None` when the
    /// sale was split (`mixed`), came through an aggregator, or its method
    /// is gone — the teller must choose, the till never guesses.
    pub default_code: Option<String>,
    /// The sale was rung before the open shift began: the money leaves
    /// TODAY's drawer, and the teller should be told so.
    pub crosses_till: bool,
}

/// What a close count means against the expected drawer.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CloseCountCheck {
    /// A count has been entered.
    pub entered: bool,
    /// counted − expected (0 until entered).
    pub variance_minor: i64,
    /// `pending` (nothing counted) · `matches` · `over` · `short`.
    pub verdict: String,
    /// A closing reason is required.
    pub needs_reason: bool,
}

/// The close count against [expected_minor]. Nothing entered is `pending`,
/// never "short by the whole float".
pub fn close_count_check(expected_minor: i64, counted_minor: Option<i64>) -> CloseCountCheck {
    match counted_minor {
        None => CloseCountCheck {
            entered: false,
            variance_minor: 0,
            verdict: "pending".into(),
            needs_reason: false,
        },
        Some(counted) => {
            let variance = counted - expected_minor;
            CloseCountCheck {
                entered: true,
                variance_minor: variance,
                verdict: match variance {
                    0 => "matches",
                    v if v > 0 => "over",
                    _ => "short",
                }
                .into(),
                needs_reason: variance != 0,
            }
        }
    }
}

/// A movement's kind as the wire names it, falling back on the sign for a
/// row that predates kinds.
pub(crate) fn movement_kind(kind: Option<&str>, amount_minor: i64) -> String {
    match kind.map(str::trim).filter(|k| !k.is_empty()) {
        Some(k) => k.to_string(),
        None if amount_minor >= 0 => "pay_in".into(),
        None => "pay_out".into(),
    }
}

/// The "cash sales" line of the drawer arithmetic — the remainder of the
/// report's own expected figure once the float and the pay-ins/outs are
/// taken out, so the lines always add up to the figure above them (offline
/// too, when it is the queued cash the core added).
pub fn cash_sales_minor(report: &till::TillReportView) -> i64 {
    report.expected_cash_minor - report.opening_cash_minor - report.cash_in_minor
        + report.cash_out_minor
}

/// Whether a settled sale's tax was INCLUDED in its prices, read from the
/// sale's own figures rather than today's branch setting: an inclusive sale
/// totals what the lines cost (less discount, plus service and delivery);
/// an exclusive one adds the tax on top. A sale with no tax is neither, and
/// reads as exclusive (no "included" claim is made).
pub fn sale_tax_inclusive(
    subtotal_minor: i64,
    discount_minor: i64,
    service_minor: i64,
    delivery_minor: i64,
    tax_minor: i64,
    total_minor: i64,
) -> bool {
    if tax_minor <= 0 {
        return false;
    }
    let before_tax = subtotal_minor - discount_minor + service_minor + delivery_minor;
    total_minor != before_tax + tax_minor && total_minor == before_tax
}

/// A payment method code in [locale]: the org's own translated label when
/// the catalog knows it, the core's word for a split (`mixed`), otherwise the
/// code made readable — never `talabat_online` in front of a teller.
pub(crate) fn method_label(methods: &[CachedPaymentMethod], code: &str, locale: &str) -> String {
    let trimmed = code.trim();
    if let Some(m) = methods
        .iter()
        .find(|m| m.name.eq_ignore_ascii_case(trimmed))
    {
        return menu::resolve(
            m.label_translations
                .as_ref()
                .unwrap_or(&serde_json::Value::Null),
            &m.name,
            locale,
        );
    }
    let key = format!("payment.{}", trimmed.to_ascii_lowercase());
    let word = i18n::tr(locale, &key);
    if word != key {
        return word;
    }
    humanize(trimmed)
}

/// `digital_wallet` → `Digital wallet`.
fn humanize(code: &str) -> String {
    let spaced = code.replace(['_', '-'], " ");
    let mut chars = spaced.trim().chars();
    match chars.next() {
        Some(first) => first.to_uppercase().collect::<String>() + chars.as_str(),
        None => String::new(),
    }
}

/// The refund plan for a sale paid by [order_method] at [order_created_at],
/// given the org's methods and the open shift's start.
pub(crate) fn refund_plan(
    methods: &[CachedPaymentMethod],
    order_method: &str,
    order_created_at: &str,
    shift_opened_at: Option<&str>,
    locale: &str,
) -> RefundMethodPlan {
    let options: Vec<PaymentMethodChoice> = methods
        .iter()
        .filter(|m| m.is_active)
        .map(|m| PaymentMethodChoice {
            code: m.name.clone(),
            label: method_label(methods, &m.name, locale),
            is_cash: m.is_cash,
        })
        .collect();
    let default_code = options
        .iter()
        .find(|o| o.code.eq_ignore_ascii_case(order_method.trim()))
        .map(|o| o.code.clone());
    let parse = |s: &str| chrono::DateTime::parse_from_rfc3339(s).ok();
    let crosses_till = match (parse(order_created_at), shift_opened_at.and_then(parse)) {
        (Some(sale), Some(opened)) => sale < opened,
        _ => false,
    };
    RefundMethodPlan {
        options,
        default_code,
        crosses_till,
    }
}

impl MadarCore {
    /// A payment method code (as on an order, a refund or a report line) in
    /// the till's language.
    pub fn payment_method_label(&self, code: String) -> String {
        let methods = menu::cached_payment_methods(&self.store).unwrap_or_default();
        method_label(&methods, &code, &self.current_locale())
    }

    /// How a refund of a sale may go back, whether the sale's own method is
    /// one of them, and whether the refund lands in a later shift.
    pub fn refund_method_plan(
        &self,
        order_payment_method: String,
        order_created_at: String,
    ) -> Result<RefundMethodPlan, CoreError> {
        let methods = menu::cached_payment_methods(&self.store)?;
        let open = till::current(&self.store)?.filter(|s| s.is_open);
        Ok(refund_plan(
            &methods,
            &order_payment_method,
            &order_created_at,
            open.as_ref().map(|s| s.opened_at.as_str()),
            &self.current_locale(),
        ))
    }
}

impl MadarCore {
    /// Every page of a shift's synced orders. The list endpoint caps a page
    /// (200), so a busy shift used to show — and count — only its first 200
    /// sales. `None` when any page fails, so the caller falls back to the
    /// cached snapshot rather than caching a partial list as the whole shift.
    pub(crate) async fn fetch_shift_orders_all_pages(
        &self,
        branch_id: &str,
        till_id: &str,
    ) -> Option<Vec<crate::orders::OrderSummaryView>> {
        use madar_api::apis::orders_api;
        /// A guard, not a business rule: 50 × 200 sales is past any shift.
        const MAX_PAGES: i64 = 50;
        let mut views = Vec::new();
        let mut page = 1i64;
        loop {
            let params = orders_api::ListOrdersParams {
                branch_id: Some(branch_id.to_string()),
                shift_id: Some(till_id.to_string()),
                updated_after: None,
                page: Some(page),
                per_page: Some(200),
                teller_name: None,
                waiter_name: None,
                payment_method: None,
                status: None,
                from: None,
                to: None,
                order_type: None,
                exclude_items: None,
                channel: None,
                include_items: Some(true),
            };
            let resp = orders_api::list_orders(&self.api.config(), params)
                .await
                .ok()?;
            // Do NOT preload these into cache:order:{id}: the list element is
            // models::Order (no items), not the OrderFull an offline reprint reads.
            views.extend(resp.data.iter().map(crate::orders::from_server));
            if page >= resp.total_pages || resp.data.is_empty() || page >= MAX_PAGES {
                break;
            }
            page += 1;
        }
        Some(views)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn method(name: &str, cash: bool, active: bool, ar: Option<&str>) -> CachedPaymentMethod {
        serde_json::from_value(json!({
            "id": uuid::Uuid::new_v4(),
            "name": name,
            "is_cash": cash,
            "is_active": active,
            "label_translations": ar.map(|a| json!({"ar": a, "en": name})),
        }))
        .unwrap()
    }

    fn methods() -> Vec<CachedPaymentMethod> {
        vec![
            method("cash", true, true, Some("نقدي")),
            method("card", false, true, Some("بطاقة")),
            method("old_voucher", false, false, None),
        ]
    }

    #[test]
    fn a_cash_sale_refunds_by_cash_by_default() {
        let plan = refund_plan(&methods(), "cash", "2026-09-12T19:00:00Z", None, "en");
        assert_eq!(plan.default_code.as_deref(), Some("cash"));
        assert_eq!(plan.options.len(), 2, "inactive methods are not offered");
    }

    #[test]
    fn a_split_or_aggregator_sale_has_no_default_method() {
        for code in ["mixed", "talabat_online", "old_voucher"] {
            let plan = refund_plan(&methods(), code, "2026-09-12T19:00:00Z", None, "en");
            assert_eq!(
                plan.default_code, None,
                "{code} must be chosen, not guessed"
            );
        }
    }

    #[test]
    fn method_codes_match_case_insensitively() {
        let plan = refund_plan(&methods(), "Card", "2026-09-12T19:00:00Z", None, "en");
        assert_eq!(plan.default_code.as_deref(), Some("card"));
    }

    #[test]
    fn a_sale_from_before_the_shift_crosses_it() {
        let opened = Some("2026-09-13T08:00:00+02:00");
        let old = refund_plan(&methods(), "cash", "2026-09-12T19:00:00Z", opened, "en");
        assert!(old.crosses_till);
        let today = refund_plan(&methods(), "cash", "2026-09-13T09:00:00Z", opened, "en");
        assert!(!today.crosses_till);
    }

    #[test]
    fn labels_are_localized_and_never_raw_codes() {
        let m = methods();
        assert_eq!(method_label(&m, "card", "ar"), "بطاقة");
        assert_eq!(method_label(&m, "mixed", "en"), "Split");
        assert_eq!(
            method_label(&m, "mixed", "ar"),
            i18n::tr("ar", "payment.mixed")
        );
        assert_eq!(method_label(&m, "digital_wallet", "en"), "Digital wallet");
    }

    #[test]
    fn a_blank_count_is_pending_not_short() {
        let c = close_count_check(238_000, None);
        assert_eq!(c.verdict, "pending");
        assert!(!c.needs_reason);
        assert!(!c.entered);
        assert_eq!(close_count_check(100, Some(100)).verdict, "matches");
        let short = close_count_check(100, Some(0));
        assert_eq!(
            (short.verdict.as_str(), short.variance_minor),
            ("short", -100)
        );
        assert!(short.needs_reason);
        assert_eq!(close_count_check(100, Some(150)).verdict, "over");
    }

    #[test]
    fn tax_inclusivity_comes_from_the_sale_not_todays_setting() {
        // Inclusive: 12% service on a 10 000 bill, VAT inside the prices.
        assert!(sale_tax_inclusive(10_000, 0, 1_200, 0, 1_228, 11_200));
        // Exclusive: 14% added on top of 2 000.
        assert!(!sale_tax_inclusive(2_000, 0, 0, 0, 280, 2_280));
        // No tax: no claim either way.
        assert!(!sale_tax_inclusive(2_000, 0, 0, 0, 0, 2_000));
    }
}
