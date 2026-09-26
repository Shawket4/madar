//! Combos on the till (COMBOS_CONTRACT §6; COMBOS_DESIGN C1–C15).
//!
//! A combo is a menu row of `kind = 'combo'` ([`menu::ComboDef`]): its price
//! P is the row's own price, and its slots say what the customer picks. The
//! RULE is madar-shared's `madar_catalog::combo` — the server's own copy:
//! the picks against the slots, P split over the parts by their menu prices,
//! a bigger size's surcharge (C9), the add-ons at their normal prices (C10),
//! and whether the combo is on sale now. This module only turns the menu
//! mirror into the rule's inputs and its answers into what the host draws:
//!
//! - [`ComboDetail`]: the combo sheet — slots, their choices (a category
//!   choice expanded against this till's menu), each choice's sizes with what
//!   a bigger one adds, and whether the combo is on sale now;
//! - [`ComboQuoteView`]: the sheet's live figures for the picks so far;
//! - [`MealOffer`] / [`ComboDraft`]: "make it a meal" (C14), the item's combo
//!   with the item already in its slot and the defaults elsewhere.
//!
//! The UI holds no rule: it sends picks and shows what comes back.

use std::collections::HashMap;

use madar_catalog::combo::{self as rule, Channel, ComboRefusal, ComboView, PickIn, Sell, Unavailable};
use madar_catalog::sale_window::LocalNow;

use crate::cart::{self, AddonSelection};
use crate::catalog_pricing::{self, PricingMirror};
use crate::i18n;
use crate::menu::{self, AddonItemView, ComboDef, MealRef, MenuItemView};

/// One pick the host sends: the slot, the item, its size and its add-ons.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ComboPickInput {
    pub slot_id: String,
    pub item_id: String,
    /// `None` = the size the combo includes.
    pub size_label: Option<String>,
    /// Units of this item per combo unit (usually 1).
    pub qty: i64,
    pub addons: Vec<AddonSelection>,
    pub optional_field_ids: Vec<String>,
    /// A note for the kitchen about this item.
    pub notes: Option<String>,
}

/// The combo sheet: everything it draws, priced.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ComboDetail {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub local_image_path: Option<String>,
    /// P: what the combo costs before any surcharge or add-on.
    pub price_minor: i64,
    /// C1's fixed bundle: one item per slot, nothing to choose.
    pub is_fixed: bool,
    pub available_now: bool,
    /// Why not, in the teller's language (`None` when on sale).
    pub why_unavailable: Option<String>,
    pub slots: Vec<ComboSlotDetail>,
}

/// One slot on the sheet.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ComboSlotDetail {
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

/// One item a slot admits, priced for this branch.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ComboChoiceDetail {
    pub item_id: String,
    pub name: String,
    pub local_image_path: Option<String>,
    /// The item's normal price at the size the combo includes.
    pub base_price_minor: i64,
    /// The size the combo includes; `None` for an item with no real size.
    pub included_size_label: Option<String>,
    /// What choosing this item adds per unit (the owner's per-choice
    /// surcharge; 0 = included).
    pub surcharge_minor: i64,
    /// The item's sizes (empty for an item with no real size), each with
    /// what it adds over the included one (C9).
    pub sizes: Vec<ComboSizeOption>,
    /// The slot's default.
    pub is_default: bool,
    /// The item has add-ons or optional fields: the sheet offers "Customise".
    pub customisable: bool,
    /// The item has a required choice with no default (a sandwich's bread):
    /// picking it opens "Customise" at once, and the combo can't be added
    /// until the choice is made ([`COMBO_PICK_CHOICE_REQUIRED`]).
    pub must_customise: bool,
}

/// A size of a choice.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ComboSizeOption {
    pub label: String,
    /// The item's normal price at this size.
    pub price_minor: i64,
    /// What this size adds inside the combo (0 for the included size).
    pub extra_minor: i64,
    pub is_included: bool,
}

/// The sheet's live figures for the picks so far.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ComboQuoteView {
    /// P.
    pub price_minor: i64,
    /// One combo with its surcharges and add-ons.
    pub unit_total_minor: i64,
    /// `qty` combos.
    pub line_total_minor: i64,
    /// Per combo: what the choices and bigger sizes add.
    pub surcharge_minor: i64,
    /// Per combo: the add-ons and optional fields at their normal prices.
    pub extras_minor: i64,
    /// Per combo: the same picks bought separately.
    pub list_minor: i64,
    /// The whole line (`qty` combos): `(list − unit_total) × qty`, like
    /// `line_total_minor` (0 or less = no saving).
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

/// The coded refusal of a pick whose item has a required choice with no
/// default that the pick leaves unmade (a sandwich's bread). The till's own:
/// the server fills an unpicked choice with a default, and this one has none.
pub const COMBO_PICK_CHOICE_REQUIRED: &str = "COMBO_PICK_CHOICE_REQUIRED";

