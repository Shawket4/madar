//! Deals on the till (COMBOS_CONTRACT §5, §6; COMBOS_DESIGN C8, C17).
//!
//! A deal rule (mix & match, multi-buy) is evaluated over the cart by
//! madar-shared's `madar_catalog::deal` — the server's own copy. On the till
//! it is only ever SUGGESTED: the cart shows "this order qualifies for X" and
//! the teller taps to apply it (C8). An application is stored on the cart
//! (kv, per context) by the lines' keys; its discount is spread over its
//! units by price and lands on each line as its `deal_cut`.
//!
//! A cart edit that breaks an application — a line gone, fewer units than it
//! claimed, a price that moved, the deal switched off or out of its window —
//! drops it ([`settle`]); the host hears why through
//! `take_deal_notices` (`deal.dropped`), toasted by the shell.
//!
//! Only plain lines take part (never a combo, a staff drink or a reward), and
//! a deal covers the item price at its size: add-ons always pay. A deal rides
//! a COUNTER sale only: a table's cart becomes a ticket's round, and the
//! ticket API carries no deals (the same rule as a staff drink).

use std::collections::HashMap;

use madar_catalog::deal::{self as rule, DealContext, DealLine, DealView, LineUnits, UsedDeal};
use madar_catalog::sale_window::LocalNow;
use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::cart::{self, Ctx};
use crate::error::{CoreError, CoreResult};
use crate::i18n;
use crate::menu::{self, MenuItemView};
use crate::store::Store;

/// kv key (per cart context): the applications, JSON `Vec<StoredApp>`.
pub(crate) const K_APPS: &str = "cart:deals";

/// How many suggestions the cart shows at once (contract §5: the top 3).
pub const SHOWN: usize = 3;

/// An applied deal on a cart.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct StoredApp {
    /// Client-minted.
    pub id: String,
    pub deal_id: String,
    pub name: String,
    pub times: i64,
    pub discount: i64,
    pub lines: Vec<StoredAppLine>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(crate) struct StoredAppLine {
    /// The cart line's key.
    pub key: String,
    pub units: i64,
    /// This application's cut of the line.
    pub discount: i64,
}

/// A deal the cart qualifies for, never applied until the teller taps it.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DealSuggestion {
    pub deal_id: String,
    pub name: String,
    pub times: i64,
    /// "Applies twice", in the teller's language (PLURAL FORMS).
    pub times_label: String,
    pub saving_minor: i64,
    /// The cart lines it would take units of.
    pub line_keys: Vec<String>,
}

/// A deal applied on the cart.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AppliedDealView {
    /// Pass to `cart_remove_deal`.
    pub id: String,
    pub deal_id: String,
    pub name: String,
    pub times: i64,
    pub discount_minor: i64,
    pub line_keys: Vec<String>,
}

/// The branch's deal rules from the mirror (`deal_rule` feed rows, already
/// branch-resolved), their names in `locale`. A row that does not parse is
/// skipped.
pub(crate) fn rules(store: &Store, locale: &str) -> Vec<DealView> {
    let rows: Vec<Value> = store
        .kv_get(menu::K_DEALS)
        .ok()
        .flatten()
        .and_then(|j| serde_json::from_str(&j).ok())
        .unwrap_or_default();
    rows.into_iter()
        .filter(|r| r.get("deleted_at").is_none_or(Value::is_null))
        .filter_map(|r| {
            let names = r.get("name_translations").cloned().unwrap_or(Value::Null);
            let mut d: DealView = serde_json::from_value(r).ok()?;
            d.name = menu::resolve(&names, &d.name, locale);
            Some(d)
        })
        .collect()
}

pub(crate) fn load_apps(store: &Store, ctx: Ctx<'_>) -> Vec<StoredApp> {
    store
        .kv_get(&cart::key_for(ctx, K_APPS))
        .ok()
        .flatten()
        .and_then(|j| serde_json::from_str(&j).ok())
        .unwrap_or_default()
}

