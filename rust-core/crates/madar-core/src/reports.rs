//! Dashboard analytics reads — projected KPI `View` DTOs for the management
//! dashboard app. Follows the direct-networked read pattern (see
//! `list_orders_for_shift`/`search_orders` in `lib.rs`). Money is integer minor
//! units (piastres) end-to-end — the host formats it with the session currency.
//!
//! Scope: a specific branch uses `branch_sales`; "all branches" (no branch)
//! aggregates `org_branch_comparison` — matching the web dashboard exactly.

use madar_api::models;
use serde::{Deserialize, Serialize};

/// kv/param sentinel the backend accepts for the all-branches timeseries roll-up.
pub const ALL_BRANCHES_ID: &str = "00000000-0000-0000-0000-000000000000";

/// One row of the "top items" list.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardItemSalesView {
    pub item_name: String,
    pub quantity_sold: i64,
    pub revenue_minor: i64,
}

/// One row of the category breakdown.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardCategorySalesView {
    pub category_name: String,
    pub quantity_sold: i64,
    pub revenue_minor: i64,
}

/// One slice of the payment-method mix.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardPaymentSliceView {
    pub method: String,
    pub revenue_minor: i64,
}

/// One branch in the all-branches revenue ranking.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardBranchRankView {
    pub branch_name: String,
    pub revenue_minor: i64,
}

/// One point of the revenue trend (per bucket).
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardTimePointView {
    pub period: String,
    pub revenue_minor: i64,
    pub orders: i64,
}

/// The dashboard home KPI summary for the active scope over a date window.
#[derive(Clone, Debug, Serialize, Deserialize)]
pub struct DashboardSummaryView {
    /// Empty for the all-branches roll-up (the host shows "All branches").
    pub branch_name: String,
    pub currency_code: String,
    pub from: String,
    pub to: String,
    pub total_orders: i64,
    pub voided_orders: i64,
    pub subtotal_minor: i64,
    pub total_discount_minor: i64,
    pub total_tax_minor: i64,
    pub total_revenue_minor: i64,
    /// Populated for a single branch; empty for all-branches (not available org-level).
    pub top_items: Vec<DashboardItemSalesView>,
    /// Populated for a single branch; empty for all-branches.
    pub by_category: Vec<DashboardCategorySalesView>,
    pub payment_mix: Vec<DashboardPaymentSliceView>,
    /// Populated for all-branches (branch revenue ranking); empty for a single branch.
    pub branch_ranking: Vec<DashboardBranchRankView>,
}

fn resolve_name(translations: &serde_json::Value, locale: &str, fallback: &str) -> String {
    translations
        .get(locale)
        .and_then(|v| v.as_str())
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string)
        .unwrap_or_else(|| fallback.to_string())
}

fn dt_to_rfc3339(d: Option<Option<chrono::DateTime<chrono::FixedOffset>>>) -> String {
    d.flatten().map(|x| x.to_rfc3339()).unwrap_or_default()
}

/// Coerce a JSON value to minor units — tolerates int, float, and stringified
/// decimals the backend might use for a payment total.
fn amount_minor(v: &serde_json::Value) -> i64 {
    v.as_i64()
        .or_else(|| v.as_f64().map(|f| f.round() as i64))
        .or_else(|| v.as_str().and_then(|s| s.trim().parse::<i64>().ok()))
        .unwrap_or(0)
}

/// Merge one or more `revenue_by_method` objects into descending slices.
fn merge_payment_maps<'a>(
    maps: impl Iterator<Item = &'a Option<serde_json::Value>>,
) -> Vec<DashboardPaymentSliceView> {
    use std::collections::BTreeMap;
    let mut acc: BTreeMap<String, i64> = BTreeMap::new();
    for m in maps {
        if let Some(serde_json::Value::Object(obj)) = m {
            for (k, v) in obj {
                *acc.entry(k.clone()).or_insert(0) += amount_minor(v);
            }
        }
    }
    let mut slices: Vec<DashboardPaymentSliceView> = acc
        .into_iter()
        .filter(|(_, v)| *v != 0)
        .map(|(method, revenue_minor)| DashboardPaymentSliceView {
            method,
            revenue_minor,
        })
        .collect();
    slices.sort_by(|a, b| b.revenue_minor.cmp(&a.revenue_minor));
    slices
}

/// Map a single-branch `BranchSalesReport` to the host summary DTO.
pub fn from_report(
    rep: models::BranchSalesReport,
    currency_code: String,
    locale: &str,
) -> DashboardSummaryView {
    let top_items = rep
        .top_items
        .iter()
        .map(|it| DashboardItemSalesView {
            item_name: resolve_name(&it.item_name_translations, locale, &it.item_name),
            quantity_sold: it.quantity_sold,
            revenue_minor: it.revenue,
        })
        .collect();
    let by_category = rep
        .by_category
        .iter()
        .map(|c| {
            let fallback = c.category_name.clone().flatten().unwrap_or_default();
            DashboardCategorySalesView {
                category_name: resolve_name(&c.category_name_translations, locale, &fallback),
                quantity_sold: c.quantity_sold,
                revenue_minor: c.revenue,
            }
        })
        .collect();
    let payment_mix = merge_payment_maps(std::iter::once(&rep.revenue_by_method));
    DashboardSummaryView {
        branch_name: rep.branch_name,
        currency_code,
        from: dt_to_rfc3339(rep.from),
        to: dt_to_rfc3339(rep.to),
        total_orders: rep.total_orders,
        voided_orders: rep.voided_orders,
        subtotal_minor: rep.subtotal,
        total_discount_minor: rep.total_discount,
        total_tax_minor: rep.total_tax,
        total_revenue_minor: rep.total_revenue,
        top_items,
        by_category,
        payment_mix,
        branch_ranking: Vec::new(),
    }
}

