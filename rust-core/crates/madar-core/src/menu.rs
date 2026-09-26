//! Menu / catalog reads (PLAN §R9). The POS consumes the server's already
//! branch-effective catalog and mirrors the canonical JSON into `kv`; the UI
//! reads always succeed offline. This module owns the read projection: it parses
//! the mirrored wire models and hands the host curated view DTOs with
//!   - money as `i64` minor-units (the wire is already integer minor-units),
//!   - `*_translations` pre-resolved to the device locale (fallback locale→en→base),
//!   - soft-deletes dropped.
//!
//! It does NOT re-implement the §3 branch-override merge — the server's
//! `?branch_id=` snapshot is already merged (R9). The fetch/orchestration lives
//! in `lib.rs`; this module is pure (store + locale in, view DTOs out) so it's
//! unit-testable without a network.

use madar_api::models;
use serde::Deserialize;
use serde_json::Value;

use crate::error::CoreResult;
use crate::store::Store;

// kv keys — one canonical JSON array per catalog stream.
pub(crate) const K_MENU_ITEMS: &str = "catalog:menu_items"; // Vec<MenuItemFull>
pub(crate) const K_CATEGORIES: &str = "catalog:categories"; // Vec<Category>
pub(crate) const K_ADDONS: &str = "catalog:addons"; // Vec<AddonItem>
/// The combos (bundles) mirror an older build kept. Combos were removed; the
/// catalog refresh deletes it.
pub(crate) const K_RETIRED_BUNDLES: &str = "catalog:bundles";
pub(crate) const K_PAYMENT_METHODS: &str = "catalog:payment_methods"; // Vec<OrgPaymentMethod>
pub(crate) const K_DISCOUNTS: &str = "catalog:discounts"; // Vec<Discount>
/// The branch's deal rules (COMBOS_CONTRACT §5), rebuilt from the `deal_rule`
/// feed rows by `project_pull_mirrors`: the §2.3 `DealRule` shape.
pub(crate) const K_DEALS: &str = "catalog:deals";

/// [`MenuItemView::kind`] of a plain item.
pub const KIND_ITEM: &str = "item";
/// [`MenuItemView::kind`] of a combo.
pub const KIND_COMBO: &str = "combo";

// ── view DTOs (host-facing) ─────────────────────────────────────────────────

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct MenuItemView {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub category_id: Option<String>,
    pub base_price_minor: i64,
    pub image_url: Option<String>,
    /// On-disk path of the CACHED image (downloaded by `refresh_catalog`'s
    /// image phase) — the host renders this, fully offline. `None` until the
    /// image lands; resolved at projection time in lib.rs, never per-cell.
    pub local_image_path: Option<String>,
    pub is_active: bool,
    /// The item's default-milk addon (swap families charge only the delta over it).
    pub default_milk_addon_id: Option<String>,
    /// Per-item addon allowlist (ids). Non-empty ⇒ the sheet shows only these by
    /// default, with a "show all" escape hatch (mirrors the dashboard). Empty =
    /// no restriction (show the type's full set).
    pub allowed_addon_ids: Vec<String>,
    pub sizes: Vec<ItemSizeView>,
    pub addon_slots: Vec<AddonSlotView>,
    pub optional_fields: Vec<OptionalFieldView>,
    /// The item's recipe lines (per size) — shown in the customization sheet.
    pub recipes: Vec<RecipeLineView>,
    /// How the item is made, in order — shown under the recipe.
    pub recipe_steps: Vec<RecipeStepView>,
    /// `"item"` or `"combo"` (COMBOS_CONTRACT §0): a combo opens the combo
    /// sheet ([`crate::combos`]) instead of the item sheet, and wears a
    /// "Combo" badge on the grid. A row from an older server is an item.
    pub kind: String,
}

