//! Catalog / menu reads — FRB delegation over madar-core's local catalog
//! mirror (menu items, categories, addons, payment methods, discounts) plus category styling and the org logo. Binding code only:
//! every method is a one-line delegation through `self.inner`.

use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::catstyle::CatStyleView;
pub use madar_core::combos::{
    ComboChoiceDetail, ComboDetail, ComboDraft, ComboPickInput, ComboPickNeed, ComboQuoteView,
    ComboSizeOption, ComboSlotDetail, MealOffer,
};
pub use madar_core::last_config::LastItemConfig;
pub use madar_core::menu::{
    AddonIngredientView, AddonItemView, AddonSlotView, CategoryView, DiscountView, ItemSizeView,
    MenuItemView, OptionalFieldView, PaymentMethodView, RecipeLineView, RecipeStepView,
};

/// A resolved category style: an icon key + four hex colours (`#RRGGBB`).
#[frb(mirror(CatStyleView))]
pub struct _CatStyleView {
    /// Icon family key — the host maps it to a platform glyph. One of:
    /// coffee, mocha, bakery, lunch, icecream, drink, tea, water, ice, matcha, cafe.
    pub icon: String,
    pub bg_top: String,
    pub bg_bottom: String,
    pub icon_color: String,
    pub accent: String,
}

#[frb(mirror(MenuItemView))]
pub struct _MenuItemView {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub category_id: Option<String>,
    pub base_price_minor: i64,
    pub image_url: Option<String>,
    /// On-disk path of the CACHED image (core-downloaded during catalog
    /// refresh) — render this, fully offline. `None` until it lands.
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
    /// `"item"` or `"combo"`: a combo opens the combo sheet and wears a
    /// "Combo" badge.
    pub kind: String,
}

/// One pick of a combo: the slot, the item, its size and its add-ons.
#[frb(mirror(ComboPickInput))]
pub struct _ComboPickInput {
    pub slot_id: String,
    pub item_id: String,
    /// `None` = the size the combo includes.
    pub size_label: Option<String>,
    /// Units per combo (usually 1).
    pub qty: i64,
    pub addons: Vec<crate::api::cart::AddonSelection>,
    pub optional_field_ids: Vec<String>,
    pub notes: Option<String>,
}

/// The combo sheet, priced.
#[frb(mirror(ComboDetail))]
pub struct _ComboDetail {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub local_image_path: Option<String>,
    /// P: the combo's price before any surcharge or add-on.
    pub price_minor: i64,
    /// One item per slot, nothing to choose.
    pub is_fixed: bool,
    pub available_now: bool,
    /// Why not, in the teller's language.
    pub why_unavailable: Option<String>,
    pub slots: Vec<ComboSlotDetail>,
}

#[frb(mirror(ComboSlotDetail))]
pub struct _ComboSlotDetail {
    pub id: String,
    pub name: String,
    pub min: i64,
    pub max: i64,
    /// "Choose 1 item", "Optional · Choose up to 2 items", … (localized).
    pub rule_label: String,
    pub default_item_id: Option<String>,
    pub default_size_label: Option<String>,
    pub choices: Vec<ComboChoiceDetail>,
}

#[frb(mirror(ComboChoiceDetail))]
pub struct _ComboChoiceDetail {
    pub item_id: String,
    pub name: String,
    pub local_image_path: Option<String>,
    /// The item's normal price at the size the combo includes.
    pub base_price_minor: i64,
    pub included_size_label: Option<String>,
    /// What choosing this item adds (0 = included).
    pub surcharge_minor: i64,
    pub sizes: Vec<ComboSizeOption>,
    pub is_default: bool,
    /// The item has add-ons or options: offer "Customise".
    pub customisable: bool,
    /// A required choice with no default (a sandwich's bread): picking the
    /// item opens "Customise" at once; the combo waits for the choice.
    pub must_customise: bool,
}

#[frb(mirror(ComboSizeOption))]
pub struct _ComboSizeOption {
    pub label: String,
    pub price_minor: i64,
    /// What this size adds inside the combo (0 = included).
    pub extra_minor: i64,
    pub is_included: bool,
}

