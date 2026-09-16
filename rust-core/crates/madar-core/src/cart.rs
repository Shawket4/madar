//! Cart — client-only, in-progress order state. The cart is NOT a wire model: it
//! lives entirely on the device, persists in `kv` so a half-built order survives
//! an app restart, and is the input to the pricing engine (`pricing::price_cart`,
//! the money source of truth). This module owns line identity + the *charged*
//! price resolution (size, addon swap-delta vs additive, optionals — mirroring
//! the Flutter ItemDetailSheet), recording the resolved prices VERBATIM so an
//! offline receipt equals the server's record. Totals still go through `pricing`.
//!
//! A line is keyed by a SIGNATURE over its full selection (item + size + addons +
//! optionals + notes) so identical configs merge and distinct ones don't. A
//! simple (option-less) line's signature is just its `item_id`, so the basic
//! add/qty/remove path is unchanged. `StoredLine` is forward-compatible: the
//! modifier fields default in, so older blobs still load.

use std::collections::HashMap;

use madar_api::models;
use serde::{Deserialize, Serialize};

use crate::error::{CoreError, CoreResult};
use crate::menu;
use crate::pricing::{self, DiscountKind, PriceCartInput};
use crate::store::Store;

/// kv key — the whole cart is one JSON array.
pub(crate) const K_CART: &str = "cart:lines";
/// kv key — the selected discount id (empty = none).
pub(crate) const K_DISCOUNT: &str = "cart:discount";
/// kv key — the ORDER's note (for the whole sale, not a line); empty = none.
pub(crate) const K_NOTE: &str = "cart:note";
/// kv key — parked/held carts (drafts) as a JSON array.
pub(crate) const K_DRAFTS: &str = "cart:drafts";
/// kv key — per-line KITCHEN-ONLY notes (JSON map, line key → text). Local
/// only: never leaves the device, never rides the order/checkout payload,
/// never prints on the customer receipt — a scribble for the cook, cleared
/// the moment that line's chit prints.
pub(crate) const K_KITCHEN_NOTES: &str = "cart:kitchen_notes";
/// kv key — the CART-level kitchen note (the whole-cart kitchen print's own
/// note, distinct from [`K_NOTE`]'s order note). Same rule: local only,
/// kitchen-chit only, cleared when the whole-cart chit prints.
pub(crate) const K_KITCHEN_NOTE: &str = "cart:kitchen_note";

#[derive(Serialize, Deserialize, Clone, Debug)]
struct StoredAddon {
    addon_item_id: String,
    name: String,
    /// The CHARGED delta (swap families) or full price (additive), per unit.
    price_modifier_minor: i64,
    qty: i64,
}

#[derive(Serialize, Deserialize, Clone, Debug)]
struct StoredOptional {
    optional_field_id: String,
    name: String,
    price_minor: i64,
}

/// One configured component inside a bundle line. The component's base/size price
/// is NEVER charged (the bundle's fixed price covers it); only its addons +
/// optionals add money. Mirrors Flutter's `BundleComponentSnapshot`.
#[derive(Serialize, Deserialize, Clone, Debug)]
struct StoredBundleComponent {
    item_id: String,
    name: String,
    qty: i64,
    size_label: Option<String>,
    addons: Vec<StoredAddon>,
    optionals: Vec<StoredOptional>,
}

/// The persisted cart line. New modifier fields default in (forward-compatible).
/// Opaque to callers — only `resolve_line`/`resolve_bundle_line`/`add_resolved`
/// construct/consume it. A bundle line sets `bundle_id` + `bundle_components`,
/// `unit_price_minor` = the fixed bundle price, and leaves its own
/// `addons`/`optionals` empty (component extras carry the up-charges).
#[derive(Serialize, Deserialize, Clone, Debug)]
pub(crate) struct StoredLine {
    item_id: String,
    name: String,
    /// Size-resolved absolute unit price (before addons/optionals).
    unit_price_minor: i64,
    qty: i64,
    #[serde(default)]
    size_label: Option<String>,
    #[serde(default)]
    addons: Vec<StoredAddon>,
    #[serde(default)]
    optionals: Vec<StoredOptional>,
    #[serde(default)]
    notes: Option<String>,
    #[serde(default)]
    bundle_id: Option<String>,
    #[serde(default)]
    bundle_components: Vec<StoredBundleComponent>,
}

/// A host-supplied addon choice (id + how many). The CORE resolves its price.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct AddonSelection {
    pub addon_item_id: String,
    pub qty: i64,
}

/// An addon offered for an item, with its CHARGED price already resolved (swap
/// delta / full) — so the customization sheet just displays it, no pricing rules
/// in the UI. Grouped by `addon_type` by the host (per slot / global card).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ItemAddonView {
    pub addon_item_id: String,
    pub name: String,
    pub addon_type: String,
    pub charged_price_minor: i64,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CartAddonView {
    pub addon_item_id: String,
    pub name: String,
    pub qty: i64,
    pub price_modifier_minor: i64,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CartOptionalView {
    pub optional_field_id: String,
    pub name: String,
    pub price_minor: i64,
}

/// A configured component of a bundle cart line, for the bundle row breakdown.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CartBundleComponentView {
    pub item_id: String,
    pub name: String,
    pub qty: i64,
    pub size_label: Option<String>,
    pub addons: Vec<CartAddonView>,
    pub optionals: Vec<CartOptionalView>,
}

/// A cart line as the host renders it (with the derived line total). When
/// `bundle_id` is set the line is a bundle: `name` is the bundle name,
/// `unit_price_minor` the fixed bundle price, and `bundle_components` the
/// configured items (the row renders their breakdown).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CartLineView {
    /// Stable line key (the selection signature) — use for set_qty/remove/edit.
    pub key: String,
    pub item_id: String,
    pub name: String,
    pub size_label: Option<String>,
    pub addons: Vec<CartAddonView>,
    pub optionals: Vec<CartOptionalView>,
    pub notes: Option<String>,
    pub unit_price_minor: i64,
    pub qty: i64,
    pub line_total_minor: i64,
    pub bundle_id: Option<String>,
    pub bundle_components: Vec<CartBundleComponentView>,
    /// A KITCHEN-ONLY note for this line — never sent with the order, never
    /// on the customer receipt. Joined in from [`K_KITCHEN_NOTES`] at read
    /// time, so `view()` itself stays a pure function of the stored lines.
    /// Cleared once this line's chit prints ([`clear_line_kitchen_note`]).
    pub kitchen_note: Option<String>,
}

/// The priced cart summary the host shows in the cart panel + action-bar badge.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct CartTotals {
    /// Sum of quantities — the badge count on the cart button.
    pub item_count: i64,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    /// Added to the bill; `0` when the branch has no service charge. Rendered
    /// as its own line, because a customer is entitled to see a charge they
    /// did not choose stated separately from the tax.
    pub service_charge_minor: i64,
    pub total_minor: i64,
}

// ── persistence ──────────────────────────────────────────────────────────────

// ── cart contexts ────────────────────────────────────────────────────────────
//
// There is not one cart, there is one cart PER CONTEXT: the counter's takeaway
// cart, and one for every table. There is NO active context: every cart
// operation (lines, discount, note, meta, undo stash, park, fire, checkout)
// names the context it acts on (`None` = takeaway, `Some(table_id)`). The
// host's screens own which cart they show, so the Sell tab can never inherit a
// table from a previous launch or a previous user. The takeaway context keeps
// the legacy keys, so a cart persisted before contexts existed is still the
// counter's after upgrade.

/// A cart context: `None` is the counter's takeaway cart, `Some(id)` a table's.
pub type Ctx<'a> = Option<&'a str>;

/// kv key — the retired GLOBAL active context. Ignored; deleted once on load.
pub(crate) const K_LEGACY_CONTEXT: &str = "cart:context";
/// kv key — JSON array of table ids that have (or had) a cart of their own,
/// so a sign-out / shift close can empty every one of them.
const K_CONTEXT_TABLES: &str = "cart:context_tables";
/// kv key — the context's cart meta (JSON `CartMeta`).
const K_META: &str = "cart:meta";

/// The identity a context's cart carries while it is being built: what it is
/// called, which parked order it came from, and the table/booking it belongs
/// to. Persisted per context so it survives a restart with its lines.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct CartMeta {
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub draft_id: Option<String>,
    #[serde(default)]
    pub booking_id: Option<String>,
    #[serde(default)]
    pub table_label: Option<String>,
    #[serde(default)]
    pub guest_name: Option<String>,
    #[serde(default)]
    pub started_at: Option<String>,
    #[serde(default)]
    pub covers: Option<i32>,
}

/// Drop the retired global-context key (idempotent; called on core open).
pub(crate) fn forget_legacy_context(store: &Store) -> CoreResult<()> {
    if store.kv_get(K_LEGACY_CONTEXT)?.is_some() {
        store.kv_delete(K_LEGACY_CONTEXT)?;
    }
    Ok(())
}

fn norm(ctx: Ctx<'_>) -> Ctx<'_> {
    ctx.filter(|s| !s.is_empty())
}

fn key_for(table: Ctx<'_>, base: &str) -> String {
    match norm(table) {
        None => base.to_string(),
        Some(id) => format!("{base}@table:{id}"),
    }
}

fn ctx_key(ctx: Ctx<'_>, base: &str) -> CoreResult<String> {
    Ok(key_for(ctx, base))
}

fn context_tables(store: &Store) -> CoreResult<Vec<String>> {
    Ok(match store.kv_get(K_CONTEXT_TABLES)? {
        Some(j) => serde_json::from_str(&j).unwrap_or_default(),
        None => Vec::new(),
    })
}

/// Remember a table context so `clear_all` can find its cart later.
fn track(store: &Store, ctx: Ctx<'_>) -> CoreResult<()> {
    if let Some(id) = norm(ctx) {
        let mut known = context_tables(store)?;
        if !known.iter().any(|k| k == id) {
            known.push(id.to_string());
            store.kv_put(K_CONTEXT_TABLES, &serde_json::to_string(&known)?)?;
        }
    }
    Ok(())
}

/// The context's cart meta (default when none was set).
pub(crate) fn meta(store: &Store, ctx: Ctx<'_>) -> CoreResult<CartMeta> {
    Ok(match store.kv_get(&key_for(ctx, K_META))? {
        Some(j) => serde_json::from_str(&j).unwrap_or_default(),
        None => CartMeta::default(),
    })
}

/// Replace the context's cart meta.
pub(crate) fn set_meta(store: &Store, ctx: Ctx<'_>, meta: &CartMeta) -> CoreResult<()> {
    track(store, ctx)?;
    store.kv_put(&key_for(ctx, K_META), &serde_json::to_string(meta)?)
}

/// Every table context that currently holds lines.
pub(crate) fn table_contexts_with_lines(store: &Store) -> CoreResult<Vec<String>> {
    let mut out = Vec::new();
    for t in context_tables(store)? {
        if !load(store, Some(&t))?.is_empty() {
            out.push(t);
        }
    }
    Ok(out)
}

/// Empty EVERY context's cart and meta (sign-out, shift close).
pub(crate) fn clear_all(store: &Store) -> CoreResult<()> {
    let tables = context_tables(store)?;
    for t in std::iter::once(None).chain(tables.iter().map(|t| Some(t.as_str()))) {
        store.kv_put(&key_for(t, K_CART), "[]")?;
        store.kv_put(&key_for(t, K_DISCOUNT), "")?;
        store.kv_put(&key_for(t, K_NOTE), "")?;
        store.kv_put(&key_for(t, K_LAST_REMOVED), "[]")?;
        store.kv_put(&key_for(t, K_META), "{}")?;
        store.kv_put(&key_for(t, K_KITCHEN_NOTES), "{}")?;
        store.kv_put(&key_for(t, K_KITCHEN_NOTE), "")?;
    }
    store.kv_put(K_CONTEXT_TABLES, "[]")?;
    forget_legacy_context(store)
}

fn load(store: &Store, ctx: Ctx<'_>) -> CoreResult<Vec<StoredLine>> {
    match store.kv_get(&ctx_key(ctx, K_CART)?)? {
        Some(json) => Ok(serde_json::from_str(&json).unwrap_or_default()),
        None => Ok(Vec::new()),
    }
}

fn save(store: &Store, ctx: Ctx<'_>, lines: &[StoredLine]) -> CoreResult<()> {
    track(store, ctx)?;
    store.kv_put(&ctx_key(ctx, K_CART)?, &serde_json::to_string(lines)?)
}

// ── pricing helpers (the line-money rules, mirrored from cart.dart) ───────────

fn addon_optional_extras(addons: &[StoredAddon], optionals: &[StoredOptional]) -> i64 {
    addons
        .iter()
        .map(|a| a.price_modifier_minor * a.qty)
        .sum::<i64>()
        + optionals.iter().map(|o| o.price_minor).sum::<i64>()
}

fn line_extras(l: &StoredLine) -> i64 {
    // A normal line's extras are its own addons/optionals; a bundle line's are
    // the sum across its components (the fixed base already covers the items).
    addon_optional_extras(&l.addons, &l.optionals)
        + l.bundle_components
            .iter()
            .map(|c| addon_optional_extras(&c.addons, &c.optionals))
            .sum::<i64>()
}

fn line_total(l: &StoredLine) -> i64 {
    (l.unit_price_minor + line_extras(l)) * l.qty
}

/// The line key: a deterministic signature over the full selection. Option-less
/// lines key by `item_id` so the basic add/qty/remove path stays stable.
fn signature(l: &StoredLine) -> String {
    // A bundle keys by its id + each component's full selection, so identical
    // configurations merge (qty++) and differently-configured ones stay distinct.
    if let Some(bid) = &l.bundle_id {
        let comps: Vec<String> = l
            .bundle_components
            .iter()
            .map(|c| {
                let mut a: Vec<String> = c
                    .addons
                    .iter()
                    .map(|x| format!("{}:{}", x.addon_item_id, x.qty))
                    .collect();
                a.sort();
                let mut o: Vec<String> = c
                    .optionals
                    .iter()
                    .map(|x| x.optional_field_id.clone())
                    .collect();
                o.sort();
                format!(
                    "{}@{}#{}#{}",
                    c.item_id,
                    c.size_label.as_deref().unwrap_or(""),
                    a.join(","),
                    o.join(",")
                )
            })
            .collect();
        return format!("bundle:{}|{}", bid, comps.join(";"));
    }
    if l.size_label.is_none() && l.addons.is_empty() && l.optionals.is_empty() && l.notes.is_none()
    {
        return l.item_id.clone();
    }
    let mut addons: Vec<String> = l
        .addons
        .iter()
        .map(|a| format!("{}:{}", a.addon_item_id, a.qty))
        .collect();
    addons.sort();
    let mut opts: Vec<String> = l
        .optionals
        .iter()
        .map(|o| o.optional_field_id.clone())
        .collect();
    opts.sort();
    format!(
        "{}|{}|{}|{}|{}",
        l.item_id,
        l.size_label.as_deref().unwrap_or(""),
        addons.join(","),
        opts.join(","),
        l.notes.as_deref().unwrap_or(""),
    )
}

fn view(lines: &[StoredLine]) -> Vec<CartLineView> {
    lines
        .iter()
        .map(|l| CartLineView {
            key: signature(l),
            item_id: l.item_id.clone(),
            name: l.name.clone(),
            size_label: l.size_label.clone(),
            addons: l
                .addons
                .iter()
                .map(|a| CartAddonView {
                    addon_item_id: a.addon_item_id.clone(),
                    name: a.name.clone(),
                    qty: a.qty,
                    price_modifier_minor: a.price_modifier_minor,
                })
                .collect(),
            optionals: l
                .optionals
                .iter()
                .map(|o| CartOptionalView {
                    optional_field_id: o.optional_field_id.clone(),
                    name: o.name.clone(),
                    price_minor: o.price_minor,
                })
                .collect(),
            notes: l.notes.clone(),
            unit_price_minor: l.unit_price_minor,
            qty: l.qty,
            line_total_minor: line_total(l),
            bundle_id: l.bundle_id.clone(),
            bundle_components: l
                .bundle_components
                .iter()
                .map(|c| CartBundleComponentView {
                    item_id: c.item_id.clone(),
                    name: c.name.clone(),
                    qty: c.qty,
                    size_label: c.size_label.clone(),
                    addons: c
                        .addons
                        .iter()
                        .map(|a| CartAddonView {
                            addon_item_id: a.addon_item_id.clone(),
                            name: a.name.clone(),
                            qty: a.qty,
                            price_modifier_minor: a.price_modifier_minor,
                        })
                        .collect(),
                    optionals: c
                        .optionals
                        .iter()
                        .map(|o| CartOptionalView {
                            optional_field_id: o.optional_field_id.clone(),
                            name: o.name.clone(),
                            price_minor: o.price_minor,
                        })
                        .collect(),
                })
                .collect(),
            kitchen_note: None,
        })
        .collect()
}

/// The addon families that REPLACE part of the recipe rather than adding to it.
///
/// A latte has milk in it already; choosing oat does not give the cup two
/// milks, it changes which milk. That is why these pay only the delta over the
/// base ([adjusted_addon_price]) and why a group of them can hold exactly one
/// selection ([item_modifier_groups]). The two rules are the same fact, so
/// they read the same constant.
pub(crate) const SWAP_FAMILIES: [&str; 2] = ["milk_type", "coffee_type"];

/// Whether `addon_type` replaces part of the recipe instead of adding to it.
pub(crate) fn is_swap_family(addon_type: &str) -> bool {
    SWAP_FAMILIES.contains(&addon_type)
}

/// Collapse a selection so each swap family carries at most ONE addon at qty 1.
///
/// A host that still sends the recipe's default milk beside the milk the
/// teller picked (or a milk at qty 2) describes a cup that cannot exist. The
/// LAST pick of a family wins — a later tap replaces, it never appends — and
/// it keeps the position of the family's first entry. Additive addons and ids
/// the catalog doesn't know pass through untouched.
pub(crate) fn normalize_swap_selections(
    addon_catalog: &[menu::AddonItemView],
    addon_sels: &[AddonSelection],
) -> Vec<AddonSelection> {
    let family = |id: &str| {
        addon_catalog
            .iter()
            .find(|a| a.id == id)
            .map(|a| a.addon_type.as_str())
            .filter(|t| is_swap_family(t))
    };
    let mut out: Vec<AddonSelection> = Vec::with_capacity(addon_sels.len());
    let mut slot_of: Vec<(&str, usize)> = Vec::new();
    for sel in addon_sels {
        match family(&sel.addon_item_id) {
            Some(fam) => {
                let one = AddonSelection {
                    addon_item_id: sel.addon_item_id.clone(),
                    qty: 1,
                };
                match slot_of.iter().find(|(f, _)| *f == fam) {
                    Some((_, i)) => out[*i] = one,
                    None => {
                        slot_of.push((fam, out.len()));
                        out.push(one);
                    }
                }
            }
            None => out.push(sel.clone()),
        }
    }
    out
}

/// Charged addon price: SWAP families (milk_type, coffee_type) pay only the delta
/// over the item's default base for that family (clamped ≥0) — re-selecting the
/// default costs 0; everything else (additive) pays the full default. The backend
/// (component_resolve) charges a coffee swap as a delta too; the POS used to charge
/// the FULL coffee price, overstating the order total vs the recorded sale.
fn adjusted_addon_price(a: &menu::AddonItemView, milk_base: i64, coffee_base: i64) -> i64 {
    match a.addon_type.as_str() {
        "milk_type" => (a.default_price_minor - milk_base).max(0),
        "coffee_type" => (a.default_price_minor - coffee_base).max(0),
        _ => a.default_price_minor,
    }
}

/// The base price a coffee swap is charged ABOVE: find the item's recipe line in
/// the `coffee_bean` category, then the coffee_type addon whose embedded ingredient
/// matches that line's org-ingredient — its default price is the base. Recipe-driven
/// (mirrors the backend's component_resolve; no precomputed default-coffee id).
fn coffee_swap_base(item: &menu::MenuItemView, addon_catalog: &[menu::AddonItemView]) -> i64 {
    swap_base_addon(item, addon_catalog, "coffee_type")
        .map(|a| a.default_price_minor)
        .unwrap_or(0)
}

/// The addon that IS the item's recipe for a swap family — the "as it comes"
/// choice. Matches the recipe line of the family's ingredient category against
/// each addon's embedded ingredient, exactly as the backend's
/// `component_resolve` decides whether a pick is a real swap or the base.
fn swap_base_addon<'a>(
    item: &menu::MenuItemView,
    addon_catalog: &'a [menu::AddonItemView],
    family: &str,
) -> Option<&'a menu::AddonItemView> {
    let category = match family {
        "milk_type" => "milk",
        "coffee_type" => "coffee_bean",
        _ => return None,
    };
    // A milk base may be authored outright; a coffee base is always derived.
    if family == "milk_type" {
        if let Some(id) = item.default_milk_addon_id.as_deref() {
            if let Some(a) = addon_catalog.iter().find(|a| a.id == id) {
                return Some(a);
            }
        }
    }
    swap_base_candidates(item, addon_catalog, family, category)
        .into_iter()
        .next()
}

