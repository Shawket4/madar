//! The compact menu body (MadarRust v1.15.0, `menu::compact`), turned back into
//! the array [`menu::K_MENU_ITEMS`] has always held.
//!
//! `GET /menu-items?full=true&shape=compact` answers an OBJECT
//! `{shape: "compact-1", items, group_options}`: every attached choice group's
//! options once, in `group_options` keyed by group id, instead of copied into
//! each item's `pricing.groups[i].options`, and without the fields no reader
//! here uses (`org_id`, `image`, `created_at`, `updated_at`). On the prod copy
//! that is 365 KB → 204 KB for 43 items (29 KB → 15 KB gzipped).
//!
//! The till asks for it and, BEFORE the body is stored, puts each group's
//! options back, so every reader of the mirror (the menu projection, the
//! combos, the pricing view and the staff comp built on it, the metrics'
//! names) reads the shape it always read. A server older than v1.15.0 ignores
//! `shape` and answers the array, which is stored exactly as before.
//!
//! Anything else (another `shape`, a group whose options are not in
//! `group_options`, an object without `items`) is never stored half-read: the
//! caller fetches the plain `full=true` array once instead, and says so.
//!
//! [`menu::K_MENU_ITEMS`]: crate::menu::K_MENU_ITEMS

use serde_json::Value;

/// The query pair that opts in to the compact body.
pub(crate) const QUERY: (&str, &str) = ("shape", "compact");

/// The one compact revision this till reads. A later revision gets a new
/// marker on the server, and this till falls back to the plain array for it.
pub(crate) const SHAPE_V1: &str = "compact-1";

/// The rows to store for a `full=true` menu answer: the body itself when it is
/// the plain array (an older server, or one that ignored `shape`), the
/// compact body with every group's options put back, or why it cannot be read
/// (the caller then fetches the plain array).
pub(crate) fn rows_to_store(body: String) -> Result<String, String> {
    match body.trim_start().as_bytes().first() {
        // The plain array, stored as today, byte for byte.
        Some(b'[') => Ok(body),
        Some(b'{') => expand(&body),
        _ => Err("the menu answer is neither an array nor an object".into()),
    }
}

/// The compact object as the plain array: `group.options = group_options[group.id]`
/// on every item's `pricing.groups`.
fn expand(body: &str) -> Result<String, String> {
    let mut doc: Value =
        serde_json::from_str(body).map_err(|e| format!("the menu answer does not parse: {e}"))?;
    match doc.get("shape").and_then(Value::as_str) {
        Some(SHAPE_V1) => {}
        Some(other) => return Err(format!("unknown menu shape {other:?}")),
        None => return Err("a menu object without a shape".into()),
    }
    let options = match doc.get_mut("group_options").map(Value::take) {
        Some(Value::Object(m)) => m,
        _ => return Err("a compact menu without group_options".into()),
    };
    let mut items = match doc.get_mut("items").map(Value::take) {
        Some(Value::Array(items)) => items,
        _ => return Err("a compact menu without items".into()),
    };
    for item in &mut items {
        let Some(groups) = item
            .pointer_mut("/pricing/groups")
            .and_then(Value::as_array_mut)
        else {
            continue;
        };
        for group in groups {
            let id = group
                .get("id")
                .and_then(Value::as_str)
                .ok_or("a pricing group without an id")?;
            let opts = options
                .get(id)
                .filter(|o| o.is_array())
                .ok_or_else(|| format!("group {id} is not in group_options"))?
                .clone();
            group["options"] = opts;
        }
    }
    serde_json::to_string(&items).map_err(|e| e.to_string())
}

#[cfg(test)]
mod tests {
    use serde_json::{json, Value};

    use super::rows_to_store;
    use crate::testkit::{self, Stub, StubResponse};
    use crate::{catalog_pricing, menu};

    /// The same menu as MadarRust v1.15.0 serves it, captured from its own
    /// `tests/menu_full_feed_tests.rs` fixture (three items, two attached
    /// choice groups, a branch size price, recipes, optional fields and
    /// add-on slots): the default array, and `&shape=compact`.
    const DEFAULT: &str = include_str!("../tests/fixtures/menu_full_v1150_default.json");
    const COMPACT: &str = include_str!("../tests/fixtures/menu_full_v1150_compact.json");

    /// What the compact body leaves out on purpose: the fields no reader here
    /// uses.
    const LEFT_OUT: [&str; 4] = ["org_id", "image", "created_at", "updated_at"];

    fn without_left_out(body: &str) -> Value {
        let mut v: Value = serde_json::from_str(body).unwrap();
        for it in v.as_array_mut().unwrap() {
            for k in LEFT_OUT {
                it.as_object_mut().unwrap().remove(k);
            }
        }
        v
    }

    #[test]
    fn the_fixture_is_a_real_pair() {
        let c: Value = serde_json::from_str(COMPACT).unwrap();
        assert_eq!(c["shape"], "compact-1");
        assert!(
            !c["group_options"].as_object().unwrap().is_empty(),
            "the fixture has choice groups"
        );
        let d: Value = serde_json::from_str(DEFAULT).unwrap();
        let with_groups = d
            .as_array()
            .unwrap()
            .iter()
            .filter(|i| i.pointer("/pricing/groups").is_some())
            .count();
        assert!(
            with_groups >= 2,
            "two or more items attach groups (so the options were copied)"
        );
        assert!(COMPACT.len() < DEFAULT.len());
    }