/// The combo sheet's live figures.
#[frb(mirror(ComboQuoteView))]
pub struct _ComboQuoteView {
    pub price_minor: i64,
    pub unit_total_minor: i64,
    pub line_total_minor: i64,
    pub surcharge_minor: i64,
    pub extras_minor: i64,
    pub list_minor: i64,
    pub saving_minor: i64,
    /// Every slot is satisfied: the combo can be added.
    pub complete: bool,
    /// The coded refusal (`COMBO_SLOT_TOO_FEW`, …) when not complete.
    pub refusal: Option<String>,
    /// The same, in the teller's language.
    pub refusal_text: Option<String>,
    /// Each pick still wanting a required choice (its slot shows why).
    pub pick_needs: Vec<ComboPickNeed>,
}

/// A combo pick still wanting a required choice with no default.
#[frb(mirror(ComboPickNeed))]
pub struct _ComboPickNeed {
    pub slot_id: String,
    pub item_id: String,
    /// The choice's name ("Bread"), in the teller's language.
    pub group_name: String,
    /// What the slot shows: "Choose Bread".
    pub text: String,
}

/// A combo to edit on the sheet (a cart line, or "make it a meal").
#[frb(mirror(ComboDraft))]
pub struct _ComboDraft {
    pub combo_id: String,
    /// The cart line saving replaces (`cart_replace_combo`); `None` = add.
    pub line_key: Option<String>,
    pub qty: i64,
    pub notes: Option<String>,
    pub picks: Vec<ComboPickInput>,
}

/// "Make it a meal +X" on an item.
#[frb(mirror(MealOffer))]
pub struct _MealOffer {
    pub combo_id: String,
    pub slot_id: String,
    pub name: String,
    pub delta_minor: i64,
    /// What the meal saves against the picks bought separately (≤ 0 = none).
    pub saving_minor: i64,
    /// "with Side + Drink", in the teller's language ("" = nothing to name).
    pub slot_hint: String,
}

/// The item sheet's "Last: …" chip: the item as this device last sold it.
#[frb(mirror(LastItemConfig))]
pub struct _LastItemConfig {
    pub size_label: Option<String>,
    pub addons: Vec<crate::api::cart::AddonSelection>,
    pub optional_field_ids: Vec<String>,
    /// In the cart line's words: "Large · Oat milk".
    pub words: String,
    /// The chip: "Last: Large · Oat milk".
    pub text: String,
}

/// One preparation step: localized, and pointing at the animation's CACHED
/// file so the sheet plays it with no network.
#[frb(mirror(RecipeStepView))]
pub struct _RecipeStepView {
    pub name: String,
    pub note: Option<String>,
    /// On-disk path of the cached animation — `None` for a written step, and
    /// until the animation has been downloaded by a sync.
    pub local_animation_path: Option<String>,
    pub animation_url: Option<String>,
}

#[frb(mirror(ItemSizeView))]
pub struct _ItemSizeView {
    pub id: String,
    pub label: String,
    /// Absolute price for this size (NOT a delta) — R9.
    pub price_minor: i64,
    pub is_active: bool,
}

#[frb(mirror(AddonSlotView))]
pub struct _AddonSlotView {
    pub id: String,
    pub label: Option<String>,
    pub addon_type: String,
    pub is_required: bool,
    pub min_selections: i32,
    /// `None` ⇒ multi-select with no cap (R9).
    pub max_selections: Option<i32>,
}

#[frb(mirror(OptionalFieldView))]
pub struct _OptionalFieldView {
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

#[frb(mirror(RecipeLineView))]
pub struct _RecipeLineView {
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
#[frb(mirror(AddonIngredientView))]
pub struct _AddonIngredientView {
    pub ingredient_name: String,
    pub unit: String,
    pub quantity: f64,
    pub org_ingredient_id: Option<String>,
}

#[frb(mirror(CategoryView))]
pub struct _CategoryView {
    pub id: String,
    pub name: String,
    pub image_url: Option<String>,
    pub is_active: bool,
    pub display_order: i32,
}

#[frb(mirror(AddonItemView))]
pub struct _AddonItemView {
    pub id: String,
    pub name: String,
    pub addon_type: String,
    pub default_price_minor: i64,
    pub is_active: bool,
    /// Embedded ingredient rows (recipe preview input). Empty when the addon has
    /// no stock impact (e.g. a flavour shot) or the wire omitted them.
    pub ingredients: Vec<AddonIngredientView>,
}

#[frb(mirror(PaymentMethodView))]
pub struct _PaymentMethodView {
    pub id: String,
    pub name: String,
    pub is_cash: bool,
    pub icon: String,
    pub color: String,
}

#[frb(mirror(DiscountView))]
pub struct _DiscountView {
    pub id: String,
    pub name: String,
    /// Open string: `percentage` | `fixed` | … — host interprets `value`.
    pub dtype: String,
    /// A FRACTION for `percentage` (0.14 = 14%), minor-units for `fixed`.
    pub value: f64,
    pub is_active: bool,
}

impl MadarBridge {
    // ── catalog reads (serve the local mirror, always succeed offline) ─────