/// The swap default for ONE group: the first catalog addon carrying the
/// recipe's own ingredient that this group actually offers. Two groups can
/// each hold an option for the same bean (Coffee Beans' "Colombian" and
/// Espresso Beans' "Colombian Espresso"), so picking catalog-wide first and
/// then checking membership left the second group with no default.
fn swap_default_in<T>(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
    family: &str,
    options: &[T],
    id_of: impl Fn(&T) -> &str,
) -> Option<String> {
    let offered = |id: &str| options.iter().any(|o| id_of(o) == id);
    if family == "milk_type" {
        if let Some(id) = item.default_milk_addon_id.as_deref() {
            if offered(id) && addon_catalog.iter().any(|a| a.id == id) {
                return Some(id.to_string());
            }
        }
    }
    let category = match family {
        "milk_type" => "milk",
        "coffee_type" => "coffee_bean",
        _ => return None,
    };
    swap_base_candidates(item, addon_catalog, family, category)
        .into_iter()
        .find(|a| offered(&a.id))
        .map(|a| a.id.clone())
}

fn swap_base_candidates<'a>(
    item: &menu::MenuItemView,
    addon_catalog: &'a [menu::AddonItemView],
    family: &str,
    category: &str,
) -> Vec<&'a menu::AddonItemView> {
    let base_ing = item
        .recipes
        .iter()
        .find(|r| r.category == category)
        .and_then(|r| r.org_ingredient_id.as_deref());
    addon_catalog
        .iter()
        .filter(move |a| a.addon_type == family && base_ing.is_some())
        .filter(move |a| {
            a.ingredients
                .iter()
                .any(|ing| ing.org_ingredient_id.as_deref() == base_ing)
        })
        .collect()
}

/// Resolve a configured line's charged prices from the cached catalog. PURE so
/// the money rules are exhaustively unit-testable. Unknown addon/optional ids
/// are dropped (defensive — a stale cache must not wedge a sale).
pub(crate) fn resolve_line(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
    size_label: Option<String>,
    addon_sels: &[AddonSelection],
    optional_ids: &[String],
    qty: i64,
    notes: Option<String>,
) -> StoredLine {
    let unit_price = match &size_label {
        Some(lbl) => item
            .sizes
            .iter()
            .find(|s| &s.label == lbl)
            .map(|s| s.price_minor)
            .unwrap_or(item.base_price_minor),
        None => item.base_price_minor,
    };
    StoredLine {
        item_id: item.id.clone(),
        name: item.name.clone(),
        unit_price_minor: unit_price,
        qty: qty.max(1),
        size_label,
        addons: resolve_addons(item, addon_catalog, addon_sels),
        optionals: resolve_optionals(item, addon_catalog, addon_sels, optional_ids),
        notes,
        bundle_id: None,
        bundle_components: vec![],
    }
}

/// Resolve a selection's charged addon prices against `item` + the catalog
/// (swap-delta vs additive). Unknown ids are dropped. Shared by normal lines and
/// bundle components.
fn resolve_addons(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
    addon_sels: &[AddonSelection],
) -> Vec<StoredAddon> {
    let milk_base = item
        .default_milk_addon_id
        .as_ref()
        .and_then(|id| addon_catalog.iter().find(|a| &a.id == id))
        .map(|a| a.default_price_minor)
        .unwrap_or(0);
    let coffee_base = coffee_swap_base(item, addon_catalog);
    normalize_swap_selections(addon_catalog, addon_sels)
        .iter()
        .filter_map(|sel| {
            let a = addon_catalog.iter().find(|x| x.id == sel.addon_item_id)?;
            Some(StoredAddon {
                addon_item_id: a.id.clone(),
                name: a.name.clone(),
                price_modifier_minor: adjusted_addon_price(a, milk_base, coffee_base),
                qty: sel.qty.max(1),
            })
        })
        .collect()
}

/// Resolve selected optional-field ids to stored optionals (price + name).
///
/// An ADDON selection whose id is not an addon but IS one of the item's
/// optional fields is the item-private "Options" group picked through an addon
/// sheet (F17: `/catalog/sync` also lists that group). The server resolves it
/// only as an optional, so it is carried in the optional slot (once) instead
/// of being dropped or submitted as an unknown addon id.
fn resolve_optionals(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
    addon_sels: &[AddonSelection],
    optional_ids: &[String],
) -> Vec<StoredOptional> {
    let mut ids: Vec<&String> = Vec::new();
    let rerouted = addon_sels
        .iter()
        .map(|s| &s.addon_item_id)
        .filter(|id| is_private_optional(item, addon_catalog, id));
    for id in optional_ids.iter().chain(rerouted) {
        if !ids.contains(&id) {
            ids.push(id);
        }
    }
    ids.into_iter()
        .filter_map(|oid| {
            let o = item.optional_fields.iter().find(|f| &f.id == oid)?;
            Some(StoredOptional {
                optional_field_id: o.id.clone(),
                name: o.name.clone(),
                price_minor: o.price_minor,
            })
        })
        .collect()
}

/// A host-supplied configured component of a bundle (which item, its size, and
/// the chosen addons/optionals). The CORE resolves the charged extra prices.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct BundleComponentSelection {
    pub item_id: String,
    pub size_label: Option<String>,
    pub qty: i64,
    pub addons: Vec<AddonSelection>,
    pub optional_field_ids: Vec<String>,
}

/// Build a bundle cart line: the fixed bundle price as the unit price, plus each
/// component with its addon/optional up-charges resolved from the catalog. The
/// component base/size price is never charged (Flutter parity).
pub(crate) fn resolve_bundle_line(
    bundle: &menu::BundleView,
    items: &[menu::MenuItemView],
    addon_catalog: &[menu::AddonItemView],
    components: &[BundleComponentSelection],
    qty: i64,
) -> StoredLine {
    let bundle_components = components
        .iter()
        .filter_map(|sel| {
            let item = items.iter().find(|i| i.id == sel.item_id)?;
            Some(StoredBundleComponent {
                item_id: item.id.clone(),
                name: item.name.clone(),
                qty: sel.qty.max(1),
                size_label: sel.size_label.clone(),
                addons: resolve_addons(item, addon_catalog, &sel.addons),
                optionals: resolve_optionals(
                    item,
                    addon_catalog,
                    &sel.addons,
                    &sel.optional_field_ids,
                ),
            })
        })
        .collect();
    StoredLine {
        item_id: bundle.id.clone(),
        name: bundle.name.clone(),
        unit_price_minor: bundle.price_minor,
        qty: qty.max(1),
        size_label: None,
        addons: vec![],
        optionals: vec![],
        notes: None,
        bundle_id: Some(bundle.id.clone()),
        bundle_components,
    }
}

/// Every active addon offered for `item`, with its charged price resolved (the
/// swap rule lives here, not in the UI). The host groups by `addon_type`.
pub(crate) fn item_addons(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
) -> Vec<ItemAddonView> {
    let milk_base = item
        .default_milk_addon_id
        .as_ref()
        .and_then(|id| addon_catalog.iter().find(|a| &a.id == id))
        .map(|a| a.default_price_minor)
        .unwrap_or(0);
    let coffee_base = coffee_swap_base(item, addon_catalog);
    addon_catalog
        .iter()
        .filter(|a| a.is_active)
        .map(|a| ItemAddonView {
            addon_item_id: a.id.clone(),
            name: a.name.clone(),
            addon_type: a.addon_type.clone(),
            charged_price_minor: adjusted_addon_price(a, milk_base, coffee_base),
        })
        .collect()
}

// ── grouped modifiers (menu-unification Wave 4) ──────────────────────────────
//
// The backend unified modifiers into reusable groups + options (stable ids:
// modifier_option.id == old addon_item.id / optional_field.id). This is the
// POS-side projection of that model, assembled from the mirrored catalog
// streams — which carry the SAME shapes whether served by the legacy tables or
// the shim views — so it works for both old and new backends. Charged prices
// reuse the flat sheet's swap-delta rules (`adjusted_addon_price`), keeping the
// grouped view money-identical to the parity-proven flat path.

/// How a group's selections are submitted at add-to-cart time.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Enum))]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModifierGroupKind {
    /// Options are addon items — submit as `AddonSelection { addon_item_id: option.id }`.
    Addon,
    /// Options are the item's priced optionals — submit their ids in `optional_field_ids`.
    Optional,
}

/// One option inside a modifier group, with its CHARGED price already resolved
/// (swap delta / full / optional price) — display-ready, no pricing in the UI.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModifierOptionView {
    /// Stable id: the addon_item_id (kind Addon) or optional_field_id (kind
    /// Optional) to submit — unchanged by the backend migration.
    pub id: String,
    pub name: String,
    pub charged_price_minor: i64,
}

/// A modifier group offered on an item. Slot-configured groups keep their
/// min/max/required; addon types offered without a slot get a default group
/// (milk is single-select by convention); the item's priced optionals surface
/// as one `Optional`-kind group.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ModifierGroupView {
    /// The slot id when slot-configured, else `type:<addon_type>` / `options`.
    pub group_id: String,
    pub name: String,
    pub kind: ModifierGroupKind,
    /// The legacy addon type driving swap-family behavior (`None` for optionals).
    pub addon_type: Option<String>,
    pub is_required: bool,
    pub min_selections: i32,
    /// `None` ⇒ multi-select with no cap.
    pub max_selections: Option<i32>,
    /// For a swap family (milk / coffee), the option that IS the item's recipe —
    /// the sheet opens with it chosen so a teller only taps to CHANGE the drink,
    /// not to confirm how it is already made. `None` for every other group, and
    /// for a swap family whose recipe names no ingredient of that category.
    ///
    /// Safe only because these groups are single-select (see below): preselecting
    /// while multi-select was allowed once sent a line out with two milks.
    pub default_option_id: Option<String>,
    pub options: Vec<ModifierOptionView>,
}

/// A group whose constraints the current selection breaks (too few / too many).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct GroupViolationView {
    pub group_id: String,
    pub group_name: String,
    /// Effective minimum (`max(min_selections, 1 if required)`).
    pub min_required: i32,
    pub max_allowed: Option<i32>,
    pub selected: i64,
}

/// The item's modifier groups, display-ready. Options honour the item's
/// allowlist when non-empty (mirrors the unified model's `included_option_ids`);
/// group order = configured slots first, then unslotted types in the POS sheet
/// order (milk, coffee, custom types A→Z, generic extras), then optionals.
pub(crate) fn item_modifier_groups(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
) -> Vec<ModifierGroupView> {
    let flat = item_addons(item, addon_catalog);
    let allowed: std::collections::HashSet<&str> =
        item.allowed_addon_ids.iter().map(|s| s.as_str()).collect();
    let offered: Vec<&ItemAddonView> = flat
        .iter()
        .filter(|a| allowed.is_empty() || allowed.contains(a.addon_item_id.as_str()))
        .collect();
    let options_of = |ty: &str| -> Vec<ModifierOptionView> {
        offered
            .iter()
            .filter(|a| a.addon_type == ty)
            .map(|a| ModifierOptionView {
                id: a.addon_item_id.clone(),
                name: a.name.clone(),
                charged_price_minor: a.charged_price_minor,
            })
            .collect()
    };

    let mut groups = Vec::new();
    let mut slotted: std::collections::HashSet<&str> = std::collections::HashSet::new();
    for slot in &item.addon_slots {
        slotted.insert(slot.addon_type.as_str());
        let options = options_of(&slot.addon_type);
        if options.is_empty() {
            continue; // a slot whose type has no offered addons renders nothing
        }
        // A SWAP family is exclusive whatever the slot says.
        //
        // `max_selections` is optional on a slot, and `None` means "no cap" —
        // so a milk slot that nobody set a maximum on made milk ADDITIVE. The
        // sheet then preselected the recipe's full-fat, the teller picked oat,
        // and the line went out with both: the customer was charged for two
        // milks and the kitchen was told to pour two. The unslotted path below
        // always got this right, so whether the bug appeared came down to
        // whether a shop happened to configure a slot for milk.
        //
        // It is not the slot's call to make. `adjusted_addon_price` already
        // charges these families as a DELTA over the base, which is only
        // coherent when exactly one is chosen — the pricing engine has always
        // assumed the exclusivity this now enforces.
        let max_selections = if is_swap_family(&slot.addon_type) {
            Some(slot.max_selections.unwrap_or(1).min(1))
        } else {
            slot.max_selections
        };
        let default_option_id =
            swap_default_in(item, addon_catalog, &slot.addon_type, &options, |o| &o.id);
        groups.push(ModifierGroupView {
            group_id: slot.id.clone(),
            name: slot
                .label
                .clone()
                .unwrap_or_else(|| slot.addon_type.clone()),
            kind: ModifierGroupKind::Addon,
            addon_type: Some(slot.addon_type.clone()),
            is_required: slot.is_required,
            min_selections: slot.min_selections.max(0),
            max_selections,
            default_option_id,
            options,
        });
    }

    // Offered types without a slot → default groups (no constraints, except the
    // milk swap family which is single-select by convention, like the sheet).
    let mut rest: Vec<&str> = Vec::new();
    for a in &offered {
        if !slotted.contains(a.addon_type.as_str()) && !rest.contains(&a.addon_type.as_str()) {
            rest.push(a.addon_type.as_str());
        }
    }
    let rank = |t: &str| match t {
        "milk_type" => 0,
        "coffee_type" => 1,
        "extra" => 3,
        _ => 2,
    };
    rest.sort_by(|a, b| rank(a).cmp(&rank(b)).then(a.cmp(b)));
    for ty in rest {
        let options = options_of(ty);
        let default_option_id = swap_default_in(item, addon_catalog, ty, &options, |o| &o.id);
        groups.push(ModifierGroupView {
            group_id: format!("type:{ty}"),
            name: ty.to_string(),
            kind: ModifierGroupKind::Addon,
            addon_type: Some(ty.to_string()),
            is_required: false,
            min_selections: 0,
            max_selections: if is_swap_family(ty) { Some(1) } else { None },
            default_option_id,
            options,
        });
    }

    // The item's priced optionals — one multi-select Optional-kind group.
    if let Some(og) = optionals_group(item) {
        groups.push(og);
    }
    groups
}

