use serde_json::{Value, json};

use super::*;

const FRESH: i64 = 30_000;
const JSON: &[(&str, &str)] = &[("Content-Type", "application/json; charset=utf-8")];

fn headers(h: &[(&str, &str)]) -> Vec<(String, String)> {
    h.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect()
}

fn scope(user: &str) -> CacheScope {
    CacheScope { user: user.into(), org: Some("o1".into()), branch: None }
}

fn get(path: &str, query: &[(&str, &str)]) -> CacheRequest {
    CacheRequest { method: "GET".into(), path: path.into(), query: headers(query), headers: vec![] }
}

fn cache(max_bytes: i64) -> ApiCache {
    let mut c = ApiCache::in_memory(FRESH).unwrap();
    c.max_bytes = max_bytes;
    c
}

fn save(c: &ApiCache, user: &str, req: &CacheRequest, body: &Value, at: i64) {
    c.save(&scope(user), req, &headers(JSON), &serde_json::to_vec(body).unwrap(), at).unwrap();
}

fn saved(c: &ApiCache, user: &str, req: &CacheRequest, zone: Option<&str>) -> Option<(Value, i64)> {
    c.saved(&scope(user), req, zone)
        .unwrap()
        .map(|s| (serde_json::from_slice(&s.body).unwrap(), s.saved_at_ms))
}

#[test]
fn keeps_only_plain_gets() {
    assert!(keepable(&get("/reports/branches/b/sales", &[])));
    assert!(!keepable(&CacheRequest { method: "POST".into(), ..get("/orders", &[]) }));
    assert!(!keepable(&CacheRequest { headers: headers(&[("x-madar-export", "1")]), ..get("/orders", &[]) }));
    for p in ["/auth/me", "/public/menu", "/sync/pull", "/realtime/x", "/devices/me/grants", "/users/pin-suggestion", "/orgs/o1/offline-auth-bundle"] {
        assert!(!keepable(&get(p, &[])), "{p}");
    }
    assert!(keepable(&get("/orgs/o1", &[])));
}

#[test]
fn one_person_at_a_time() {
    let c = cache(DEFAULT_MAX_BYTES);
    let r = get("/orgs/o1", &[]);
    save(&c, "u1", &r, &json!({"a": 1}), 10);
    // Nobody claimed it yet: dropped.
    assert_eq!(saved(&c, "u1", &r, None), None);
    c.claim("u1").unwrap();
    save(&c, "u1", &r, &json!({"a": 1}), 10);
    save(&c, "u2", &r, &json!({"a": 2}), 11); // not the owner
    assert_eq!(saved(&c, "u1", &r, None), Some((json!({"a": 1}), 10)));
    assert_eq!(saved(&c, "u2", &r, None), None);
    c.claim("u2").unwrap();
    assert_eq!(saved(&c, "u1", &r, None), None, "another person's answers are wiped");
    save(&c, "u2", &r, &json!({"a": 2}), 12);
    c.wipe().unwrap();
    assert_eq!(saved(&c, "u2", &r, None), None);
    save(&c, "u2", &r, &json!({"a": 3}), 13);
    assert_eq!(saved(&c, "u2", &r, None), None, "after a wipe nothing is saved until a claim");
}

#[test]
fn only_json_bodies_are_saved_and_the_query_order_does_not_matter() {
    let c = cache(DEFAULT_MAX_BYTES);
    c.claim("u1").unwrap();
    let a = get("/x", &[("b", "2"), ("a", "1"), ("a", "0")]);
    c.save(&scope("u1"), &a, &headers(&[("content-type", "text/csv")]), b"a,b", 1).unwrap();
    assert_eq!(saved(&c, "u1", &a, None), None);
    save(&c, "u1", &a, &json!([1]), 2);
    assert!(saved(&c, "u1", &get("/x", &[("a", "1"), ("a", "0"), ("b", "2")]), None).is_some());
    // A name's values keep their order.
    assert_eq!(saved(&c, "u1", &get("/x", &[("a", "0"), ("a", "1"), ("b", "2")]), None), None);
}

#[test]
fn past_its_bound_the_least_recently_used_answers_go() {
    let c = cache(100);
    c.claim("u1").unwrap();
    let body = json!("x".repeat(28)); // 30 bytes
    for (i, p) in ["/a", "/b", "/c"].iter().enumerate() {
        save(&c, "u1", &get(p, &[]), &body, i as i64);
    }
    // /a read again: /b is now the least recently used.
    assert!(saved(&c, "u1", &get("/a", &[]), None).is_some());
    save(&c, "u1", &get("/d", &[]), &body, 4); // 120 bytes: down to 90
    assert!(saved(&c, "u1", &get("/b", &[]), None).is_none());
    for p in ["/a", "/c", "/d"] {
        assert!(saved(&c, "u1", &get(p, &[]), None).is_some(), "{p}");
    }
    save(&c, "u1", &get("/big", &[]), &json!("y".repeat(200)), 5);
    assert!(saved(&c, "u1", &get("/big", &[]), None).is_none(), "past the bound alone: dropped");
}