    /// Themed style (icon key + gradient palette) for a category/item name —
    /// the host maps `icon` to a glyph and paints the gradient. Pure; mirrors
    /// Flutter's `CatStyle.of`. `dark` picks the dark-mode palette.
    #[frb(sync)]
    pub fn category_style(&self, name: String, dark: bool) -> CatStyleView {
        self.inner.category_style(name, dark)
    }

    pub fn list_menu_items(&self) -> Result<Vec<MenuItemView>, MadarError> {
        self.inner.list_menu_items().map_err(MadarError::from)
    }

    pub fn list_categories(&self) -> Result<Vec<CategoryView>, MadarError> {
        self.inner.list_categories().map_err(MadarError::from)
    }

    pub fn list_addon_catalog(&self) -> Result<Vec<AddonItemView>, MadarError> {
        self.inner.list_addon_catalog().map_err(MadarError::from)
    }

    pub fn list_payment_methods(&self) -> Result<Vec<PaymentMethodView>, MadarError> {
        self.inner.list_payment_methods().map_err(MadarError::from)
    }

    pub fn list_discounts(&self) -> Result<Vec<DiscountView>, MadarError> {
        self.inner.list_discounts().map_err(MadarError::from)
    }

    // ── combos (COMBOS_CONTRACT §6) ──────────────────────────────────────

    /// The combo sheet for a `kind == "combo"` item: slots, priced choices,
    /// sizes with what they add, and whether it is on sale now. Offline.
    #[frb(sync)]
    pub fn combo_detail(&self, item_id: String) -> Option<ComboDetail> {
        self.inner.combo_detail(item_id)
    }

    /// The picks a fresh combo opens with (every slot's default).
    #[frb(sync)]
    pub fn combo_new_draft(&self, item_id: String) -> Option<ComboDraft> {
        self.inner.combo_new_draft(item_id)
    }

    /// "Make it a meal +X" for an item, when it has a meal on sale now.
    #[frb(sync)]
    pub fn meal_offer(&self, item_id: String) -> Option<MealOffer> {
        self.inner.meal_offer(item_id)
    }

    /// The item sheet's meal banner for the item as configured there: "+X ·
    /// save Y" and the slots it brings.
    #[frb(sync)]
    pub fn meal_offer_for(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<crate::api::cart::AddonSelection>,
        optional_field_ids: Vec<String>,
    ) -> Option<MealOffer> {
        self.inner
            .meal_offer_for(item_id, size_label, addons, optional_field_ids)
    }

    /// The item as this device last sold it (local rows only), for the item
    /// sheet's "Last: …" chip; `None` when it never sold it here.
    #[frb(sync)]
    pub fn last_item_config(&self, item_id: String) -> Option<LastItemConfig> {
        self.inner.last_item_config(item_id)
    }

    /// Pull the branch-effective catalog (items + categories + addons +
    /// payment methods + discounts) and mirror the canonical JSON into the local
    /// store. Online-only; the offline reads (`list_*`) then serve this mirror.
    /// Atomic-ish: every stream is fetched before any is written, so a mid-pull
    /// failure leaves the previous mirror intact.
    pub async fn refresh_catalog(&self) -> Result<(), MadarError> {
        self.inner.refresh_catalog().await.map_err(MadarError::from)
    }

    /// The org's logo URL for the current branch, from the durable kv mirror
    /// (`cache_numbering_context`/`refresh_catalog` persist it from `get_branch`).
    /// `None` until the first online branch fetch. The host reads this as the
    /// source of truth for the receipt logo, so it survives restarts + offline and
    /// refreshes on a manual data sync.
    pub fn org_logo_url(&self) -> Option<String> {
        self.inner.org_logo_url()
    }

    /// Local file path of the core-cached org logo — `None` until the first
    /// successful catalog image sync. Render the receipt-preview logo from
    /// this (fully offline).
    #[frb(sync)]
    pub fn org_logo_local_path(&self) -> Option<String> {
        self.inner.org_logo_local_path()
    }
}