/// Is `id` one of the item's optional fields that the addon catalog does not
/// know — i.e. an option of the item-private "Options" group
/// (`legacy_source='optional'`), which the server only accepts as an optional.
fn is_private_optional(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
    id: &str,
) -> bool {
    item.optional_fields.iter().any(|f| f.id == id) && !addon_catalog.iter().any(|a| a.id == id)
}

/// The per-item priced-optionals group (shared by the legacy and unified
/// projections — optionals ride their own wire either way, keyed by the same
/// stable `optional_field_id`s the order payload submits).
fn optionals_group(item: &menu::MenuItemView) -> Option<ModifierGroupView> {
    let opts: Vec<ModifierOptionView> = item
        .optional_fields
        .iter()
        .filter(|f| f.is_active)
        .map(|f| ModifierOptionView {
            id: f.id.clone(),
            name: f.name.clone(),
            charged_price_minor: f.price_minor,
        })
        .collect();
    if opts.is_empty() {
        return None;
    }
    Some(ModifierGroupView {
        default_option_id: None,
        group_id: "options".into(),
        name: "options".into(),
        kind: ModifierGroupKind::Optional,
        addon_type: None,
        is_required: false,
        min_selections: 0,
        max_selections: None,
        options: opts,
    })
}

/// Grouped modifiers from the UNIFIED catalog mirror (`GET /catalog/sync`) —
/// the new-model wire is authoritative for grouping, naming and constraints.
/// Charged prices still go through the flat sheet's swap-delta rules where the
/// option exists in the addon catalog (options ARE addons by stable id); an
/// option the legacy catalog doesn't know falls back to its unified effective
/// price. Effectively-unavailable options are dropped; emptied groups too. The
/// item's priced optionals are appended exactly as in the legacy projection.
pub(crate) fn item_modifier_groups_unified(
    item: &menu::MenuItemView,
    addon_catalog: &[menu::AddonItemView],
    unified: Vec<menu::UnifiedGroup>,
    locale: &str,
) -> Vec<ModifierGroupView> {
    let flat = item_addons(item, addon_catalog);
    let charged = |id: &str, fallback: i64| {
        flat.iter()
            .find(|a| a.addon_item_id == id)
            .map(|a| a.charged_price_minor)
            .unwrap_or(fallback)
    };
    let mut groups: Vec<ModifierGroupView> = unified
        .into_iter()
        .filter_map(|g| {
            let options: Vec<ModifierOptionView> = g
                .options
                .iter()
                .filter(|o| o.is_available)
                // F17: the item-private "Options" group rides this wire too;
                // its options already render once in the Optional group below
                // (and must be submitted as optionals), so never as addons.
                .filter(|o| !is_private_optional(item, addon_catalog, &o.id))
                .map(|o| ModifierOptionView {
                    id: o.id.clone(),
                    name: menu::resolve(&o.name_translations, &o.name, locale),
                    charged_price_minor: charged(&o.id, o.price),
                })
                .collect();
            if options.is_empty() {
                return None;
            }
            // A swap family (milk, coffee) is ONE choice whatever the wire
            // says. The backend backfill often writes a milk group as
            // `multi` with no max, which rendered milk as a multi-select with
            // a quantity stepper: the recipe's full-fat stayed selected, oat
            // landed beside it, and the line carried two milks. Recognise the
            // family by the group's legacy type OR by any option being a
            // swap-family addon in the catalog (a renamed/custom milk group).
            let swap = g.legacy_addon_type.as_deref().is_some_and(is_swap_family)
                || g.options.iter().any(|o| {
                    addon_catalog
                        .iter()
                        .any(|a| a.id == o.id && is_swap_family(&a.addon_type))
                });
            let single = swap || g.selection_type == "single" || g.max == Some(1);
            let swap_type = if swap {
                g.legacy_addon_type.clone().or_else(|| {
                    g.options.iter().find_map(|o| {
                        addon_catalog
                            .iter()
                            .find(|a| a.id == o.id && is_swap_family(&a.addon_type))
                            .map(|a| a.addon_type.clone())
                    })
                })
            } else {
                g.legacy_addon_type.clone()
            };
            // The recipe's own milk / bean, preselected — the SAME rule as the
            // legacy projection. This path is the one every unified-catalog
            // org actually uses, and it had been left at None, so the sheet
            // opened blank for every coffee and milk choice.
            let default_option_id = swap_type.as_deref().filter(|_| swap).and_then(|family| {
                swap_default_in(item, addon_catalog, family, &options, |o| &o.id)
            });
            Some(ModifierGroupView {
                default_option_id,
                group_id: g.group_id.clone(),
                // Custom groups carry an authored name; legacy-typed groups fall
                // back to the type string, which the host localizes (same rule
                // as the legacy projection).
                name: if g.name.is_empty() {
                    g.legacy_addon_type
                        .clone()
                        .unwrap_or_else(|| "extra".into())
                } else {
                    menu::resolve(&g.name_translations, &g.name, locale)
                },
                kind: ModifierGroupKind::Addon,
                addon_type: swap_type,
                is_required: g.is_required,
                min_selections: if swap {
                    g.min.clamp(0, 1)
                } else {
                    g.min.max(0)
                },
                max_selections: if swap {
                    Some(1)
                } else if single && g.max.is_none() {
                    Some(1)
                } else {
                    g.max
                },
                options,
            })
        })
        .collect();
    if let Some(og) = optionals_group(item) {
        groups.push(og);
    }
    groups
}

/// Check a selection against each group's constraints. Empty = valid. Selections
/// whose id isn't in any group are ignored here (the resolver drops unknown ids
/// defensively); the count per Addon group sums quantities, Optional groups
/// count picked ids.
pub(crate) fn validate_group_selections(
    groups: &[ModifierGroupView],
    addon_sels: &[AddonSelection],
    optional_ids: &[String],
) -> Vec<GroupViolationView> {
    groups
        .iter()
        .filter_map(|g| {
            let selected: i64 = match g.kind {
                ModifierGroupKind::Addon => addon_sels
                    .iter()
                    .filter(|s| g.options.iter().any(|o| o.id == s.addon_item_id))
                    .map(|s| s.qty.max(1))
                    .sum(),
                ModifierGroupKind::Optional => optional_ids
                    .iter()
                    .filter(|oid| g.options.iter().any(|o| &o.id == *oid))
                    .count() as i64,
            };
            let min = g.min_selections.max(if g.is_required { 1 } else { 0 });
            let too_few = selected < i64::from(min);
            let too_many = g.max_selections.is_some_and(|m| selected > i64::from(m));
            (too_few || too_many).then(|| GroupViolationView {
                group_id: g.group_id.clone(),
                group_name: g.name.clone(),
                min_required: min,
                max_allowed: g.max_selections,
                selected,
            })
        })
        .collect()
}

// ── operations (store in, updated views out) ─────────────────────────────────

pub(crate) fn lines(store: &Store, ctx: Ctx<'_>) -> CoreResult<Vec<CartLineView>> {
    let mut views = view(&load(store, ctx)?);
    let notes = kitchen_notes_map(store, ctx)?;
    for v in &mut views {
        v.kitchen_note = notes.get(&v.key).cloned();
    }
    Ok(views)
}

// ── kitchen-only notes (local; never checkout, never the receipt) ────────────

fn kitchen_notes_map(store: &Store, ctx: Ctx<'_>) -> CoreResult<HashMap<String, String>> {
    Ok(match store.kv_get(&ctx_key(ctx, K_KITCHEN_NOTES)?)? {
        Some(j) => serde_json::from_str(&j).unwrap_or_default(),
        None => HashMap::new(),
    })
}

fn save_kitchen_notes_map(
    store: &Store,
    ctx: Ctx<'_>,
    map: &HashMap<String, String>,
) -> CoreResult<()> {
    store.kv_put(
        &ctx_key(ctx, K_KITCHEN_NOTES)?,
        &serde_json::to_string(map)?,
    )
}

/// Set (or, blank/`None`, clear) ONE line's kitchen-only note, by its cart
/// line key. Local only — never part of the checkout payload, never on the
/// customer receipt.
pub(crate) fn set_line_kitchen_note(
    store: &Store,
    ctx: Ctx<'_>,
    line_key: &str,
    note: Option<&str>,
) -> CoreResult<()> {
    let mut map = kitchen_notes_map(store, ctx)?;
    match note.map(str::trim).filter(|s| !s.is_empty()) {
        Some(n) => {
            map.insert(line_key.to_string(), n.to_string());
        }
        None => {
            map.remove(line_key);
        }
    }
    save_kitchen_notes_map(store, ctx, &map)
}

/// Clear one line's kitchen note — called the moment that line's chit
/// actually printed, never on preview alone.
pub(crate) fn clear_line_kitchen_note(
    store: &Store,
    ctx: Ctx<'_>,
    line_key: &str,
) -> CoreResult<()> {
    set_line_kitchen_note(store, ctx, line_key, None)
}

/// Set (or clear) the CART-level kitchen note — the whole-cart kitchen
/// print's own note, distinct from the order note ([`set_note`]). Local
/// only, same rule as the per-line note.
pub(crate) fn set_kitchen_note(store: &Store, ctx: Ctx<'_>, note: Option<&str>) -> CoreResult<()> {
    let note = note.map(str::trim).unwrap_or("");
    store.kv_put(&ctx_key(ctx, K_KITCHEN_NOTE)?, note)
}

/// The cart's kitchen-only note, or `None` when blank.
pub(crate) fn kitchen_note(store: &Store, ctx: Ctx<'_>) -> CoreResult<Option<String>> {
    Ok(store
        .kv_get(&ctx_key(ctx, K_KITCHEN_NOTE)?)?
        .filter(|s| !s.trim().is_empty()))
}

/// Clear the cart-level kitchen note — called once the whole-cart chit
/// actually printed.
pub(crate) fn clear_kitchen_note(store: &Store, ctx: Ctx<'_>) -> CoreResult<()> {
    set_kitchen_note(store, ctx, None)
}

/// Clear EVERY kitchen note in this context — the cart-level one and every
/// line's own — in one go. Called once the whole-cart kitchen print has
/// actually printed: "the cart-level note and the printed rows' notes" is
/// exactly every note that context is holding at that moment.
pub(crate) fn clear_all_kitchen_notes(store: &Store, ctx: Ctx<'_>) -> CoreResult<()> {
    clear_kitchen_note(store, ctx)?;
    save_kitchen_notes_map(store, ctx, &HashMap::new())
}

/// Push a resolved line, merging into an identical existing line (same key).
pub(crate) fn add_resolved(
    store: &Store,
    ctx: Ctx<'_>,
    line: StoredLine,
) -> CoreResult<Vec<CartLineView>> {
    let mut lines = load(store, ctx)?;
    let sig = signature(&line);
    match lines.iter_mut().find(|l| signature(l) == sig) {
        Some(l) => l.qty += line.qty,
        None => lines.push(line),
    }
    save(store, ctx, &lines)?;
    Ok(view(&lines))
}

/// Replace the line keyed `line_key` with `line`, in ONE write.
///
/// Editing a line used to be two bridge calls — remove, then add — so an add
/// that failed (an item gone from the menu, a stale catalogue) left the cart
/// with the line DELETED and nothing in its place. Here the old line is only
/// dropped in the same save that puts the new one down; a key that is no
/// longer in the cart refuses before anything is touched.
///
/// The edited line keeps its position. If the new configuration is identical
/// to ANOTHER line already in the cart, it merges into that one (qty added),
/// exactly as a fresh add would.
pub(crate) fn replace_resolved(
    store: &Store,
    ctx: Ctx<'_>,
    line_key: &str,
    line: StoredLine,
) -> CoreResult<Vec<CartLineView>> {
    let mut lines = load(store, ctx)?;
    let Some(at) = lines.iter().position(|l| signature(l) == line_key) else {
        return Err(CoreError::Validation {
            field: "line".into(),
            detail: "that line is no longer in the cart".into(),
        });
    };
    lines.remove(at);
    let sig = signature(&line);
    match lines.iter_mut().find(|l| signature(l) == sig) {
        Some(l) => l.qty += line.qty,
        None => lines.insert(at.min(lines.len()), line),
    }
    save(store, ctx, &lines)?;
    Ok(view(&lines))
}

/// What a configured line WOULD cost, without adding it — the item sheet's
/// header and footer figures.
///
/// The sheet used to add the charged prices up itself, and got a different
/// number from the cart whenever a swap family collapsed (the recipe's milk
/// plus the picked milk). This resolves through the same [resolve_line] the
/// add uses, so the sheet and the cart can never disagree.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct LinePreviewView {
    /// One unit: the size's price plus every extra.
    pub unit_total_minor: i64,
    /// One unit's extras only (addons + optionals) — what a bundle component
    /// charges on top of the bundle price.
    pub extras_minor: i64,
    /// The whole line at its quantity.
    pub line_total_minor: i64,
}

pub(crate) fn preview_line(line: &StoredLine) -> LinePreviewView {
    let extras = line_extras(line);
    LinePreviewView {
        unit_total_minor: line.unit_price_minor + extras,
        extras_minor: extras,
        line_total_minor: line_total(line),
    }
}

/// Add one unit of an option-less item (the basic catalog tap).
pub(crate) fn add(
    store: &Store,
    ctx: Ctx<'_>,
    item_id: &str,
    name: &str,
    unit_price_minor: i64,
) -> CoreResult<Vec<CartLineView>> {
    add_resolved(
        store,
        ctx,
        StoredLine {
            item_id: item_id.to_string(),
            name: name.to_string(),
            unit_price_minor,
            qty: 1,
            size_label: None,
            addons: vec![],
            optionals: vec![],
            notes: None,
            bundle_id: None,
            bundle_components: vec![],
        },
    )
}

/// Set the absolute quantity for a line (by its key); `qty <= 0` removes it.
pub(crate) fn set_qty(
    store: &Store,
    ctx: Ctx<'_>,
    line_key: &str,
    qty: i64,
) -> CoreResult<Vec<CartLineView>> {
    let mut lines = load(store, ctx)?;
    if qty <= 0 {
        lines.retain(|l| signature(l) != line_key);
    } else if let Some(l) = lines.iter_mut().find(|l| signature(l) == line_key) {
        l.qty = qty;
    }
    save(store, ctx, &lines)?;
    Ok(view(&lines))
}

/// Where a swiped-away line is stashed so `restore_last_removed` can undo it.
const K_LAST_REMOVED: &str = "cart:last_removed";

/// Remove a line entirely (by its key), stashing it so the host can offer an
/// "Undo" (see `restore_last_removed`).
pub(crate) fn remove(store: &Store, ctx: Ctx<'_>, line_key: &str) -> CoreResult<Vec<CartLineView>> {
    let mut lines = load(store, ctx)?;
    let removed: Vec<StoredLine> = lines
        .iter()
        .filter(|l| signature(l) == line_key)
        .cloned()
        .collect();
    lines.retain(|l| signature(l) != line_key);
    if !removed.is_empty() {
        store.kv_put(
            &ctx_key(ctx, K_LAST_REMOVED)?,
            &serde_json::to_string(&removed)?,
        )?;
    }
    save(store, ctx, &lines)?;
    Ok(view(&lines))
}

/// Re-insert the most recently `remove`d line(s) — the Undo for a swipe-delete.
/// Merges back into an identical line (same signature) if one exists, else
/// re-appends. Clears the stash; a no-op when nothing was stashed.
pub(crate) fn restore_last_removed(store: &Store, ctx: Ctx<'_>) -> CoreResult<Vec<CartLineView>> {
    let stash: Vec<StoredLine> = match store.kv_get(&ctx_key(ctx, K_LAST_REMOVED)?)? {
        Some(j) => serde_json::from_str(&j).unwrap_or_default(),
        None => Vec::new(),
    };
    let mut lines = load(store, ctx)?;
    for r in stash {
        match lines.iter_mut().find(|l| signature(l) == signature(&r)) {
            Some(l) => l.qty += r.qty,
            None => lines.push(r),
        }
    }
    store.kv_put(&ctx_key(ctx, K_LAST_REMOVED)?, "[]")?; // consume the stash (no double-undo)
    save(store, ctx, &lines)?;
    Ok(view(&lines))
}