    /// The compact body, expanded, is the stored array the old path produced,
    /// minus only the fields the compact body leaves out.
    #[test]
    fn a_compact_body_expands_to_the_default_array() {
        let stored = rows_to_store(COMPACT.into()).unwrap();
        let stored: Value = serde_json::from_str(&stored).unwrap();
        assert_eq!(stored, without_left_out(DEFAULT));
    }

    #[test]
    fn an_array_from_an_older_server_is_stored_unchanged() {
        assert_eq!(
            rows_to_store(DEFAULT.into()).unwrap(),
            DEFAULT,
            "byte for byte"
        );
        assert_eq!(rows_to_store("[]".into()).unwrap(), "[]");
    }

    #[test]
    fn a_shape_this_till_cannot_read_is_refused_whole() {
        let mut c: Value = serde_json::from_str(COMPACT).unwrap();
        c["shape"] = json!("compact-2");
        assert!(rows_to_store(c.to_string())
            .unwrap_err()
            .contains("compact-2"));

        let mut c: Value = serde_json::from_str(COMPACT).unwrap();
        let first = c["group_options"]
            .as_object()
            .unwrap()
            .keys()
            .next()
            .unwrap()
            .clone();
        c["group_options"].as_object_mut().unwrap().remove(&first);
        assert!(
            rows_to_store(c.to_string()).unwrap_err().contains(&first),
            "a missing group is named"
        );

        for bad in [
            r#"{"items":[]}"#,
            r#"{"shape":"compact-1","items":[]}"#,
            r#"{"shape":"compact-1","group_options":{}}"#,
            "",
            "null",
            "{",
        ] {
            assert!(rows_to_store(bad.into()).is_err(), "{bad:?}");
        }
        assert_eq!(
            rows_to_store(r#"{"shape":"compact-1","items":[],"group_options":{}}"#.into()).unwrap(),
            "[]"
        );
    }

    /// A stub that answers the menu with `compact` when the till asks for the
    /// compact shape and with the plain array otherwise; the rest of the
    /// catalog empty.
    async fn menu_server(compact: String) -> Stub {
        Stub::start(move |r| {
            let p = r.path.as_str();
            if p.starts_with("/menu-items") {
                let body = if p.contains("shape=compact") {
                    compact.clone()
                } else {
                    DEFAULT.to_string()
                };
                Some(StubResponse::text(200, &body))
            } else if p.starts_with("/addon-items") || p.starts_with("/categories") {
                Some(StubResponse::text(200, "[]"))
            } else {
                None
            }
        })
        .await
    }

    fn stored_menu(core: &crate::MadarCore) -> String {
        core.store.kv_get(menu::K_MENU_ITEMS).unwrap().unwrap()
    }

    /// One request, for the compact body, and the mirror holds the array.
    #[tokio::test]
    async fn the_refresh_asks_for_the_compact_body_and_stores_the_array() {
        let stub = menu_server(COMPACT.to_string()).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.refresh_catalog().await.unwrap();
        let seen = stub.requests("/menu-items");
        assert_eq!(seen.len(), 1, "{seen:?}");
        assert!(
            seen[0].path.contains("full=true") && seen[0].path.contains("shape=compact"),
            "{}",
            seen[0].path
        );
        let stored: Value = serde_json::from_str(&stored_menu(&core)).unwrap();
        assert_eq!(stored, without_left_out(DEFAULT));
        assert_eq!(
            core.list_menu_items().unwrap().len(),
            3,
            "the projection reads it"
        );
    }

    /// An older server ignores `shape`: its array is stored as it came.
    #[tokio::test]
    async fn an_older_server_s_array_is_stored_as_it_came() {
        let stub = menu_server(DEFAULT.to_string()).await;
        let core = testkit::online_core(&stub.base, "").await;
        core.refresh_catalog().await.unwrap();
        assert_eq!(stub.requests("/menu-items").len(), 1);
        assert_eq!(stored_menu(&core), DEFAULT);
    }

    /// A shape this till cannot read, or a group missing from
    /// `group_options`: the plain array is fetched once and stored, never a
    /// partial menu.
    #[tokio::test]
    async fn a_bad_shape_falls_back_to_the_plain_array_once() {
        let mut other: Value = serde_json::from_str(COMPACT).unwrap();
        other["shape"] = json!("compact-9");
        let mut holed: Value = serde_json::from_str(COMPACT).unwrap();
        holed["group_options"] = json!({});
        for body in [other.to_string(), holed.to_string()] {
            let stub = menu_server(body).await;
            let core = testkit::online_core(&stub.base, "").await;
            core.refresh_catalog().await.unwrap();
            let seen: Vec<String> = stub
                .requests("/menu-items")
                .into_iter()
                .map(|r| r.path)
                .collect();
            assert_eq!(seen.len(), 2, "{seen:?}");
            assert!(seen[0].contains("shape=compact"));
            assert!(
                seen[1].contains("full=true") && !seen[1].contains("shape="),
                "{}",
                seen[1]
            );
            assert_eq!(stored_menu(&core), DEFAULT, "the plain array, as it came");
        }
    }

    /// The staff comp reads each item's `pricing.groups` with their options.
    /// Over the compact path's mirror and the old path's, every item's view
    /// and every line's comp input are the same, for madar-shared's staff
    /// input vectors (served both ways) and for the captured menu.
    #[test]
    fn a_staff_line_prices_the_same_from_the_compact_and_the_old_path() {
        use madar_catalog::staff::vectors::StaffInputVector;

        let vectors: Vec<StaffInputVector> =
            serde_json::from_str(madar_catalog::vectors::STAFF_INPUT).unwrap();
        assert!(vectors.len() >= 10);
        for v in &vectors {
            // The old path's row, and the compact body the server builds from it.
            let row = json!({"id": v.item.id, "name": v.name, "base_price": 0, "is_active": true,
                             "org_id": testkit::ORG, "created_at": "2026-10-18T00:00:00Z",
                             "updated_at": "2026-10-18T00:00:00Z", "pricing": v.item});
            let old = json!([row]).to_string();
            let compact = compact_of(&old);
            let (from_old, from_compact) = (
                mirror_view(&old, &v.item.id),
                mirror_view(&rows_to_store(compact).unwrap(), &v.item.id),
            );
            assert_eq!(
                from_old, v.item,
                "{}: the mirror read the row's pricing",
                v.name
            );
            assert_eq!(from_compact, from_old, "{}", v.name);
            assert_eq!(
                madar_catalog::staff::comp_input(&from_compact, &v.line),
                v.expected,
                "{}",
                v.name
            );
            assert_eq!(
                madar_money::staff_comp::comp(&madar_catalog::staff::comp_input(
                    &from_compact,
                    &v.line
                )),
                madar_money::staff_comp::comp(&v.expected),
                "{}",
                v.name
            );
        }

        // The captured menu: every item, every size, every pick of a group.
        let old = DEFAULT.to_string();
        let new = rows_to_store(COMPACT.into()).unwrap();
        let d: Value = serde_json::from_str(DEFAULT).unwrap();
        for it in d.as_array().unwrap() {
            let id = it["id"].as_str().unwrap();
            let (a, b) = (mirror_view(&old, id), mirror_view(&new, id));
            assert_eq!(a, b, "{id}");
            let sizes: Vec<Option<String>> = std::iter::once(None)
                .chain(a.sizes.iter().map(|s| Some(s.label.clone())))
                .collect();
            for size in sizes {
                for g in &a.groups {
                    for o in &g.options {
                        let line = madar_catalog::staff::StaffLine {
                            size_label: size.clone(),
                            eligible: true,
                            unit_price: 5000,
                            picks: vec![crate::staff_comp::CompPick {
                                option_id: o.id.clone(),
                                unit_price: o.price as i32,
                                quantity: 1,
                            }],
                            optionals_per_unit: 0,
                            quantity: 2,
                        };
                        let (ia, ib) = (
                            madar_catalog::staff::comp_input(&a, &line),
                            madar_catalog::staff::comp_input(&b, &line),
                        );
                        assert_eq!(ia, ib);
                        assert_eq!(
                            madar_money::staff_comp::comp(&ia),
                            madar_money::staff_comp::comp(&ib)
                        );
                    }
                }
            }
        }
    }

    /// The server's compact transform (MadarRust `menu::compact::build`) over
    /// a default array: each group's options moved to `group_options`, the
    /// four unread fields left out.
    fn compact_of(default: &str) -> String {
        let mut items: Vec<Value> = serde_json::from_str(default).unwrap();
        let mut options = serde_json::Map::new();
        for it in &mut items {
            for k in LEFT_OUT {
                it.as_object_mut().unwrap().remove(k);
            }
            for g in it
                .pointer_mut("/pricing/groups")
                .and_then(Value::as_array_mut)
                .into_iter()
                .flatten()
            {
                let o = g
                    .as_object_mut()
                    .unwrap()
                    .remove("options")
                    .unwrap_or(json!([]));
                options
                    .entry(g["id"].as_str().unwrap().to_string())
                    .or_insert(o);
            }
        }
        json!({"shape": "compact-1", "items": items, "group_options": options}).to_string()
    }

    /// An item's pricing view as the core's own reader of the mirror builds it
    /// (`catalog_pricing::PricingMirror`, what `cart::comp_input` prices from).
    fn mirror_view(stored: &str, id: &str) -> madar_catalog::ItemView {
        let store = crate::store::Store::open("").unwrap();
        store.kv_put(menu::K_MENU_ITEMS, stored).unwrap();
        let item = menu::menu_items(&store, "en")
            .unwrap()
            .into_iter()
            .find(|i| i.id == id)
            .expect("the row projects");
        catalog_pricing::PricingMirror::load(&store)
            .view_for(&item, &[])
            .item
    }
}