fn save_apps(store: &Store, ctx: Ctx<'_>, apps: &[StoredApp]) -> CoreResult<()> {
    store.kv_put(&cart::key_for(ctx, K_APPS), &serde_json::to_string(apps)?)?;
    // Each line carries the sum of its cuts (and the last deal's name).
    let mut cuts: HashMap<String, (i64, String)> = HashMap::new();
    for a in apps {
        for l in &a.lines {
            let e = cuts.entry(l.key.clone()).or_insert((0, String::new()));
            e.0 += l.discount;
            e.1 = a.name.clone();
        }
    }
    cart::set_deal_cuts(store, ctx, &cuts)
}

/// The applications as a held order parks them (`cart_payload`).
pub(crate) fn apps_json(store: &Store, ctx: Ctx<'_>) -> Value {
    serde_json::to_value(load_apps(store, ctx)).unwrap_or(Value::Array(vec![]))
}

/// Put a parked order's applications back (`set_cart_payload`). The lines
/// came back with their cuts; the next [`settle`] re-checks both.
pub(crate) fn restore_apps(store: &Store, ctx: Ctx<'_>, v: Option<&Value>) -> CoreResult<()> {
    let apps: Vec<StoredApp> = v
        .cloned()
        .and_then(|v| serde_json::from_value(v).ok())
        .unwrap_or_default();
    store.kv_put(&cart::key_for(ctx, K_APPS), &serde_json::to_string(&apps)?)
}

/// Forget every application of a context (the cart was emptied).
pub(crate) fn clear(store: &Store, ctx: Ctx<'_>) -> CoreResult<()> {
    store.kv_put(&cart::key_for(ctx, K_APPS), "[]")
}

/// The applications of a context, as the host lists them.
pub(crate) fn applied(store: &Store, ctx: Ctx<'_>) -> Vec<AppliedDealView> {
    load_apps(store, ctx)
        .into_iter()
        .map(|a| AppliedDealView {
            line_keys: a.lines.iter().map(|l| l.key.clone()).collect(),
            id: a.id,
            deal_id: a.deal_id,
            name: a.name,
            times: a.times,
            discount_minor: a.discount,
        })
        .collect()
}

/// Where and when: the branch and its wall clock.
pub(crate) struct When<'a> {
    pub branch_id: Option<&'a str>,
    pub now: &'a LocalNow,
    /// The channel switch (§11: deals follow the combos' switches). Off = no
    /// suggestion and no application on the till.
    pub pos_on: bool,
}

/// The eligible lines with the units `claimed` leaves free, by cart position.
fn deal_lines(
    cands: &[cart::DealCandidate],
    items: &[MenuItemView],
    claimed: &HashMap<String, i64>,
) -> Vec<DealLine> {
    cands
        .iter()
        .filter(|c| c.eligible)
        .filter_map(|c| {
            let free = c.qty - claimed.get(&c.key).copied().unwrap_or(0);
            (free > 0).then(|| DealLine {
                line_index: c.index,
                menu_item_id: c.item_id.clone(),
                category_id: items
                    .iter()
                    .find(|i| i.id == c.item_id)
                    .and_then(|i| i.category_id.clone()),
                size_label: c.size_label.clone(),
                unit_price: c.unit_price_minor,
                quantity: free,
            })
        })
        .collect()
}

fn claimed_by(apps: &[StoredApp]) -> HashMap<String, i64> {
    let mut out = HashMap::new();
    for a in apps {
        for l in &a.lines {
            *out.entry(l.key.clone()).or_insert(0) += l.units;
        }
    }
    out
}

fn context(when: &When<'_>, apps: &[StoredApp]) -> DealContext {
    DealContext {
        branch_id: when.branch_id.map(str::to_string),
        now: when.now.clone(),
        used: apps
            .iter()
            .map(|a| UsedDeal {
                deal_id: a.deal_id.clone(),
                times: a.times,
            })
            .collect(),
    }
}

fn key_at(cands: &[cart::DealCandidate], index: usize) -> Option<String> {
    cands.iter().find(|c| c.index == index).map(|c| c.key.clone())
}