/// Empty the cart + its discount (e.g. after checkout or on sign-out).
pub(crate) fn clear(store: &Store, ctx: Ctx<'_>) -> CoreResult<()> {
    clear_discount(store, ctx)?;
    set_note(store, ctx, None)?;
    store.kv_put(&ctx_key(ctx, K_LAST_REMOVED)?, "[]")?; // a stale undo must not resurrect a sold line
    store.kv_put(&key_for(ctx, K_META), "{}")?; // the spent cart forgets its name/draft/booking
    save(store, ctx, &[])
}

// ── cart payload (the wire shape a held order carries) ───────────────────────
//
// A server-backed held order stores the WHOLE working cart as one opaque JSON
// payload: the raw `StoredLine`s plus the selected discount. The backend never
// interprets it — these functions are the only (de)serialization boundary, so
// a payload written by any till restores bit-identically on any other.

/// Snapshot the current cart (lines + discount) as the held-order payload.
pub(crate) fn cart_payload(store: &Store, ctx: Ctx<'_>) -> CoreResult<serde_json::Value> {
    let lines = load(store, ctx)?;
    Ok(serde_json::json!({
        "lines": serde_json::to_value(&lines)?,
        "discount_id": discount_id(store, ctx)?,
        "note": note(store, ctx)?,
    }))
}

/// Replace the cart with a held-order payload (lines + discount). Malformed
/// lines are dropped defensively — a corrupt payload must not wedge the till.
/// Returns the restored cart view.
pub(crate) fn set_cart_payload(
    store: &Store,
    ctx: Ctx<'_>,
    payload: &serde_json::Value,
) -> CoreResult<Vec<CartLineView>> {
    let lines: Vec<StoredLine> = payload
        .get("lines")
        .cloned()
        .map(|v| serde_json::from_value(v).unwrap_or_default())
        .unwrap_or_default();
    match payload.get("discount_id").and_then(|v| v.as_str()) {
        Some(d) if !d.is_empty() => set_discount(store, ctx, d)?,
        _ => clear_discount(store, ctx)?,
    }
    set_note(store, ctx, payload.get("note").and_then(|v| v.as_str()))?;
    store.kv_put(&ctx_key(ctx, K_LAST_REMOVED)?, "[]")?; // a stale undo must not leak across orders
    save(store, ctx, &lines)?;
    Ok(view(&lines))
}

/// `(item_count, total_minor)` of a held-order payload — the strip/list badges,
/// computed without touching the live cart.
pub(crate) fn payload_counts(payload: &serde_json::Value) -> (i64, i64) {
    let lines: Vec<StoredLine> = payload
        .get("lines")
        .cloned()
        .map(|v| serde_json::from_value(v).unwrap_or_default())
        .unwrap_or_default();
    (
        lines.iter().map(|l| l.qty).sum(),
        lines.iter().map(line_total).sum(),
    )
}

// ── drafts (parked / held carts) ─────────────────────────────────────────────
//
// LEGACY device-local drafts. Superseded by the server-backed `held` module
// (branch-shared, table-owning); these remain only so `held::migrate_legacy`
// can lift pre-existing parked carts off a device into the new model.

#[derive(Serialize, Deserialize, Clone, Debug)]
struct StoredDraft {
    id: String,
    name: String,
    created_at: String,
    lines: Vec<StoredLine>,
}

/// A parked cart, summarized for the drafts list. `table_*`/`locked_by_other`
/// come from the server-backed held-order model (always unset on the legacy
/// local path).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DraftView {
    pub id: String,
    pub name: String,
    pub item_count: i64,
    pub total_minor: i64,
    pub created_at: String,
    /// The floor table this held order owns, if any.
    pub table_id: Option<String>,
    pub table_label: Option<String>,
    /// True when ANOTHER till is editing this order right now (resume claim
    /// held elsewhere) — the chip renders locked and cannot be restored.
    pub locked_by_other: bool,
}

/// The identity a cart is parked under: its free-text name (may be empty), the
/// draft it was restored from (a re-park keeps that draft), and when it was
/// started (the strip's order).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct HeldParkInput {
    pub name: String,
    pub draft_id: Option<String>,
    pub started_at: Option<String>,
}

/// What `switch_to_draft` left in hand: the restored lines and the order's own
/// identity, so the host adopts it without a second read.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct DraftSwitchView {
    pub lines: Vec<CartLineView>,
    /// The context now active — the draft's table, or `None` for the counter.
    pub table_id: Option<String>,
    pub table_label: Option<String>,
    pub name: String,
    pub created_at: String,
    /// A cart parked on the way asked for a table that was already taken; it
    /// parked without it.
    pub table_taken: bool,
}

fn load_drafts(store: &Store) -> CoreResult<Vec<StoredDraft>> {
    match store.kv_get(K_DRAFTS)? {
        Some(json) => Ok(serde_json::from_str(&json).unwrap_or_default()),
        None => Ok(Vec::new()),
    }
}
fn save_drafts(store: &Store, drafts: &[StoredDraft]) -> CoreResult<()> {
    store.kv_put(K_DRAFTS, &serde_json::to_string(drafts)?)
}

/// Park the current cart as a named draft and empty the cart. `id`/`now` are
/// host-supplied (the core stays free of clock/uuid). Errors if the cart is empty.
#[cfg_attr(not(test), allow(dead_code))] // legacy path: exercised by tests + kept for reference
pub(crate) fn hold(
    store: &Store,
    ctx: Ctx<'_>,
    id: String,
    name: String,
    now: String,
) -> CoreResult<()> {
    let lines = load(store, ctx)?;
    if lines.is_empty() {
        return Err(crate::error::CoreError::Validation {
            field: "cart".into(),
            detail: "cart is empty".into(),
        });
    }
    let mut drafts = load_drafts(store)?;
    drafts.push(StoredDraft {
        id,
        name,
        created_at: now,
        lines,
    });
    save_drafts(store, &drafts)?;
    clear(store, ctx)
}

/// The parked drafts, newest first.
#[cfg_attr(not(test), allow(dead_code))] // legacy path: exercised by tests + kept for reference
pub(crate) fn drafts(store: &Store) -> CoreResult<Vec<DraftView>> {
    let mut out: Vec<DraftView> = load_drafts(store)?
        .iter()
        .map(|d| DraftView {
            id: d.id.clone(),
            name: d.name.clone(),
            item_count: d.lines.iter().map(|l| l.qty).sum(),
            total_minor: d.lines.iter().map(line_total).sum(),
            created_at: d.created_at.clone(),
            table_id: None,
            table_label: None,
            locked_by_other: false,
        })
        .collect();
    out.reverse();
    Ok(out)
}

/// Drain the LEGACY local drafts for migration into the server-backed held
/// model: returns `(id, name, created_at, payload)` per draft and clears the
/// legacy key, so the lift happens exactly once.
pub(crate) fn take_legacy_drafts(
    store: &Store,
) -> CoreResult<Vec<(String, String, String, serde_json::Value)>> {
    let drafts = load_drafts(store)?;
    if drafts.is_empty() {
        return Ok(Vec::new());
    }
    let out = drafts
        .iter()
        .map(|d| {
            Ok((
                d.id.clone(),
                d.name.clone(),
                d.created_at.clone(),
                serde_json::json!({
                    "lines": serde_json::to_value(&d.lines)?,
                    "discount_id": serde_json::Value::Null,
                }),
            ))
        })
        .collect::<CoreResult<Vec<_>>>()?;
    save_drafts(store, &[])?;
    Ok(out)
}

/// Restore a draft into the cart (replacing any current lines) and drop it from
/// the drafts list. Returns the new cart view.
#[cfg_attr(not(test), allow(dead_code))] // legacy path: exercised by tests + kept for reference
pub(crate) fn restore_draft(
    store: &Store,
    ctx: Ctx<'_>,
    id: &str,
) -> CoreResult<Vec<CartLineView>> {
    let mut drafts = load_drafts(store)?;
    let Some(pos) = drafts.iter().position(|d| d.id == id) else {
        return Ok(view(&load(store, ctx)?));
    };
    let draft = drafts.remove(pos);
    save_drafts(store, &drafts)?;
    clear_discount(store, ctx)?;
    save(store, ctx, &draft.lines)?;
    Ok(view(&draft.lines))
}

/// Discard a parked draft without restoring it.
#[cfg_attr(not(test), allow(dead_code))] // legacy path: exercised by tests + kept for reference
pub(crate) fn discard_draft(store: &Store, id: &str) -> CoreResult<()> {
    let mut drafts = load_drafts(store)?;
    drafts.retain(|d| d.id != id);
    save_drafts(store, &drafts)
}

// ── discount ─────────────────────────────────────────────────────────────────

pub(crate) fn set_discount(store: &Store, ctx: Ctx<'_>, discount_id: &str) -> CoreResult<()> {
    store.kv_put(&ctx_key(ctx, K_DISCOUNT)?, discount_id)
}
pub(crate) fn clear_discount(store: &Store, ctx: Ctx<'_>) -> CoreResult<()> {
    store.kv_put(&ctx_key(ctx, K_DISCOUNT)?, "")
}
/// Set (or, with `None` / blank, clear) the order note of the cart in hand.
pub(crate) fn set_note(store: &Store, ctx: Ctx<'_>, note: Option<&str>) -> CoreResult<()> {
    let note = note.map(str::trim).unwrap_or("");
    store.kv_put(&ctx_key(ctx, K_NOTE)?, note)
}
/// The cart's order note, or `None` when blank.
pub(crate) fn note(store: &Store, ctx: Ctx<'_>) -> CoreResult<Option<String>> {
    Ok(store
        .kv_get(&ctx_key(ctx, K_NOTE)?)?
        .filter(|s| !s.trim().is_empty()))
}
/// The selected discount id, or `None`.
pub(crate) fn discount_id(store: &Store, ctx: Ctx<'_>) -> CoreResult<Option<String>> {
    Ok(store
        .kv_get(&ctx_key(ctx, K_DISCOUNT)?)?
        .filter(|s| !s.is_empty() && s != "null"))
}

/// Resolve the cart's selected discount → (kind, value) from the cached catalog.
/// Inactive / absent / unknown → no discount. The pricing engine then clamps it.

/// The stored value of a discount — a FRACTION for a percentage, minor units
/// for a fixed one.
///
/// Read `value_rate`, never `value`. `value` is the LEGACY spelling on the
/// wire: an integer, 0-100 for a percentage, kept because every till in the
/// field was generated against `integer` and a double there fails to
/// deserialise the whole object rather than reading as a small number.
/// Reading `value` as if it were the fraction charges 1400% instead of 14%.
///
/// The fallback is for a server that predates the split, not a preference:
/// if `value_rate` is absent, `value` still carries 0-100 and has to come
/// back down. A percentage is told apart by `dtype` here because we have it.
pub(crate) fn discount_rate(d: &models::Discount) -> f64 {
    if let Some(r) = d.value_rate {
        return r;
    }
    if d.dtype == "percentage" {
        d.value as f64 / 100.0
    } else {
        d.value as f64
    }
}

pub(crate) fn discount(store: &Store, ctx: Ctx<'_>) -> CoreResult<(DiscountKind, f64)> {
    let id = match discount_id(store, ctx)? {
        Some(id) => id,
        None => return Ok((DiscountKind::None, 0.0)),
    };
    let raw: Vec<models::Discount> = match store.kv_get(menu::K_DISCOUNTS)? {
        Some(j) => serde_json::from_str(&j).unwrap_or_default(),
        None => Vec::new(),
    };
    match raw.iter().find(|d| d.id.to_string() == id && d.is_active) {
        Some(d) => Ok((kind_from_dtype(&d.dtype), discount_rate(d))),
        None => Ok((DiscountKind::None, 0.0)),
    }
}

fn kind_from_dtype(dtype: &str) -> DiscountKind {
    match dtype {
        "percentage" => DiscountKind::Percentage,
        "fixed" => DiscountKind::Fixed,
        _ => DiscountKind::None,
    }
}

/// Map a stored line to the pricing engine's `CartLine` (the money input).
fn priced(l: &StoredLine) -> pricing::CartLine {
    pricing::CartLine {
        quantity: l.qty,
        unit_price: l.unit_price_minor,
        is_bundle: l.bundle_id.is_some(),
        reward_units: 0,
        addons: l
            .addons
            .iter()
            .map(|a| pricing::AddonSel {
                price_modifier: a.price_modifier_minor,
                quantity: a.qty,
            })
            .collect(),
        optionals: l
            .optionals
            .iter()
            .map(|o| pricing::OptionalSel {
                price: o.price_minor,
            })
            .collect(),
        bundle_components: l
            .bundle_components
            .iter()
            .map(|c| pricing::BundleComponentSel {
                addons: c
                    .addons
                    .iter()
                    .map(|a| pricing::AddonSel {
                        price_modifier: a.price_modifier_minor,
                        quantity: a.qty,
                    })
                    .collect(),
                optionals: c
                    .optionals
                    .iter()
                    .map(|o| pricing::OptionalSel {
                        price: o.price_minor,
                    })
                    .collect(),
            })
            .collect(),
    }
}

/// Price the cart under `policy` via the pricing engine, applying the selected
/// discount before tax.
pub(crate) fn totals(
    store: &Store,
    ctx: Ctx<'_>,
    policy: &crate::tax::TaxPolicy,
) -> CoreResult<CartTotals> {
    totals_with_rewards(store, ctx, policy, &Default::default())
}

/// [`totals`] with loyalty rewards covering units of some lines (by cart
/// position): covered first, then the discount on what is left — the
/// Charge screen's hero, change and split all read this.
pub(crate) fn totals_with_rewards(
    store: &Store,
    ctx: Ctx<'_>,
    policy: &crate::tax::TaxPolicy,
    reward_units: &std::collections::HashMap<usize, i64>,
) -> CoreResult<CartTotals> {
    use rust_decimal::prelude::ToPrimitive;
    let lines = load(store, ctx)?;
    let item_count = lines.iter().map(|l| l.qty).sum();
    let (discount_kind, discount_value) = discount(store, ctx)?;
    let priced = pricing::price_cart(PriceCartInput {
        lines: lines
            .iter()
            .enumerate()
            .map(|(i, l)| {
                let mut line = priced(l);
                if !line.is_bundle {
                    line.reward_units = reward_units.get(&i).copied().unwrap_or(0);
                }
                line
            })
            .collect(),
        discount_kind,
        discount_value,
        tax_rate: policy.tax_rate.to_f64().unwrap_or(0.0),
        tax_inclusive: policy.tax_inclusive,
        service_charge_rate: policy.service_charge_rate.to_f64().unwrap_or(0.0),
        service_charge_taxable: policy.service_charge_taxable,
        amount_tendered: None,
        cash_tip: 0,
    });
    Ok(CartTotals {
        item_count,
        subtotal_minor: priced.subtotal_minor,
        discount_minor: priced.discount_minor,
        tax_minor: priced.tax_minor,
        service_charge_minor: priced.service_charge_minor,
        total_minor: priced.total_minor,
    })
}

