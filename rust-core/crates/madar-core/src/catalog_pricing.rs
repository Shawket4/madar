//! The catalogue as the pricing rule reads it, from the menu mirror.
//!
//! A line is priced by madar-shared's `madar-catalog` — the server's own rule
//! (size price, swaps charged over the recipe's own choice, add-ons, optional
//! fields) — over a [`CatalogView`]. The server ships the view's two halves in
//! the rows this device already mirrors: every `/menu-items?full=true` row
//! carries its `ItemView` as `pricing`, every add-on row (`/addon-items`, the
//! `addon_item` feed rows) its `OptionView`. [`PricingMirror`] holds them.
//!
//! A row from a server that predates the field has no `pricing`; for it the
//! view is built from the legacy fields ([`legacy_item`], [`legacy_option`]):
//! the swap families inferred from the add-on type, the recipe's lines as
//! mirrored, the item's own price (`base_price`: the branch's item price, else
//! its lowest size) for a line with no size. That is the best reading of the
//! same rule the older server applies.

use std::collections::HashMap;

use madar_catalog::{
    BaseCandidate, BaseCandidates, CatalogView, IngredientLine, ItemView, OptionView, OptionalView,
    RecipeLine, SizeView,
};
use serde_json::Value;

use crate::menu::{self, AddonItemView, MenuItemView};
use crate::store::Store;

/// The `pricing` of every mirrored menu row and add-on row, by id.
#[derive(Clone, Debug, Default)]
pub(crate) struct PricingMirror {
    items: HashMap<String, ItemView>,
    options: HashMap<String, OptionView>,
}

impl PricingMirror {
    /// Read the mirror. A row that does not parse, or carries no `pricing`,
    /// is simply absent (its view comes from the legacy fields).
    pub(crate) fn load(store: &Store) -> Self {
        let rows = |key: &str| -> Vec<Value> {
            store
                .kv_get(key)
                .ok()
                .flatten()
                .and_then(|raw| serde_json::from_str::<Vec<Value>>(&raw).ok())
                .unwrap_or_default()
        };
        let items = rows(menu::K_MENU_ITEMS)
            .iter()
            .filter(|r| r.get("deleted_at").is_none_or(Value::is_null))
            .filter_map(madar_catalog::feed::item_of)
            .map(|v| (v.id.clone(), v))
            .collect();
        let options = rows(menu::K_ADDONS)
            .iter()
            .filter_map(madar_catalog::feed::option_of)
            .map(|v| (v.id.clone(), v))
            .collect();
        Self { items, options }
    }

    /// The rule's view of `item`, over the add-ons this till offers.
    pub(crate) fn view_for(&self, item: &MenuItemView, addons: &[AddonItemView]) -> CatalogView {
        let options: Vec<OptionView> = addons
            .iter()
            .map(|a| {
                self.options
                    .get(&a.id)
                    .cloned()
                    .unwrap_or_else(|| legacy_option(a))
            })
            .collect();
        let item = match self.items.get(&item.id) {
            Some(v) => madar_catalog::feed::with_fresh_candidates(v.clone(), &options),
            None => legacy_item(item, addons),
        };
        CatalogView { item, options }
    }
}

/// An option from the legacy `/addon-items` fields: its type, price and
/// ingredient lines (no group: the swap family is the type's).
pub(crate) fn legacy_option(a: &AddonItemView) -> OptionView {
    OptionView {
        id: a.id.clone(),
        name: a.name.clone(),
        kind: a.addon_type.clone(),
        price: a.default_price_minor,
        ingredients: a
            .ingredients
            .iter()
            .map(|i| IngredientLine {
                id: i.org_ingredient_id.clone(),
                name: i.ingredient_name.clone(),
                unit: i.unit.clone(),
            })
            .collect(),
        ..Default::default()
    }
}

