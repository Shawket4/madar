//! Catalog / menu reads — FRB delegation over madar-core's local catalog
//! mirror (menu items, categories, addons, bundles, payment methods,
//! discounts) plus category styling and the org logo. Binding code only:
//! every method is a one-line delegation through `self.inner`.

use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::catstyle::CatStyleView;
pub use madar_core::menu::{
    AddonIngredientView, AddonItemView, AddonSlotView, BundleComponentView, BundleView,
    CategoryView, DiscountView, ItemSizeView, MenuItemView, OptionalFieldView, PaymentMethodView,
    RecipeLineView,
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

#[frb(mirror(BundleView))]
pub struct _BundleView {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub price_minor: i64,
    pub image_url: Option<String>,
    /// `status == active`. The date/time availability window (below) is gated in
    /// the branch timezone by the cart/order context, not in this static read.
    pub is_available: bool,
    pub available_from_date: Option<String>,
    pub available_until_date: Option<String>,
    pub available_from_time: Option<String>,
    pub available_until_time: Option<String>,
    /// The bundle's component items (which menu item + how many). The detail
    /// sheet configures each one through the normal item-customization flow.
    pub components: Vec<BundleComponentView>,
}

/// One item that makes up a bundle (hydrated from the bundle list). The
/// component's base price is never charged separately — the bundle price covers
/// it; only its addon/optional up-charges add money.
#[frb(mirror(BundleComponentView))]
pub struct _BundleComponentView {
    pub item_id: String,
    pub item_name: String,
    pub quantity: i64,
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
    /// Percent points for `percentage`, minor-units for `fixed`.
    pub value: i64,
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

    /// Bundles orderable right now — status active and within their date/time
    /// window at `now` (branch-local). The host passes its local time so the
    /// window is evaluated in the till's timezone (Flutter parity).
    pub fn available_bundles(&self, now_rfc3339: String) -> Result<Vec<BundleView>, MadarError> {
        self.inner
            .available_bundles(now_rfc3339)
            .map_err(MadarError::from)
    }

    pub fn list_payment_methods(&self) -> Result<Vec<PaymentMethodView>, MadarError> {
        self.inner.list_payment_methods().map_err(MadarError::from)
    }

    pub fn list_discounts(&self) -> Result<Vec<DiscountView>, MadarError> {
        self.inner.list_discounts().map_err(MadarError::from)
    }

    /// Pull the branch-effective catalog (items + categories + addons + bundles +
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
}