/// A pick still wanting a required choice.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct ComboPickNeed {
    pub slot_id: String,
    pub item_id: String,
    /// The choice's name ("Bread"), in the teller's language.
    pub group_name: String,
    /// What the slot shows: "Choose Bread".
    pub text: String,
}

/// A combo ready to edit on the sheet: a combo line in the cart, or "make it
/// a meal" pre-filled with the item in its slot and the defaults elsewhere.
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct ComboDraft {
    pub combo_id: String,
    /// The cart line the draft replaces on save (`cart_replace_combo`);
    /// `None` = a new line (`cart_add_combo`).
    pub line_key: Option<String>,
    pub qty: i64,
    pub notes: Option<String>,
    pub picks: Vec<ComboPickInput>,
}

/// "Make it a meal +X" on an item (C14).
#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct MealOffer {
    pub combo_id: String,
    pub slot_id: String,
    /// The combo's name.
    pub name: String,
    /// What the meal adds over the item alone: the combo with this item in
    /// its slot and the defaults elsewhere, minus the item's own price.
    pub delta_minor: i64,
}

/// Where and when the till sells: the channel switches at this branch, the
/// branch, and the branch's wall clock.
pub(crate) struct At {
    pub sell: Sell,
    pub branch_id: Option<String>,
    pub now: LocalNow,
}

/// The switches at this branch (§11: org-wide per channel, with branch
/// overrides; the server resolves them onto every combo row). The first row
/// that carries them answers; a server that sends none sells on every channel.
pub(crate) fn channel_sell(combos: &[ComboDef], feed: Option<Sell>) -> Sell {
    feed.or_else(|| combos.iter().find_map(|c| c.sell)).unwrap_or_default()
}

/// The items a choice admits that this till can sell: the item itself, or
/// every plain item of the category — active, never a combo (a combo never
/// contains a combo).
pub(crate) fn choice_items<'a>(
    choice: &rule::ChoiceView,
    items: &'a [MenuItemView],
) -> Vec<&'a MenuItemView> {
    items
        .iter()
        .filter(|i| i.kind != menu::KIND_COMBO && i.is_active)
        .filter(|i| match (&choice.menu_item_id, &choice.category_id) {
            (Some(id), _) => &i.id == id,
            (None, Some(cat)) => i.category_id.as_deref() == Some(cat.as_str()),
            (None, None) => false,
        })
        .collect()
}

/// Is the combo on sale at the till now? The rule's order of reasons.
pub(crate) fn availability(
    view: &ComboView,
    items: &[MenuItemView],
    at: &At,
) -> Result<(), Unavailable> {
    rule::available(
        view,
        &rule::Availability {
            channel: Channel::Pos,
            sell: &at.sell,
            // The mirrored menu is the branch's: a combo the branch switched
            // off is not active on it.
            branch_enabled: true,
            branch_id: at.branch_id.as_deref(),
            now: &at.now,
        },
        |c| !choice_items(c, items).is_empty(),
    )
}