/// An item from the legacy `/menu-items?full=true` fields.
pub(crate) fn legacy_item(item: &MenuItemView, addons: &[AddonItemView]) -> ItemView {
    let mut sizes: Vec<SizeView> = item
        .sizes
        .iter()
        .map(|s| SizeView {
            label: s.label.clone(),
            price: Some(s.price_minor),
            is_active: s.is_active,
            branch_price: None,
        })
        .collect();
    if sizes.is_empty() {
        // The legacy projection hides the synthetic `one_size` row.
        sizes.push(SizeView {
            label: "one_size".into(),
            price: Some(item.base_price_minor),
            is_active: true,
            branch_price: None,
        });
    }

    // A recipe line without a size (a hand-built catalogue) applies to every
    // size the item or its recipe names.
    let mut recipe_labels: Vec<String> = Vec::new();
    for r in &item.recipes {
        if let Some(l) = &r.size_label {
            if !recipe_labels.contains(l) {
                recipe_labels.push(l.clone());
            }
        }
    }
    let mut every_label = recipe_labels.clone();
    for s in &sizes {
        if !every_label.contains(&s.label) {
            every_label.push(s.label.clone());
        }
    }
    let recipe: Vec<RecipeLine> = item
        .recipes
        .iter()
        .flat_map(|r| {
            let labels = match &r.size_label {
                Some(l) => vec![l.clone()],
                None => every_label.clone(),
            };
            labels.into_iter().map(move |size_label| RecipeLine {
                size_label,
                category: Some(r.category.clone()).filter(|c| !c.is_empty()),
                ingredient_id: r.org_ingredient_id.clone(),
            })
        })
        .collect();
    // The recipe a sizeless line is made from: the item's first size (active
    // first) that the recipe names, else the recipe's first size.
    let default_recipe_size = if item.recipes.is_empty() {
        None
    } else {
        let mut ordered: Vec<&SizeView> = sizes.iter().collect();
        ordered.sort_by_key(|s| !s.is_active);
        ordered
            .iter()
            .map(|s| s.label.clone())
            .find(|l| recipe_labels.contains(l))
            .or_else(|| recipe_labels.first().cloned())
            .or_else(|| ordered.first().map(|s| s.label.clone()))
    };

    // Each recipe ingredient's candidates: the add-ons carrying it, active
    // first, in catalogue order.
    let mut ingredients: Vec<String> = Vec::new();
    for r in &item.recipes {
        if let Some(i) = &r.org_ingredient_id {
            if !ingredients.contains(i) {
                ingredients.push(i.clone());
            }
        }
    }
    let mut ordered_addons: Vec<&AddonItemView> = addons.iter().collect();
    ordered_addons.sort_by_key(|a| !a.is_active);
    let bases = ingredients
        .into_iter()
        .filter_map(|ing| {
            let candidates: Vec<BaseCandidate> = ordered_addons
                .iter()
                .filter(|a| {
                    a.ingredients
                        .iter()
                        .any(|i| i.org_ingredient_id.as_deref() == Some(ing.as_str()))
                })
                .map(|a| BaseCandidate {
                    option_id: a.id.clone(),
                    name: a.name.clone(),
                    kind: a.addon_type.clone(),
                    price: a.default_price_minor,
                    group_id: None,
                    swap_category_id: None,
                })
                .collect();
            (!candidates.is_empty()).then_some(BaseCandidates {
                ingredient_id: ing,
                candidates,
            })
        })
        .collect();

    ItemView {
        id: item.id.clone(),
        // `base_price` is the server's answer for a line with no size: the
        // branch's item price, else the lowest active size.
        branch_price: Some(item.base_price_minor),
        sizes,
        default_recipe_size,
        recipe,
        bases,
        optionals: item
            .optional_fields
            .iter()
            .filter(|f| f.is_active)
            .map(|f| OptionalView {
                id: f.id.clone(),
                price: f.price_minor,
                size_label: None,
            })
            .collect(),
    }
}

/// Whether option `id` replaces part of the recipe (a swap family: milk,
/// beans, or an explicit `swaps` group) rather than adding to it.
pub(crate) fn is_swap(view: &CatalogView, id: &str) -> bool {
    view.option(id).and_then(madar_catalog::target_of).is_some()
}

/// Whether an add-on TYPE is a swap family by itself (`milk_type`,
/// `coffee_type`) — the legacy slots and groups carry only a type.
pub(crate) fn is_swap_type(addon_type: &str) -> bool {
    madar_catalog::swap_target(Some(addon_type), None, None, None).is_some()
}

/// The first of `options` that is the recipe's own choice on a sizeless line:
/// the option a sheet opens with already chosen.
pub(crate) fn recipe_choice_in<'a>(
    view: &CatalogView,
    options: impl IntoIterator<Item = &'a str>,
) -> Option<String> {
    options
        .into_iter()
        .find(|id| madar_catalog::is_recipe_choice(view, None, id))
        .map(str::to_string)
}

#[cfg(test)]
mod tests {
    //! madar-catalog's vectors (generated from the SERVER's order path) read
    //! through this device's mirror: the feed rows go into the kv mirror the
    //! catalogue refresh writes, and the cart prices every case from there.
    use super::*;
    use crate::cart::{self, AddonSelection, BundleComponentSelection};
    use madar_catalog::vectors::{Expected, Vectors};
    use serde_json::json;