#[cfg(test)]
#[allow(dead_code)]
fn tax_policy_at(rate: f64) -> crate::tax::TaxPolicy {
    use std::str::FromStr;
    crate::tax::TaxPolicy {
        tax_rate: rust_decimal::Decimal::from_str(&rate.to_string()).unwrap(),
        ..Default::default()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn store() -> Store {
        Store::open("").unwrap()
    }

    fn addon(id: &str, kind: &str, price: i64) -> menu::AddonItemView {
        menu::AddonItemView {
            id: id.into(),
            name: id.into(),
            addon_type: kind.into(),
            default_price_minor: price,
            is_active: true,
            ingredients: vec![],
        }
    }

    fn item() -> menu::MenuItemView {
        menu::MenuItemView {
            id: "latte".into(),
            name: "Latte".into(),
            description: None,
            category_id: None,
            base_price_minor: 5000,
            image_url: None,
            local_image_path: None,
            is_active: true,
            default_milk_addon_id: Some("oat".into()), // base milk = oat @1500
            allowed_addon_ids: vec![],
            sizes: vec![menu::ItemSizeView {
                id: "lg".into(),
                label: "Large".into(),
                price_minor: 6000,
                is_active: true,
            }],
            addon_slots: vec![],
            optional_fields: vec![menu::OptionalFieldView {
                id: "van".into(),
                name: "Vanilla".into(),
                price_minor: 300,
                is_active: true,
                ingredient_name: None,
                ingredient_unit: None,
                quantity_used: None,
                org_ingredient_id: None,
            }],
            recipes: vec![],
            recipe_steps: vec![],
        }
    }

    fn catalog() -> Vec<menu::AddonItemView> {
        vec![
            addon("oat", "milk_type", 1500),    // the default-milk base
            addon("almond", "milk_type", 2000), // swap → delta 500
            addon("whole", "milk_type", 0),     // downgrade → 0
            addon("shot", "extra", 800),        // additive → full
        ]
    }

    /// Two groups can each offer an option for the recipe's bean (Coffee
    /// Beans' "Colombian", Espresso Beans' "Colombian Espresso"). Each group
    /// preselects ITS OWN match — not the catalog's first, which the other
    /// group doesn't carry.
    #[test]
    fn swap_default_picks_the_match_this_group_offers() {
        let bean = |id: &str| {
            let mut a = addon(id, "coffee_type", 0);
            a.ingredients = vec![menu::AddonIngredientView {
                ingredient_name: "Colombian Espresso".into(),
                unit: "g".into(),
                quantity: 18.0,
                org_ingredient_id: Some("ing-col".into()),
            }];
            a
        };
        let catalog = vec![bean("colombian"), bean("colombian-espresso")];
        let mut espresso = item();
        espresso.recipes = vec![menu::RecipeLineView {
            ingredient_name: "Colombian Espresso".into(),
            quantity: 18.0,
            unit: "g".into(),
            size_label: None,
            category: "coffee_bean".into(),
            org_ingredient_id: Some("ing-col".into()),
        }];
        let offered = ["colombian-espresso", "decaf"];
        assert_eq!(
            swap_default_in(&espresso, &catalog, "coffee_type", &offered, |o| o),
            Some("colombian-espresso".to_string())
        );
        let none: [&str; 1] = ["decaf"];
        assert_eq!(
            swap_default_in(&espresso, &catalog, "coffee_type", &none, |o| o),
            None
        );
    }

    fn names(v: &[CartLineView]) -> Vec<String> {
        v.iter().map(|l| format!("{}x{}", l.name, l.qty)).collect()
    }

    /// Every table and the counter keep their own cart; nothing is "active".
    #[test]
    fn each_context_keeps_its_own_cart() {
        let s = store();
        let (t1, t2) = (Some("t1"), Some("t2"));
        add(&s, None, "c", "Cookie", 300).unwrap();
        add(&s, t1, "a", "Latte", 5000).unwrap();
        add(&s, t1, "a", "Latte", 5000).unwrap();
        add(&s, t1, "b", "Mocha", 4000).unwrap();
        set_discount(&s, t1, "d1").unwrap();
        set_note(&s, t1, Some("window")).unwrap();

        // T2: empty, and no T1 discount / note leaks in.
        assert!(lines(&s, t2).unwrap().is_empty());
        assert_eq!(discount_id(&s, t2).unwrap(), None);
        assert_eq!(note(&s, t2).unwrap(), None);
        assert_eq!(note(&s, None).unwrap(), None);

        // Takeaway untouched; an empty-string context is takeaway.
        assert_eq!(names(&lines(&s, None).unwrap()), vec!["Cookiex1"]);
        assert_eq!(names(&lines(&s, Some("")).unwrap()), vec!["Cookiex1"]);
        assert_eq!(discount_id(&s, None).unwrap(), None);

        // qty / remove / undo act on their context only.
        set_qty(&s, None, "c", 3).unwrap();
        assert_eq!(names(&lines(&s, t1).unwrap()), vec!["Lattex2", "Mochax1"]);
        remove(&s, t1, "b").unwrap();
        assert!(restore_last_removed(&s, None).unwrap().len() == 1); // no stash here
        assert_eq!(
            names(&restore_last_removed(&s, t1).unwrap()),
            vec!["Lattex2", "Mochax1"]
        );
        assert_eq!(names(&lines(&s, None).unwrap()), vec!["Cookiex3"]);
        assert_eq!(cart_payload(&s, t1).unwrap()["discount_id"], "d1");

        // Firing T1 clears only T1.
        clear(&s, t1).unwrap();
        assert!(lines(&s, t1).unwrap().is_empty());
        assert_eq!(discount_id(&s, t1).unwrap(), None);
        assert_eq!(names(&lines(&s, None).unwrap()), vec!["Cookiex3"]);
    }

    /// Meta lives per context, survives a reopen of the same db, and is
    /// forgotten when that cart is spent.
    #[test]
    fn meta_is_per_context_and_persists() {
        let dir = std::env::temp_dir().join(format!("cartmeta-{}", uuid::Uuid::new_v4()));
        let path = dir.to_string_lossy().to_string();
        {
            let s = Store::open(&path).unwrap();
            s.kv_put(K_LEGACY_CONTEXT, "t1").unwrap();
            add(&s, None, "c", "Cookie", 300).unwrap();
            add(&s, Some("t1"), "a", "Latte", 5000).unwrap();
            let m = CartMeta {
                name: "Sara".into(),
                draft_id: Some("d9".into()),
                booking_id: Some("b1".into()),
                table_label: Some("T1".into()),
                guest_name: Some("Sara".into()),
                started_at: Some("2026-09-13T10:00:00Z".into()),
                covers: Some(4),
            };
            set_meta(&s, Some("t1"), &m).unwrap();
            set_meta(
                &s,
                None,
                &CartMeta {
                    name: "Walk-in".into(),
                    ..Default::default()
                },
            )
            .unwrap();
        }
        let s = Store::open(&path).unwrap();
        forget_legacy_context(&s).unwrap();
        assert_eq!(s.kv_get(K_LEGACY_CONTEXT).unwrap(), None);
        assert_eq!(names(&lines(&s, None).unwrap()), vec!["Cookiex1"]);
        assert_eq!(names(&lines(&s, Some("t1")).unwrap()), vec!["Lattex1"]);
        assert_eq!(meta(&s, Some("t1")).unwrap().covers, Some(4));
        assert_eq!(
            meta(&s, Some("t1")).unwrap().draft_id.as_deref(),
            Some("d9")
        );
        assert_eq!(meta(&s, None).unwrap().name, "Walk-in");
        assert_eq!(meta(&s, Some("t2")).unwrap(), CartMeta::default());
        assert_eq!(
            table_contexts_with_lines(&s).unwrap(),
            vec!["t1".to_string()]
        );
        clear(&s, Some("t1")).unwrap();
        assert_eq!(meta(&s, Some("t1")).unwrap(), CartMeta::default());
        assert_eq!(meta(&s, None).unwrap().name, "Walk-in");
        let _ = std::fs::remove_file(&path);
    }

    /// Sign-out / shift close empties every context and its meta.
    #[test]
    fn clear_all_empties_every_context() {
        let s = store();
        add(&s, None, "c", "Cookie", 300).unwrap();
        add(&s, Some("t1"), "a", "Latte", 5000).unwrap();
        set_meta(
            &s,
            Some("t1"),
            &CartMeta {
                name: "x".into(),
                ..Default::default()
            },
        )
        .unwrap();
        clear_all(&s).unwrap();
        assert!(lines(&s, None).unwrap().is_empty());
        assert!(lines(&s, Some("t1")).unwrap().is_empty());
        assert_eq!(meta(&s, Some("t1")).unwrap(), CartMeta::default());
    }
    #[test]
    fn add_merges_and_appends() {
        let s = store();
        assert!(lines(&s, None).unwrap().is_empty());
        add(&s, None, "a", "Latte", 5000).unwrap();
        let v = add(&s, None, "a", "Latte", 5000).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 2);
        assert_eq!(v[0].line_total_minor, 10_000);
        assert_eq!(v[0].key, "a"); // option-less → key is item_id
        let v = add(&s, None, "b", "Tea", 3000).unwrap();
        assert_eq!(v.len(), 2);
    }

    #[test]
    fn set_qty_and_remove_by_key() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        let v = set_qty(&s, None, "a", 4).unwrap();
        assert_eq!(v[0].qty, 4);
        assert!(set_qty(&s, None, "a", 0).unwrap().is_empty());
        add(&s, None, "a", "Latte", 5000).unwrap();
        assert!(remove(&s, None, "a").unwrap().is_empty());
    }

    #[test]
    fn resolve_line_prices_size_swap_additive_and_optionals() {
        // Large(6000) + almond(milk swap: 2000-1500=500) + 2×shot(additive 800)
        // + vanilla optional(300), qty 2.
        let line = resolve_line(
            &item(),
            &catalog(),
            Some("Large".into()),
            &[
                AddonSelection {
                    addon_item_id: "almond".into(),
                    qty: 1,
                },
                AddonSelection {
                    addon_item_id: "shot".into(),
                    qty: 2,
                },
            ],
            &["van".into()],
            2,
            None,
        );
        assert_eq!(line.unit_price_minor, 6000);
        assert_eq!(line.addons.len(), 2);
        let almond = line
            .addons
            .iter()
            .find(|a| a.addon_item_id == "almond")
            .unwrap();
        assert_eq!(almond.price_modifier_minor, 500); // swap delta over oat base
        let shot = line
            .addons
            .iter()
            .find(|a| a.addon_item_id == "shot")
            .unwrap();
        assert_eq!(shot.price_modifier_minor, 800); // additive: full
        assert_eq!(shot.qty, 2);
        assert_eq!(line.optionals[0].price_minor, 300);
        // line unit = 6000 + (500*1 + 800*2) + 300 = 8400 ; ×2 = 16800
        assert_eq!(line_total(&line), 16_800);
    }

    #[test]
    fn milk_downgrade_is_free_not_negative() {
        let line = resolve_line(
            &item(),
            &catalog(),
            None,
            &[AddonSelection {
                addon_item_id: "whole".into(),
                qty: 1,
            }],
            &[],
            1,
            None,
        );
        // whole(0) - oat base(1500) = -1500 → clamped to 0.
        assert_eq!(line.addons[0].price_modifier_minor, 0);
        assert_eq!(line.unit_price_minor, 5000); // no size → base
    }

    #[test]
    fn no_milk_base_treats_swap_as_full() {
        let mut it = item();
        it.default_milk_addon_id = None; // no base → milk swap charges full
        let line = resolve_line(
            &it,
            &catalog(),
            None,
            &[AddonSelection {
                addon_item_id: "almond".into(),
                qty: 1,
            }],
            &[],
            1,
            None,
        );
        assert_eq!(line.addons[0].price_modifier_minor, 2000);
    }

    fn coffee(id: &str, price: i64, ing: &str) -> menu::AddonItemView {
        menu::AddonItemView {
            id: id.into(),
            name: id.into(),
            addon_type: "coffee_type".into(),
            default_price_minor: price,
            is_active: true,
            ingredients: vec![menu::AddonIngredientView {
                ingredient_name: ing.into(),
                unit: "g".into(),
                quantity: 18.0,
                org_ingredient_id: Some(ing.into()),
            }],
        }
    }

    #[test]
    fn coffee_swap_charges_delta_over_recipe_base_not_full() {
        // The item's recipe uses the house bean; its coffee_type addon (1200) is the
        // DEFAULT. Swapping to a single-origin bean (1800) costs the delta 600 — not
        // the full 1800 (the POS bug) — and re-selecting the house bean costs 0.
        let mut it = item();
        it.recipes = vec![menu::RecipeLineView {
            ingredient_name: "House Bean".into(),
            quantity: 18.0,
            unit: "g".into(),
            size_label: None,
            category: "coffee_bean".into(),
            org_ingredient_id: Some("bean-house".into()),
        }];
        let catalog = vec![
            coffee("house", 1200, "bean-house"),
            coffee("single", 1800, "bean-single"),
        ];

        let line = resolve_line(
            &it,
            &catalog,
            None,
            &[AddonSelection {
                addon_item_id: "single".into(),
                qty: 1,
            }],
            &[],
            1,
            None,
        );
        assert_eq!(
            line.addons[0].price_modifier_minor, 600,
            "coffee swap = 1800 - 1200 base"
        );

        let line = resolve_line(
            &it,
            &catalog,
            None,
            &[AddonSelection {
                addon_item_id: "house".into(),
                qty: 1,
            }],
            &[],
            1,
            None,
        );
        assert_eq!(
            line.addons[0].price_modifier_minor, 0,
            "re-selecting the default coffee is free"
        );
    }

    #[test]
    fn coffee_swap_without_recipe_base_falls_back_to_full() {
        // No coffee_bean recipe line → no base derivable → full price (best-effort).
        let line = resolve_line(
            &item(),
            &[coffee("single", 1800, "bean-single")],
            None,
            &[AddonSelection {
                addon_item_id: "single".into(),
                qty: 1,
            }],
            &[],
            1,
            None,
        );
        assert_eq!(line.addons[0].price_modifier_minor, 1800);
    }

    #[test]
    fn configured_lines_merge_only_when_identical() {
        let s = store();
        let mk = |milk: &str| {
            resolve_line(
                &item(),
                &catalog(),
                Some("Large".into()),
                &[AddonSelection {
                    addon_item_id: milk.into(),
                    qty: 1,
                }],
                &[],
                1,
                None,
            )
        };
        add_resolved(&s, None, mk("almond")).unwrap();
        let v = add_resolved(&s, None, mk("almond")).unwrap(); // same config → merge
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 2);
        let v = add_resolved(&s, None, mk("whole")).unwrap(); // different milk → new line
        assert_eq!(v.len(), 2);
        // qty + remove by the configured key.
        let key = v[0].key.clone();
        assert!(key.contains("latte|Large"));
        let v = set_qty(&s, None, &key, 5).unwrap();
        assert_eq!(v.iter().find(|l| l.key == key).unwrap().qty, 5);
    }

    fn configured(milk: &str, qty: i64) -> StoredLine {
        resolve_line(
            &item(),
            &catalog(),
            Some("Large".into()),
            &[AddonSelection {
                addon_item_id: milk.into(),
                qty: 1,
            }],
            &[],
            qty,
            None,
        )
    }

    /// An edit replaces the line where it stood, in one write.
    #[test]
    fn replace_swaps_the_line_in_place() {
        let s = store();
        add(&s, None, "tea", "Tea", 2000).unwrap();
        let v = add_resolved(&s, None, configured("almond", 1)).unwrap();
        add(&s, None, "cake", "Cake", 3000).unwrap();
        let key = v[1].key.clone();
        let v = replace_resolved(&s, None, &key, configured("whole", 2)).unwrap();
        assert_eq!(names(&v), vec!["Teax1", "Lattex2", "Cakex1"]);
        assert!(v[1].key.contains("whole"), "the new milk: {}", v[1].key);
        assert!(!v.iter().any(|l| l.key == key), "the old line is gone");
    }

    /// The bug: a failed edit used to delete the line. A key the cart no longer
    /// holds refuses and leaves every line exactly as it was.
    #[test]
    fn replace_of_a_missing_line_refuses_and_keeps_the_cart() {
        let s = store();
        let before = add_resolved(&s, None, configured("almond", 1)).unwrap();
        let err = replace_resolved(&s, None, "not-a-key", configured("whole", 1));
        assert!(matches!(err, Err(CoreError::Validation { .. })));
        assert_eq!(lines(&s, None).unwrap(), before);
    }

    /// An edit that makes a line identical to another one merges, like an add.
    #[test]
    fn replace_into_an_identical_line_merges() {
        let s = store();
        add_resolved(&s, None, configured("whole", 1)).unwrap();
        let v = add_resolved(&s, None, configured("almond", 1)).unwrap();
        let almond = v.iter().find(|l| l.key.contains("almond")).unwrap();
        let v = replace_resolved(&s, None, &almond.key.clone(), configured("whole", 3)).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 4);
    }

    /// The sheet's figure is the cart's figure, swap collapse included.
    #[test]
    fn preview_matches_what_the_cart_charges() {
        let s = store();
        // The recipe's oat AND a picked almond: the core keeps one milk.
        let line = resolve_line(
            &item(),
            &catalog(),
            Some("Large".into()),
            &[
                AddonSelection {
                    addon_item_id: "oat".into(),
                    qty: 1,
                },
                AddonSelection {
                    addon_item_id: "almond".into(),
                    qty: 1,
                },
            ],
            &["van".into()],
            2,
            None,
        );
        let p = preview_line(&line);
        let v = add_resolved(&s, None, line).unwrap();
        assert_eq!(p.line_total_minor, v[0].line_total_minor);
        assert_eq!(p.extras_minor, 500 + 300);
        assert_eq!(p.unit_total_minor, 6000 + 800);
        assert_eq!(p.line_total_minor, 13_600);
    }

    #[test]
    fn totals_include_addon_and_optional_money() {
        let s = store();
        // base 5000 + almond(500) + vanilla(300) = 5800, qty 2 → 11600 subtotal.
        add_resolved(
            &s,
            None,
            resolve_line(
                &item(),
                &catalog(),
                None,
                &[AddonSelection {
                    addon_item_id: "almond".into(),
                    qty: 1,
                }],
                &["van".into()],
                2,
                None,
            ),
        )
        .unwrap();
        let t = totals(&s, None, &tax_policy_at(0.14)).unwrap();
        assert_eq!(t.item_count, 2);
        assert_eq!(t.subtotal_minor, 11_600);
        assert_eq!(t.tax_minor, 1624); // round(11600 * 0.14)
        assert_eq!(t.total_minor, 13_224);
    }

    #[test]
    fn modifier_groups_project_slots_types_and_optionals() {
        // A configured milk slot (required, exactly one) + an allowlist limited to
        // oat/almond/shot. Expect: [slot milk (oat, almond)], [type:extra (shot)],
        // [optionals (vanilla)] — with charged prices identical to the flat sheet.
        let mut it = item();
        it.addon_slots = vec![menu::AddonSlotView {
            id: "slot-milk".into(),
            label: Some("Milk".into()),
            addon_type: "milk_type".into(),
            is_required: true,
            min_selections: 1,
            max_selections: Some(1),
        }];
        it.allowed_addon_ids = vec!["oat".into(), "almond".into(), "shot".into()];
        let groups = item_modifier_groups(&it, &catalog());
        assert_eq!(groups.len(), 3);

        let milk = &groups[0];
        assert_eq!(milk.group_id, "slot-milk");
        assert_eq!(milk.name, "Milk");
        assert_eq!(
            (milk.is_required, milk.min_selections, milk.max_selections),
            (true, 1, Some(1))
        );
        let ids: Vec<&str> = milk.options.iter().map(|o| o.id.as_str()).collect();
        assert_eq!(ids, ["oat", "almond"], "allowlist filters 'whole' out");

        // Grouped charged prices == flat-sheet charged prices (same swap rules) —
        // the grouped view must be money-identical to the parity-proven flat path.
        let flat = item_addons(&it, &catalog());
        for o in groups
            .iter()
            .filter(|g| g.kind == ModifierGroupKind::Addon)
            .flat_map(|g| &g.options)
        {
            let f = flat.iter().find(|a| a.addon_item_id == o.id).unwrap();
            assert_eq!(
                o.charged_price_minor, f.charged_price_minor,
                "option {}",
                o.id
            );
        }

        let extra = &groups[1];
        assert_eq!(extra.group_id, "type:extra");
        assert_eq!(extra.options.len(), 1);
        assert_eq!(extra.options[0].id, "shot");
        assert_eq!(extra.options[0].charged_price_minor, 800);

        let opts = &groups[2];
        assert_eq!(opts.kind, ModifierGroupKind::Optional);
        assert_eq!(opts.options[0].id, "van");
        assert_eq!(opts.options[0].charged_price_minor, 300);
    }

    #[test]
    fn modifier_groups_default_when_unslotted_milk_single_select() {
        // No slots, no allowlist: milk becomes a default single-select group and
        // extras an uncapped one; group order is milk → extra → optionals.
        let groups = item_modifier_groups(&item(), &catalog());
        let ids: Vec<&str> = groups.iter().map(|g| g.group_id.as_str()).collect();
        assert_eq!(ids, ["type:milk_type", "type:extra", "options"]);
        assert_eq!(
            groups[0].max_selections,
            Some(1),
            "milk family is single-select"
        );
        assert_eq!(groups[1].max_selections, None);
        // The oat default costs 0, almond the 500 delta (swap rules intact).
        let p = |g: &ModifierGroupView, id: &str| {
            g.options
                .iter()
                .find(|o| o.id == id)
                .unwrap()
                .charged_price_minor
        };
        assert_eq!(p(&groups[0], "oat"), 0);
        assert_eq!(p(&groups[0], "almond"), 500);
    }

    #[test]
    fn validate_group_selections_enforces_min_and_max() {
        let mut it = item();
        it.addon_slots = vec![menu::AddonSlotView {
            id: "slot-milk".into(),
            label: None,
            addon_type: "milk_type".into(),
            is_required: true,
            min_selections: 1,
            max_selections: Some(1),
        }];
        let groups = item_modifier_groups(&it, &catalog());

        // Nothing selected → the required milk group is violated (0 < 1).
        let v = validate_group_selections(&groups, &[], &[]);
        assert_eq!(v.len(), 1);
        assert_eq!(
            (
                v[0].group_id.as_str(),
                v[0].selected,
                v[0].min_required,
                v[0].max_allowed
            ),
            ("slot-milk", 0, 1, Some(1))
        );

        // Exactly one milk → valid (extras/optionals stay optional).
        let one = [AddonSelection {
            addon_item_id: "almond".into(),
            qty: 1,
        }];
        assert!(validate_group_selections(&groups, &one, &[]).is_empty());

        // qty 2 of a milk → exceeds max 1.
        let two = [AddonSelection {
            addon_item_id: "almond".into(),
            qty: 2,
        }];
        let v = validate_group_selections(&groups, &two, &[]);
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].selected, 2);

        // Selections outside any group (unknown id) are ignored, not counted.
        let stray = [
            AddonSelection {
                addon_item_id: "ghost".into(),
                qty: 9,
            },
            AddonSelection {
                addon_item_id: "almond".into(),
                qty: 1,
            },
        ];
        assert!(validate_group_selections(&groups, &stray, &[]).is_empty());
    }

    fn uopt(id: &str) -> menu::UnifiedOption {
        menu::UnifiedOption {
            id: id.into(),
            name: id.into(),
            name_translations: serde_json::json!({}),
            price: 0,
            is_available: true,
        }
    }

    #[test]
    fn unified_multi_configured_milk_group_becomes_single() {
        // What the backend backfill writes: milk as `multi`, max NULL — once by
        // legacy type, once as a renamed group recognised only by its options.
        let groups = item_modifier_groups_unified(
            &item(),
            &catalog(),
            vec![
                menu::UnifiedGroup {
                    group_id: "g-milk".into(),
                    name: "Milk".into(),
                    name_translations: serde_json::json!({}),
                    selection_type: "multi".into(),
                    min: 0,
                    max: None,
                    is_required: false,
                    legacy_addon_type: Some("milk_type".into()),
                    options: vec![uopt("oat"), uopt("almond")],
                },
                menu::UnifiedGroup {
                    group_id: "g-dairy".into(),
                    name: "Dairy".into(),
                    name_translations: serde_json::json!({}),
                    selection_type: "multi".into(),
                    min: 0,
                    max: Some(3),
                    is_required: false,
                    legacy_addon_type: None,
                    options: vec![uopt("whole"), uopt("almond")],
                },
                menu::UnifiedGroup {
                    group_id: "g-extra".into(),
                    name: "Extras".into(),
                    name_translations: serde_json::json!({}),
                    selection_type: "multi".into(),
                    min: 0,
                    max: None,
                    is_required: false,
                    legacy_addon_type: Some("extra".into()),
                    options: vec![uopt("shot")],
                },
            ],
            "en",
        );
        assert_eq!(groups[0].max_selections, Some(1));
        assert_eq!(groups[1].max_selections, Some(1));
        assert_eq!(groups[1].addon_type.as_deref(), Some("milk_type"));
        assert_eq!(groups[2].max_selections, None); // additive stays multi

        // Two milks (the default beside the pick) is a violation, one is not.
        let two = [
            AddonSelection {
                addon_item_id: "oat".into(),
                qty: 1,
            },
            AddonSelection {
                addon_item_id: "almond".into(),
                qty: 1,
            },
        ];
        let v = validate_group_selections(&groups[..1], &two, &[]);
        assert_eq!(v.len(), 1);
        assert_eq!((v[0].selected, v[0].max_allowed), (2, Some(1)));
        assert!(validate_group_selections(&groups[..1], &two[1..], &[]).is_empty());
    }

    #[test]
    fn swap_family_selections_replace_not_append() {
        let sels = [
            AddonSelection {
                addon_item_id: "oat".into(),
                qty: 1,
            },
            AddonSelection {
                addon_item_id: "shot".into(),
                qty: 2,
            },
            AddonSelection {
                addon_item_id: "almond".into(),
                qty: 3,
            },
        ];
        let n = normalize_swap_selections(&catalog(), &sels);
        let got: Vec<(&str, i64)> = n
            .iter()
            .map(|s| (s.addon_item_id.as_str(), s.qty))
            .collect();
        assert_eq!(got, vec![("almond", 1), ("shot", 2)]);

        let mut it = item();
        it.default_milk_addon_id = Some("oat".into());
        let line = resolve_line(&it, &catalog(), None, &sels, &[], 1, None);
        let ids: Vec<&str> = line
            .addons
            .iter()
            .map(|a| a.addon_item_id.as_str())
            .collect();
        assert_eq!(ids, vec!["almond", "shot"]);
    }

    #[test]
    fn unified_modifier_groups_map_wire_constraints_and_swap_prices() {
        // The unified wire is authoritative for grouping/naming/constraints;
        // charged prices still ride the flat sheet's swap rules by stable id.
        let unified = vec![
            menu::UnifiedGroup {
                group_id: "g-milk".into(),
                name: "milk_type".into(), // type-y name → host localizes
                name_translations: serde_json::json!({}),
                selection_type: "single".into(),
                min: 1,
                max: None,
                is_required: true,
                legacy_addon_type: Some("milk_type".into()),
                options: vec![
                    menu::UnifiedOption {
                        id: "oat".into(),
                        name: "Oat".into(),
                        name_translations: serde_json::json!({}),
                        price: 1500,
                        is_available: true,
                    },
                    menu::UnifiedOption {
                        id: "almond".into(),
                        name: "Almond".into(),
                        name_translations: serde_json::json!({}),
                        price: 2000,
                        is_available: true,
                    },
                    menu::UnifiedOption {
                        id: "soy".into(),
                        name: "Soy".into(),
                        name_translations: serde_json::json!({}),
                        price: 1800,
                        is_available: false,
                    },
                ],
            },
            menu::UnifiedGroup {
                group_id: "g-custom".into(),
                name: "Spice level".into(),
                name_translations: serde_json::json!({"ar": "الحرارة"}),
                selection_type: "multi".into(),
                min: 0,
                max: Some(2),
                is_required: false,
                legacy_addon_type: None,
                options: vec![menu::UnifiedOption {
                    id: "hot".into(),
                    name: "Hot".into(),
                    name_translations: serde_json::json!({}),
                    price: 250,
                    is_available: true,
                }],
            },
        ];
        let groups = item_modifier_groups_unified(&item(), &catalog(), unified, "en");

        let p = |g: &ModifierGroupView, id: &str| {
            g.options
                .iter()
                .find(|o| o.id == id)
                .unwrap()
                .charged_price_minor
        };
        // Milk: single → max 1; swap deltas from the flat catalog by stable id.
        let milk = &groups[0];
        assert_eq!(milk.group_id, "g-milk");
        assert_eq!(
            (milk.is_required, milk.min_selections, milk.max_selections),
            (true, 1, Some(1))
        );
        assert_eq!(p(milk, "oat"), 0, "re-selecting the default milk is free");
        assert_eq!(
            milk.default_option_id.as_deref(),
            Some("oat"),
            "the unified path preselects the recipe's own milk, like the legacy one"
        );
        assert_eq!(p(milk, "almond"), 500, "swap delta over the 1500 oat base");
        assert!(
            milk.options.iter().all(|o| o.id != "soy"),
            "effectively-unavailable options are dropped"
        );
        // Custom group: authored name; option unknown to the flat catalog keeps
        // its unified effective price.
        let custom = &groups[1];
        assert_eq!(custom.name, "Spice level");
        assert_eq!(custom.max_selections, Some(2));
        assert_eq!(p(custom, "hot"), 250);
        // Priced optionals still appended, same as the legacy projection.
        assert_eq!(groups.last().unwrap().kind, ModifierGroupKind::Optional);
        assert_eq!(groups.last().unwrap().options[0].id, "van");
    }

    /// F17: the item-private "Options" group (backend `legacy_origin='options'`,
    /// options `legacy_source='optional'`) is ALSO in `/catalog/sync`'s
    /// modifier_groups — with `legacy_addon_type` NULL and option ids equal to
    /// the item's `optional_field` ids. Rendered as an Addon group it listed
    /// "Vanilla" twice, and the addon copy submitted an `addon_item_id` the
    /// server does not know as an addon (404 → order fails).
    #[test]
    fn unified_private_options_group_is_listed_once_as_optional() {
        let unified = vec![
            menu::UnifiedGroup {
                group_id: "g-milk".into(),
                name: "Milk".into(),
                name_translations: serde_json::json!({}),
                selection_type: "single".into(),
                min: 0,
                max: Some(1),
                is_required: false,
                legacy_addon_type: Some("milk_type".into()),
                options: vec![uopt("oat"), uopt("almond")],
            },
            menu::UnifiedGroup {
                group_id: "g-options-latte".into(),
                name: "Options".into(),
                name_translations: serde_json::json!({}),
                selection_type: "multi".into(),
                min: 0,
                max: None,
                is_required: false,
                legacy_addon_type: None,
                options: vec![menu::UnifiedOption {
                    id: "van".into(),
                    name: "Vanilla".into(),
                    name_translations: serde_json::json!({}),
                    price: 300,
                    is_available: true,
                }],
            },
        ];
        let groups = item_modifier_groups_unified(&item(), &catalog(), unified, "en");
        // (a) exactly once, and in the Optional-kind group.
        let hits: Vec<(&ModifierGroupView, &ModifierOptionView)> = groups
            .iter()
            .flat_map(|g| g.options.iter().map(move |o| (g, o)))
            .filter(|(_, o)| o.id == "van")
            .collect();
        assert_eq!(hits.len(), 1, "private option listed once: {groups:?}");
        assert_eq!(hits[0].0.kind, ModifierGroupKind::Optional);
        assert!(groups.iter().all(|g| g.group_id != "g-options-latte"));
        assert!(groups.iter().any(|g| g.group_id == "g-milk"));

        // (b) payload: picked through the Optional group → optional-field slot.
        let line = resolve_line(&item(), &catalog(), None, &[], &["van".into()], 1, None);
        assert!(line.addons.is_empty());
        assert_eq!(line.optionals.len(), 1);
        assert_eq!(line.optionals[0].optional_field_id, "van");
        assert_eq!(line.optionals[0].price_minor, 300);

        // A host holding a stale sheet that submits it as an ADDON still lands
        // in the optional slot (never an addon id), without double-counting.
        let stale = [AddonSelection {
            addon_item_id: "van".into(),
            qty: 1,
        }];
        let line = resolve_line(&item(), &catalog(), None, &stale, &["van".into()], 1, None);
        assert!(line.addons.is_empty());
        assert_eq!(line.optionals.len(), 1);
        let line = resolve_line(&item(), &catalog(), None, &stale, &[], 1, None);
        assert!(line.addons.iter().all(|a| a.addon_item_id != "van"));
        assert_eq!(
            line.optionals.iter().map(|o| o.optional_field_id.as_str()).collect::<Vec<_>>(),
            vec!["van"]
        );
    }

    #[test]
    fn unified_mirror_helpers_parse_and_gate() {
        let s = store();
        assert_eq!(menu::unified_revision(&s), None, "no mirror yet");
        assert!(
            !menu::unified_unchanged(r#"{"catalog_revision":7,"changed":true}"#),
            "changed:true carries a payload"
        );
        assert!(
            menu::unified_unchanged(r#"{"catalog_revision":7,"changed":false}"#),
            "changed:false = keep the current mirror"
        );
        s.kv_put(
            menu::K_UNIFIED,
            r#"{"catalog_revision":42,"changed":true,"items":[{"id":"latte","modifier_groups":[{"group_id":"g1","name":"Milk","selection_type":"single","min":0,"max":1,"is_required":false,"legacy_addon_type":"milk_type","options":[{"id":"oat","name":"Oat","price":1500,"is_available":true}]}]},{"id":"water","modifier_groups":[]}]}"#,
        )
        .unwrap();
        assert_eq!(menu::unified_revision(&s), Some(42));
        let g = menu::unified_groups_for(&s, "latte").unwrap();
        assert_eq!(g.len(), 1);
        assert_eq!(g[0].group_id, "g1");
        assert_eq!(g[0].options[0].id, "oat");
        assert!(
            menu::unified_groups_for(&s, "ghost").is_none(),
            "unknown item ⇒ fall back to the legacy projection"
        );
        assert!(
            menu::unified_groups_for(&s, "water").is_none(),
            "item with NO attached groups (implicit-all-addons default, not yet \
             authored) ⇒ fall back too — the flat catalog keeps the full offer"
        );
    }

    #[test]
    fn item_addons_resolve_charged_prices_for_display() {
        let v = item_addons(&item(), &catalog());
        let p = |id: &str| {
            v.iter()
                .find(|a| a.addon_item_id == id)
                .unwrap()
                .charged_price_minor
        };
        assert_eq!(p("almond"), 500); // milk swap delta over oat base
        assert_eq!(p("whole"), 0); // downgrade clamped
        assert_eq!(p("oat"), 0); // the default milk itself is free
        assert_eq!(p("shot"), 800); // additive full
    }

    #[test]
    fn empty_cart_totals_are_zero() {
        let s = store();
        let t = totals(&s, None, &tax_policy_at(0.14)).unwrap();
        assert_eq!(
            t,
            CartTotals {
                service_charge_minor: 0,
                item_count: 0,
                subtotal_minor: 0,
                discount_minor: 0,
                tax_minor: 0,
                total_minor: 0
            }
        );
    }

    fn seed_discounts(s: &Store) {
        // The wire as the server now speaks it: `value` is the LEGACY
        // integer every shipped till was built for, `value_rate` the stored
        // fraction beside it. See `discount_rate`.
        s.kv_put(menu::K_DISCOUNTS, r#"[
          {"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z","dtype":"percentage","id":"00000000-0000-0000-0000-0000000000d1","is_active":true,"name":"10% off","name_translations":{},"org_id":"00000000-0000-0000-0000-0000000000ff","value":10,"value_rate":0.10},
          {"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z","dtype":"fixed","id":"00000000-0000-0000-0000-0000000000d2","is_active":true,"name":"250 off","name_translations":{},"org_id":"00000000-0000-0000-0000-0000000000ff","value":250,"value_rate":250}
        ]"#).unwrap();
    }

    #[test]
    fn percentage_discount_applies_before_tax() {
        let s = store();
        seed_discounts(&s);
        add(&s, None, "a", "Latte", 1000).unwrap();
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        let t = totals(&s, None, &tax_policy_at(0.14)).unwrap();
        assert_eq!(t.subtotal_minor, 1000);
        assert_eq!(t.discount_minor, 100); // 10%
        assert_eq!(t.tax_minor, 126); // round((1000-100) * 0.14)
        assert_eq!(t.total_minor, 1026);
    }

    #[test]
    fn fixed_discount_taxes_the_discounted_base() {
        let s = store();
        seed_discounts(&s);
        add(&s, None, "a", "Latte", 1000).unwrap();
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d2").unwrap();
        let t = totals(&s, None, &tax_policy_at(0.14)).unwrap();
        assert_eq!(t.discount_minor, 250);
        assert_eq!(t.tax_minor, 105); // round(750 * 0.14)
        assert_eq!(t.total_minor, 855);
    }

    #[test]
    fn unknown_or_cleared_discount_is_none() {
        let s = store();
        seed_discounts(&s);
        add(&s, None, "a", "Latte", 1000).unwrap();
        set_discount(&s, None, "not-a-real-id").unwrap(); // not in the catalog → ignored
        assert_eq!(
            totals(&s, None, &tax_policy_at(0.0))
                .unwrap()
                .discount_minor,
            0
        );
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        assert_eq!(
            totals(&s, None, &tax_policy_at(0.0))
                .unwrap()
                .discount_minor,
            100
        );
        clear_discount(&s, None).unwrap();
        assert_eq!(
            totals(&s, None, &tax_policy_at(0.0))
                .unwrap()
                .discount_minor,
            0
        );
    }

    #[test]
    fn hold_then_restore_roundtrips_the_cart() {
        let s = store();
        add(&s, None, "latte", "Latte", 5000).unwrap();
        add(&s, None, "bun", "Bun", 2000).unwrap();
        hold(
            &s,
            None,
            "d1".into(),
            "Table 4".into(),
            "2026-06-21T10:00:00Z".into(),
        )
        .unwrap();
        // Held → cart empty, one draft summarizing the two lines.
        assert!(lines(&s, None).unwrap().is_empty());
        let ds = drafts(&s).unwrap();
        assert_eq!(ds.len(), 1);
        assert_eq!(ds[0].name, "Table 4");
        assert_eq!(ds[0].item_count, 2);
        assert_eq!(ds[0].total_minor, 7000);
        // Restore → cart back, draft gone.
        let restored = restore_draft(&s, None, "d1").unwrap();
        assert_eq!(restored.len(), 2);
        assert!(drafts(&s).unwrap().is_empty());
        // Holding an empty cart is rejected.
        clear(&s, None).unwrap();
        assert!(hold(&s, None, "d2".into(), "x".into(), "t".into()).is_err());
    }

    #[test]
    fn remove_then_restore_brings_the_line_back() {
        let s = store();
        add(&s, None, "latte", "Latte", 5000).unwrap();
        set_qty(&s, None, &lines(&s, None).unwrap()[0].key, 3).unwrap(); // a 3× line
        add(&s, None, "bun", "Bun", 2000).unwrap();
        let key = lines(&s, None)
            .unwrap()
            .iter()
            .find(|l| l.name == "Latte")
            .unwrap()
            .key
            .clone();
        // Swipe-remove the latte → one line left.
        let after = remove(&s, None, &key).unwrap();
        assert_eq!(after.len(), 1);
        assert_eq!(after[0].name, "Bun");
        // Undo → the 3× latte is back (qty preserved).
        let restored = restore_last_removed(&s, None).unwrap();
        assert_eq!(restored.len(), 2);
        let latte = restored.iter().find(|l| l.name == "Latte").unwrap();
        assert_eq!(latte.qty, 3);
        // The stash is consumed — a second undo is a no-op.
        let again = restore_last_removed(&s, None).unwrap();
        assert_eq!(again.iter().find(|l| l.name == "Latte").unwrap().qty, 3);
    }

    #[test]
    fn clearing_the_cart_resets_the_discount() {
        let s = store();
        seed_discounts(&s);
        add(&s, None, "a", "Latte", 1000).unwrap();
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        clear(&s, None).unwrap();
        assert!(discount_id(&s, None).unwrap().is_none());
    }

    fn bundle() -> menu::BundleView {
        menu::BundleView {
            id: "b1".into(),
            name: "Morning Combo".into(),
            description: None,
            price_minor: 10000,
            image_url: None,
            local_image_path: None,
            is_available: true,
            available_from_date: None,
            available_until_date: None,
            available_from_time: None,
            available_until_time: None,
            components: vec![],
        }
    }

    fn combo_component() -> BundleComponentSelection {
        // Latte, Large, + almond milk (milk_type 2000 − oat base 1500 = +500 swap
        // delta) + vanilla optional (+300). Component base/size price NOT charged.
        BundleComponentSelection {
            item_id: "latte".into(),
            size_label: Some("Large".into()),
            qty: 1,
            addons: vec![AddonSelection {
                addon_item_id: "almond".into(),
                qty: 1,
            }],
            optional_field_ids: vec!["van".into()],
        }
    }

    #[test]
    fn bundle_line_charges_fixed_price_plus_component_extras() {
        let s = store();
        let line = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[combo_component()], 1);
        add_resolved(&s, None, line).unwrap();
        let lines = lines(&s, None).unwrap();
        assert_eq!(lines.len(), 1);
        let l = &lines[0];
        assert_eq!(l.bundle_id.as_deref(), Some("b1"));
        assert_eq!(l.unit_price_minor, 10000, "fixed bundle price");
        // (10000 base + 500 almond delta + 300 vanilla) × 1
        assert_eq!(l.line_total_minor, 10800);
        assert_eq!(l.bundle_components.len(), 1);
        assert_eq!(l.bundle_components[0].name, "Latte");
        assert_eq!(l.bundle_components[0].size_label.as_deref(), Some("Large"));
    }

    #[test]
    fn identical_bundle_configs_merge_distinct_ones_dont() {
        let s = store();
        let a = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[combo_component()], 1);
        add_resolved(&s, None, a).unwrap();
        // Same config again → merges (qty 2, one line).
        let b = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[combo_component()], 1);
        add_resolved(&s, None, b).unwrap();
        assert_eq!(lines(&s, None).unwrap().len(), 1);
        assert_eq!(lines(&s, None).unwrap()[0].qty, 2);
        // A different component config → a separate line.
        let mut plain = combo_component();
        plain.addons = vec![];
        plain.optional_field_ids = vec![];
        let c = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[plain], 1);
        add_resolved(&s, None, c).unwrap();
        assert_eq!(lines(&s, None).unwrap().len(), 2);
    }

    // ── add / merge edge cases ────────────────────────────────────────────────

    #[test]
    fn add_to_empty_creates_single_line() {
        let s = store();
        let v = add(&s, None, "a", "Latte", 5000).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 1);
        assert_eq!(v[0].line_total_minor, 5000);
        assert_eq!(v[0].key, "a");
    }

    #[test]
    fn add_resolved_merges_on_matching_signature() {
        let s = store();
        // Two option-less lines for the same item id merge regardless of name/price
        // because the signature for an option-less line is just the item_id.
        add_resolved(
            &s,
            None,
            resolve_line(&item(), &catalog(), None, &[], &[], 1, None),
        )
        .unwrap();
        let v = add_resolved(
            &s,
            None,
            resolve_line(&item(), &catalog(), None, &[], &[], 1, None),
        )
        .unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 2);
        assert_eq!(v[0].key, "latte"); // option-less → key is item_id
    }

    // ── set_qty boundaries ────────────────────────────────────────────────────

    #[test]
    fn set_qty_to_one_keeps_line() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        let v = set_qty(&s, None, "a", 1).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 1);
    }

    #[test]
    fn set_qty_negative_removes_line() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        assert!(set_qty(&s, None, "a", -5).unwrap().is_empty());
    }

    #[test]
    fn set_qty_on_missing_key_is_noop() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        // A positive qty on a non-existent key changes nothing.
        let v = set_qty(&s, None, "nope", 9).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 1);
    }

    #[test]
    fn set_qty_zero_on_missing_key_leaves_others() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        add(&s, None, "b", "Tea", 3000).unwrap();
        // qty<=0 only retains lines whose signature differs from the key; an
        // unknown key removes nothing.
        let v = set_qty(&s, None, "nope", 0).unwrap();
        assert_eq!(v.len(), 2);
    }

    #[test]
    fn set_qty_on_empty_cart_is_noop() {
        let s = store();
        assert!(set_qty(&s, None, "a", 3).unwrap().is_empty());
        assert!(set_qty(&s, None, "a", 0).unwrap().is_empty());
    }

    // ── remove edge cases ─────────────────────────────────────────────────────

    #[test]
    fn remove_missing_key_does_not_stash() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        let v = remove(&s, None, "nope").unwrap();
        assert_eq!(v.len(), 1); // nothing removed
                                // Nothing was stashed, so undo is a no-op (cart unchanged).
        let after = restore_last_removed(&s, None).unwrap();
        assert_eq!(after.len(), 1);
        assert_eq!(after[0].qty, 1);
    }

    #[test]
    fn remove_from_empty_cart_is_noop() {
        let s = store();
        assert!(remove(&s, None, "a").unwrap().is_empty());
    }

    // ── undo (restore_last_removed) edge cases ───────────────────────────────

    #[test]
    fn restore_with_no_stash_is_noop() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        let v = restore_last_removed(&s, None).unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].qty, 1);
    }

    #[test]
    fn restore_merges_back_into_matching_line() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        set_qty(&s, None, "a", 2).unwrap(); // 2× in cart
                                            // Remove it (stash = 2×), then re-add one fresh, then undo: the stashed 2
                                            // merges into the existing 1× for qty 3 in a single line.
        remove(&s, None, "a").unwrap();
        add(&s, None, "a", "Latte", 5000).unwrap();
        let restored = restore_last_removed(&s, None).unwrap();
        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].qty, 3);
    }

    #[test]
    fn clear_drops_the_undo_stash() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        remove(&s, None, "a").unwrap(); // stash now holds the latte
        clear(&s, None).unwrap(); // a stale undo must not resurrect a sold line
        let after = restore_last_removed(&s, None).unwrap();
        assert!(after.is_empty());
    }

    // ── signature determinism ─────────────────────────────────────────────────

    #[test]
    fn signature_is_order_independent_for_addons_and_optionals() {
        // Same selection, different option ORDER → identical signature → merge.
        let mut it = item();
        it.optional_fields.push(menu::OptionalFieldView {
            id: "cin".into(),
            name: "Cinnamon".into(),
            price_minor: 100,
            is_active: true,
            ingredient_name: None,
            ingredient_unit: None,
            quantity_used: None,
            org_ingredient_id: None,
        });
        let a = resolve_line(
            &it,
            &catalog(),
            Some("Large".into()),
            &[
                AddonSelection {
                    addon_item_id: "almond".into(),
                    qty: 1,
                },
                AddonSelection {
                    addon_item_id: "shot".into(),
                    qty: 1,
                },
            ],
            &["van".into(), "cin".into()],
            1,
            None,
        );
        let b = resolve_line(
            &it,
            &catalog(),
            Some("Large".into()),
            &[
                AddonSelection {
                    addon_item_id: "shot".into(),
                    qty: 1,
                },
                AddonSelection {
                    addon_item_id: "almond".into(),
                    qty: 1,
                },
            ],
            &["cin".into(), "van".into()],
            1,
            None,
        );
        let s = store();
        add_resolved(&s, None, a).unwrap();
        let v = add_resolved(&s, None, b).unwrap();
        assert_eq!(v.len(), 1, "reordered options must merge");
        assert_eq!(v[0].qty, 2);
    }

    #[test]
    fn signature_distinguishes_notes() {
        // Same item, different notes → distinct lines.
        let s = store();
        add_resolved(
            &s,
            None,
            resolve_line(
                &item(),
                &catalog(),
                None,
                &[],
                &[],
                1,
                Some("no sugar".into()),
            ),
        )
        .unwrap();
        add_resolved(
            &s,
            None,
            resolve_line(
                &item(),
                &catalog(),
                None,
                &[],
                &[],
                1,
                Some("extra hot".into()),
            ),
        )
        .unwrap();
        assert_eq!(lines(&s, None).unwrap().len(), 2);
    }

    #[test]
    fn signature_distinguishes_addon_qty() {
        // Same addon, different qty → distinct lines (qty is in the signature).
        let s = store();
        let mk = |q: i64| {
            resolve_line(
                &item(),
                &catalog(),
                None,
                &[AddonSelection {
                    addon_item_id: "shot".into(),
                    qty: q,
                }],
                &[],
                1,
                None,
            )
        };
        add_resolved(&s, None, mk(1)).unwrap();
        let v = add_resolved(&s, None, mk(2)).unwrap();
        assert_eq!(v.len(), 2);
    }

    #[test]
    fn signature_distinguishes_size() {
        let s = store();
        add_resolved(
            &s,
            None,
            resolve_line(&item(), &catalog(), Some("Large".into()), &[], &[], 1, None),
        )
        .unwrap();
        // No size → falls back to the option-less item_id signature, distinct from
        // the sized line.
        add_resolved(
            &s,
            None,
            resolve_line(&item(), &catalog(), None, &[], &[], 1, None),
        )
        .unwrap();
        assert_eq!(lines(&s, None).unwrap().len(), 2);
    }

    // ── resolve_line boundaries / malformed input ─────────────────────────────

    #[test]
    fn resolve_line_clamps_qty_floor_to_one() {
        let line = resolve_line(&item(), &catalog(), None, &[], &[], 0, None);
        assert_eq!(line.qty, 1);
        let line = resolve_line(&item(), &catalog(), None, &[], &[], -3, None);
        assert_eq!(line.qty, 1);
    }

    #[test]
    fn resolve_line_clamps_addon_qty_floor_to_one() {
        let line = resolve_line(
            &item(),
            &catalog(),
            None,
            &[AddonSelection {
                addon_item_id: "shot".into(),
                qty: 0,
            }],
            &[],
            1,
            None,
        );
        assert_eq!(line.addons.len(), 1);
        assert_eq!(line.addons[0].qty, 1);
    }

    #[test]
    fn resolve_line_unknown_size_falls_back_to_base() {
        let line = resolve_line(
            &item(),
            &catalog(),
            Some("Gigantic".into()),
            &[],
            &[],
            1,
            None,
        );
        assert_eq!(line.unit_price_minor, 5000); // base, unknown size label ignored
                                                 // The bogus size label is still recorded (and so part of the signature).
        assert_eq!(line.size_label.as_deref(), Some("Gigantic"));
    }

    #[test]
    fn resolve_line_drops_unknown_addon_and_optional_ids() {
        let line = resolve_line(
            &item(),
            &catalog(),
            None,
            &[
                AddonSelection {
                    addon_item_id: "ghost".into(),
                    qty: 1,
                },
                AddonSelection {
                    addon_item_id: "shot".into(),
                    qty: 1,
                },
            ],
            &["nope".into(), "van".into()],
            1,
            None,
        );
        assert_eq!(line.addons.len(), 1); // only "shot" survives
        assert_eq!(line.addons[0].addon_item_id, "shot");
        assert_eq!(line.optionals.len(), 1); // only "van" survives
        assert_eq!(line.optionals[0].optional_field_id, "van");
    }

    #[test]
    fn resolve_line_with_no_options_keys_by_item_id() {
        let line = resolve_line(&item(), &catalog(), None, &[], &[], 1, None);
        assert_eq!(signature(&line), "latte");
    }

    // ── item_addons filtering ─────────────────────────────────────────────────

    #[test]
    fn item_addons_drops_inactive_entries() {
        let mut cat = catalog();
        cat.push(menu::AddonItemView {
            id: "retired".into(),
            name: "Retired".into(),
            addon_type: "extra".into(),
            default_price_minor: 999,
            is_active: false,
            ingredients: vec![],
        });
        let v = item_addons(&item(), &cat);
        assert!(v.iter().all(|a| a.addon_item_id != "retired"));
    }

    // ── bundle pricing / component resolution ─────────────────────────────────

    #[test]
    fn resolve_bundle_line_uses_fixed_price_and_clamps_qty() {
        let line = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[combo_component()], 0);
        assert_eq!(line.unit_price_minor, 10000); // fixed bundle price
        assert_eq!(line.qty, 1); // qty clamped up from 0
        assert!(line.addons.is_empty()); // bundle's own addons stay empty
        assert!(line.optionals.is_empty());
        assert_eq!(line.bundle_id.as_deref(), Some("b1"));
    }

    #[test]
    fn resolve_bundle_line_drops_components_with_unknown_item() {
        let mut ghost = combo_component();
        ghost.item_id = "not-in-catalog".into();
        // One good + one ghost component → only the resolvable one survives.
        let line = resolve_bundle_line(
            &bundle(),
            &[item()],
            &catalog(),
            &[combo_component(), ghost],
            1,
        );
        assert_eq!(line.bundle_components.len(), 1);
        assert_eq!(line.bundle_components[0].item_id, "latte");
    }

    #[test]
    fn resolve_bundle_line_with_no_components_charges_only_base() {
        let line = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[], 2);
        assert!(line.bundle_components.is_empty());
        // (10000 base + 0 extras) × 2 = 20000.
        assert_eq!(line_total(&line), 20000);
    }

    #[test]
    fn bundle_component_qty_does_not_scale_extras() {
        // A component qty of 5 must NOT multiply the addon/optional up-charge; the
        // bundle's own line qty is the only multiplier (Flutter parity — extras are
        // per-bundle, base covers the component count).
        let mut comp = combo_component();
        comp.qty = 5;
        let line = resolve_bundle_line(&bundle(), &[item()], &catalog(), &[comp], 1);
        assert_eq!(line.bundle_components[0].qty, 5);
        // 10000 base + 500 almond delta + 300 vanilla = 10800 (extras counted once).
        assert_eq!(line_total(&line), 10800);
    }

    #[test]
    fn bundle_totals_flow_through_pricing_engine() {
        let s = store();
        add_resolved(
            &s,
            None,
            resolve_bundle_line(&bundle(), &[item()], &catalog(), &[combo_component()], 2),
        )
        .unwrap();
        let t = totals(&s, None, &tax_policy_at(0.0)).unwrap();
        assert_eq!(t.item_count, 2);
        // (10000 + 500 + 300) × 2 = 21600.
        assert_eq!(t.subtotal_minor, 21600);
    }

    // ── drafts ────────────────────────────────────────────────────────────────

    #[test]
    fn hold_empty_cart_errors_with_validation() {
        let s = store();
        let err = hold(&s, None, "d1".into(), "x".into(), "now".into()).unwrap_err();
        match err {
            crate::error::CoreError::Validation { field, detail } => {
                assert_eq!(field, "cart");
                assert_eq!(detail, "cart is empty");
            }
            other => panic!("expected Validation, got {other:?}"),
        }
    }

    #[test]
    fn drafts_are_listed_newest_first() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        hold(
            &s,
            None,
            "d1".into(),
            "First".into(),
            "2026-06-21T10:00:00Z".into(),
        )
        .unwrap();
        add(&s, None, "b", "Tea", 3000).unwrap();
        hold(
            &s,
            None,
            "d2".into(),
            "Second".into(),
            "2026-06-21T11:00:00Z".into(),
        )
        .unwrap();
        let ds = drafts(&s).unwrap();
        assert_eq!(ds.len(), 2);
        assert_eq!(ds[0].name, "Second"); // newest first (reversed)
        assert_eq!(ds[1].name, "First");
    }

    #[test]
    fn drafts_empty_when_none_held() {
        let s = store();
        assert!(drafts(&s).unwrap().is_empty());
    }

    #[test]
    fn restore_draft_replaces_current_cart_lines() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        hold(&s, None, "d1".into(), "Held".into(), "t".into()).unwrap();
        // Build a new, different cart, then restore — the draft REPLACES it.
        add(&s, None, "b", "Tea", 3000).unwrap();
        let restored = restore_draft(&s, None, "d1").unwrap();
        assert_eq!(restored.len(), 1);
        assert_eq!(restored[0].name, "Latte"); // the held line, not the Tea
        assert!(drafts(&s).unwrap().is_empty()); // draft consumed
    }

    #[test]
    fn restore_draft_clears_any_selected_discount() {
        let s = store();
        seed_discounts(&s);
        add(&s, None, "a", "Latte", 1000).unwrap();
        hold(&s, None, "d1".into(), "Held".into(), "t".into()).unwrap();
        // Pick a discount on the (now empty) cart, then restore the draft.
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        restore_draft(&s, None, "d1").unwrap();
        assert!(discount_id(&s, None).unwrap().is_none());
    }

    #[test]
    fn restore_unknown_draft_is_noop_returning_current_cart() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        let v = restore_draft(&s, None, "ghost").unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].name, "Latte"); // current cart unchanged
    }

    #[test]
    fn discard_draft_removes_only_the_target() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        hold(&s, None, "d1".into(), "One".into(), "t".into()).unwrap();
        add(&s, None, "b", "Tea", 3000).unwrap();
        hold(&s, None, "d2".into(), "Two".into(), "t".into()).unwrap();
        discard_draft(&s, "d1").unwrap();
        let ds = drafts(&s).unwrap();
        assert_eq!(ds.len(), 1);
        assert_eq!(ds[0].id, "d2");
    }

    #[test]
    fn discard_unknown_draft_is_noop() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        hold(&s, None, "d1".into(), "One".into(), "t".into()).unwrap();
        discard_draft(&s, "ghost").unwrap();
        assert_eq!(drafts(&s).unwrap().len(), 1);
    }

    #[test]
    fn hold_clears_the_cart_and_its_discount() {
        let s = store();
        seed_discounts(&s);
        add(&s, None, "a", "Latte", 1000).unwrap();
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        hold(&s, None, "d1".into(), "Held".into(), "t".into()).unwrap();
        assert!(lines(&s, None).unwrap().is_empty());
        assert!(discount_id(&s, None).unwrap().is_none()); // hold → clear → clear_discount
    }

    #[test]
    fn draft_summary_counts_quantities_and_totals() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        set_qty(&s, None, "a", 3).unwrap();
        add(&s, None, "b", "Tea", 2000).unwrap();
        hold(&s, None, "d1".into(), "Table".into(), "t".into()).unwrap();
        let ds = drafts(&s).unwrap();
        assert_eq!(ds[0].item_count, 4); // 3 + 1
        assert_eq!(ds[0].total_minor, 17000); // 5000*3 + 2000
    }

    // ── discount set / clear / resolve ────────────────────────────────────────

    #[test]
    fn the_order_note_persists_rides_the_payload_and_clears_with_the_cart() {
        let s = store();
        assert!(note(&s, None).unwrap().is_none());
        set_note(&s, None, Some("  no onions for the table  ")).unwrap();
        assert_eq!(
            note(&s, None).unwrap().as_deref(),
            Some("no onions for the table")
        );
        let payload = cart_payload(&s, None).unwrap();
        clear(&s, None).unwrap();
        assert!(note(&s, None).unwrap().is_none());
        set_cart_payload(&s, None, &payload).unwrap();
        assert_eq!(
            note(&s, None).unwrap().as_deref(),
            Some("no onions for the table")
        );
        set_note(&s, None, Some("   ")).unwrap();
        assert!(note(&s, None).unwrap().is_none());
    }

    #[test]
    fn discount_id_none_when_unset() {
        let s = store();
        assert!(discount_id(&s, None).unwrap().is_none());
    }

    #[test]
    fn set_then_clear_discount_id() {
        let s = store();
        set_discount(&s, None, "abc").unwrap();
        assert_eq!(discount_id(&s, None).unwrap().as_deref(), Some("abc"));
        clear_discount(&s, None).unwrap();
        assert!(discount_id(&s, None).unwrap().is_none());
    }

    #[test]
    fn discount_id_treats_literal_null_as_none() {
        let s = store();
        set_discount(&s, None, "null").unwrap(); // the string "null" is filtered out
        assert!(discount_id(&s, None).unwrap().is_none());
    }

    #[test]
    fn discount_resolves_kind_and_value_from_catalog() {
        let s = store();
        seed_discounts(&s);
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        let (kind, value) = discount(&s, None).unwrap();
        assert_eq!(kind, DiscountKind::Percentage);
        assert_eq!(value, 0.10);
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d2").unwrap();
        let (kind, value) = discount(&s, None).unwrap();
        assert_eq!(kind, DiscountKind::Fixed);
        assert_eq!(value, 250.0);
    }

    #[test]
    fn discount_none_when_nothing_selected() {
        let s = store();
        seed_discounts(&s);
        let (kind, value) = discount(&s, None).unwrap();
        assert_eq!(kind, DiscountKind::None);
        assert_eq!(value, 0.0);
    }

    #[test]
    fn discount_none_when_catalog_missing() {
        // A selected id but no discounts catalog seeded → resolves to none.
        let s = store();
        set_discount(&s, None, "00000000-0000-0000-0000-0000000000d1").unwrap();
        let (kind, value) = discount(&s, None).unwrap();
        assert_eq!(kind, DiscountKind::None);
        assert_eq!(value, 0.0);
    }

    // ── clear ─────────────────────────────────────────────────────────────────

    #[test]
    fn clear_empties_lines_and_keeps_drafts() {
        let s = store();
        add(&s, None, "a", "Latte", 5000).unwrap();
        hold(&s, None, "d1".into(), "Held".into(), "t".into()).unwrap(); // parks + clears
        add(&s, None, "b", "Tea", 3000).unwrap();
        clear(&s, None).unwrap();
        assert!(lines(&s, None).unwrap().is_empty());
        // clear() empties the live cart but does NOT touch the drafts stash.
        assert_eq!(drafts(&s).unwrap().len(), 1);
    }
    /// A milk SLOT with no maximum set used to make milk additive: the group
    /// came out multi-select, the sheet preselected the recipe's default, and
    /// the teller's alternative landed BESIDE it. The cup was charged for two
    /// milks and the kitchen was told to pour two.
    ///
    /// The unslotted path never had this bug, so whether a shop hit it came
    /// down to whether it happened to configure a slot for milk.
    #[test]
    fn a_milk_slot_with_no_maximum_is_still_choose_one() {
        let mut i = item();
        i.addon_slots = vec![menu::AddonSlotView {
            id: "slot-milk".into(),
            label: Some("Milk".into()),
            addon_type: "milk_type".into(),
            is_required: false,
            min_selections: 0,
            // The shape that did it: nobody set a cap, and `None` means
            // "no cap" everywhere else in this model.
            max_selections: None,
        }];
        let catalog = vec![
            addon("oat", "milk_type", 1500),
            addon("full_fat", "milk_type", 1000),
        ];
        let groups = item_modifier_groups(&i, &catalog);
        let milk = groups
            .iter()
            .find(|g| g.addon_type.as_deref() == Some("milk_type"))
            .expect("the slot is offered");
        assert_eq!(
            milk.max_selections,
            Some(1),
            "a swap family replaces part of the recipe, so exactly one of it \
             can be chosen — the slot does not get a say"
        );
    }

    /// Coffee is the other swap family and was never capped at all, slotted
    /// or not: `adjusted_addon_price` charges it as a delta over the base,
    /// which only means anything when one is selected.
    #[test]
    fn coffee_is_choose_one_too_slotted_or_not() {
        let mut i = item();
        let catalog = vec![
            addon("house", "coffee_type", 0),
            addon("single_origin", "coffee_type", 800),
        ];

        let unslotted = item_modifier_groups(&i, &catalog);
        let g = unslotted
            .iter()
            .find(|g| g.addon_type.as_deref() == Some("coffee_type"))
            .expect("offered without a slot");
        assert_eq!(g.max_selections, Some(1));

        i.addon_slots = vec![menu::AddonSlotView {
            id: "slot-coffee".into(),
            label: None,
            addon_type: "coffee_type".into(),
            is_required: true,
            min_selections: 1,
            max_selections: Some(3),
        }];
        let slotted = item_modifier_groups(&i, &catalog);
        let g = slotted
            .iter()
            .find(|g| g.addon_type.as_deref() == Some("coffee_type"))
            .expect("offered with a slot");
        assert_eq!(
            g.max_selections,
            Some(1),
            "a slot asking for three is still asking for three of a thing \
             that replaces one"
        );
    }

    /// The ordinary families keep their slot's own answer — this narrows
    /// swap families and nothing else.
    #[test]
    fn an_additive_family_keeps_whatever_its_slot_asked_for() {
        let mut i = item();
        i.addon_slots = vec![menu::AddonSlotView {
            id: "slot-extra".into(),
            label: None,
            addon_type: "extra".into(),
            is_required: false,
            min_selections: 0,
            max_selections: None,
        }];
        let catalog = vec![addon("shot", "extra", 500), addon("syrup", "extra", 300)];
        let groups = item_modifier_groups(&i, &catalog);
        let g = groups
            .iter()
            .find(|g| g.addon_type.as_deref() == Some("extra"))
            .expect("offered");
        assert_eq!(g.max_selections, None, "extras still stack");
    }

    /// The incident: `value` went back to an integer on the wire, so reading
    /// it as the fraction charges 1400% instead of 14%. Every read goes
    /// through `discount_rate`.
    #[test]
    fn a_discount_reads_its_rate_and_not_the_spelling_kept_for_old_tills() {
        let now = chrono::Utc::now().fixed_offset();
        let mut d = models::Discount::new(
            now,
            "percentage".into(),
            uuid::Uuid::nil(),
            true,
            "Staff".into(),
            serde_json::json!({}),
            uuid::Uuid::nil(),
            now,
            14,
        );
        d.value_rate = Some(0.14);
        assert_eq!(discount_rate(&d), 0.14);

        // A server that predates the split sends only the legacy integer.
        d.value_rate = None;
        assert_eq!(
            discount_rate(&d),
            0.14,
            "the legacy spelling still has to come back down"
        );

        // A fixed discount is minor units in BOTH spellings — never divided.
        d.dtype = "fixed".into();
        d.value = 5000;
        assert_eq!(discount_rate(&d), 5000.0);
    }

    // ── kitchen-only notes: local, kitchen-chit only, cleared on print ────────

    #[test]
    fn a_line_kitchen_note_joins_the_view_and_clears_independently_of_the_order_note() {
        let s = store();
        let views = add(&s, None, "latte", "Latte", 5000).unwrap();
        let key = views[0].key.clone();
        set_note(&s, None, Some("extra hot")).unwrap(); // the ORDER note

        assert_eq!(lines(&s, None).unwrap()[0].kitchen_note, None);
        set_line_kitchen_note(&s, None, &key, Some("  no salt  ")).unwrap();
        assert_eq!(
            lines(&s, None).unwrap()[0].kitchen_note.as_deref(),
            Some("no salt"),
            "trimmed, and joined onto the view by line key"
        );
        // The order note is untouched by the kitchen note and vice versa.
        assert_eq!(note(&s, None).unwrap().as_deref(), Some("extra hot"));

        clear_line_kitchen_note(&s, None, &key).unwrap();
        assert_eq!(
            lines(&s, None).unwrap()[0].kitchen_note,
            None,
            "cleared on print"
        );
        assert_eq!(
            note(&s, None).unwrap().as_deref(),
            Some("extra hot"),
            "clearing the kitchen note must not touch the order note"
        );
    }

    #[test]
    fn a_blank_kitchen_note_is_the_same_as_no_note() {
        let s = store();
        let views = add(&s, None, "latte", "Latte", 5000).unwrap();
        let key = views[0].key.clone();
        set_line_kitchen_note(&s, None, &key, Some("   ")).unwrap();
        assert_eq!(lines(&s, None).unwrap()[0].kitchen_note, None);
    }

    #[test]
    fn the_cart_level_kitchen_note_is_its_own_slot() {
        let s = store();
        assert_eq!(kitchen_note(&s, None).unwrap(), None);
        set_kitchen_note(&s, None, Some("fire on the pass call")).unwrap();
        assert_eq!(
            kitchen_note(&s, None).unwrap().as_deref(),
            Some("fire on the pass call")
        );
        clear_kitchen_note(&s, None).unwrap();
        assert_eq!(kitchen_note(&s, None).unwrap(), None);
    }

    #[test]
    fn clear_all_kitchen_notes_wipes_the_cart_note_and_every_line_note() {
        let s = store();
        let views = add(&s, None, "latte", "Latte", 5000).unwrap();
        let key = views[0].key.clone();
        set_line_kitchen_note(&s, None, &key, Some("no salt")).unwrap();
        set_kitchen_note(&s, None, Some("rush")).unwrap();
        set_note(&s, None, Some("extra hot")).unwrap(); // untouched by this call

        clear_all_kitchen_notes(&s, None).unwrap();
        assert_eq!(kitchen_note(&s, None).unwrap(), None);
        assert_eq!(lines(&s, None).unwrap()[0].kitchen_note, None);
        assert_eq!(
            note(&s, None).unwrap().as_deref(),
            Some("extra hot"),
            "the order note is a different thing entirely"
        );
    }

    #[test]
    fn clear_all_wipes_every_context_kitchen_note() {
        let s = store();
        let views = add(&s, None, "latte", "Latte", 5000).unwrap();
        set_line_kitchen_note(&s, None, &views[0].key, Some("no salt")).unwrap();
        set_kitchen_note(&s, None, Some("rush")).unwrap();
        clear_all(&s).unwrap();
        assert_eq!(kitchen_note(&s, None).unwrap(), None);
        assert!(lines(&s, None).unwrap().is_empty());
    }
}