/// The rule's inputs for a combo line: the combo's view and one `PickIn` per
/// pick, each over its own item's view with the till's selection
/// normalisation ([`cart::selection_for`]). A pick naming an item this till
/// does not sell is not allowed in its slot.
pub(crate) fn rule_inputs(
    def: &ComboDef,
    combo_item: &MenuItemView,
    items: &[MenuItemView],
    addons: &[AddonItemView],
    pricing: &PricingMirror,
    picks: &[ComboPickInput],
) -> Result<(ComboView, Vec<PickIn>), ComboRefusal> {
    let view = catalog_pricing::combo_view_for(def, combo_item, pricing);
    let ins = picks
        .iter()
        .map(|p| {
            let item = items
                .iter()
                .find(|i| i.id == p.item_id && i.kind != menu::KIND_COMBO)
                .ok_or_else(|| ComboRefusal::NotAllowed {
                    slot_id: p.slot_id.clone(),
                    menu_item_id: p.item_id.clone(),
                })?;
            let cv = pricing.view_for(item, addons);
            let selection = cart::selection_for(
                item,
                addons,
                &cv,
                p.size_label.as_deref(),
                &p.addons,
                &p.optional_field_ids,
            );
            Ok(PickIn {
                slot_id: p.slot_id.clone(),
                category_id: item.category_id.clone(),
                view: cv,
                selection,
                quantity: p.qty,
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    Ok((view, ins))
}

/// A slot's rule in words: "Choose 1 item", "Choose up to 2 items",
/// "Choose 1 to 3", with "Optional" in front when nothing is required.
fn rule_label(min: i64, max: i64, locale: &str) -> String {
    let fill = |key: &str, n: i64| i18n::tr_count(locale, key, n).replace("{count}", &n.to_string());
    if min == 0 {
        return format!(
            "{} · {}",
            i18n::tr(locale, "combo.pick_optional"),
            fill("combo.pick_up_to", max)
        );
    }
    if min == max {
        return fill("combo.pick_n", min);
    }
    i18n::tr(locale, "combo.pick_range")
        .replace("{min}", &min.to_string())
        .replace("{max}", &max.to_string())
}

/// Why a combo is off, in the teller's words.
pub(crate) fn why_text(why: &Unavailable, locale: &str) -> String {
    match why {
        Unavailable::Channel => i18n::tr(locale, "combo.channel_off"),
        _ => i18n::tr(locale, "combo.unavailable"),
    }
}

/// A refusal of the picks, in the teller's words (§2.7).
pub(crate) fn refusal_text(
    refusal: &ComboRefusal,
    def: &ComboDef,
    items: &[MenuItemView],
    locale: &str,
) -> String {
    let slot = |id: &str| {
        def.slots
            .iter()
            .find(|s| s.id == id)
            .map(|s| s.name.clone())
            .unwrap_or_default()
    };
    match refusal {
        ComboRefusal::TooFew { slot_id, min, .. } => i18n::tr(locale, "combo.slot_too_few")
            .replace("{min}", &min.to_string())
            .replace("{slot}", &slot(slot_id)),
        ComboRefusal::BadQuantity { slot_id } => i18n::tr(locale, "combo.slot_too_few")
            .replace("{min}", "1")
            .replace("{slot}", &slot(slot_id)),
        ComboRefusal::TooMany { slot_id, max, .. } => i18n::tr(locale, "combo.slot_too_many")
            .replace("{max}", &max.to_string())
            .replace("{slot}", &slot(slot_id)),
        ComboRefusal::UnknownSlot { .. } | ComboRefusal::NotAllowed { .. } => {
            i18n::tr(locale, "combo.choice_not_allowed")
        }
        ComboRefusal::Price { menu_item_id, .. } => {
            let name = items
                .iter()
                .find(|i| &i.id == menu_item_id)
                .map(|i| i.name.clone())
                .unwrap_or_default();
            i18n::tr(locale, "combo.item_unavailable").replace("{item}", &name)
        }
    }
}

/// The detail the combo sheet draws. `customisable` says whether an item has
/// anything to pick (the item sheet's own modifier groups), `must_customise`
/// whether one of those picks is required and has no default.
#[allow(clippy::too_many_arguments)]
pub(crate) fn detail(
    def: &ComboDef,
    combo_item: &MenuItemView,
    items: &[MenuItemView],
    addons: &[AddonItemView],
    pricing: &PricingMirror,
    at: &At,
    locale: &str,
    customisable: impl Fn(&MenuItemView) -> bool,
    must_customise: impl Fn(&MenuItemView) -> bool,
) -> ComboDetail {
    let view = catalog_pricing::combo_view_for(def, combo_item, pricing);
    let avail = availability(&view, items, at);
    let slots = def
        .slots
        .iter()
        .map(|slot| {
            let rule_slot = view
                .slots
                .iter()
                .find(|s| s.id == slot.id)
                .expect("the view carries every slot");
            let mut choices: Vec<&rule::ChoiceView> = slot.choices.iter().collect();
            choices.sort_by_key(|c| c.sort);
            let mut seen: Vec<String> = Vec::new();
            let mut out: Vec<ComboChoiceDetail> = Vec::new();
            for c in choices {
                for item in choice_items(c, items) {
                    if seen.contains(&item.id) {
                        continue;
                    }
                    // The rule's own choice for this item (an item choice
                    // beats a category one): its surcharge and sizes apply.
                    let Some(choice) =
                        rule::choice_for(rule_slot, &item.id, item.category_id.as_deref())
                    else {
                        continue;
                    };
                    let cv = pricing.view_for(item, addons);
                    let Ok(included) = rule::included_size(&cv, choice) else {
                        continue;
                    };
                    let Ok(base) = madar_catalog::unit_price(&cv.item, Some(&included)) else {
                        continue;
                    };
                    let sizes = item
                        .sizes
                        .iter()
                        .filter(|s| s.is_active && !cart::is_one_size(&s.label))
                        .filter_map(|s| {
                            let price = madar_catalog::unit_price(&cv.item, Some(&s.label)).ok()?;
                            let extra = if s.label == included {
                                0
                            } else if let Some(o) =
                                choice.size_surcharges.iter().find(|o| o.size_label == s.label)
                            {
                                o.surcharge
                            } else {
                                (price - base).max(0)
                            };
                            Some(ComboSizeOption {
                                label: s.label.clone(),
                                price_minor: price,
                                extra_minor: extra,
                                is_included: s.label == included,
                            })
                        })
                        .collect();
                    seen.push(item.id.clone());
                    out.push(ComboChoiceDetail {
                        item_id: item.id.clone(),
                        name: item.name.clone(),
                        local_image_path: item.local_image_path.clone(),
                        base_price_minor: base,
                        included_size_label: Some(included).filter(|l| !cart::is_one_size(l)),
                        surcharge_minor: choice.surcharge,
                        sizes,
                        is_default: slot.default_item_id.as_deref() == Some(item.id.as_str()),
                        customisable: customisable(item),
                        must_customise: must_customise(item),
                    });
                }
            }
            ComboSlotDetail {
                id: slot.id.clone(),
                name: slot.name.clone(),
                min: slot.min,
                max: slot.max,
                rule_label: rule_label(slot.min, slot.max, locale),
                default_item_id: slot.default_item_id.clone(),
                default_size_label: slot.default_size_label.clone(),
                choices: out,
            }
        })
        .collect();
    ComboDetail {
        id: def.id.clone(),
        name: def.name.clone(),
        description: combo_item.description.clone(),
        local_image_path: combo_item.local_image_path.clone(),
        price_minor: view.price,
        is_fixed: rule::is_fixed(&view),
        available_now: avail.is_ok(),
        why_unavailable: avail.err().map(|w| why_text(&w, locale)),
        slots,
    }
}

/// The live figures for `picks` × `qty`. While a slot still wants a pick the
/// figures are those of the picks so far (the combo with that slot's minimum
/// set aside) and `complete` is false.
#[allow(clippy::too_many_arguments)]
pub(crate) fn quote_view(
    def: &ComboDef,
    combo_item: &MenuItemView,
    items: &[MenuItemView],
    addons: &[AddonItemView],
    pricing: &PricingMirror,
    picks: &[ComboPickInput],
    qty: i64,
    locale: &str,
) -> ComboQuoteView {
    let figures = |q: &rule::ComboQuote| ComboQuoteView {
        price_minor: q.price,
        unit_total_minor: q.unit_total,
        line_total_minor: q.line_total(),
        surcharge_minor: q.parts.iter().map(|p| p.pick_quantity * p.surcharge_unit).sum(),
        extras_minor: q.parts.iter().map(|p| p.pick_quantity * p.extras_unit).sum(),
        list_minor: q.list_unit,
        saving_minor: q.saving_unit * qty,
        complete: true,
        refusal: None,
        refusal_text: None,
        pick_needs: Vec::new(),
    };
    let refused = |r: &ComboRefusal, mut v: ComboQuoteView| {
        v.complete = false;
        v.refusal = Some(r.code().to_string());
        v.refusal_text = Some(refusal_text(r, def, items, locale));
        v
    };
    let (view, ins) = match rule_inputs(def, combo_item, items, addons, pricing, picks) {
        Ok(x) => x,
        Err(r) => {
            let price = catalog_pricing::combo_view_for(def, combo_item, pricing).price;
            let base = ComboQuoteView {
                price_minor: price,
                unit_total_minor: price,
                line_total_minor: price * qty.max(1),
                ..Default::default()
            };
            return refused(&r, base);
        }
    };
    match rule::quote(&view, &ins, qty) {
        Ok(q) => figures(&q),
        Err(r) => {
            // The picks so far: every slot's minimum set aside, so a combo
            // half chosen still shows what it comes to.
            let mut relaxed = view.clone();
            relaxed.slots.iter_mut().for_each(|s| s.min = 0);
            let partial = rule::quote(&relaxed, &ins, qty).map(|q| figures(&q)).unwrap_or(
                ComboQuoteView {
                    price_minor: view.price,
                    unit_total_minor: view.price,
                    line_total_minor: view.price * qty.max(1),
                    ..Default::default()
                },
            );
            refused(&r, partial)
        }
    }
}

/// The picks a slot starts with: its default item (at its default size) ×
/// its minimum. With `fill_required`, a required slot with no usable default
/// takes its first choice — only for a figure ("+X"), never for a draft the
/// teller has not seen.
fn default_picks(
    def: &ComboDef,
    items: &[MenuItemView],
    skip_slot: Option<&str>,
    fill_required: bool,
) -> Vec<ComboPickInput> {
    let mut out = Vec::new();
    for slot in &def.slots {
        if Some(slot.id.as_str()) == skip_slot || slot.min < 1 {
            continue;
        }
        let admitted = |id: &str| {
            slot.choices
                .iter()
                .any(|c| choice_items(c, items).iter().any(|i| i.id == id))
        };
        let default = slot
            .default_item_id
            .as_deref()
            .filter(|id| admitted(id))
            .map(|id| (id.to_string(), slot.default_size_label.clone()));
        let only = || {
            let all: Vec<&MenuItemView> =
                slot.choices.iter().flat_map(|c| choice_items(c, items)).collect();
            match all.as_slice() {
                [one] => Some((one.id.clone(), None)),
                [first, ..] if fill_required => Some((first.id.clone(), None)),
                _ => None,
            }
        };
        if let Some((item_id, size_label)) = default.or_else(only) {
            out.push(ComboPickInput {
                slot_id: slot.id.clone(),
                item_id,
                size_label,
                qty: slot.min,
                ..Default::default()
            });
        }
    }
    out
}

/// The draft a new combo opens with: every slot's default.
pub(crate) fn new_draft(def: &ComboDef, items: &[MenuItemView]) -> ComboDraft {
    ComboDraft {
        combo_id: def.id.clone(),
        line_key: None,
        qty: 1,
        notes: None,
        picks: default_picks(def, items, None, false),
    }
}

/// "Make it a meal" (C14): the item's combo, with `pick` (the item as the
/// teller configured it) in the meal's slot and the defaults elsewhere.
/// `None` when the item has no meal, the combo is not on sale now, or its
/// slot no longer admits the item.
#[allow(clippy::too_many_arguments)]
pub(crate) fn meal_draft(
    item: &MenuItemView,
    pick: ComboPickInput,
    qty: i64,
    notes: Option<String>,
    line_key: Option<String>,
    meals: &HashMap<String, MealRef>,
    combos: &[ComboDef],
    items: &[MenuItemView],
    pricing: &PricingMirror,
    at: &At,
) -> Option<ComboDraft> {
    let (meal, def, combo_item) = meal_target(item, meals, combos, items, pricing, at)?;
    let mut picks = default_picks(def, items, Some(&meal.slot_id), false);
    picks.push(ComboPickInput {
        slot_id: meal.slot_id.clone(),
        ..pick
    });
    Some(ComboDraft {
        combo_id: combo_item.id.clone(),
        line_key,
        qty: qty.max(1),
        notes,
        picks,
    })
}

/// The meal an item upgrades to, when it can now: its combo is on sale and
/// the meal's slot admits the item.
fn meal_target<'a>(
    item: &MenuItemView,
    meals: &'a HashMap<String, MealRef>,
    combos: &'a [ComboDef],
    items: &'a [MenuItemView],
    pricing: &PricingMirror,
    at: &At,
) -> Option<(&'a MealRef, &'a ComboDef, &'a MenuItemView)> {
    let meal = meals.get(&item.id)?;
    let def = combos.iter().find(|c| c.id == meal.combo_id)?;
    let combo_item = items.iter().find(|i| i.id == def.id)?;
    let view = catalog_pricing::combo_view_for(def, combo_item, pricing);
    availability(&view, items, at).ok()?;
    let slot = view.slots.iter().find(|s| s.id == meal.slot_id)?;
    rule::choice_for(slot, &item.id, item.category_id.as_deref())?;
    Some((meal, def, combo_item))
}

/// "Make it a meal +X" for `item` (C14): the combo with the item at the size
/// the combo includes and the defaults elsewhere, minus the item alone at
/// that size.
#[allow(clippy::too_many_arguments)]
pub(crate) fn meal_offer(
    item: &MenuItemView,
    meals: &HashMap<String, MealRef>,
    combos: &[ComboDef],
    items: &[MenuItemView],
    addons: &[AddonItemView],
    pricing: &PricingMirror,
    at: &At,
) -> Option<MealOffer> {
    let (meal, def, combo_item) = meal_target(item, meals, combos, items, pricing, at)?;
    let mut picks = default_picks(def, items, Some(&meal.slot_id), true);
    picks.push(ComboPickInput {
        slot_id: meal.slot_id.clone(),
        item_id: item.id.clone(),
        qty: 1,
        ..Default::default()
    });
    let (view, ins) = rule_inputs(def, combo_item, items, addons, pricing, &picks).ok()?;
    let q = rule::quote(&view, &ins, 1).ok()?;
    let own = q.parts.iter().find(|p| p.slot_id == meal.slot_id && p.menu_item_id == item.id)?;
    Some(MealOffer {
        combo_id: combo_item.id.clone(),
        slot_id: meal.slot_id.clone(),
        name: def.name.clone(),
        delta_minor: q.unit_total - own.unit_price,
    })
}

/// A pick from what an item line or the item sheet holds.
pub(crate) fn pick_of(
    item_id: &str,
    size_label: Option<String>,
    addons: Vec<AddonSelection>,
    optional_field_ids: Vec<String>,
    notes: Option<String>,
) -> ComboPickInput {
    ComboPickInput {
        slot_id: String::new(),
        item_id: item_id.to_string(),
        size_label: size_label.filter(|s| !cart::is_one_size(s)),
        qty: 1,
        addons,
        optional_field_ids,
        notes,
    }
}

/// The first required choice among an item's `groups` that a selection
/// leaves unmade and that has no default to stand in for it, named in the
/// teller's words. A default is the item as it is made (the recipe's milk):
/// the rule applies it to a pick nobody customised, so it never counts as
/// missing. A sandwich's bread has none: nobody can guess it.
pub(crate) fn unmade_choice(
    groups: &[cart::ModifierGroupView],
    addons: &[AddonSelection],
    optional_ids: &[String],
    locale: &str,
) -> Option<String> {
    cart::validate_group_selections(groups, addons, optional_ids)
        .into_iter()
        .filter(|v| v.selected < i64::from(v.min_required))
        .find_map(|v| {
            let g = groups.iter().find(|g| g.group_id == v.group_id)?;
            let stands_in = g.default_option_id.is_some() && v.selected == 0 && v.min_required <= 1;
            (!stands_in).then(|| group_word(g, locale))
        })
}

/// A group's name as the item sheet shows it: an authored name as it is, a
/// bare addon type in the till's words.
fn group_word(g: &cart::ModifierGroupView, locale: &str) -> String {
    match g.addon_type.as_deref() {
        Some(ty) if g.name == ty => {
            let key = format!("order.addon_{ty}");
            match i18n::tr(locale, &key) {
                word if word != key => word,
                _ => i18n::tr(locale, "order.addon_other"),
            }
        }
        _ => g.name.clone(),
    }
}

/// The refusal of a pick still wanting a choice, in the teller's words.
fn need_text(need: &ComboPickNeed, items: &[MenuItemView], locale: &str) -> String {
    let item = items
        .iter()
        .find(|i| i.id == need.item_id)
        .map(|i| i.name.as_str())
        .unwrap_or_default();
    i18n::tr(locale, "combo.pick_choice_required")
        .replace("{group}", &need.group_name)
        .replace("{item}", item)
}

// ── the core's surface (FRB: `api/catalog.rs`, `api/cart.rs`) ────────────────

impl crate::MadarCore {
    /// The branch's wall clock now (the till's corrected clock in the branch
    /// zone): what a window is judged against.
    pub(crate) fn branch_local_now(&self) -> LocalNow {
        let (date, time) = crate::timefmt::wall_clock_in(
            self.corrected_now(),
            crate::timefmt::branch_tz(&self.store),
        );
        LocalNow::new(date, time)
    }

    pub(crate) fn combo_at(&self, catalog: &crate::CatalogSnapshot) -> At {
        At {
            sell: channel_sell(&catalog.combos, crate::deals::feed_sell(&self.store)),
            branch_id: self.session_branch_id().ok(),
            now: self.branch_local_now(),
        }
    }

    pub(crate) fn combo_on_sale(&self, catalog: &crate::CatalogSnapshot, combo_id: &str, at: &At) -> bool {
        let (Some(def), Some(item)) = (
            catalog.combos.iter().find(|c| c.id == combo_id),
            catalog.items.iter().find(|i| i.id == combo_id),
        ) else {
            return false;
        };
        let view = catalog_pricing::combo_view_for(def, item, &catalog.pricing);
        availability(&view, &catalog.items, at).is_ok()
    }

    fn combo_of<'a>(
        catalog: &'a crate::CatalogSnapshot,
        combo_id: &str,
    ) -> Result<(&'a ComboDef, &'a MenuItemView), crate::error::CoreError> {
        // The detail is the whole sentence, in the till's language (the host
        // shows it as it is when `field` is empty).
        let unknown = || crate::error::CoreError::Validation {
            field: String::new(),
            detail: i18n::tr(&catalog.locale, "combo.unavailable"),
        };
        let def = catalog.combos.iter().find(|c| c.id == combo_id).ok_or_else(unknown)?;
        let item = catalog.items.iter().find(|i| i.id == combo_id).ok_or_else(unknown)?;
        Ok((def, item))
    }

    /// Whether an item has anything to pick on its own sheet.
    fn customisable(&self, catalog: &crate::CatalogSnapshot, item: &MenuItemView) -> bool {
        // The sizes are the combo sheet's own chips; the add-ons decide.
        match catalog.unified.as_ref().and_then(|d| d.groups_for(&item.id)) {
            Some(groups) => !groups.is_empty(),
            None => !cart::item_modifier_groups(item, &catalog.addons, &catalog.pricing).is_empty(),
        }
    }

    /// Whether an item has a required choice with no default: picking it
    /// opens its sheet at once.
    fn must_customise(catalog: &crate::CatalogSnapshot, item: &MenuItemView) -> bool {
        let groups = Self::modifier_groups_in(catalog, item);
        unmade_choice(&groups, &[], &[], &catalog.locale).is_some()
    }

    /// Each pick whose item still wants a required choice with no default.
    fn pick_needs(catalog: &crate::CatalogSnapshot, picks: &[ComboPickInput]) -> Vec<ComboPickNeed> {
        picks
            .iter()
            .filter_map(|p| {
                let item = catalog
                    .items
                    .iter()
                    .find(|i| i.id == p.item_id && i.kind != menu::KIND_COMBO)?;
                let groups = Self::modifier_groups_in(catalog, item);
                let group_name =
                    unmade_choice(&groups, &p.addons, &p.optional_field_ids, &catalog.locale)?;
                Some(ComboPickNeed {
                    slot_id: p.slot_id.clone(),
                    item_id: p.item_id.clone(),
                    text: i18n::tr(&catalog.locale, "combo.pick_choose").replace("{group}", &group_name),
                    group_name,
                })
            })
            .collect()
    }

    /// The combo sheet for `item_id`, or `None` when it is not a combo here.
    pub fn combo_detail(&self, item_id: String) -> Option<ComboDetail> {
        let catalog = self.catalog().ok()?;
        let (def, item) = Self::combo_of(&catalog, &item_id).ok()?;
        let at = self.combo_at(&catalog);
        Some(detail(
            def,
            item,
            &catalog.items,
            &catalog.addons,
            &catalog.pricing,
            &at,
            &catalog.locale,
            |i| self.customisable(&catalog, i),
            |i| Self::must_customise(&catalog, i),
        ))
    }

    /// The draft a fresh combo opens with: every slot's default pick.
    pub fn combo_new_draft(&self, item_id: String) -> Option<ComboDraft> {
        let catalog = self.catalog().ok()?;
        let (def, _) = Self::combo_of(&catalog, &item_id).ok()?;
        Some(new_draft(def, &catalog.items))
    }

    /// "Make it a meal +X" for an item (C14): `None` when it has no meal the
    /// till can sell now.
    pub fn meal_offer(&self, item_id: String) -> Option<MealOffer> {
        let catalog = self.catalog().ok()?;
        let item = catalog.items.iter().find(|i| i.id == item_id)?;
        let at = self.combo_at(&catalog);
        meal_offer(
            item,
            &catalog.meals,
            &catalog.combos,
            &catalog.items,
            &catalog.addons,
            &catalog.pricing,
            &at,
        )
    }

    /// The live figures for the picks so far (the combo sheet's total).
    pub fn combo_quote(
        &self,
        _table_id: Option<String>,
        combo_id: String,
        picks: Vec<ComboPickInput>,
        qty: i64,
    ) -> Result<ComboQuoteView, crate::error::CoreError> {
        let catalog = self.catalog()?;
        let (def, item) = Self::combo_of(&catalog, &combo_id)?;
        let mut q = quote_view(
            def,
            item,
            &catalog.items,
            &catalog.addons,
            &catalog.pricing,
            &picks,
            qty,
            &catalog.locale,
        );
        // The slots first; then a pick still wanting its bread.
        q.pick_needs = Self::pick_needs(&catalog, &picks);
        if let (true, Some(need)) = (q.complete, q.pick_needs.first()) {
            q.complete = false;
            q.refusal = Some(COMBO_PICK_CHOICE_REQUIRED.to_string());
            q.refusal_text = Some(need_text(need, &catalog.items, &catalog.locale));
        }
        Ok(q)
    }

    /// The combo line for `picks`, priced, or the refusal in the teller's
    /// words. A combo not on sale now is refused (`combo.unavailable`).
    fn resolve_combo(
        &self,
        combo_id: &str,
        picks: &[ComboPickInput],
        qty: i64,
        notes: Option<String>,
    ) -> Result<cart::StoredLine, crate::error::CoreError> {
        let catalog = self.catalog()?;
        let (def, item) = Self::combo_of(&catalog, combo_id)?;
        let at = self.combo_at(&catalog);
        let view = catalog_pricing::combo_view_for(def, item, &catalog.pricing);
        if let Err(why) = availability(&view, &catalog.items, &at) {
            return Err(crate::error::CoreError::Validation {
                field: String::new(),
                detail: why_text(&why, &catalog.locale),
            });
        }
        let line = cart::resolve_combo_line(
            def,
            item,
            &catalog.items,
            &catalog.addons,
            &catalog.pricing,
            picks,
            qty,
            notes,
        )
        .map_err(|r| crate::error::CoreError::Validation {
            field: String::new(),
            detail: refusal_text(&r, def, &catalog.items, &catalog.locale),
        })?;
        // A pick still wanting a required choice with no default (a
        // sandwich's bread) never reaches the cart, whichever path asks
        // (COMBO_PICK_CHOICE_REQUIRED).
        if let Some(need) = Self::pick_needs(&catalog, picks).first() {
            return Err(crate::error::CoreError::Validation {
                field: String::new(),
                detail: need_text(need, &catalog.items, &catalog.locale),
            });
        }
        Ok(line)
    }

    /// Add a combo line (identical combos merge their quantity).
    pub fn cart_add_combo(
        &self,
        table_id: Option<String>,
        combo_id: String,
        picks: Vec<ComboPickInput>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<cart::CartLineView>, crate::error::CoreError> {
        let line = self.resolve_combo(&combo_id, &picks, qty, notes)?;
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        let lines = cart::add_resolved(&self.store, table_id.as_deref(), line)?;
        drop(_guard);
        self.lines_with_deals_settled(table_id.as_deref(), lines)
    }

    /// Replace the line keyed `line_key` with a combo in one write: an edited
    /// combo, or "make it a meal" turning an item line into its combo.
    pub fn cart_replace_combo(
        &self,
        table_id: Option<String>,
        line_key: String,
        combo_id: String,
        picks: Vec<ComboPickInput>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<Vec<cart::CartLineView>, crate::error::CoreError> {
        let line = self.resolve_combo(&combo_id, &picks, qty, notes)?;
        let _guard = self.cart_ops.lock().unwrap_or_else(|e| e.into_inner());
        let lines = cart::replace_resolved(&self.store, table_id.as_deref(), &line_key, line)?;
        drop(_guard);
        self.lines_with_deals_settled(table_id.as_deref(), lines)
    }

    /// A combo line in the cart as a draft to edit on the sheet.
    pub fn cart_combo_draft(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<ComboDraft, crate::error::CoreError> {
        let (combo_id, picks, qty, notes) = cart::combo_picks(&self.store, table_id.as_deref(), &line_key)?
            .ok_or_else(|| crate::error::CoreError::Validation {
                field: "line".into(),
                detail: "that line is no longer in the cart".into(),
            })?;
        Ok(ComboDraft {
            combo_id,
            line_key: Some(line_key),
            qty,
            notes,
            picks,
        })
    }

    /// "Make it a meal" from an item line (C14): the item's combo with the
    /// line's item, size and add-ons in its slot, the defaults elsewhere, at
    /// the line's quantity. The host opens the sheet with it and saves with
    /// `cart_replace_combo`.
    pub fn cart_make_it_a_meal(
        &self,
        table_id: Option<String>,
        line_key: String,
    ) -> Result<ComboDraft, crate::error::CoreError> {
        let line = cart::lines(&self.store, table_id.as_deref())?
            .into_iter()
            .find(|l| l.key == line_key)
            .ok_or_else(|| crate::error::CoreError::Validation {
                field: "line".into(),
                detail: "that line is no longer in the cart".into(),
            })?;
        let pick = pick_of(
            &line.item_id,
            line.size_label.clone(),
            line.addons
                .iter()
                .map(|a| AddonSelection { addon_item_id: a.addon_item_id.clone(), qty: a.qty })
                .collect(),
            line.optionals.iter().map(|o| o.optional_field_id.clone()).collect(),
            None,
        );
        self.meal_draft_for(&line.item_id, pick, line.qty, line.notes.clone(), Some(line_key))
    }

    /// "Make it a meal" from the item sheet, before the item is in the cart:
    /// the item as configured there, in its combo.
    pub fn item_meal_draft(
        &self,
        item_id: String,
        size_label: Option<String>,
        addons: Vec<AddonSelection>,
        optional_field_ids: Vec<String>,
        qty: i64,
        notes: Option<String>,
    ) -> Result<ComboDraft, crate::error::CoreError> {
        let pick = pick_of(&item_id, size_label, addons, optional_field_ids, None);
        self.meal_draft_for(&item_id, pick, qty, notes, None)
    }

    fn meal_draft_for(
        &self,
        item_id: &str,
        pick: ComboPickInput,
        qty: i64,
        notes: Option<String>,
        line_key: Option<String>,
    ) -> Result<ComboDraft, crate::error::CoreError> {
        let catalog = self.catalog()?;
        let invalid = || crate::error::CoreError::Validation {
            field: String::new(),
            detail: i18n::tr(&catalog.locale, "meal.target_invalid"),
        };
        let item = catalog.items.iter().find(|i| i.id == item_id).ok_or_else(invalid)?;
        let at = self.combo_at(&catalog);
        meal_draft(
            item,
            pick,
            qty,
            notes,
            line_key,
            &catalog.meals,
            &catalog.combos,
            &catalog.items,
            &catalog.pricing,
            &at,
        )
        .ok_or_else(invalid)
    }
}

impl crate::MadarCore {
    /// A cart line as the round's single-dish kitchen chits (the fire print):
    /// one per dish — a combo's items each tagged with it (C12). The time is
    /// the branch's; the teller is the signed-in person.
    pub fn kitchen_chits_for_line(
        &self,
        line: cart::CartLineView,
        table_label: Option<String>,
        ticket_ref: Option<String>,
    ) -> Vec<crate::receipt::KitchenChit> {
        let loc = self.current_locale();
        let at = crate::timefmt::format(
            &self.store,
            &self.corrected_now().to_rfc3339(),
            crate::timefmt::TimeStyle::Time,
            &loc,
        );
        let teller = self
            .current_session()
            .map(|s| s.display_name)
            .filter(|n| !n.trim().is_empty());
        crate::receipt::chits_for_cart_line(&line, table_label, ticket_ref, at, teller, &loc)
    }
}
