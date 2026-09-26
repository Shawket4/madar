//! Cart domain: lines, configured adds, addon lookup, recipe preview,
//! drafts (held orders), discounts, and totals. Binding code only — every
//! method is a one-line delegation through `MadarBridge.inner`.
use flutter_rust_bridge::frb;

use crate::api::bridge::MadarBridge;
use crate::api::error::MadarError;

pub use madar_core::deals::{AppliedDealView, DealSuggestion};
pub use madar_core::cart::{
    AddonSelection, CartAddonView, CartLineView, CartOptionalView, CartPartView, CartStaffDrinkView, CartStaffSummary, CartTotals, CartMeta, DraftSwitchView, DraftView, GroupViolationView, HeldParkInput,
    ItemAddonView, LinePreviewView, LinePriceRowView, LineSummaryPartView, ModifierGroupKind, ModifierGroupView, ModifierOptionView,
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
    pub default_option_id: Option<String>,
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

/// A cart line as the host renders it (with the derived line total).
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
    /// A KITCHEN-ONLY note for this line — never on the checkout payload,
    /// never on the customer receipt. Cleared once this line's chit prints.
    pub kitchen_note: Option<String>,
    /// Set when the line is a STAFF DRINK. `line_total_minor` stays the normal
    /// price; this carries the comp and what is still charged.
    pub staff_drink: Option<CartStaffDrinkView>,
    /// `"item"` or `"combo"`. A combo's `unit_price_minor` is its price P,
    /// `line_total_minor` the whole line, and its items are `parts`.
    pub kind: String,
    pub parts: Vec<CartPartView>,
    /// What an applied deal takes off this line (0 = none);
    /// `line_total_minor` stays the normal price.
    pub deal_cut_minor: i64,
    pub deal_name: Option<String>,
}

/// One item of a combo line, drawn indented under the combo.
#[frb(mirror(CartPartView))]
pub struct _CartPartView {
    pub slot_id: String,
    pub slot_name: String,
    pub item_id: String,
    pub item_name: String,
    /// `None` for an item with no real size.
    pub size_label: Option<String>,
    /// Units per combo.
    pub qty: i64,
    /// The item's normal price at its size.
    pub unit_price_minor: i64,
    /// Its share of ONE combo price.
    pub share_minor: i64,
    /// Per unit: what the choice and a bigger size add (0 = included).
    pub surcharge_minor: i64,
    pub addons: Vec<CartAddonView>,
    pub optionals: Vec<CartOptionalView>,
    pub notes: Option<String>,
}

/// A deal the cart qualifies for — the teller taps it to apply (C8).
#[frb(mirror(DealSuggestion))]
pub struct _DealSuggestion {
    pub deal_id: String,
    pub name: String,
    pub times: i64,
    /// "Applies twice", localized.
    pub times_label: String,
    pub saving_minor: i64,
    pub line_keys: Vec<String>,
}

/// A deal applied on the cart.
#[frb(mirror(AppliedDealView))]
pub struct _AppliedDealView {
    /// Pass to `cart_remove_deal`.
    pub id: String,
    pub deal_id: String,
    pub name: String,
    pub times: i64,
    pub discount_minor: i64,
    pub line_keys: Vec<String>,
}

/// A cart line's staff-drink mark.
#[frb(mirror(CartStaffDrinkView))]
pub struct _CartStaffDrinkView {
    pub id: String,
    pub note: String,
    pub comp_minor: i64,
    pub charged_minor: i64,
}

/// The cart's staff drinks in one figure, for the Charge sheet.
#[frb(mirror(CartStaffSummary))]
pub struct _CartStaffSummary {
    pub units: i64,
    pub comp_minor: i64,
    pub charged_minor: i64,
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

/// A parked cart, summarized for the drafts list. Now server-backed: shared
/// across the branch's tills, optionally owning a floor table.
/// What a configured line would cost — the item sheet's figures.
#[frb(mirror(LinePreviewView))]
pub struct _LinePreviewView {
    pub unit_total_minor: i64,
    pub extras_minor: i64,
    pub line_total_minor: i64,
    pub qty: i64,
    pub base_minor: i64,
    pub size_label: Option<String>,
    pub size_delta_minor: i64,
    pub paid: Vec<LinePriceRowView>,
    pub summary: Vec<LineSummaryPartView>,
}

/// One word of a line's summary (the cart line's and the receipt's word).
#[frb(mirror(LineSummaryPartView))]
pub struct _LineSummaryPartView {
    pub kind: String,
    pub ref_id: String,
    pub text: String,
}

/// One paid option in a line's price breakdown, per unit.
#[frb(mirror(LinePriceRowView))]
pub struct _LinePriceRowView {
    pub text: String,
    pub amount_minor: i64,
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
    pub customer_id: Option<String>,
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
    /// Someone other than the signed-in person started it: show whose it is.
    pub by_other: bool,
    /// Who started it, when known.
    pub created_by_name: Option<String>,
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