/// What the cart qualifies for now, best first (the top [`SHOWN`]).
pub(crate) fn suggest(
    store: &Store,
    ctx: Ctx<'_>,
    deals: &[DealView],
    items: &[MenuItemView],
    when: &When<'_>,
    locale: &str,
) -> CoreResult<Vec<DealSuggestion>> {
    // A deal rides a counter sale only: a table's cart becomes a ticket's
    // round, and a ticket carries no deal (as it carries no staff drink).
    if !when.pos_on || ctx.is_some() || deals.is_empty() {
        return Ok(Vec::new());
    }
    let apps = load_apps(store, ctx);
    let cands = cart::deal_candidates(store, ctx)?;
    let lines = deal_lines(&cands, items, &claimed_by(&apps));
    Ok(rule::suggest(deals, &lines, &context(when, &apps))
        .into_iter()
        .take(SHOWN)
        .filter_map(|s| {
            let d = deals.iter().find(|d| d.id == s.deal_id)?;
            Some(DealSuggestion {
                deal_id: s.deal_id.clone(),
                name: d.name.clone(),
                times: s.times,
                times_label: i18n::tr_count(locale, "deal.applies_times", s.times)
                    .replace("{count}", &s.times.to_string()),
                saving_minor: s.saving,
                line_keys: s
                    .units
                    .iter()
                    .filter_map(|u| key_at(&cands, u.line_index))
                    .collect(),
            })
        })
        .collect())
}

/// Apply `deal_id` the best way the cart allows now (the suggestion the
/// teller tapped). Refused (`deal.not_eligible`, the whole sentence in the
/// till's language) when it no longer saves anything.
pub(crate) fn apply(
    store: &Store,
    ctx: Ctx<'_>,
    deal_id: &str,
    deals: &[DealView],
    items: &[MenuItemView],
    when: &When<'_>,
    locale: &str,
) -> CoreResult<()> {
    let refuse = || CoreError::Validation {
        field: String::new(),
        detail: i18n::tr(locale, "deal.not_eligible"),
    };
    if !when.pos_on || ctx.is_some() {
        return Err(refuse());
    }
    let deal = deals.iter().find(|d| d.id == deal_id).ok_or_else(refuse)?;
    let mut apps = load_apps(store, ctx);
    let cands = cart::deal_candidates(store, ctx)?;
    let lines = deal_lines(&cands, items, &claimed_by(&apps));
    let dctx = context(when, &apps);
    let best = rule::best(deal, &lines, &dctx).ok_or_else(refuse)?;
    let app = rule::price_application(deal, &lines, &best.units, &dctx).map_err(|_| refuse())?;
    apps.push(StoredApp {
        id: uuid::Uuid::new_v4().to_string(),
        deal_id: deal.id.clone(),
        name: deal.name.clone(),
        times: app.times,
        discount: app.discount,
        lines: app
            .lines
            .iter()
            .filter_map(|l| {
                Some(StoredAppLine {
                    key: key_at(&cands, l.line_index)?,
                    units: l.units,
                    discount: l.discount,
                })
            })
            .collect(),
    });
    save_apps(store, ctx, &apps)
}

/// Take an application off (the teller's "Remove deal").
pub(crate) fn remove(store: &Store, ctx: Ctx<'_>, app_id: &str) -> CoreResult<()> {
    let mut apps = load_apps(store, ctx);
    apps.retain(|a| a.id != app_id);
    save_apps(store, ctx, &apps)
}