    /// The mirror as the feed leaves it: the `/menu-items` row, and the
    /// `addon_item` rows as `project_pull_mirrors` writes them (an add-on the
    /// branch switched off is not offered).
    fn mirror(menu_item: &Value, addon_rows: &[Value]) -> Store {
        let store = Store::open("").unwrap();
        store
            .kv_put(menu::K_MENU_ITEMS, &json!([menu_item]).to_string())
            .unwrap();
        let offered: Vec<Value> = addon_rows
            .iter()
            .filter(|a| a.get("is_available").and_then(Value::as_bool) != Some(false))
            .map(|a| {
                let mut a = a.clone();
                if let Some(m) = a.as_object_mut() {
                    m.remove("is_available");
                    m.remove("seq");
                }
                a
            })
            .collect();
        store
            .kv_put(menu::K_ADDONS, &Value::Array(offered).to_string())
            .unwrap();
        store
    }

    fn priced_addons(v: &Value) -> Vec<(String, i64, i64)> {
        v.as_array()
            .unwrap()
            .iter()
            .map(|a| {
                (
                    a["addon_item_id"].as_str().unwrap().to_string(),
                    a["price_modifier_minor"].as_i64().unwrap(),
                    a["qty"].as_i64().unwrap(),
                )
            })
            .collect()
    }

    fn priced_optionals(v: &Value) -> Vec<(String, i64)> {
        v.as_array()
            .unwrap()
            .iter()
            .map(|o| {
                (
                    o["optional_field_id"].as_str().unwrap().to_string(),
                    o["price_minor"].as_i64().unwrap(),
                )
            })
            .collect()
    }

    /// `(id, charge, quantity)` per option, `(id, price)` per optional field.
    type Charged = (Vec<(String, i64, i64)>, Vec<(String, i64)>);

    fn expected_options(p: &madar_catalog::PricedOptions) -> Charged {
        (
            p.options
                .iter()
                .map(|o| (o.id.clone(), o.unit_price, o.quantity))
                .collect(),
            p.optionals
                .iter()
                .map(|o| (o.id.clone(), o.price))
                .collect(),
        )
    }

    #[test]
    fn the_mirror_rebuilds_the_servers_view() {
        let v = Vectors::load();
        for fixture in &v.items {
            let store = mirror(&fixture.menu_item, &v.addon_items);
            let items = menu::menu_items(&store, "en").unwrap();
            let addons = menu::addons(&store, "en").unwrap();
            let item = items.iter().find(|i| i.id == fixture.view.id).unwrap();
            let view = PricingMirror::load(&store).view_for(item, &addons);
            assert_eq!(view.item, fixture.view, "{}", fixture.key);
            for o in &view.options {
                assert_eq!(Some(o), v.options.iter().find(|x| x.id == o.id), "{}", o.id);
            }
        }
    }

