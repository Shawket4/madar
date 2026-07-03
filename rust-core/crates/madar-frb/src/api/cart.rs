//! Cart domain: lines, configured/bundle adds, addon lookup, recipe preview,
//! drafts (held orders), discounts, and totals. Binding code only — every
//! method is a one-line delegation through `MadarBridge.inner`.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::cart::{
    AddonSelection, BundleComponentSelection, CartAddonView, CartBundleComponentView, CartLineView,
    CartOptionalView, CartTotals, DraftView, GroupViolationView, ItemAddonView, ModifierGroupKind,
    ModifierGroupView, ModifierOptionView,
};
pub use madar_core::recipe::ComputedRecipeLineView;

/// A host-supplied addon choice (id + how many). The CORE resolves its price.
#[frb(mirror(AddonSelection))]
pub struct _AddonSelection {
    pub addon_item_id: String,
    pub qty: i64,
}

/// An addon offered for an item, with its CHARGED price already resolved (swap
/// delta / full) — so the customization sheet just displays it, no pricing rules
/// in the UI. Grouped by `addon_type` by the host (per slot / global card).
#[frb(mirror(ItemAddonView))]
pub struct _ItemAddonView {
    pub addon_item_id: String,
    pub name: String,
    pub addon_type: String,
    pub charged_price_minor: i64,
}

/// How a modifier group's selections are submitted at add-to-cart time.
#[frb(mirror(ModifierGroupKind))]
pub enum _ModifierGroupKind {
    /// Options are addon items — submit as `AddonSelection { addon_item_id: option.id }`.
    Addon,
    /// Options are the item's priced optionals — submit their ids in `optional_field_ids`.
    Optional,
}

/// One option inside a modifier group, with its CHARGED price already resolved.
#[frb(mirror(ModifierOptionView))]
pub struct _ModifierOptionView {
    pub id: String,
    pub name: String,
    pub charged_price_minor: i64,
}

/// A modifier group offered on an item (unified-model projection): slot groups
/// keep min/max/required; unslotted types get defaults; optionals are one
/// `Optional`-kind group.
#[frb(mirror(ModifierGroupView))]
pub struct _ModifierGroupView {
    pub group_id: String,
    pub name: String,
    pub kind: ModifierGroupKind,
    pub addon_type: Option<String>,
    pub is_required: bool,
    pub min_selections: i32,
    pub max_selections: Option<i32>,
    pub options: Vec<ModifierOptionView>,
}

/// A group whose constraints the current selection breaks (too few / too many).
#[frb(mirror(GroupViolationView))]
pub struct _GroupViolationView {
    pub group_id: String,
    pub group_name: String,
    pub min_required: i32,
    pub max_allowed: Option<i32>,
    pub selected: i64,
}

#[frb(mirror(CartAddonView))]
pub struct _CartAddonView {
    pub addon_item_id: String,
    pub name: String,
    pub qty: i64,
    pub price_modifier_minor: i64,
}

#[frb(mirror(CartOptionalView))]
pub struct _CartOptionalView {
    pub optional_field_id: String,
    pub name: String,
    pub price_minor: i64,
}

/// A configured component of a bundle cart line, for the bundle row breakdown.
#[frb(mirror(CartBundleComponentView))]
pub struct _CartBundleComponentView {
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
#[frb(mirror(CartLineView))]
pub struct _CartLineView {
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
}

/// The priced cart summary the host shows in the cart panel + action-bar badge.
#[frb(mirror(CartTotals))]
pub struct _CartTotals {
    /// Sum of quantities — the badge count on the cart button.
    pub item_count: i64,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub total_minor: i64,
}

/// A host-supplied configured component of a bundle (which item, its size, and
/// the chosen addons/optionals). The CORE resolves the charged extra prices.
#[frb(mirror(BundleComponentSelection))]
pub struct _BundleComponentSelection {
    pub item_id: String,
    pub size_label: Option<String>,
    pub qty: i64,
    pub addons: Vec<AddonSelection>,
    pub optional_field_ids: Vec<String>,
}

/// A parked cart, summarized for the drafts list.
#[frb(mirror(DraftView))]
pub struct _DraftView {
    pub id: String,
    pub name: String,
    pub item_count: i64,
    pub total_minor: i64,
    pub created_at: String,
}

/// One effective ingredient line, tagged by origin so the sheet can chip it.
#[frb(mirror(ComputedRecipeLineView))]
pub struct _ComputedRecipeLineView {
    pub ingredient_name: String,
    pub unit: String,
    pub quantity: f64,
    /// Display tag: `"base"`, `"addon"`, the swap addon's name, or the optional
    /// field's name — the sheet renders this (uppercased) as a chip.
    pub source_label: String,
    /// True for base drink-recipe lines (the sheet tones these as the accent).
    pub is_base: bool,
}

impl MadarBridge {
    // ── cart (client-only order state, offline-safe, kv-persisted) ────────

    /// The current cart lines (empty when none).
    pub fn cart_lines(&self) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.cart_lines().map_err(MadarError::from)
    }

