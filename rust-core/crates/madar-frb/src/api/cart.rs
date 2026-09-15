//! Cart domain: lines, configured/bundle adds, addon lookup, recipe preview,
//! drafts (held orders), discounts, and totals. Binding code only — every
//! method is a one-line delegation through `MadarBridge.inner`.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::cart::{
    AddonSelection, BundleComponentSelection, CartAddonView, CartBundleComponentView, CartLineView,
    CartOptionalView, CartTotals, CartMeta, DraftSwitchView, DraftView, GroupViolationView, HeldParkInput,
    ItemAddonView, LinePreviewView, ModifierGroupKind, ModifierGroupView, ModifierOptionView,
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
    /// A KITCHEN-ONLY note for this line — never on the checkout payload,
    /// never on the customer receipt. Cleared once this line's chit prints.
    pub kitchen_note: Option<String>,
}

/// The priced cart summary the host shows in the cart panel + action-bar badge.
#[frb(mirror(CartTotals))]
pub struct _CartTotals {
    /// Sum of quantities — the badge count on the cart button.
    pub item_count: i64,
    pub subtotal_minor: i64,
    pub discount_minor: i64,
    pub tax_minor: i64,
    pub service_charge_minor: i64,
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

/// A parked cart, summarized for the drafts list. Now server-backed: shared
/// across the branch's tills, optionally owning a floor table.
/// What a configured line would cost — the item sheet's figures.
#[frb(mirror(LinePreviewView))]
pub struct _LinePreviewView {
    pub unit_total_minor: i64,
    pub extras_minor: i64,
    pub line_total_minor: i64,
}

/// The identity a cart is parked under.
#[frb(mirror(HeldParkInput))]
pub struct _HeldParkInput {
    pub name: String,
    pub draft_id: Option<String>,
    pub started_at: Option<String>,
}

/// What `switch_to_draft` left in hand.
#[frb(mirror(CartMeta))]
pub struct _CartMeta {
    pub name: String,
    pub draft_id: Option<String>,
    pub booking_id: Option<String>,
    pub table_label: Option<String>,
    pub guest_name: Option<String>,
    pub started_at: Option<String>,
    pub covers: Option<i32>,
}

#[frb(mirror(DraftSwitchView))]
pub struct _DraftSwitchView {
    pub lines: Vec<CartLineView>,
    pub table_id: Option<String>,
    pub table_label: Option<String>,
    pub name: String,
    pub created_at: String,
    pub table_taken: bool,
}

#[frb(mirror(DraftView))]
pub struct _DraftView {
    pub id: String,
    pub name: String,
    pub item_count: i64,
    pub total_minor: i64,
    pub created_at: String,
    /// The floor table this held order owns, if any.
    pub table_id: Option<String>,
    pub table_label: Option<String>,
    /// True when ANOTHER till is editing this order right now — the chip
    /// renders locked and cannot be restored.
    pub locked_by_other: bool,
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
    pub fn cart_lines(&self, table_id: Option<String>) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.cart_lines(table_id).map_err(MadarError::from)
    }

    /// Add one unit of a menu item (merges into the matching line). The host
    /// passes the resolved display name + unit price so the cart is self-contained.
    pub fn cart_add(
        &self,
        table_id: Option<String>,
        item_id: String,
        name: String,
        unit_price_minor: i64,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add(table_id, item_id, name, unit_price_minor)
            .map_err(MadarError::from)
    }

    /// Add a CONFIGURED line (size + addons + optionals + notes). The core
    /// resolves the charged prices from the cached catalog and merges identical
    /// configs — the addon prices are resolved here, not trusted from the host.
    pub fn cart_add_configured(
        &self,
        table_id: Option<String>,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add_configured(table_id, item_id, size_label, addons, optional_field_ids, qty, notes)
            .map_err(MadarError::from)
    }

    /// EDIT a configured line: resolve, then swap it in for `line_key` in one
    /// write. A failure leaves the original line in the cart.
    #[allow(clippy::too_many_arguments)]
    pub fn cart_replace_configured(
        &self,
        table_id: Option<String>,
        line_key: String,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_replace_configured(
                table_id,
                line_key,
                item_id,
                size_label,
                addons,
                optional_field_ids,
                qty,
                notes,
            )
            .map_err(MadarError::from)
    }

    /// What a configured line would cost (unit, extras, whole line) — priced
    /// by the resolver the add uses. Adds nothing.
    pub fn preview_configured_line(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
    ) -> Result<LinePreviewView, MadarError> {
        self.inner
            .preview_configured_line(item_id, size_label, addons, optional_field_ids, qty)
            .map_err(MadarError::from)
    }

    /// The bill's subtotal so far plus this round's.
    pub fn cart_bill_so_far_minor(&self, table_id: Option<String>, ticket_subtotal_minor: i64) -> Result<i64, MadarError> {
        self.inner
            .cart_bill_so_far_minor(table_id, ticket_subtotal_minor)
            .map_err(MadarError::from)
    }

