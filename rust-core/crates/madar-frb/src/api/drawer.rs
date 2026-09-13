//! Drawer and Orders decisions (madar-core `till_views`): payment method names,
//! the refund method plan, the close count, the drawer's cash-sales line and a
//! sale's tax inclusivity. Binding code only.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;
use crate::api::till::TillReportView;

pub use madar_core::till_views::{CloseCountCheck, PaymentMethodChoice, RefundMethodPlan};

/// One way money can go back: the wire code and its name.
#[frb(mirror(PaymentMethodChoice))]
pub struct _PaymentMethodChoice {
    pub code: String,
    pub label: String,
    pub is_cash: bool,
}

/// How a refund of one sale may be paid back.
#[frb(mirror(RefundMethodPlan))]
pub struct _RefundMethodPlan {
    pub options: Vec<PaymentMethodChoice>,
    /// The sale's own method when the server accepts it; `None` → choose.
    pub default_code: Option<String>,
    /// The sale predates the open shift: the refund leaves today's drawer.
    pub crosses_till: bool,
}

/// What a close count means against the expected drawer.
#[frb(mirror(CloseCountCheck))]
pub struct _CloseCountCheck {
    pub entered: bool,
    pub variance_minor: i64,
    /// `pending` · `matches` · `over` · `short`.
    pub verdict: String,
    pub needs_reason: bool,
}

impl MadarBridge {
    /// A payment method code in the till's language — never a raw code.
    #[frb(sync)]
    pub fn payment_method_label(&self, code: String) -> String {
        self.inner.payment_method_label(code)
    }

    /// The methods a refund of this sale may go back by, the sale's own when
    /// allowed, and whether the refund lands in a later shift than the sale.
    #[frb(sync)]
    pub fn refund_method_plan(
        &self,
        order_payment_method: String,
        order_created_at: String,
    ) -> Result<RefundMethodPlan, MadarError> {
        self.inner
            .refund_method_plan(order_payment_method, order_created_at)
            .map_err(MadarError::from)
    }

    /// The close count against the expected drawer (`None` = not counted).
    #[frb(sync)]
    pub fn close_count_check(&self, expected_minor: i64, counted_minor: Option<i64>) -> CloseCountCheck {
        madar_core::till_views::close_count_check(expected_minor, counted_minor)
    }

    /// The drawer arithmetic's cash-sales line, closed on the report's figure.
    #[frb(sync)]
    pub fn till_cash_sales_minor(&self, report: TillReportView) -> i64 {
        madar_core::till_views::cash_sales_minor(&report)
    }

    /// Whether a settled sale's tax was included, from its own figures.
    #[frb(sync)]
    pub fn sale_tax_inclusive(
        &self,
        subtotal_minor: i64,
        discount_minor: i64,
        service_minor: i64,
        delivery_minor: i64,
        tax_minor: i64,
        total_minor: i64,
    ) -> bool {
        madar_core::till_views::sale_tax_inclusive(
            subtotal_minor,
            discount_minor,
            service_minor,
            delivery_minor,
            tax_minor,
            total_minor,
        )
    }
}