/// One preparation step, ready to draw: already localized, and pointing at the
/// animation's CACHED file rather than a URL, so the sheet works offline.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq)]
pub struct RecipeStepView {
    /// The preset's name, or the typed name of a custom step.
    pub name: String,
    /// The preset's note, when it has one.
    pub note: Option<String>,
    /// On-disk path of the cached animation, resolved at projection time in
    /// lib.rs. `None` for a custom step, and for a preset whose animation has
    /// not been downloaded yet — the host shows the name alone.
    pub local_animation_path: Option<String>,
    /// The animation's address, relative to the API base. The core downloads
    /// it during a manual sync; the host never fetches it.
    pub animation_url: Option<String>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct ItemSizeView {
    pub id: String,
    pub label: String,
    /// Absolute price for this size (NOT a delta) — R9.
    pub price_minor: i64,
    pub is_active: bool,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct AddonSlotView {
    pub id: String,
    pub label: Option<String>,
    pub addon_type: String,
    pub is_required: bool,
    pub min_selections: i32,
    /// `None` ⇒ multi-select with no cap (R9).
    pub max_selections: Option<i32>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct OptionalFieldView {
    pub id: String,
    pub name: String,
    pub price_minor: i64,
    pub is_active: bool,
    /// Optional ingredient deduction: an optional that maps to stock carries a
    /// full `(name, unit, quantity)` triplet; cosmetic fields leave these `None`
    /// and contribute no recipe line. Mirrors Flutter's `OptionalField`.
    pub ingredient_name: Option<String>,
    pub ingredient_unit: Option<String>,
    pub quantity_used: Option<f64>,
    pub org_ingredient_id: Option<String>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct RecipeLineView {
    pub ingredient_name: String,
    /// Quantity used (major units of the ingredient's unit, e.g. 18.0 g).
    pub quantity: f64,
    pub unit: String,
    /// `None` = applies to all sizes; otherwise the size this line is for.
    pub size_label: Option<String>,
    /// Ingredient category (e.g. `milk`, `coffee_bean`) — the swap engine matches
    /// a milk/coffee addon against the base line of the same category.
    pub category: String,
    /// The org-ingredient identity — used to tell a real swap from re-selecting
    /// the default (same id ⇒ no swap). May be absent on older rows.
    pub org_ingredient_id: Option<String>,
}

/// One ingredient embedded in an addon item (`/addon-items` wire). Drives the
/// recipe preview: a milk/coffee addon's first ingredient replaces the base
/// line; other addons add their ingredients (scaled by qty).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct AddonIngredientView {
    pub ingredient_name: String,
    pub unit: String,
    pub quantity: f64,
    pub org_ingredient_id: Option<String>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct CategoryView {
    pub id: String,
    pub name: String,
    pub image_url: Option<String>,
    pub is_active: bool,
    /// Dashboard-authored drag-and-drop position (lower first). `list_categories`
    /// already returns rows sorted by this (ties on name), so callers can just
    /// render in order — the field is exposed for any screen that re-sorts a
    /// filtered subset and needs to preserve it.
    pub display_order: i32,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct AddonItemView {
    pub id: String,
    pub name: String,
    pub addon_type: String,
    pub default_price_minor: i64,
    pub is_active: bool,
    /// Embedded ingredient rows (recipe preview input). Empty when the addon has
    /// no stock impact (e.g. a flavour shot) or the wire omitted them.
    pub ingredients: Vec<AddonIngredientView>,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct PaymentMethodView {
    pub id: String,
    pub name: String,
    pub is_cash: bool,
    pub icon: String,
    pub color: String,
}

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug)]
pub struct DiscountView {
    pub id: String,
    pub name: String,
    /// Open string: `percentage` | `fixed` | … — host interprets `value`.
    pub dtype: String,
    /// A FRACTION for `percentage` (0.14 = 14%), minor-units for `fixed`.
    pub value: f64,
    pub is_active: bool,
}

// ── projections (kv → views) ────────────────────────────────────────────────

// Local, deserialization-TOLERANT shapes for the `?full=true` menu-item wire.
//
// We deliberately DO NOT reuse `models::MenuItemFull` here: that generated struct
// embeds `recipes: Vec<MenuItemRecipe>` and `optional_fields[].quantity_used`,
// both typed `f64` by the generator — but the backend serializes those Postgres
// `numeric` columns via `BigDecimal`, i.e. as JSON *strings* ("0.500"). serde
// then fails the WHOLE `Vec<MenuItemFull>` parse, which blanked the menu (the
// host swallows the error to an empty list). These local structs capture only
// the fields the POS projection actually needs and omit every decimal field, so
// the wire's string-vs-number encoding can't break the read. Unknown JSON fields
// are ignored by serde, so this stays forward-compatible.
#[derive(Deserialize)]
struct FullItem {
    id: uuid::Uuid,
    name: String,
    #[serde(default)]
    name_translations: Value,
    #[serde(default)]
    description: Option<String>,
    #[serde(default)]
    description_translations: Value,
    #[serde(default)]
    category_id: Option<uuid::Uuid>,
    base_price: i32,
    #[serde(default)]
    image_url: Option<String>,
    is_active: bool,
    #[serde(default)]
    deleted_at: Option<chrono::DateTime<chrono::FixedOffset>>,
    #[serde(default)]
    default_milk_addon_id: Option<String>,
    #[serde(default)]
    allowed_addon_ids: Vec<String>,
    #[serde(default)]
    sizes: Vec<FullSize>,
    #[serde(default)]
    addon_slots: Vec<FullSlot>,
    #[serde(default)]
    optional_fields: Vec<FullOptional>,
    #[serde(default)]
    recipes: Vec<FullRecipe>,
    #[serde(default)]
    recipe_steps: Vec<FullStep>,
    /// `item` | `combo`; absent from a server older than the combos module.
    #[serde(default)]
    kind: Option<String>,
}

#[derive(Deserialize)]
struct FullStep {
    #[serde(default)]
    name: String,
    #[serde(default)]
    name_ar: String,
    #[serde(default)]
    note: Option<String>,
    #[serde(default)]
    note_ar: Option<String>,
    #[serde(default)]
    animation_url: Option<String>,
}

#[derive(Deserialize)]
struct FullRecipe {
    #[serde(default)]
    ingredient_name: String,
    #[serde(default)]
    ingredient_unit: String,
    #[serde(default)]
    size_label: Option<String>,
    #[serde(default)]
    category: String,
    #[serde(default)]
    org_ingredient_id: Option<String>,
    // A `Value`, so either encoding parses. The backend sends a NUMBER now
    // (`decimals::serialize`, and a guard test that fails the build if a new
    // `numeric` field forgets it), but it used to send the string `"18.000"`
    // and a till in the field may still be talking to a server that does.
    // Tolerating both is what makes the deploy order not matter; projected to
    // f64 below either way.
    #[serde(default)]
    quantity_used: Value,
}

#[derive(Deserialize)]
struct FullSize {
    id: uuid::Uuid,
    label: String,
    price_override: i32,
    is_active: bool,
}

#[derive(Deserialize)]
struct FullSlot {
    id: uuid::Uuid,
    #[serde(default)]
    label: Option<String>,
    #[serde(default)]
    label_translations: Value,
    addon_type: String,
    is_required: bool,
    min_selections: i32,
    #[serde(default)]
    max_selections: Option<i32>,
}

#[derive(Deserialize)]
struct FullOptional {
    id: uuid::Uuid,
    name: String,
    #[serde(default)]
    name_translations: Value,
    price: i32,
    is_active: bool,
    #[serde(default)]
    ingredient_name: Option<String>,
    #[serde(default)]
    ingredient_unit: Option<String>,
    #[serde(default)]
    org_ingredient_id: Option<String>,
    // numeric → BigDecimal → JSON STRING; tolerant Value (projected below).
    #[serde(default)]
    quantity_used: Value,
}

// Tolerant local shape for the `/addon-items` wire. Like the menu, the embedded
// ingredient `quantity_used` is a Postgres `numeric` → BigDecimal → JSON STRING,
// so the generated `models::AddonItem` (which types it `f64`) can't parse it. We
// capture only what the catalog + recipe preview need, decimals as `Value`.
#[derive(Deserialize)]
struct FullAddon {
    id: uuid::Uuid,
    name: String,
    #[serde(default)]
    name_translations: Value,
    addon_type: String,
    default_price: i32,
    is_active: bool,
    #[serde(default)]
    ingredients: Vec<FullAddonIngredient>,
}

#[derive(Deserialize)]
struct FullAddonIngredient {
    #[serde(default)]
    ingredient_name: String,
    #[serde(default)]
    ingredient_unit: String,
    #[serde(default)]
    org_ingredient_id: Option<String>,
    #[serde(default)]
    quantity_used: Value,
}

/// Pick the language for a value that ships as a plain pair rather than a
/// translations map. An empty side falls back to the other, so a step typed in
/// one language shows everywhere rather than rendering blank.
pub(crate) fn pick_lang(base: &str, ar: &str, locale: &str) -> String {
    let want_ar = locale.starts_with("ar");
    let chosen = if want_ar && !ar.is_empty() { ar } else { base };
    if chosen.is_empty() {
        let other = if want_ar { base } else { ar };
        return other.to_string();
    }
    chosen.to_string()
}

pub(crate) fn menu_items(store: &Store, locale: &str) -> CoreResult<Vec<MenuItemView>> {
    let items: Vec<FullItem> = parse_kv_lenient(store, K_MENU_ITEMS)?;
    Ok(items
        .into_iter()
        .filter(|i| i.deleted_at.is_none())
        .map(|i| MenuItemView {
            id: i.id.to_string(),
            name: resolve(&i.name_translations, &i.name, locale),
            description: i
                .description
                .clone()
                .map(|d| resolve(&i.description_translations, &d, locale)),
            category_id: i.category_id.map(|c| c.to_string()),
            base_price_minor: i.base_price as i64,
            image_url: i.image_url.clone(),
            local_image_path: None,
            is_active: i.is_active,
            default_milk_addon_id: i.default_milk_addon_id.clone(),
            allowed_addon_ids: i.allowed_addon_ids.clone(),
            recipes: i
                .recipes
                .iter()
                .map(|r| RecipeLineView {
                    ingredient_name: r.ingredient_name.clone(),
                    quantity: value_to_f64(&r.quantity_used),
                    unit: r.ingredient_unit.clone(),
                    size_label: r.size_label.clone().filter(|s| !s.is_empty()),
                    category: r.category.clone(),
                    org_ingredient_id: r.org_ingredient_id.clone().filter(|s| !s.is_empty()),
                })
                .collect(),
            kind: match i.kind.as_deref() {
                Some(KIND_COMBO) => KIND_COMBO.to_string(),
                _ => KIND_ITEM.to_string(),
            },
            recipe_steps: i
                .recipe_steps
                .iter()
                .map(|s| RecipeStepView {
                    // The step carries both languages; pick one here so the
                    // host renders a string rather than choosing again.
                    name: pick_lang(&s.name, &s.name_ar, locale),
                    note: {
                        let n = pick_lang(
                            s.note.as_deref().unwrap_or_default(),
                            s.note_ar.as_deref().unwrap_or_default(),
                            locale,
                        );
                        Some(n).filter(|n| !n.is_empty())
                    },
                    local_animation_path: None,
                    animation_url: s.animation_url.clone().filter(|u| !u.is_empty()),
                })
                .collect(),
            sizes: i
                .sizes
                .iter()
                .map(|s| ItemSizeView {
                    id: s.id.to_string(),
                    label: s.label.clone(),
                    price_minor: s.price_override as i64,
                    is_active: s.is_active,
                })
                .collect(),
            addon_slots: i
                .addon_slots
                .iter()
                .map(|sl| AddonSlotView {
                    id: sl.id.to_string(),
                    label: sl
                        .label
                        .clone()
                        .map(|l| resolve(&sl.label_translations, &l, locale)),
                    addon_type: sl.addon_type.clone(),
                    is_required: sl.is_required,
                    min_selections: sl.min_selections,
                    max_selections: sl.max_selections,
                })
                .collect(),
            optional_fields: i
                .optional_fields
                .iter()
                .map(|o| OptionalFieldView {
                    id: o.id.to_string(),
                    name: resolve(&o.name_translations, &o.name, locale),
                    price_minor: o.price as i64,
                    is_active: o.is_active,
                    ingredient_name: o.ingredient_name.clone().filter(|s| !s.is_empty()),
                    ingredient_unit: o.ingredient_unit.clone().filter(|s| !s.is_empty()),
                    quantity_used: value_to_opt_f64(&o.quantity_used),
                    org_ingredient_id: o.org_ingredient_id.clone().filter(|s| !s.is_empty()),
                })
                .collect(),
        })
        .collect())
}

// ── combos and "make it a meal" (COMBOS_CONTRACT §2.4) ──────────────────────
//
// A combo is a menu row of `kind = 'combo'`: its price is the row's usual
// price, its own half (`combo`) the slots, choices and windows. A plain row
// may carry `meal`: the combo it upgrades to and the slot it fills (C14).
// Parsed leniently on their own, so a malformed `combo` never blanks the menu:
// the row stays on the grid and simply cannot be sold as a combo.

/// A combo's own half, localized, as the till sells it.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct ComboDef {
    pub id: String,
    pub name: String,
    pub is_active: bool,
    pub category_id: Option<String>,
    /// The channel switches the row carries resolved for this branch (§2.4);
    /// `None` from a server that sends them elsewhere (branch settings).
    pub sell: Option<madar_catalog::combo::Sell>,
    pub windows: Vec<madar_catalog::sale_window::Window>,
    pub slots: Vec<ComboSlotDef>,
}

/// One slot of a combo, localized.
#[derive(Clone, Debug, Default, PartialEq)]
pub(crate) struct ComboSlotDef {
    pub id: String,
    pub name: String,
    pub sort: i64,
    pub min: i64,
    pub max: i64,
    pub default_item_id: Option<String>,
    pub default_size_label: Option<String>,
    pub choices: Vec<madar_catalog::combo::ChoiceView>,
}

/// "Make it a meal": the combo a plain item upgrades to and the slot it fills.
#[derive(Clone, Debug, Default, PartialEq, Eq, Deserialize)]
pub(crate) struct MealRef {
    pub combo_id: String,
    pub slot_id: String,
}

#[derive(Deserialize)]
struct WireComboRow {
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    name_translations: Value,
    #[serde(default)]
    category_id: Option<String>,
    #[serde(default = "yes")]
    is_active: bool,
    #[serde(default)]
    deleted_at: Option<Value>,
    #[serde(default)]
    kind: Option<String>,
    #[serde(default)]
    combo: Option<Value>,
    #[serde(default)]
    meal: Option<Value>,
}

#[derive(Deserialize)]
struct WireCombo {
    #[serde(default)]
    sell: Option<madar_catalog::combo::Sell>,
    #[serde(default)]
    windows: Vec<madar_catalog::sale_window::Window>,
    #[serde(default)]
    slots: Vec<WireSlot>,
}

#[derive(Deserialize)]
struct WireSlot {
    id: String,
    #[serde(default)]
    name: String,
    #[serde(default)]
    name_translations: Value,
    #[serde(default)]
    sort: i64,
    #[serde(default = "one", alias = "min_picks")]
    min: i64,
    #[serde(default = "one", alias = "max_picks")]
    max: i64,
    #[serde(default)]
    default_item_id: Option<String>,
    #[serde(default)]
    default_size_label: Option<String>,
    #[serde(default)]
    choices: Vec<madar_catalog::combo::ChoiceView>,
}

fn yes() -> bool {
    true
}

fn one() -> i64 {
    1
}

/// Every combo on the mirrored menu (soft-deleted rows dropped), localized,
/// with its slots in their sort order.
pub(crate) fn combos(store: &Store, locale: &str) -> CoreResult<Vec<ComboDef>> {
    let rows: Vec<WireComboRow> = parse_kv_lenient(store, K_MENU_ITEMS)?;
    Ok(rows
        .into_iter()
        .filter(|r| r.deleted_at.as_ref().is_none_or(Value::is_null))
        .filter(|r| r.kind.as_deref() == Some(KIND_COMBO))
        .filter_map(|r| {
            let wire: WireCombo = serde_json::from_value(r.combo?).ok()?;
            let mut slots: Vec<ComboSlotDef> = wire
                .slots
                .into_iter()
                .map(|sl| ComboSlotDef {
                    name: resolve(&sl.name_translations, &sl.name, locale),
                    id: sl.id,
                    sort: sl.sort,
                    min: sl.min.max(0),
                    max: sl.max.max(1),
                    default_item_id: sl.default_item_id.filter(|s| !s.is_empty()),
                    default_size_label: sl.default_size_label.filter(|s| !s.is_empty()),
                    choices: sl.choices,
                })
                .collect();
            slots.sort_by_key(|s| s.sort);
            Some(ComboDef {
                name: resolve(&r.name_translations, &r.name, locale),
                id: r.id,
                is_active: r.is_active,
                category_id: r.category_id,
                sell: wire.sell,
                windows: wire.windows,
                slots,
            })
        })
        .collect())
}

/// Every plain item's "make it a meal" pointer, by item id.
pub(crate) fn meals(store: &Store) -> CoreResult<std::collections::HashMap<String, MealRef>> {
    let rows: Vec<WireComboRow> = parse_kv_lenient(store, K_MENU_ITEMS)?;
    Ok(rows
        .into_iter()
        .filter(|r| r.deleted_at.as_ref().is_none_or(Value::is_null))
        .filter(|r| r.kind.as_deref() != Some(KIND_COMBO))
        .filter_map(|r| {
            let m: MealRef = serde_json::from_value(r.meal?).ok()?;
            (!m.combo_id.is_empty() && !m.slot_id.is_empty()).then(|| (r.id, m))
        })
        .collect())
}

/// Own (lenient) shape for the cached `/categories` mirror, rather than the
/// generated `models::Category` directly: `display_order` is new, and a
/// category cached by a build from before it existed must still decode —
/// `#[serde(default)]` makes a missing value 0 (sorts first, same as
/// everything else that predates ordering) instead of blanking the whole
/// category list.
#[derive(Deserialize)]
struct LocalCategory {
    id: uuid::Uuid,
    name: String,
    #[serde(default)]
    name_translations: Value,
    #[serde(default)]
    image_url: Option<String>,
    is_active: bool,
    #[serde(default)]
    deleted_at: Option<Value>,
    #[serde(default)]
    display_order: i32,
}

pub(crate) fn categories(store: &Store, locale: &str) -> CoreResult<Vec<CategoryView>> {
    let cats: Vec<LocalCategory> = parse_kv(store, K_CATEGORIES)?;
    let mut views: Vec<CategoryView> = cats
        .into_iter()
        .filter(|c| c.deleted_at.as_ref().map(|v| v.is_null()).unwrap_or(true))
        .map(|c| CategoryView {
            id: c.id.to_string(),
            name: resolve(&c.name_translations, &c.name, locale),
            image_url: c.image_url,
            is_active: c.is_active,
            display_order: c.display_order,
        })
        .collect();
    // Custom drag-and-drop order, authored on the dashboard; ties break on the
    // resolved (locale) name so two categories at the same position are still
    // deterministic offline.
    views.sort_by(|a, b| {
        a.display_order
            .cmp(&b.display_order)
            .then_with(|| a.name.cmp(&b.name))
    });
    Ok(views)
}

pub(crate) fn addons(store: &Store, locale: &str) -> CoreResult<Vec<AddonItemView>> {
    // Lenient, decimal-tolerant parse: the `/addon-items` wire embeds ingredient
    // `quantity_used` as a BigDecimal string, which the generated `AddonItem`
    // (f64) can't decode — and a single bad row must never blank the addon list.
    let items: Vec<FullAddon> = parse_kv_lenient(store, K_ADDONS)?;
    Ok(items
        .into_iter()
        .map(|a| AddonItemView {
            id: a.id.to_string(),
            name: resolve(&a.name_translations, &a.name, locale),
            addon_type: a.addon_type.clone(),
            default_price_minor: a.default_price as i64,
            is_active: a.is_active,
            ingredients: a
                .ingredients
                .iter()
                .map(|ing| AddonIngredientView {
                    ingredient_name: ing.ingredient_name.clone(),
                    unit: ing.ingredient_unit.clone(),
                    quantity: value_to_f64(&ing.quantity_used),
                    org_ingredient_id: ing.org_ingredient_id.clone().filter(|s| !s.is_empty()),
                })
                .collect(),
        })
        .collect())
}

/// The payment-method catalog AS CACHED ON DISK.
///
/// Deliberately a core-local shape rather than `madar_api::models::OrgPaymentMethod`.
/// The cache is written by whatever build was installed yesterday and read by the
/// one installed today, so a field the backend adds — which the generator then
/// marks REQUIRED — makes every existing device's cached catalog fail to decode.
/// That is not hypothetical: `visible_in_integrations` did exactly this. And the
/// failure is silent and expensive, because the read sites fall back to an empty
/// list: checkout stops recognising any payment method, and the offline Z-report
/// counts no cash at all. Every field here is therefore optional-with-default, so
/// both an older and a newer payload still yield a usable row.
#[derive(Clone, Debug, serde::Deserialize)]
pub(crate) struct CachedPaymentMethod {
    pub id: uuid::Uuid,
    pub name: String,
    #[serde(default)]
    pub is_cash: bool,
    /// A method present in the catalog is presumed usable when the payload
    /// predates the flag — defaulting to false would hide every method.
    #[serde(default = "cached_method_active_default")]
    pub is_active: bool,
    #[serde(default)]
    pub icon: String,
    #[serde(default)]
    pub color: String,
    #[serde(default)]
    pub label_translations: Option<Value>,
}

fn cached_method_active_default() -> bool {
    true
}

/// Read the cached payment-method catalog. One place, so no caller reintroduces
/// a strict decode against the generated model.
pub(crate) fn cached_payment_methods(store: &Store) -> CoreResult<Vec<CachedPaymentMethod>> {
    parse_kv_lenient(store, K_PAYMENT_METHODS)
}

pub(crate) fn payment_methods(store: &Store, locale: &str) -> CoreResult<Vec<PaymentMethodView>> {
    let items = cached_payment_methods(store)?;
    Ok(items
        .into_iter()
        .filter(|p| p.is_active)
        .map(|p| PaymentMethodView {
            id: p.id.to_string(),
            name: resolve(
                p.label_translations.as_ref().unwrap_or(&Value::Null),
                &p.name,
                locale,
            ),
            is_cash: p.is_cash,
            icon: p.icon.clone(),
            color: p.color.clone(),
        })
        .collect())
}

pub(crate) fn discounts(store: &Store, locale: &str) -> CoreResult<Vec<DiscountView>> {
    let items: Vec<models::Discount> = parse_kv(store, K_DISCOUNTS)?;
    Ok(items
        .into_iter()
        .map(|d| DiscountView {
            id: d.id.to_string(),
            name: resolve(&d.name_translations, &d.name, locale),
            dtype: d.dtype.clone(),
            value: crate::cart::discount_rate(&d),
            is_active: d.is_active,
        })
        .collect())
}

// ── unified catalog mirror (menu unification: `GET /catalog/sync`) ──────────
//
// The NEW backend serves the unified modifier model (groups + options with
// branch-effective prices) revision-gated at `/catalog/sync`. The raw response
// JSON is mirrored under `K_UNIFIED` by `refresh_catalog`, and each pull keeps
// its per-item groups equal to the feed's `menu_item` rows
// (`unified_with_feed_groups`); these tolerant
// shapes read back only what the POS consumes. An OLD backend (404) or a
// not-yet-backfilled org simply never writes the key, and every reader falls
// back to the legacy projection — no version coupling in either direction.

pub(crate) const K_UNIFIED: &str = "catalog:unified"; // raw CatalogSyncResponse JSON

#[derive(Clone, Deserialize)]
pub(crate) struct UnifiedOption {
    pub id: String,
    pub name: String,
    #[serde(default)]
    pub name_translations: Value,
    #[serde(default)]
    pub price: i64,
    #[serde(default = "unified_true")]
    pub is_available: bool,
    /// The group's default pick. The staff comp's allowance is its price; an
    /// older backend omits it and the cheapest option sets the allowance.
    #[serde(default)]
    pub is_default: bool,
}

#[derive(Clone, Deserialize)]
pub(crate) struct UnifiedGroup {
    pub group_id: String,
    #[serde(default)]
    pub name: String,
    #[serde(default)]
    pub name_translations: Value,
    #[serde(default)]
    pub selection_type: String,
    #[serde(default)]
    pub min: i32,
    #[serde(default)]
    pub max: Option<i32>,
    #[serde(default)]
    pub is_required: bool,
    #[serde(default)]
    pub legacy_addon_type: Option<String>,
    /// `adds` | `swaps`. A swap group is never a comp group (staff drinks).
    #[serde(default)]
    pub effect: String,
    #[serde(default)]
    pub options: Vec<UnifiedOption>,
}

#[derive(Deserialize)]
struct UnifiedItem {
    id: String,
    #[serde(default)]
    modifier_groups: Vec<UnifiedGroup>,
}

#[derive(Deserialize)]
pub(crate) struct UnifiedDoc {
    #[serde(default)]
    catalog_revision: i64,
    #[serde(default)]
    items: Vec<UnifiedItem>,
}

impl UnifiedDoc {
    /// The unified groups for one item, from an ALREADY-PARSED doc — same
    /// `None`/empty fallback semantics as [`unified_groups_for`]. The core's
    /// catalog snapshot holds the parsed doc so the customization sheet's
    /// per-toggle reads stop re-parsing the whole mirror.
    pub(crate) fn groups_for(&self, item_id: &str) -> Option<Vec<UnifiedGroup>> {
        self.items
            .iter()
            .find(|i| i.id == item_id)
            .map(|i| i.modifier_groups.clone())
            .filter(|groups| !groups.is_empty())
    }

    /// The item is listed with NO attached group. The unified wire (the feed
    /// and `/catalog/sync`) lists only ACTIVE groups, while the legacy
    /// `/menu-items` slots are a view over the same attachments that keeps a
    /// soft-deleted group: for such an item every legacy slot is stale.
    pub(crate) fn lists_without_groups(&self, item_id: &str) -> bool {
        self.items
            .iter()
            .any(|i| i.id == item_id && i.modifier_groups.is_empty())
    }
}

/// Parse the mirrored unified catalog once (`None` = never synced / unreadable).
pub(crate) fn unified_doc(store: &Store) -> Option<UnifiedDoc> {
    let raw = store.kv_get(K_UNIFIED).ok()??;
    serde_json::from_str(&raw).ok()
}

fn unified_true() -> bool {
    true
}

/// The mirrored unified catalog's revision. `None` = never synced (old backend
/// or pre-backfill org) — callers pass no `since` and fall back on reads.
pub(crate) fn unified_revision(store: &Store) -> Option<i64> {
    let raw = store.kv_get(K_UNIFIED).ok()??;
    serde_json::from_str::<UnifiedDoc>(&raw)
        .ok()
        .map(|d| d.catalog_revision)
}

/// True when `body` is a `changed:false` poll response — the device is current
/// and the existing mirror must be KEPT (the body carries no payload).
pub(crate) fn unified_unchanged(body: &str) -> bool {
    #[derive(Deserialize)]
    struct Changed {
        #[serde(default = "unified_true")]
        changed: bool,
    }
    serde_json::from_str::<Changed>(body)
        .map(|c| !c.changed)
        .unwrap_or(false)
}

/// The revision of a unified mirror built from the feed alone: never a real
/// one, so the next manual sync asks `/catalog/sync` for everything.
const FEED_ONLY_REVISION: i64 = -1;

/// Keep the unified mirror's per-item modifier groups equal to the
/// changefeed's `menu_item` rows. A row is the same `SyncItem` shape
/// `/catalog/sync` returns (the options' recipes stripped), and the feed
/// moves within seconds of a dashboard edit, while `/catalog/sync` is fetched
/// only by a first boot or a manual sync. Reading groups from that fetch alone
/// kept a REQUIRED group attached on the dashboard off the item sheet until
/// someone pressed sync, and the next tap added the item without its pick
/// (T1, the till sheet-cache regression). An attached, edited or detached
/// group now reaches every reader of the mirror with the pull.
///
/// Items the feed does not carry keep what the last fetch said, and the
/// revision is kept, so a manual sync still asks for what changed since.
/// Returns the new mirror when a group changed, `None` when it already agrees.
pub(crate) fn unified_with_feed_groups(raw: Option<&str>, feed_items: &[Value]) -> Option<String> {
    let mut doc = raw
        .and_then(|r| serde_json::from_str::<Value>(r).ok())
        .filter(Value::is_object)
        .unwrap_or_else(
            || serde_json::json!({ "catalog_revision": FEED_ONLY_REVISION, "items": [] }),
        );
    let items = doc
        .as_object_mut()?
        .entry("items")
        .or_insert_with(|| Value::Array(Vec::new()));
    if !items.is_array() {
        *items = Value::Array(Vec::new());
    }
    let items = items.as_array_mut()?;
    let mut changed = false;
    for row in feed_items {
        let Some(id) = row.get("id").and_then(Value::as_str) else {
            continue;
        };
        let groups = row
            .get("modifier_groups")
            .filter(|g| g.is_array())
            .cloned()
            .unwrap_or_else(|| Value::Array(Vec::new()));
        match items
            .iter()
            .position(|i| i.get("id").and_then(Value::as_str) == Some(id))
        {
            Some(at) => {
                if items[at]
                    .get("modifier_groups")
                    .is_some_and(|g| same_groups(g, &groups))
                {
                    continue;
                }
                items[at]["modifier_groups"] = groups;
            }
            None => {
                let mut item = row.clone();
                if let Some(m) = item.as_object_mut() {
                    m.remove("seq");
                }
                items.push(item);
            }
        }
        changed = true;
    }
    changed.then(|| doc.to_string())
}

/// Two lists of an item's groups say the same thing to the till. The
/// `/catalog/sync` fetch carries each option's recipe and the feed does not;
/// nothing on the till reads it, so it never counts as a change.
fn same_groups(a: &Value, b: &Value) -> bool {
    fn without_recipes(v: &Value) -> Value {
        let mut v = v.clone();
        for g in v.as_array_mut().into_iter().flatten() {
            let options = g.get_mut("options").and_then(Value::as_array_mut);
            for o in options.into_iter().flatten() {
                if let Some(m) = o.as_object_mut() {
                    m.remove("recipe");
                }
            }
        }
        v
    }
    without_recipes(a) == without_recipes(b)
}

/// The unified modifier groups for one item. `None` ⇒ no unified mirror, the
/// item isn't in it, or the item has NO attached groups ⇒ the caller uses the
/// legacy projection. The empty case matters during the migration: items that
/// relied on the legacy implicit "offer all org addons" default have no
/// attachments yet (the backfill's `info.implicit_all_addons` note), and the
/// flat-catalog fallback keeps showing them the full offer — same per-item
/// fallback rule as the storefront customizer. Once a group IS attached, the
/// unified wire becomes authoritative for that item.
#[cfg(test)] // production reads go through the core's parsed CatalogSnapshot
pub(crate) fn unified_groups_for(store: &Store, item_id: &str) -> Option<Vec<UnifiedGroup>> {
    unified_doc(store).and_then(|doc| doc.groups_for(item_id))
}

// ── helpers ─────────────────────────────────────────────────────────────────

/// Parse a kv catalog stream into a typed vec; an absent key = empty list (the
/// host shows nothing until the first sync, never an error).
fn parse_kv<T: serde::de::DeserializeOwned>(store: &Store, key: &str) -> CoreResult<Vec<T>> {
    match store.kv_get(key)? {
        Some(json) => Ok(serde_json::from_str(&json)?),
        None => Ok(Vec::new()),
    }
}

/// Like `parse_kv`, but parses the array element-by-element and SKIPS any row
/// that fails to deserialize, instead of failing the whole stream. A single
/// malformed item must never blank an entire catalog screen — better to show the
/// rows that parse. Used for the menu items, whose `?full=true` payload is the
/// widest (and historically the most fragile) shape on the wire.
fn parse_kv_lenient<T: serde::de::DeserializeOwned>(
    store: &Store,
    key: &str,
) -> CoreResult<Vec<T>> {
    let rows: Vec<Value> = match store.kv_get(key)? {
        Some(json) => serde_json::from_str(&json)?,
        None => return Ok(Vec::new()),
    };
    Ok(rows
        .into_iter()
        .filter_map(|v| serde_json::from_value(v).ok())
        .collect())
}

/// Resolve a `*_translations` object to the device locale, falling back
/// locale → its language subtag → `en` → the base field (R9).
pub(crate) fn resolve(translations: &Value, base: &str, locale: &str) -> String {
    let lang = locale.split(['-', '_']).next().unwrap_or(locale);
    for key in [locale, lang, "en"] {
        if let Some(s) = translations.get(key).and_then(Value::as_str) {
            if !s.is_empty() {
                return s.to_string();
            }
        }
    }
    base.to_string()
}

/// A JSON number OR a BigDecimal-as-string ("18.000") → f64 (0.0 on failure).
fn value_to_f64(v: &Value) -> f64 {
    v.as_f64()
        .or_else(|| v.as_str().and_then(|s| s.parse().ok()))
        .unwrap_or(0.0)
}

/// Like `value_to_f64` but preserves absence: JSON `null`/missing → `None`, so a
/// cosmetic optional (no ingredient deduction) is distinguishable from a 0 qty.
fn value_to_opt_f64(v: &Value) -> Option<f64> {
    match v {
        Value::Null => None,
        Value::Number(_) => v.as_f64(),
        Value::String(s) => s.parse().ok(),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn seed(store: &Store, key: &str, json: &str) {
        store.kv_put(key, json).unwrap();
    }

    #[test]
    fn menu_items_project_and_resolve_locale() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[{
              "base_price": 5000,
              "created_at": "2026-06-19T10:00:00Z",
              "updated_at": "2026-06-19T10:00:00Z",
              "id": "00000000-0000-0000-0000-0000000000a1",
              "org_id": "00000000-0000-0000-0000-0000000000ff",
              "is_active": true,
              "name": "Latte",
              "name_translations": {"ar": "لاتيه", "en": "Latte"},
              "description_translations": {},
              "addon_slots": [{
                  "addon_type": "milk_type", "id": "00000000-0000-0000-0000-0000000000b1",
                  "created_at": "2026-06-19T10:00:00Z",
                  "is_required": false, "label": null, "label_translations": {},
                  "max_selections": null, "menu_item_id": "00000000-0000-0000-0000-0000000000a1",
                  "min_selections": 0
              }],
              "allowed_addon_ids": [],
              "optional_fields": [],
              "recipes": [],
              "sizes": [{
                  "id": "00000000-0000-0000-0000-0000000000c1", "is_active": true,
                  "label": "Large", "menu_item_id": "00000000-0000-0000-0000-0000000000a1",
                  "price_override": 6000
              }]
            }]"#,
        );

        let ar = menu_items(&store, "ar-EG").unwrap();
        assert_eq!(ar.len(), 1);
        assert_eq!(ar[0].name, "لاتيه"); // ar-EG → ar
        assert_eq!(ar[0].base_price_minor, 5000);
        assert_eq!(ar[0].sizes[0].price_minor, 6000);
        assert_eq!(ar[0].addon_slots[0].max_selections, None); // null = no cap

        let en = menu_items(&store, "en").unwrap();
        assert_eq!(en[0].name, "Latte");

        // Unknown locale with no match → base field.
        let fr = menu_items(&store, "fr").unwrap();
        assert_eq!(fr[0].name, "Latte");
    }

    #[test]
    fn menu_items_tolerate_bigdecimal_string_quantity_used() {
        // Regression: the backend serializes `quantity_used` (Postgres numeric)
        // via BigDecimal, i.e. as a JSON STRING. The generated MenuItemFull types
        // it `f64`, so the full-payload parse used to fail and blank the menu.
        // Recipes + optional_fields here carry string quantity_used — the read
        // must still surface the item.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[{
              "base_price": 5000,
              "created_at": "2026-06-19T10:00:00Z",
              "updated_at": "2026-06-19T10:00:00Z",
              "id": "00000000-0000-0000-0000-0000000000a1",
              "org_id": "00000000-0000-0000-0000-0000000000ff",
              "is_active": true,
              "name": "Latte",
              "name_translations": {"en": "Latte"},
              "description_translations": {},
              "addon_slots": [],
              "allowed_addon_ids": ["00000000-0000-0000-0000-0000000000d1"],
              "optional_fields": [{
                  "id": "00000000-0000-0000-0000-0000000000f1",
                  "created_at": "2026-06-19T10:00:00Z",
                  "updated_at": "2026-06-19T10:00:00Z",
                  "menu_item_id": "00000000-0000-0000-0000-0000000000a1",
                  "name": "Extra shot",
                  "name_translations": {"en": "Extra shot"},
                  "price": 1500,
                  "is_active": true,
                  "quantity_used": "0.500",
                  "ingredient_unit": "shot"
              }],
              "recipes": [{
                  "category": "coffee", "ingredient_name": "Beans",
                  "ingredient_unit": "g", "quantity_used": "18.000", "size_label": "Large"
              }],
              "recipe_steps": [
                {"kind": "preset", "name": "Steam milk", "name_ar": "تبخير الحليب",
                 "note": "60 °C with foam", "note_ar": "٦٠° مع رغوة",
                 "animation_url": "/static/step-animations/steam_milk.json?v=abc123"},
                {"kind": "custom", "name": "Serve with the branded straw",
                 "name_ar": "Serve with the branded straw", "animation_url": null}
              ],
              "sizes": []
            }]"#,
        );