    /// Add a configured BUNDLE line: the fixed bundle price + each component's
    /// chosen item/size/addons/optionals, up-charges resolved from the catalog.
    pub fn cart_add_bundle(
        &self,
        table_id: Option<String>,
        bundle_id: String,
        components: Vec<BundleComponentSelection>,
        qty: i64,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add_bundle(table_id, bundle_id, components, qty)
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
    pub fn cart_set_qty(&self, table_id: Option<String>, item_id: String, qty: i64) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_set_qty(table_id, item_id, qty)
            .map_err(MadarError::from)
    }

    /// Remove a line entirely (stashed for undo — see `cart_restore_removed`).
    pub fn cart_remove(&self, table_id: Option<String>, item_id: String) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.cart_remove(table_id, item_id).map_err(MadarError::from)
    }

    /// Undo the last `cart_remove` — re-inserts the swiped-away line. No-op if
    /// nothing was removed (or it was already restored / the cart was cleared).
    pub fn cart_restore_removed(&self, table_id: Option<String>) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.cart_restore_removed(table_id).map_err(MadarError::from)
    }

    /// Empty the ACTIVE context's cart (other tables / takeaway untouched).
    pub fn cart_clear(&self, table_id: Option<String>) -> Result<(), MadarError> {
        self.inner.cart_clear(table_id).map_err(MadarError::from)
    }

    /// One context's cart meta (`None` = takeaway): name, parked-order id,
    /// booking, table label, guest, covers, started_at. Persisted in the core.
    pub fn cart_meta(&self, table_id: Option<String>) -> Result<CartMeta, MadarError> {
        self.inner.cart_meta(table_id).map_err(MadarError::from)
    }

    /// Replace one context's cart meta (reset when that cart is spent).
    pub fn cart_set_meta(&self, table_id: Option<String>, meta: CartMeta) -> Result<(), MadarError> {
        self.inner.cart_set_meta(table_id, meta).map_err(MadarError::from)
    }

    /// Table ids whose cart currently holds unsent lines.
    pub fn cart_table_contexts(&self) -> Result<Vec<String>, MadarError> {
        self.inner.cart_table_contexts().map_err(MadarError::from)
    }

    /// Empty EVERY context's cart and meta (sign-out / shift close).
    pub fn cart_clear_all(&self) -> Result<(), MadarError> {
        self.inner.cart_clear_all().map_err(MadarError::from)
    }

    /// Park `table_id`'s cart (`None` = takeaway) as a named draft with no
    /// table, and empty that cart. Pass the ORIGINAL `draft_id`/`started_at`
    /// when re-parking a restored draft so it keeps its identity and position.
    pub fn hold_cart(
        &self,
        table_id: Option<String>,
        name: String,
        draft_id: Option<String>,
        started_at: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .hold_cart(table_id, name, draft_id, started_at)
            .map_err(MadarError::from)
    }

    /// Park `table_id`'s cart onto floor table `onto_table_id` (or none).
    /// Returns `true` when that table was DROPPED because it's taken — the
    /// park itself still succeeded.
    pub fn hold_cart_on_table(
        &self,
        table_id: Option<String>,
        name: String,
        draft_id: Option<String>,
        started_at: Option<String>,
        onto_table_id: Option<String>,
    ) -> Result<bool, MadarError> {
        self.inner
            .hold_cart_on_table(table_id, name, draft_id, started_at, onto_table_id)
            .map_err(MadarError::from)
    }

    /// The branch's parked drafts (every till's), newest first. Drafts being
    /// edited on another till come back `locked_by_other` (not restorable).
    pub fn list_drafts(&self) -> Result<Vec<DraftView>, MadarError> {
        self.inner.list_drafts().map_err(MadarError::from)
    }

    /// Restore a draft into `table_id`'s cart (replaces its lines) and CLAIM
    /// it for this till. Errors when another till is editing it.
    pub fn restore_draft(
        &self,
        table_id: Option<String>,
        id: String,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner.restore_draft(table_id, id).map_err(MadarError::from)
    }

    /// Resume a parked order in one call: park `from_table_id`'s cart (if
    /// asked), park anything already in the draft's own context, restore the
    /// draft there with its meta. Activates nothing: the view's `table_id`
    /// names the context the host should now show.
    pub fn switch_to_draft(
        &self,
        from_table_id: Option<String>,
        id: String,
        park_in_hand: Option<HeldParkInput>,
        park_at_target: Option<HeldParkInput>,
    ) -> Result<DraftSwitchView, MadarError> {
        self.inner
            .switch_to_draft(from_table_id, id, park_in_hand, park_at_target)
            .map_err(MadarError::from)
    }
    /// Give a restored draft's claim back without changes (the "never mind"
    /// path out of a resume).
    pub fn release_draft(&self, id: String) -> Result<(), MadarError> {
        self.inner.release_draft(id).map_err(MadarError::from)
    }

    /// Rename a parked draft in place — no restore, no re-park, nothing
    /// displaced. Held orders are device-local, so nothing is queued.
    pub fn rename_draft(&self, id: String, name: String) -> Result<(), MadarError> {
        self.inner.rename_draft(id, name).map_err(MadarError::from)
    }

    /// Discard a parked draft (frees its table + any waitlist wish).
    pub fn discard_draft(&self, id: String) -> Result<(), MadarError> {
        self.inner.discard_draft(id).map_err(MadarError::from)
    }

    /// Mark a restored draft COMPLETED after its cart checked out — the host
    /// calls this right after a successful ring-up of a resumed draft.
    pub fn complete_draft(&self, id: String, order_id: Option<String>) -> Result<(), MadarError> {
        self.inner
            .complete_draft(id, order_id)
            .map_err(MadarError::from)
    }

    /// Assign / move / unassign a parked draft's table. Errors loudly when the
    /// table is taken (interactive path — the teller picks another).
    pub fn assign_draft_table(
        &self,
        id: String,
        table_id: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .assign_draft_table(id, table_id)
            .map_err(MadarError::from)
    }

    /// Apply a discount (by id) to the cart — reflected in `cart_totals`.
    pub fn cart_set_discount(&self, table_id: Option<String>, discount_id: String) -> Result<(), MadarError> {
        self.inner
            .cart_set_discount(table_id, discount_id)
            .map_err(MadarError::from)
    }

    /// Remove the cart discount.
    pub fn cart_clear_discount(&self, table_id: Option<String>) -> Result<(), MadarError> {
        self.inner.cart_clear_discount(table_id).map_err(MadarError::from)
    }

    /// Set or clear (None / blank) the note for the whole order in hand.
    pub fn cart_set_note(&self, table_id: Option<String>, note: Option<String>) -> Result<(), MadarError> {
        self.inner.cart_set_note(table_id, note).map_err(MadarError::from)
    }

    /// The cart's order note, or `None`.
    pub fn cart_note(&self, table_id: Option<String>) -> Result<Option<String>, MadarError> {
        self.inner.cart_note(table_id).map_err(MadarError::from)
    }

    /// Set or clear (None / blank) ONE cart line's KITCHEN-ONLY note (by its
    /// [`CartLineView.key`]). Local only — never checkout, never the receipt.
    pub fn cart_set_line_kitchen_note(
        &self,
        table_id: Option<String>,
        line_key: String,
        note: Option<String>,
    ) -> Result<(), MadarError> {
        self.inner
            .cart_set_line_kitchen_note(table_id, line_key, note)
            .map_err(MadarError::from)
    }

    /// Clear one line's kitchen note — call once that line's chit has
    /// actually printed.
    pub fn cart_clear_line_kitchen_note(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<(), MadarError> {
        self.inner
            .cart_clear_line_kitchen_note(table_id, line_key)
            .map_err(MadarError::from)
    }

    /// Set or clear (None / blank) the CART-level kitchen note (the
    /// whole-cart kitchen print's own note). Local only.
    pub fn cart_set_kitchen_note(&self, table_id: Option<String>, note: Option<String>) -> Result<(), MadarError> {
        self.inner.cart_set_kitchen_note(table_id, note).map_err(MadarError::from)
    }

    /// The cart's kitchen-only note, or `None`.
    pub fn cart_kitchen_note(&self, table_id: Option<String>) -> Result<Option<String>, MadarError> {
        self.inner.cart_kitchen_note(table_id).map_err(MadarError::from)
    }

    /// Clear the cart-level kitchen note — call once the whole-cart chit has
    /// actually printed.
    pub fn cart_clear_kitchen_note(&self, table_id: Option<String>) -> Result<(), MadarError> {
        self.inner.cart_clear_kitchen_note(table_id).map_err(MadarError::from)
    }

    /// Clear EVERY kitchen note in this cart (cart-level + every line's own)
    /// in one go — call once the whole-cart kitchen print has actually
    /// printed.
    pub fn cart_clear_all_kitchen_notes(&self, table_id: Option<String>) -> Result<(), MadarError> {
        self.inner
            .cart_clear_all_kitchen_notes(table_id)
            .map_err(MadarError::from)
    }

    /// The selected discount id (for the tender UI), or `None`.
    pub fn cart_discount_id(&self, table_id: Option<String>) -> Result<Option<String>, MadarError> {
        self.inner.cart_discount_id(table_id).map_err(MadarError::from)
    }

    /// Priced cart summary at the session's org tax rate (0 when signed out),
    /// computed through the pricing engine.
    pub fn cart_totals(&self, table_id: Option<String>) -> Result<CartTotals, MadarError> {
        self.inner.cart_totals(table_id).map_err(MadarError::from)
    }
}