/// Re-check every application against the cart as it is now; drop the ones
/// it no longer carries (the host is told, `deal.dropped`). Returns the
/// dropped deals' names. Cheap when nothing is applied.
pub(crate) fn settle(
    store: &Store,
    ctx: Ctx<'_>,
    deals: &[DealView],
    items: &[MenuItemView],
    when: &When<'_>,
) -> CoreResult<Vec<String>> {
    let apps = load_apps(store, ctx);
    if apps.is_empty() {
        // A line restored with a cut but no application keeps none.
        cart::set_deal_cuts(store, ctx, &HashMap::new())?;
        return Ok(Vec::new());
    }
    let cands = cart::deal_candidates(store, ctx)?;
    let mut kept: Vec<StoredApp> = Vec::new();
    let mut dropped: Vec<String> = Vec::new();
    for a in apps {
        let ok = (|| {
            if !when.pos_on || ctx.is_some() {
                return None;
            }
            let deal = deals.iter().find(|d| d.id == a.deal_id)?;
            let lines = deal_lines(&cands, items, &claimed_by(&kept));
            let units: Vec<LineUnits> = a
                .lines
                .iter()
                .map(|l| {
                    let c = cands.iter().find(|c| c.key == l.key && c.eligible)?;
                    Some(LineUnits {
                        line_index: c.index,
                        units: l.units,
                    })
                })
                .collect::<Option<Vec<_>>>()?;
            let app = rule::price_application(deal, &lines, &units, &context(when, &kept)).ok()?;
            (app.discount == a.discount && app.times == a.times).then_some(app)
        })();
        match ok {
            Some(app) => kept.push(StoredApp {
                lines: app
                    .lines
                    .iter()
                    .filter_map(|l| {
                        Some(StoredAppLine {
                            key: key_at(&cands, l.line_index)?,
                            units: l.units,
                            discount: l.discount,
                        })
                    })
                    .collect(),
                ..a
            }),
            None => dropped.push(a.name.clone()),
        }
    }
    save_apps(store, ctx, &kept)?;
    Ok(dropped)
}

/// The order's `deals` as the wire carries them (contract §3.1): each
/// application by the index of its lines in `items[]` (the cart position),
/// with the till's discount (the server keeps it on replay).
pub(crate) fn wire_apps(store: &Store, ctx: Ctx<'_>) -> CoreResult<Vec<WireApp>> {
    let cands = cart::deal_candidates(store, ctx)?;
    Ok(load_apps(store, ctx)
        .into_iter()
        .filter_map(|a| {
            let lines = a
                .lines
                .iter()
                .map(|l| {
                    Some(LineUnits {
                        line_index: cands.iter().find(|c| c.key == l.key)?.index,
                        units: l.units,
                    })
                })
                .collect::<Option<Vec<_>>>()?;
            Some(WireApp {
                deal_rule_id: a.deal_id,
                name: a.name,
                times: a.times,
                lines,
                discount: a.discount,
            })
        })
        .collect())
}

/// One application on the order payload.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct WireApp {
    pub deal_rule_id: String,
    pub name: String,
    pub times: i64,
    pub lines: Vec<LineUnits>,
    pub discount: i64,
}

/// The channel switches a `deal_rule` row carries (§11: deals follow the
/// combos' org/branch switches, which the server resolves onto the rows).
pub(crate) fn feed_sell(store: &Store) -> Option<madar_catalog::combo::Sell> {
    let rows: Vec<Value> = store
        .kv_get(menu::K_DEALS)
        .ok()
        .flatten()
        .and_then(|j| serde_json::from_str(&j).ok())
        .unwrap_or_default();
    rows.iter()
        .find_map(|r| serde_json::from_value(r.get("sell")?.clone()).ok())
}

/// kv key: the dropped-deal sentences the host has not toasted yet.
const K_NOTICES: &str = "cart:deal_notices";

/// `orders.deals.apply` (contract §2.1).
pub const CAP_APPLY: &str = "orders.deals.apply";

impl crate::MadarCore {
    fn deal_when(&self, catalog: &crate::CatalogSnapshot) -> (Option<String>, LocalNow, bool) {
        let at = self.combo_at(catalog);
        (at.branch_id, at.now, at.sell.pos)
    }

    /// Re-check the context's applied deals after a cart change; dropped ones
    /// are kept for [`Self::take_deal_notices`]. Returns the lines as they
    /// stand after. Free when nothing is applied.
    pub(crate) fn lines_with_deals_settled(
        &self,
        table_id: Option<&str>,
        lines: Vec<cart::CartLineView>,
    ) -> CoreResult<Vec<cart::CartLineView>> {
        if load_apps(&self.store, table_id).is_empty() && lines.iter().all(|l| l.deal_cut_minor == 0) {
            return Ok(lines);
        }
        self.settle_deals(table_id);
        cart::lines(&self.store, table_id)
    }