        let items = menu_items(&store, "en").unwrap();
        assert_eq!(
            items.len(),
            1,
            "string quantity_used must not blank the menu"
        );
        assert_eq!(items[0].name, "Latte");
        assert_eq!(items[0].base_price_minor, 5000);
        assert_eq!(items[0].optional_fields.len(), 1);
        assert_eq!(items[0].optional_fields[0].name, "Extra shot");
        assert_eq!(items[0].optional_fields[0].price_minor, 1500);
        // Optional ingredient mapping projects (BigDecimal-string qty tolerated).
        assert_eq!(items[0].optional_fields[0].quantity_used, Some(0.5));
        assert_eq!(
            items[0].optional_fields[0].ingredient_unit.as_deref(),
            Some("shot")
        );
        assert_eq!(items[0].optional_fields[0].ingredient_name, None); // absent → None
                                                                       // Recipes now parse despite the BigDecimal-as-string quantity_used.
        assert_eq!(items[0].recipes.len(), 1);
        assert_eq!(items[0].recipes[0].ingredient_name, "Beans");
        assert_eq!(items[0].recipes[0].quantity, 18.0);
        assert_eq!(items[0].recipes[0].unit, "g");
        assert_eq!(items[0].recipes[0].size_label.as_deref(), Some("Large"));