    /// Every case, priced by the cart from the mirror, is what the server
    /// charges. An option the till does not offer (switched off at the
    /// branch, or unknown) is dropped from the line before it is priced, as
    /// the till always did; an item with no priced size keeps selling at its
    /// mirrored price (the server refuses the sale).
    #[test]
    fn the_cart_prices_every_vector_as_the_server_does() {
        let v = Vectors::load();
        let mut checked = 0;
        for case in &v.cases {
            let fixture = v.item(&case.item);
            let store = mirror(&fixture.menu_item, &v.addon_items);
            let items = menu::menu_items(&store, "en").unwrap();
            let addons = menu::addons(&store, "en").unwrap();
            let pricing = PricingMirror::load(&store);
            let item = items.iter().find(|i| i.id == fixture.view.id).unwrap();
            let sels: Vec<AddonSelection> = case
                .selection
                .options
                .iter()
                .map(|p| AddonSelection {
                    addon_item_id: p.id.clone(),
                    qty: p.quantity,
                })
                .collect();
            let offered = case
                .selection
                .options
                .iter()
                .all(|p| addons.iter().any(|a| a.id == p.id));
            let size = case.selection.size_label.clone();
            if case.part == "component" {
                let bundle = menu::BundleView {
                    id: "b".into(),
                    name: "b".into(),
                    description: None,
                    price_minor: 0,
                    image_url: None,
                    local_image_path: None,
                    is_available: true,
                    available_from_date: None,
                    available_until_date: None,
                    available_from_time: None,
                    available_until_time: None,
                    components: vec![],
                };
                let line = cart::resolve_bundle_line(
                    &bundle,
                    &items,
                    &addons,
                    &pricing,
                    &[BundleComponentSelection {
                        item_id: item.id.clone(),
                        size_label: size,
                        qty: 1,
                        addons: sels,
                        optional_field_ids: case.selection.optionals.clone(),
                    }],
                    1,
                );
                let line = serde_json::to_value(&line).unwrap();
                let comp = &line["bundle_components"][0];
                let Expected::Component(p) = &case.expected else {
                    panic!("{}: {:?}", case.name, case.expected)
                };
                assert!(offered, "{}", case.name);
                let (a, o) = expected_options(p);
                assert_eq!(priced_addons(&comp["addons"]), a, "{}", case.name);
                assert_eq!(priced_optionals(&comp["optionals"]), o, "{}", case.name);
                checked += 1;
                continue;
            }
            let line = cart::resolve_line(
                item,
                &addons,
                &pricing,
                size,
                &sels,
                &case.selection.optionals,
                1,
                None,
            );
            let line = serde_json::to_value(&line).unwrap();
            // The till names an optional field once (the server would charge a
            // repeat again; no till sends one): the rule over what it sends.
            let mut once = case.selection.clone();
            once.optionals.dedup();
            let expected = if once != case.selection {
                Expected::Line(madar_catalog::price_line(&v.view(&case.item), &once).unwrap())
            } else {
                case.expected.clone()
            };
            match &expected {
                Expected::Line(l) if offered => {
                    assert_eq!(
                        line["unit_price_minor"],
                        json!(l.unit_price),
                        "{}",
                        case.name
                    );
                    let (a, o) = expected_options(&l.options);
                    assert_eq!(priced_addons(&line["addons"]), a, "{}", case.name);
                    assert_eq!(priced_optionals(&line["optionals"]), o, "{}", case.name);
                    checked += 1;
                }
                Expected::Line(l) => {
                    // Not offered here: dropped, the rest priced as the server.
                    assert_eq!(
                        line["unit_price_minor"],
                        json!(l.unit_price),
                        "{}",
                        case.name
                    );
                    for a in priced_addons(&line["addons"]) {
                        assert!(addons.iter().any(|x| x.id == a.0), "{}", case.name);
                    }
                }
                Expected::Error(madar_catalog::PriceError::UnknownOption { id }) => {
                    assert!(
                        priced_addons(&line["addons"]).iter().all(|a| &a.0 != id),
                        "{}",
                        case.name
                    );
                }
                Expected::Error(madar_catalog::PriceError::NoPricedSize) => {
                    assert_eq!(
                        line["unit_price_minor"],
                        json!(item.base_price_minor),
                        "{}",
                        case.name
                    );
                }
                other => panic!("{}: {other:?}", case.name),
            }
        }
        assert!(checked >= 45, "only {checked} cases priced end to end");
    }

    /// The recipe preview shows the cup the line is charged for: an explicit
    /// swap group replaces the recipe's line (it used to add a line, as it was
    /// charged in full), the recipe's own choice changes nothing, and a swap
    /// group picked twice shows the last pick once.
    #[test]
    fn the_preview_swaps_what_the_rule_swaps() {
        let v = Vectors::load();
        let preview = |key: &str, size: &str, picks: &[(&str, i64)]| {
            let fixture = v.item(key);
            let store = mirror(&fixture.menu_item, &v.addon_items);
            let items = menu::menu_items(&store, "en").unwrap();
            let addons = menu::addons(&store, "en").unwrap();
            let item = items.iter().find(|i| i.id == fixture.view.id).unwrap();
            let sels: Vec<AddonSelection> = picks
                .iter()
                .map(|(id, q)| AddonSelection {
                    addon_item_id: format!("c0de0000-0000-4000-8000-0000000000{id}"),
                    qty: *q,
                })
                .collect();
            crate::recipe::compute_recipe(
                item,
                &addons,
                &PricingMirror::load(&store),
                Some(size),
                &sels,
                &[],
            )
            .into_iter()
            .map(|r| (r.ingredient_name, r.is_base))
            .collect::<Vec<_>>()
        };
        // Green tea (5d) over the recipe's black tea.
        assert_eq!(
            preview("tea", "Cup", &[("5d", 1)]),
            vec![
                ("Green tea".to_string(), false),
                ("Water".to_string(), true)
            ]
        );
        // Black tea (5c) is the recipe's own: nothing changes.
        assert_eq!(
            preview("tea", "Cup", &[("5c", 1)]),
            vec![("Black tea".to_string(), true), ("Water".to_string(), true)]
        );
        // Two vanilla (5f) and a caramel (60): the caramel, once.
        let syrup = preview("vanilla_latte", "Regular", &[("5f", 2), ("60", 1)]);
        assert!(
            syrup.contains(&("Caramel syrup".to_string(), false)),
            "{syrup:?}"
        );
        assert!(!syrup.iter().any(|r| r.0 == "Vanilla syrup"), "{syrup:?}");
    }
}