// ── narrower ranges ────────────────────────────────────────────────────

const B: &str = "11111111-1111-1111-1111-111111111111";

fn drinks(rows: &[(&str, i64, Value)]) -> Value {
    Value::Array(
        rows.iter()
            .map(|(d, q, comp)| json!({"business_date": d, "quantity": q, "comp_minor": comp, "overspent": *q > 1}))
            .collect(),
    )
}

#[test]
fn rows_are_cut_to_the_range_with_every_other_parameter_the_same() {
    let c = cache(DEFAULT_MAX_BYTES);
    c.claim("u1").unwrap();
    let wide = get("/staff-pool/drinks", &[("from", "2026-10-01"), ("to", "2026-10-08"), ("branch_id", B)]);
    save(&c, "u1", &wide, &drinks(&[("2026-10-08", 1, json!(500)), ("2026-10-03", 2, json!(null)), ("2026-10-01", 1, json!(100))]), 50);
    let sub = get("/staff-pool/drinks", &[("branch_id", B), ("from", "2026-10-02"), ("to", "2026-10-08")]);
    assert_eq!(
        saved(&c, "u1", &sub, None),
        Some((drinks(&[("2026-10-08", 1, json!(500)), ("2026-10-03", 2, json!(null))]), 50))
    );
    // Another branch, or a range past the one held: not derived.
    let other = get("/staff-pool/drinks", &[("branch_id", "b2"), ("from", "2026-10-02"), ("to", "2026-10-08")]);
    assert_eq!(saved(&c, "u1", &other, None), None);
    let wider = get("/staff-pool/drinks", &[("branch_id", B), ("from", "2026-09-30"), ("to", "2026-10-08")]);
    assert_eq!(saved(&c, "u1", &wider, None), None);
    // The summary from the list.
    let summary = get("/staff-pool/drinks/summary", &[("branch_id", B), ("from", "2026-10-02"), ("to", "2026-10-08")]);
    let (s, _) = saved(&c, "u1", &summary, None).unwrap();
    assert_eq!(
        s,
        json!({"drinks": 2, "quantity": 3, "overspent": 1, "comp_minor": 500, "extras_minor": 0,
               "cost_minor": 0, "comp_mismatches": 0, "unpriced": 1})
    );
}