/// Aggregate an all-branches `OrgComparisonReport` into the summary DTO — the
/// same source the web dashboard uses for the all-branches roll-up. Subtotal /
/// tax / discount and item/category breakdowns aren't available org-level, so
/// they're zero/empty; the branch ranking is populated instead.
pub fn from_comparison(
    rep: models::OrgComparisonReport,
    currency_code: String,
) -> DashboardSummaryView {
    let mut total_revenue = 0i64;
    let mut total_orders = 0i64;
    let mut voided = 0i64;
    for b in &rep.branches {
        total_revenue += b.total_revenue;
        total_orders += b.total_orders;
        voided += b.voided_orders;
    }
    let payment_mix = merge_payment_maps(rep.branches.iter().map(|b| &b.revenue_by_method));
    let mut branch_ranking: Vec<DashboardBranchRankView> = rep
        .branches
        .iter()
        .map(|b| DashboardBranchRankView {
            branch_name: b.branch_name.clone(),
            revenue_minor: b.total_revenue,
        })
        .collect();
    branch_ranking.sort_by(|a, b| b.revenue_minor.cmp(&a.revenue_minor));
    DashboardSummaryView {
        branch_name: String::new(),
        currency_code,
        from: dt_to_rfc3339(rep.from),
        to: dt_to_rfc3339(rep.to),
        total_orders,
        voided_orders: voided,
        subtotal_minor: 0,
        total_discount_minor: 0,
        total_tax_minor: 0,
        total_revenue_minor: total_revenue,
        top_items: Vec::new(),
        by_category: Vec::new(),
        payment_mix,
        branch_ranking,
    }
}

/// Map wire timeseries points to host trend points.
pub fn timepoints_from(points: Vec<models::TimeseriesPoint>) -> Vec<DashboardTimePointView> {
    points
        .into_iter()
        .map(|p| DashboardTimePointView {
            period: p.period,
            revenue_minor: p.revenue,
            orders: p.orders,
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn amount_minor_handles_int_float_string() {
        assert_eq!(amount_minor(&serde_json::json!(1200)), 1200);
        assert_eq!(amount_minor(&serde_json::json!(1200.6)), 1201);
        assert_eq!(amount_minor(&serde_json::json!("1200")), 1200);
        assert_eq!(amount_minor(&serde_json::json!(null)), 0);
    }

    #[test]
    fn merge_payment_maps_sums_across_and_sorts() {
        let a = Some(serde_json::json!({ "cash": 3000, "card": 1000 }));
        let b = Some(serde_json::json!({ "cash": 2000, "card": 8000, "zero": 0 }));
        let mix = merge_payment_maps([&a, &b].into_iter());
        assert_eq!(mix.len(), 2); // zero filtered
        assert_eq!(mix[0].method, "card");
        assert_eq!(mix[0].revenue_minor, 9000);
        assert_eq!(mix[1].method, "cash");
        assert_eq!(mix[1].revenue_minor, 5000);
    }

    #[test]
    fn from_comparison_aggregates_branches_and_ranks() {
        let branch = |name: &str, rev: i64, orders: i64| models::BranchComparison {
            avg_order_value: if orders > 0 { rev / orders } else { 0 },
            branch_id: uuid::Uuid::nil(),
            branch_name: name.into(),
            cash_tips: None,
            total_tips: None,
            revenue_by_method: Some(serde_json::json!({ "cash": rev })),
            total_orders: orders,
            total_revenue: rev,
            void_rate_pct: 0.0,
            voided_orders: 1,
        };
        let rep = models::OrgComparisonReport {
            branches: vec![branch("A", 3000, 10), branch("B", 7000, 20)],
            from: None,
            org_id: uuid::Uuid::nil(),
            to: None,
        };
        let v = from_comparison(rep, "EGP".into());
        assert_eq!(v.total_revenue_minor, 10000);
        assert_eq!(v.total_orders, 30);
        assert_eq!(v.voided_orders, 2);
        assert_eq!(v.subtotal_minor, 0); // not available org-level
        assert!(v.top_items.is_empty());
        assert_eq!(v.payment_mix.len(), 1);
        assert_eq!(v.payment_mix[0].revenue_minor, 10000);
        assert_eq!(
            v.branch_ranking.first().map(|b| b.branch_name.as_str()),
            Some("B")
        );
    }
}