        // Steps arrive in order, localized, with the animation's address kept
        // for the sync to fetch and the local path still unresolved here.
        let steps = &items[0].recipe_steps;
        assert_eq!(steps.len(), 2);
        assert_eq!(steps[0].name, "Steam milk");
        assert_eq!(steps[0].note.as_deref(), Some("60 °C with foam"));
        assert!(steps[0]
            .animation_url
            .as_deref()
            .is_some_and(|u| u.contains("steam_milk")));
        assert_eq!(
            steps[0].local_animation_path, None,
            "resolved at projection, not parse"
        );
        // A written step has no animation at all.
        assert_eq!(steps[1].name, "Serve with the branded straw");
        assert_eq!(steps[1].animation_url, None);
        assert_eq!(steps[1].note, None, "a blank note stays absent");

        // Arabic picks the other side of each pair.
        let ar = menu_items(&store, "ar").unwrap();
        assert_eq!(ar[0].recipe_steps[0].name, "تبخير الحليب");
        assert_eq!(ar[0].recipe_steps[0].note.as_deref(), Some("٦٠° مع رغوة"));
        assert_eq!(items[0].recipes[0].category, "coffee");
        // Per-item addon allowlist surfaces for the "show item's options" default.
        assert_eq!(
            items[0].allowed_addon_ids,
            vec!["00000000-0000-0000-0000-0000000000d1"]
        );
    }

    #[test]
    fn menu_items_skip_malformed_rows_keep_good_ones() {
        // One broken row (missing required base_price) must not nuke the rest.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[
              {"id":"00000000-0000-0000-0000-0000000000a1","name":"Broken","is_active":true},
              {"base_price":4200,"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000a2","org_id":"00000000-0000-0000-0000-0000000000ff",
               "is_active":true,"name":"Espresso","name_translations":{"en":"Espresso"},
               "description_translations":{},"addon_slots":[],"allowed_addon_ids":[],
               "optional_fields":[],"recipes":[],"sizes":[]}
            ]"#,
        );
        let items = menu_items(&store, "en").unwrap();
        assert_eq!(items.len(), 1);
        assert_eq!(items[0].name, "Espresso");
    }

    #[test]
    fn absent_catalog_is_empty_not_error() {
        let store = Store::open("").unwrap();
        assert!(menu_items(&store, "en").unwrap().is_empty());
        assert!(categories(&store, "en").unwrap().is_empty());
        assert!(addons(&store, "en").unwrap().is_empty());
        assert!(payment_methods(&store, "en").unwrap().is_empty());
        assert!(discounts(&store, "en").unwrap().is_empty());
    }

    #[test]
    fn addons_and_payment_methods_project() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_ADDONS,
            r#"[{"addon_type":"milk_type","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z","default_price":1500,"id":"00000000-0000-0000-0000-0000000000d1","is_active":true,"name":"Oat Milk","name_translations":{"ar":"حليب شوفان"},"org_id":"00000000-0000-0000-0000-0000000000ff","ingredients":[{"ingredient_name":"Oat milk","ingredient_unit":"ml","org_ingredient_id":"00000000-0000-0000-0000-0000000000aa","quantity_used":"200.000"}]}]"#,
        );
        let a = addons(&store, "ar").unwrap();
        assert_eq!(a[0].name, "حليب شوفان");
        assert_eq!(a[0].default_price_minor, 1500);
        assert_eq!(a[0].addon_type, "milk_type");
        // Embedded ingredients project despite the BigDecimal-string quantity.
        assert_eq!(a[0].ingredients.len(), 1);
        assert_eq!(a[0].ingredients[0].ingredient_name, "Oat milk");
        assert_eq!(a[0].ingredients[0].quantity, 200.0);
        assert_eq!(
            a[0].ingredients[0].org_ingredient_id.as_deref(),
            Some("00000000-0000-0000-0000-0000000000aa")
        );

        seed(
            &store,
            K_PAYMENT_METHODS,
            r##"[{"color":"#000","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z","icon":"cash","id":"00000000-0000-0000-0000-0000000000e1","is_active":true,"is_cash":true,"name":"Cash","org_id":"00000000-0000-0000-0000-0000000000ff","label_translations":null},
              {"color":"#111","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z","icon":"card","id":"00000000-0000-0000-0000-0000000000e2","is_active":false,"is_cash":false,"name":"Card","org_id":"00000000-0000-0000-0000-0000000000ff","label_translations":null}]"##,
        );
        let pm = payment_methods(&store, "en").unwrap();
        assert_eq!(pm.len(), 1); // inactive filtered
        assert_eq!(pm[0].name, "Cash");
        assert!(pm[0].is_cash);
    }

    // ── locale resolution (resolve via the public menu_items projection) ─────

    #[test]
    fn locale_resolution_falls_back_locale_then_lang_then_en_then_base() {
        // name_translations has only `en`; description has `ar` and `en`.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[{
              "base_price": 100,
              "created_at": "2026-06-19T10:00:00Z",
              "updated_at": "2026-06-19T10:00:00Z",
              "id": "00000000-0000-0000-0000-0000000000a1",
              "org_id": "00000000-0000-0000-0000-0000000000ff",
              "is_active": true,
              "name": "BaseName",
              "name_translations": {"en": "English"},
              "description": "BaseDesc",
              "description_translations": {"ar": "وصف", "en": "Desc"},
              "addon_slots": [], "allowed_addon_ids": [],
              "optional_fields": [], "recipes": [], "sizes": []
            }]"#,
        );
        // ar-EG: name has no ar/en-EG → falls through ar → en ("English").
        let ar = menu_items(&store, "ar-EG").unwrap();
        assert_eq!(ar[0].name, "English"); // locale & lang miss → en
        assert_eq!(ar[0].description.as_deref(), Some("وصف")); // ar hit
                                                               // Underscore-separated locale also splits to lang subtag.
        let ar_us = menu_items(&store, "ar_SA").unwrap();
        assert_eq!(ar_us[0].description.as_deref(), Some("وصف"));
    }

    #[test]
    fn locale_resolution_empty_translation_string_falls_through() {
        // An empty-string translation value must be skipped (treated as a miss),
        // falling to the next candidate, ultimately the base field.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[{
              "base_price": 100,
              "created_at": "2026-06-19T10:00:00Z",
              "updated_at": "2026-06-19T10:00:00Z",
              "id": "00000000-0000-0000-0000-0000000000a1",
              "org_id": "00000000-0000-0000-0000-0000000000ff",
              "is_active": true,
              "name": "Fallback",
              "name_translations": {"en": "", "ar": ""},
              "description_translations": {},
              "addon_slots": [], "allowed_addon_ids": [],
              "optional_fields": [], "recipes": [], "sizes": []
            }]"#,
        );
        let v = menu_items(&store, "ar").unwrap();
        assert_eq!(v[0].name, "Fallback"); // both empty → base
    }

    #[test]
    fn locale_resolution_exact_locale_wins_over_lang() {
        // A region-specific key ("pt-BR") must beat the bare language ("pt").
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[{
              "base_price": 100,
              "created_at": "2026-06-19T10:00:00Z",
              "updated_at": "2026-06-19T10:00:00Z",
              "id": "00000000-0000-0000-0000-0000000000a1",
              "org_id": "00000000-0000-0000-0000-0000000000ff",
              "is_active": true,
              "name": "Base",
              "name_translations": {"pt-BR": "Brasil", "pt": "Portugal", "en": "Eng"},
              "description_translations": {},
              "addon_slots": [], "allowed_addon_ids": [],
              "optional_fields": [], "recipes": [], "sizes": []
            }]"#,
        );
        assert_eq!(menu_items(&store, "pt-BR").unwrap()[0].name, "Brasil");
        // A different region of the same language falls to the bare lang key.
        assert_eq!(menu_items(&store, "pt-PT").unwrap()[0].name, "Portugal");
    }

    // ── soft-delete filtering ───────────────────────────────────────────────

    #[test]
    fn menu_items_drop_soft_deleted_rows() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[
              {"base_price":100,"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000a1","org_id":"00000000-0000-0000-0000-0000000000ff",
               "is_active":true,"name":"Gone","name_translations":{"en":"Gone"},
               "deleted_at":"2026-06-18T10:00:00Z",
               "description_translations":{},"addon_slots":[],"allowed_addon_ids":[],
               "optional_fields":[],"recipes":[],"sizes":[]},
              {"base_price":200,"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000a2","org_id":"00000000-0000-0000-0000-0000000000ff",
               "is_active":true,"name":"Live","name_translations":{"en":"Live"},
               "description_translations":{},"addon_slots":[],"allowed_addon_ids":[],
               "optional_fields":[],"recipes":[],"sizes":[]}
            ]"#,
        );
        let v = menu_items(&store, "en").unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].name, "Live");
    }

    #[test]
    fn menu_items_keep_inactive_rows_but_flag_them() {
        // is_active=false is NOT a soft-delete: the row stays (so the host can grey
        // it out); only deleted_at drops it.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_MENU_ITEMS,
            r#"[{
              "base_price":100,"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
              "id":"00000000-0000-0000-0000-0000000000a1","org_id":"00000000-0000-0000-0000-0000000000ff",
              "is_active":false,"name":"Hidden","name_translations":{"en":"Hidden"},
              "description_translations":{},"addon_slots":[],"allowed_addon_ids":[],
              "optional_fields":[],"recipes":[],"sizes":[]
            }]"#,
        );
        let v = menu_items(&store, "en").unwrap();
        assert_eq!(v.len(), 1);
        assert!(!v[0].is_active);
    }

    #[test]
    fn categories_drop_soft_deleted_and_resolve_locale() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_CATEGORIES,
            r#"[
              {"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000c1","org_id":"00000000-0000-0000-0000-0000000000ff",
               "is_active":true,"name":"Coffee","name_translations":{"ar":"قهوة"},
               "deleted_at":"2026-06-18T10:00:00Z","image_url":null},
              {"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000c2","org_id":"00000000-0000-0000-0000-0000000000ff",
               "is_active":true,"name":"Tea","name_translations":{"ar":"شاي"},
               "deleted_at":null,"image_url":"http://img/tea.png"}
            ]"#,
        );
        let v = categories(&store, "ar").unwrap();
        assert_eq!(v.len(), 1); // soft-deleted Coffee dropped
        assert_eq!(v[0].name, "شاي"); // ar resolved
        assert_eq!(v[0].image_url.as_deref(), Some("http://img/tea.png")); // flat()
                                                                           // Locale with no translation → base name.
        assert_eq!(categories(&store, "fr").unwrap()[0].name, "Tea");
    }

    #[test]
    fn categories_null_image_url_flattens_to_none() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_CATEGORIES,
            r#"[{"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000c2","org_id":"00000000-0000-0000-0000-0000000000ff",
               "is_active":true,"name":"Tea","name_translations":{},"deleted_at":null,"image_url":null}]"#,
        );
        let v = categories(&store, "en").unwrap();
        assert_eq!(v[0].image_url, None); // double-option null → None
    }

    #[test]
    fn categories_sort_by_display_order_then_name() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_CATEGORIES,
            r#"[
              {"id":"00000000-0000-0000-0000-0000000000c1","is_active":true,
               "name":"Zebra","name_translations":{},"display_order":2},
              {"id":"00000000-0000-0000-0000-0000000000c2","is_active":true,
               "name":"Bread","name_translations":{},"display_order":0},
              {"id":"00000000-0000-0000-0000-0000000000c3","is_active":true,
               "name":"Apple","name_translations":{},"display_order":0}
            ]"#,
        );
        let v = categories(&store, "en").unwrap();
        // display_order wins; a tie (both 0) breaks on name.
        assert_eq!(v.iter().map(|c| c.name.as_str()).collect::<Vec<_>>(), vec!["Apple", "Bread", "Zebra"]);
        assert_eq!(v[0].display_order, 0);
        assert_eq!(v[2].display_order, 2);
    }

    #[test]
    fn a_category_cached_before_display_order_existed_still_decodes() {
        // display_order is new; a row cached by an older build never wrote it.
        // It must default to 0 rather than blank the whole category list.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_CATEGORIES,
            r#"[{"id":"00000000-0000-0000-0000-0000000000c1","is_active":true,
               "name":"Legacy","name_translations":{}}]"#,
        );
        let v = categories(&store, "en").unwrap();
        assert_eq!(v.len(), 1);
        assert_eq!(v[0].display_order, 0);
    }

    // ── payment methods & discounts ─────────────────────────────────────────

    #[test]
    fn a_payment_method_cache_written_by_an_older_build_still_decodes() {
        // The exact regression `visible_in_integrations` caused: the backend adds
        // a field, the generator marks it required, and every device's existing
        // cache stops decoding. An empty catalog means checkout cannot take cash
        // and the offline Z-report counts none of it, so this must keep working
        // for BOTH a payload missing tomorrow's fields and one carrying fields
        // this build has never heard of.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_PAYMENT_METHODS,
            r##"[{"id":"00000000-0000-0000-0000-0000000000e1","name":"Cash","is_cash":true,
                  "is_active":true,"icon":"cash","color":"#000","label_translations":null},
                 {"id":"00000000-0000-0000-0000-0000000000e2","name":"Wallet","is_cash":false,
                  "is_active":true,"icon":"wallet","color":"#222","label_translations":null,
                  "some_future_flag":true,"another_one":{"nested":1}}]"##,
        );
        let pm = payment_methods(&store, "en").unwrap();
        assert_eq!(
            pm.len(),
            2,
            "neither an old nor a new payload may be dropped"
        );
        assert!(
            pm[0].is_cash,
            "the cash flag must survive — the drawer depends on it"
        );
        assert_eq!(pm[1].name, "Wallet");
    }

    #[test]
    fn a_cached_method_missing_is_active_is_treated_as_usable() {
        // Defaulting to false would hide every method from a pre-flag payload,
        // which is the same outage as failing to decode it.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_PAYMENT_METHODS,
            r##"[{"id":"00000000-0000-0000-0000-0000000000e1","name":"Cash","is_cash":true}]"##,
        );
        let pm = payment_methods(&store, "en").unwrap();
        assert_eq!(pm.len(), 1);
        assert_eq!(pm[0].name, "Cash");
    }

    #[test]
    fn payment_methods_resolve_label_translations_when_present() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_PAYMENT_METHODS,
            r##"[{"color":"#000","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "icon":"cash","id":"00000000-0000-0000-0000-0000000000e1","is_active":true,"is_cash":true,
               "name":"Cash","org_id":"00000000-0000-0000-0000-0000000000ff",
               "label_translations":{"ar":"نقدي"}}]"##,
        );
        let pm = payment_methods(&store, "ar").unwrap();
        assert_eq!(pm[0].name, "نقدي"); // translation resolves
        assert_eq!(pm[0].icon, "cash");
        assert_eq!(pm[0].color, "#000");
        // Unknown locale → base name.
        assert_eq!(payment_methods(&store, "fr").unwrap()[0].name, "Cash");
    }

    #[test]
    fn discounts_project_all_rows_with_type_and_value() {
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_DISCOUNTS,
            r#"[
              {"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000f1","org_id":"00000000-0000-0000-0000-0000000000ff",
               "dtype":"percentage","value":10,"value_rate":0.10,"is_active":true,"name":"Ten Off",
               "name_translations":{"ar":"خصم"}},
              {"created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "id":"00000000-0000-0000-0000-0000000000f2","org_id":"00000000-0000-0000-0000-0000000000ff",
               "dtype":"fixed","value":500,"is_active":false,"name":"Five EGP",
               "name_translations":{}}
            ]"#,
        );
        // Discounts are NOT filtered by is_active (host decides) — both surface.
        let d = discounts(&store, "ar").unwrap();
        assert_eq!(d.len(), 2);
        assert_eq!(d[0].name, "خصم");
        assert_eq!(d[0].dtype, "percentage");
        assert_eq!(d[0].value, 0.10);
        assert!(d[0].is_active);
        assert_eq!(d[1].dtype, "fixed");
        assert_eq!(d[1].value, 500.0);
        assert!(!d[1].is_active);
        assert_eq!(d[1].name, "Five EGP"); // no translation → base
    }

    // ── addons: lenient skip + ordering preserved ───────────────────────────

    #[test]
    fn addons_skip_malformed_rows_keep_good_ones() {
        // A bad addon row (missing required default_price) must not blank the list.
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_ADDONS,
            r#"[
              {"id":"00000000-0000-0000-0000-0000000000d0","name":"Broken","addon_type":"x"},
              {"addon_type":"milk_type","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "default_price":1500,"id":"00000000-0000-0000-0000-0000000000d1","is_active":true,
               "name":"Oat","name_translations":{},"org_id":"00000000-0000-0000-0000-0000000000ff",
               "ingredients":[]}
            ]"#,
        );
        let a = addons(&store, "en").unwrap();
        assert_eq!(a.len(), 1);
        assert_eq!(a[0].name, "Oat");
        assert!(a[0].ingredients.is_empty());
    }

    #[test]
    fn addon_ingredient_numeric_quantity_used_also_parses() {
        // value_to_f64 must accept a JSON NUMBER (not only a BigDecimal string).
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_ADDONS,
            r#"[{"addon_type":"extra","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "default_price":0,"id":"00000000-0000-0000-0000-0000000000d1","is_active":true,
               "name":"Shot","name_translations":{},"org_id":"00000000-0000-0000-0000-0000000000ff",
               "ingredients":[{"ingredient_name":"Espresso","ingredient_unit":"ml","quantity_used":30}]}]"#,
        );
        let a = addons(&store, "en").unwrap();
        assert_eq!(a[0].ingredients[0].quantity, 30.0);
    }

    #[test]
    fn addon_ingredient_bad_quantity_used_falls_back_to_zero() {
        // A non-numeric, non-parsable string → value_to_f64 yields 0.0 (no panic).
        let store = Store::open("").unwrap();
        seed(
            &store,
            K_ADDONS,
            r#"[{"addon_type":"extra","created_at":"2026-06-19T10:00:00Z","updated_at":"2026-06-19T10:00:00Z",
               "default_price":0,"id":"00000000-0000-0000-0000-0000000000d1","is_active":true,
               "name":"Shot","name_translations":{},"org_id":"00000000-0000-0000-0000-0000000000ff",
               "ingredients":[{"ingredient_name":"Espresso","ingredient_unit":"ml","quantity_used":"oops"}]}]"#,
        );
        let a = addons(&store, "en").unwrap();
        assert_eq!(a[0].ingredients[0].quantity, 0.0);
    }

    // ── the feed keeps the unified groups current (T1 sheet-cache regression) ──

    #[test]
    fn the_feed_rows_keep_the_unified_groups_current() {
        let fetched = r#"{"catalog_revision":7,"changed":true,"items":[
            {"id":"latte","modifier_groups":[{"group_id":"g","options":[{"id":"o","name":"Oat","price":100,
              "recipe":[{"ingredient_id":"i","quantity":"1","unit":"ml"}]}]}]},
            {"id":"cake","modifier_groups":[]}]}"#;
        // The same groups, the recipes stripped as the feed ships them: nothing to write.
        let same = serde_json::json!([{"id":"latte","seq":3,"modifier_groups":[
            {"group_id":"g","options":[{"id":"o","name":"Oat","price":100}]}]}]);
        assert!(unified_with_feed_groups(Some(fetched), same.as_array().unwrap()).is_none());

        // A required group on the cake, and an item the fetch never had.
        let rows = serde_json::json!([
            {"id":"cake","seq":4,"modifier_groups":[{"group_id":"k","is_required":true,"min":1,
              "options":[{"id":"x","name":"Knife"}]}]},
            {"id":"tea","seq":5,"modifier_groups":[]}]);
        let raw = unified_with_feed_groups(Some(fetched), rows.as_array().unwrap()).unwrap();
        let doc: UnifiedDoc = serde_json::from_str(&raw).unwrap();
        assert_eq!(doc.catalog_revision, 7, "the fetch's revision is kept");
        assert!(doc.groups_for("cake").unwrap()[0].is_required);
        assert_eq!(
            doc.groups_for("latte").unwrap()[0].options[0].name,
            "Oat",
            "an item the feed did not carry keeps what the fetch said"
        );
        assert!(doc.items.iter().any(|i| i.id == "tea"));
        assert!(
            !raw.contains("\"seq\""),
            "the feed's cursor is not the catalogue's"
        );

        // No mirror yet: built from the feed, at a revision no server has.
        let raw = unified_with_feed_groups(None, rows.as_array().unwrap()).unwrap();
        let doc: UnifiedDoc = serde_json::from_str(&raw).unwrap();
        assert_eq!(doc.catalog_revision, FEED_ONLY_REVISION);
        assert!(doc.groups_for("cake").is_some());
        assert!(
            unified_with_feed_groups(None, &[]).is_none(),
            "nothing to build from"
        );
    }

    // ── lenient parse: completely malformed kv JSON IS an error ──────────────

    #[test]
    fn menu_items_non_array_json_is_error() {
        // parse_kv_lenient parses the outer Vec<Value> eagerly; a non-array top
        // level is a hard error (distinct from per-row tolerance).
        let store = Store::open("").unwrap();
        seed(&store, K_MENU_ITEMS, r#"{"not":"an array"}"#);
        assert!(menu_items(&store, "en").is_err());
    }
}