#[test]
fn a_kept_row_is_the_bytes_the_server_sent() {
    let c = cache(DEFAULT_MAX_BYTES);
    c.claim("u1").unwrap();
    let wide = get("/staff/attendance", &[("from", "2026-10-01"), ("to", "2026-10-08")]);
    // Re-encoded, the keys would sort and a long float could move a digit.
    let body = br#"[{"n":5.0,"lat":30.091473536413375,"business_date":"2026-10-02"},{"business_date":"2026-10-07"}]"#;
    c.save(&scope("u1"), &wide, &headers(JSON), body, 1).unwrap();
    let sub = get("/staff/attendance", &[("from", "2026-10-02"), ("to", "2026-10-02")]);
    let got = c.saved(&scope("u1"), &sub, None).unwrap().unwrap();
    assert_eq!(got.body, br#"[{"n":5.0,"lat":30.091473536413375,"business_date":"2026-10-02"}]"#);
}

#[test]
fn offline_the_later_saved_wins() {
    let c = cache(DEFAULT_MAX_BYTES);
    c.claim("u1").unwrap();
    let exact = get("/staff/attendance", &[("from", "2026-10-02"), ("to", "2026-10-02")]);
    let wide = get("/staff/attendance", &[("from", "2026-10-01"), ("to", "2026-10-08")]);
    let row = |n: &str| json!([{"business_date": "2026-10-02", "name": n}]);
    save(&c, "u1", &exact, &row("old"), 10);
    save(&c, "u1", &wide, &row("new"), 20);
    assert_eq!(saved(&c, "u1", &exact, None), Some((row("new"), 20)));
    save(&c, "u1", &exact, &row("newest"), 30);
    assert_eq!(saved(&c, "u1", &exact, None), Some((row("newest"), 30)));
}

/// The period picker's bounds for the Cairo days `first..=last`: madar-time's
/// day bounds at Cairo's real offset on those days (+03 in summer, +02 in winter).
fn cairo(first: &str, last: &str) -> [(&'static str, String); 2] {
    let day = |s: &str| chrono::NaiveDate::parse_from_str(s, "%Y-%m-%d").unwrap();
    let (start, _) = madar_time::day_bounds(madar_time::DEFAULT_ZONE, day(first));
    [("from", iso_ms(start)), ("to", iso_ms(madar_time::last_instant_of_day(madar_time::DEFAULT_ZONE, day(last))))]
}

/// `2026-10-01T21:00:00.000Z`, the shape the period picker sends.
fn iso_ms(at: chrono::DateTime<chrono::Utc>) -> String {
    at.to_rfc3339_opts(chrono::SecondsFormat::Millis, true)
}

fn series_req(id: &str, g: &str, from: &str, to: &str) -> CacheRequest {
    let mut q = vec![("granularity".to_string(), g.to_string())];
    q.extend(cairo(from, to).map(|(k, v)| (k.to_string(), v)));
    CacheRequest { query: q, ..get(&format!("/reports/branches/{id}/sales/timeseries"), &[]) }
}

#[test]
fn timeseries_points_of_whole_local_days_in_the_named_zone() {
    // Summer days (UTC+3: 1 Oct starts at 30 Sep 21:00Z) and winter days
    // (UTC+2: 14 Jan starts at 13 Jan 22:00Z) alike.
    for [d1, d2, d3] in [["2026-01-14", "2026-01-15", "2026-01-16"], ["2026-10-01", "2026-10-02", "2026-10-03"]] {
        let c = cache(DEFAULT_MAX_BYTES);
        c.claim("u1").unwrap();
        let points = json!([{"period": d1, "net": 1}, {"period": d2, "net": 2}, {"period": d3, "net": 3}]);
        save(&c, "u1", &series_req(B, "daily", d1, d3), &points, 5);
        assert_eq!(
            saved(&c, "u1", &series_req(B, "daily", d2, d3), Some("Africa/Cairo")).map(|s| s.0),
            Some(json!([{"period": d2, "net": 2}, {"period": d3, "net": 3}])),
            "{d1}"
        );
    }
    let c = cache(DEFAULT_MAX_BYTES);
    c.claim("u1").unwrap();
    let points = json!([{"period": "2026-10-01", "net": 1}, {"period": "2026-10-02", "net": 2}, {"period": "2026-10-03", "net": 3}]);
    save(&c, "u1", &series_req(B, "daily", "2026-10-01", "2026-10-03"), &points, 5);
    let sub = series_req(B, "daily", "2026-10-02", "2026-10-03");
    assert_eq!(saved(&c, "u1", &sub, None), None, "no zone: never guessed");
    assert_eq!(saved(&c, "u1", &sub, Some("UTC")), None, "not whole days there");
    let mut late = sub.clone();
    // 01:00 on 2 Oct in Cairo.
    let second = chrono::NaiveDate::from_ymd_opt(2026, 10, 2).unwrap();
    let one_am = madar_time::testing::wall(madar_time::DEFAULT_ZONE, second, "01:00");
    late.query[1].1 = iso_ms(one_am);
    assert_eq!(saved(&c, "u1", &late, Some("Africa/Cairo")), None, "a range must start at a local midnight");
    // Monthly points are never cut by days.
    save(&c, "u1", &series_req(B, "monthly", "2026-10-01", "2026-10-03"), &json!([]), 6);
    assert_eq!(saved(&c, "u1", &series_req(B, "monthly", "2026-10-02", "2026-10-02"), Some("Africa/Cairo")), None);
    assert_eq!(zone_branch(&sub.path), Some(Some(B.to_string())));
    assert_eq!(zone_branch(&format!("/reports/branches/{ALL}/sales/timeseries", ALL = crate::reports::ALL_BRANCHES_ID)), Some(None));
    assert_eq!(zone_branch("/staff/attendance"), None);
}

#[test]
fn online_a_live_wider_answer_answers_once_within_the_stale_time() {
    let c = cache(DEFAULT_MAX_BYTES);
    c.claim("u1").unwrap();
    let wide = get("/staff/attendance", &[("from", "2026-10-01"), ("to", "2026-10-08")]);
    let sub = get("/staff/attendance", &[("from", "2026-10-02"), ("to", "2026-10-02")]);
    let rows = json!([{"business_date": "2026-10-02"}, {"business_date": "2026-10-05"}]);
    save(&c, "u1", &wide, &rows, 1_000);
    let s = scope("u1");
    let got = c.recent(&s, &sub, 2_000, None).unwrap();
    assert_eq!(serde_json::from_slice::<Value>(&got).unwrap(), json!([{"business_date": "2026-10-02"}]));
    assert_eq!(c.recent(&s, &sub, 3_000, None), None, "asked again: a refetch, to the server");
    let other = get("/staff/attendance", &[("from", "2026-10-05"), ("to", "2026-10-05")]);
    assert_eq!(c.recent(&s, &other, 1_000 + FRESH, None), None, "past the stale time");
    save(&c, "u1", &wide, &rows, 40_000);
    assert_eq!(c.recent(&s, &wide, 41_000, None), None, "never its own answer");
    c.forget_recent();
    assert_eq!(c.recent(&s, &other, 41_000, None), None, "forgotten after a write");
}