    /// Re-check the applied deals of a context (see [`settle`]).
    pub(crate) fn settle_deals(&self, table_id: Option<&str>) -> Vec<String> {
        let Ok(catalog) = self.catalog() else { return Vec::new() };
        let (branch, now, pos_on) = self.deal_when(&catalog);
        let when = When { branch_id: branch.as_deref(), now: &now, pos_on };
        let dropped = settle(&self.store, table_id, &catalog.deals, &catalog.items, &when).unwrap_or_default();
        if !dropped.is_empty() {
            let said: Vec<String> = dropped
                .iter()
                .map(|d| i18n::tr(&catalog.locale, "deal.dropped").replace("{deal}", d))
                .collect();
            let mut kept: Vec<String> = self
                .store
                .kv_get(K_NOTICES)
                .ok()
                .flatten()
                .and_then(|j| serde_json::from_str(&j).ok())
                .unwrap_or_default();
            kept.extend(said);
            let _ = self.store.kv_put(K_NOTICES, &serde_json::to_string(&kept).unwrap_or_default());
        }
        dropped
    }

    /// Why applied deals came off since the host last asked — each already a
    /// sentence in the till's language, for the shell toast. Re-checks the
    /// cart first. Draining: a reason is handed over once.
    pub fn take_deal_notices(&self, table_id: Option<String>) -> Vec<String> {
        let _ = self.settle_deals(table_id.as_deref());
        let kept: Vec<String> = self
            .store
            .kv_get(K_NOTICES)
            .ok()
            .flatten()
            .and_then(|j| serde_json::from_str(&j).ok())
            .unwrap_or_default();
        if !kept.is_empty() {
            let _ = self.store.kv_put(K_NOTICES, "[]");
        }
        kept
    }

    /// The deals the cart qualifies for now, best first (C8: never applied
    /// until the teller taps one). Empty when the POS switch is off.
    pub fn cart_deal_suggestions(&self, table_id: Option<String>) -> Vec<DealSuggestion> {
        let Ok(catalog) = self.catalog() else { return Vec::new() };
        let (branch, now, pos_on) = self.deal_when(&catalog);
        let when = When { branch_id: branch.as_deref(), now: &now, pos_on };
        suggest(&self.store, table_id.as_deref(), &catalog.deals, &catalog.items, &when, &catalog.locale)
            .unwrap_or_default()
    }

    /// The deals applied on the cart.
    pub fn cart_applied_deals(&self, table_id: Option<String>) -> Vec<AppliedDealView> {
        applied(&self.store, table_id.as_deref())
    }

    /// May the signed-in person apply a deal here (the Apply button)?
    pub fn can_apply_deals(&self) -> bool {
        self.decide_act(CAP_APPLY.to_string(), None, None, None).outcome == "allow"
    }

    /// Apply the suggested deal `deal_id` (the teller's tap). Needs
    /// `orders.deals.apply`; refused (`deal.not_eligible`) when the cart no
    /// longer qualifies.
    pub fn cart_apply_deal(
        &self,
        table_id: Option<String>,
        deal_id: String,
    ) -> CoreResult<Vec<cart::CartLineView>> {
        let access = self.decide_act(CAP_APPLY.to_string(), None, None, None);
        if access.outcome != "allow" {
            let catalog_locale = self.current_locale();
            return Err(CoreError::Forbidden {
                resource: "deal".into(),
                action: i18n::tr(&catalog_locale, "deal.not_allowed"),
            });
        }
        let catalog = self.catalog()?;
        let (branch, now, pos_on) = self.deal_when(&catalog);
        let when = When { branch_id: branch.as_deref(), now: &now, pos_on };
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        apply(
            &self.store,
            table_id.as_deref(),
            &deal_id,
            &catalog.deals,
            &catalog.items,
            &when,
            &catalog.locale,
        )?;
        drop(_guard);
        cart::lines(&self.store, table_id.as_deref())
    }

    /// Take an applied deal off the cart.
    pub fn cart_remove_deal(
        &self,
        table_id: Option<String>,
        application_id: String,
    ) -> CoreResult<Vec<cart::CartLineView>> {
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        remove(&self.store, table_id.as_deref(), &application_id)?;
        drop(_guard);
        cart::lines(&self.store, table_id.as_deref())
    }
}