    /// What a configured line would cost (unit, extras, whole line), its price
    /// breakdown and its summary words — from the resolver the add uses.
    /// Adds nothing.
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
    /// names the context the host should now show. Resuming an order someone
    /// else started carries the manager's `approval` when `decide_draft_act`
    /// asked for one.
    pub fn switch_to_draft(
        &self,
        from_table_id: Option<String>,
        id: String,
        park_in_hand: Option<HeldParkInput>,
        park_at_target: Option<HeldParkInput>,
        approval: Option<crate::api::approvals::ApprovalView>,
    ) -> Result<DraftSwitchView, MadarError> {
        self.inner
            .switch_to_draft_approved(from_table_id, id, park_in_hand, park_at_target, approval)
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

    /// Discard a parked draft (frees its table + any waitlist wish). One
    /// someone else started carries the manager's `approval` when
    /// `decide_draft_act("discard")` asked for one.
    pub fn discard_draft(
        &self,
        id: String,
        approval: Option<crate::api::approvals::ApprovalView>,
    ) -> Result<(), MadarError> {
        self.inner
            .discard_draft_approved(id, approval)
            .map_err(MadarError::from)
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

    // ── combos (COMBOS_CONTRACT §6) ──────────────────────────────────────

    /// The combo sheet's live figures for the picks so far (× `qty`).
    pub fn combo_quote(
        &self,
        table_id: Option<String>,
        combo_id: String,
        picks: Vec<crate::api::catalog::ComboPickInput>,
        qty: i64,
    ) -> Result<crate::api::catalog::ComboQuoteView, MadarError> {
        self.inner
            .combo_quote(table_id, combo_id, picks, qty)
            .map_err(MadarError::from)
    }

    /// Add a combo line (identical combos merge). Refused, in the teller's
    /// words, when a slot is short or the combo is not on sale now.
    pub fn cart_add_combo(
        &self,
        table_id: Option<String>,
        combo_id: String,
        picks: Vec<crate::api::catalog::ComboPickInput>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_add_combo(table_id, combo_id, picks, qty, notes)
            .map_err(MadarError::from)
    }

    /// Replace a cart line with a combo in one write: an edited combo, or
    /// "make it a meal" turning an item line into its combo.
    pub fn cart_replace_combo(
        &self,
        table_id: Option<String>,
        line_key: String,
        combo_id: String,
        picks: Vec<crate::api::catalog::ComboPickInput>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_replace_combo(table_id, line_key, combo_id, picks, qty, notes)
            .map_err(MadarError::from)
    }

    /// A combo line in the cart as a draft to edit on the sheet.
    pub fn cart_combo_draft(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<crate::api::catalog::ComboDraft, MadarError> {
        self.inner
            .cart_combo_draft(table_id, line_key)
            .map_err(MadarError::from)
    }

    /// "Make it a meal" from an item line: the draft pre-filled with the
    /// line's item in its slot; save it with `cart_replace_combo`.
    pub fn cart_make_it_a_meal(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<crate::api::catalog::ComboDraft, MadarError> {
        self.inner
            .cart_make_it_a_meal(table_id, line_key)
            .map_err(MadarError::from)
    }

    /// "Make it a meal" from the item sheet, before the item is in the cart.
    pub fn item_meal_draft(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<crate::api::catalog::ComboDraft, MadarError> {
        self.inner
            .item_meal_draft(item_id, size_label, addons, optional_field_ids, qty, notes)
            .map_err(MadarError::from)
    }

    // ── deals (C8: suggested, the teller applies) ────────────────────────

    /// The deals this cart qualifies for now, best first. Never applied.
    #[frb(sync)]
    pub fn cart_deal_suggestions(&self, table_id: Option<String>) -> Vec<DealSuggestion> {
        self.inner.cart_deal_suggestions(table_id)
    }

    /// The deals applied on the cart.
    #[frb(sync)]
    pub fn cart_applied_deals(&self, table_id: Option<String>) -> Vec<AppliedDealView> {
        self.inner.cart_applied_deals(table_id)
    }

    /// Whether the signed-in person may apply a deal (`orders.deals.apply`).
    #[frb(sync)]
    pub fn can_apply_deals(&self) -> bool {
        self.inner.can_apply_deals()
    }

    /// Apply the suggested deal (the teller's tap).
    pub fn cart_apply_deal(
        &self,
        table_id: Option<String>,
        deal_id: String,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_apply_deal(table_id, deal_id)
            .map_err(MadarError::from)
    }

    /// Take an applied deal off the cart.
    pub fn cart_remove_deal(
        &self,
        table_id: Option<String>,
        application_id: String,
    ) -> Result<Vec<CartLineView>, MadarError> {
        self.inner
            .cart_remove_deal(table_id, application_id)
            .map_err(MadarError::from)
    }

    /// Why applied deals came off since the last ask, each a sentence for
    /// the shell toast. Draining.
    pub fn take_deal_notices(&self, table_id: Option<String>) -> Vec<String> {
        self.inner.take_deal_notices(table_id)
    }
}