    /// Add one unit of a menu item (merges into the matching line). The host
    /// passes the resolved display name + unit price so the cart is self-contained.
    pub fn cart_add(
        &self,
        item_id: String,
        name: String,
        unit_price_minor: i64,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add(item_id, name, unit_price_minor)
            .map_err(MadarError::from)
    }

    /// Add a CONFIGURED line (size + addons + optionals + notes). The core
    /// resolves the charged prices from the cached catalog and merges identical
    /// configs — the addon prices are resolved here, not trusted from the host.
    pub fn cart_add_configured(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add_configured(item_id, size_label, addons, optional_field_ids, qty, notes)
            .map_err(MadarError::from)
    }

    /// Add a configured BUNDLE line: the fixed bundle price + each component's
    /// chosen item/size/addons/optionals, up-charges resolved from the catalog.
    pub fn cart_add_bundle(
        &self,
        bundle_id: String,
        components: Vec<BundleComponentSelection>,
        qty: i64,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add_bundle(bundle_id, components, qty)
            .map_err(MadarError::from)
    }

    /// Active addons offered for an item, with their CHARGED price resolved (swap
    /// delta / full) — the customization sheet groups these by `addon_type`.
    pub fn list_item_addons(&self, item_id: String) -> Result<Vec<ItemAddonView>, MadarError> {
        self.inner
            .list_item_addons(item_id)
            .map_err(MadarError::from)
    }

    /// The item's MODIFIER GROUPS (unified-model projection of `list_item_addons`
    /// + priced optionals) — display-ready, constraints included, prices resolved
    /// by the same swap rules as the flat sheet. Works offline.
    pub fn list_item_modifier_groups(
        &self,
        item_id: String,
    ) -> Result<Vec<ModifierGroupView>, MadarError> {
        self.inner
            .list_item_modifier_groups(item_id)
            .map_err(MadarError::from)
    }

    /// Check a selection against the item's group constraints (min/max/required).
    /// Empty result = valid; each entry is one violated group for inline display.
    /// Call before `cart_add_configured`.
    pub fn validate_item_selections(
        &self,
        item_id: String,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
    ) -> Result<Vec<GroupViolationView>, MadarError> {
        self.inner
            .validate_item_selections(item_id, addons, optional_field_ids)
            .map_err(MadarError::from)
    }

    /// Live recipe preview for the current selection (size + addons + optionals).
    /// Pure projection over the mirrored catalog, so the customization sheet can
    /// recompute on every toggle, online or offline.
    pub fn compute_recipe(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
    ) -> Result<Vec<ComputedRecipeLineView>, MadarError> {
        self.inner
            .compute_recipe(item_id, size_label, addons, optional_field_ids)
            .map_err(MadarError::from)
    }

    /// Set a line's absolute quantity (by its key); `qty <= 0` removes the line.
    pub fn cart_set_qty(&self, item_id: String, qty: i64) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_set_qty(item_id, qty)
            .map_err(MadarError::from)
    }

    /// Remove a line entirely (stashed for undo — see `cart_restore_removed`).
    pub fn cart_remove(&self, item_id: String) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.cart_remove(item_id).map_err(MadarError::from)
    }

    /// Undo the last `cart_remove` — re-inserts the swiped-away line. No-op if
    /// nothing was removed (or it was already restored / the cart was cleared).
    pub fn cart_restore_removed(&self) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.cart_restore_removed().map_err(MadarError::from)
    }

    /// Empty the cart.
    pub fn cart_clear(&self) -> Result<(), MadarError> {
        self.inner.cart_clear().map_err(MadarError::from)
    }

    /// Park the current cart as a named draft (held order) and empty the cart.
    pub fn hold_cart(&self, name: String) -> Result<(), MadarError> {
        self.inner.hold_cart(name).map_err(MadarError::from)
    }

    /// The parked drafts (held orders), newest first.
    pub fn list_drafts(&self) -> Result<Vec<DraftView>, MadarError> {
        self.inner.list_drafts().map_err(MadarError::from)
    }

    /// Restore a draft into the cart (replaces current lines) and drop it.
    pub fn restore_draft(&self, id: String) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.restore_draft(id).map_err(MadarError::from)
    }

    /// Discard a parked draft.
    pub fn discard_draft(&self, id: String) -> Result<(), MadarError> {
        self.inner.discard_draft(id).map_err(MadarError::from)
    }

    /// Apply a discount (by id) to the cart — reflected in `cart_totals`.
    pub fn cart_set_discount(&self, discount_id: String) -> Result<(), MadarError> {
        self.inner
            .cart_set_discount(discount_id)
            .map_err(MadarError::from)
    }

    /// Remove the cart discount.
    pub fn cart_clear_discount(&self) -> Result<(), MadarError> {
        self.inner.cart_clear_discount().map_err(MadarError::from)
    }

    /// The selected discount id (for the tender UI), or `None`.
    pub fn cart_discount_id(&self) -> Result<Option<String>, MadarError> {
        self.inner.cart_discount_id().map_err(MadarError::from)
    }

    /// Priced cart summary at the session's org tax rate (0 when signed out),
    /// computed through the pricing engine.
    pub fn cart_totals(&self) -> Result<CartTotals, MadarError> {
        self.inner.cart_totals().map_err(MadarError::from)
    }
}
