//! Exact answers for a narrower date range, computed from an answer already
//! held for a wider one (the owner's "smart inference": month to date is
//! held, the 1st to the 8th is asked, and every figure of it is in hand).
//!
//! A deriver is registered ONLY where every field of the narrower answer is
//! provably the same as the server's: the wider answer carries a per-day (or
//! finer) breakdown, or the full row list (never a page, never a top-N), and
//! the backend's own query filters by a column every row carries. Totals
//! summed from rows are exact; distinct counts, top-N lists, averages over
//! the range's days and shares of a range total never are. The dashboard's
//! `offline_derivers_test.dart` compares each one with the mock server's own
//! answer over many sub-ranges.
//!
//! Rejected (MadarRust handlers read 2026-10-09), never derived:
//! - `/reports/branches/{id}/sales`: subtotal, service charge, delivery fees,
//!   tips, money in by method and the top items are in no per-day answer;
//! - `.../sales/peak-hours`, `peak-days`, `channel-breakdown`,
//!   `items-combined`, `addons`, `tellers`, `waiters`, `delivery-sales`,
//!   `/reports/orgs/{id}/comparison`, `/reports/bundles`, `/insights/...`
//!   (margin watch, menu margin, repricing): totals over the whole range
//!   (by hour of day, weekday, channel, item, person, branch), no per-day
//!   breakdown;
//! - `waste-report`, `supplier-spend`: grouped over the range;
//!   `po-lead-time`: averages; `material-cost-trend`: "3+ consecutive
//!   rises" read over the range as a whole;
//! - `/staff/attendance/summary`: per person over the range;
//!   `/staff/discipline-report`: distinct day counts;
//! - `/loyalty/liability-trend`: weekly buckets (weeks from Saturday);
//!   `/loyalty/behavior`, `campaign-effectiveness`: range aggregates;
//! - `/orders`, `/inventory/branches/{id}/movements`: paginated;
//!   `/staff/expense-advances`, `/staff/adjustments`: cut at 200/300 rows;
//! - `/staff/requests`: a span-overlap filter (not a column in a range);
//!   `/bookings`: the page asks for one service day by `date`.

use std::collections::BTreeMap;

use chrono::{DateTime, Duration, Utc};
use serde_json::value::RawValue;
use serde_json::{Value, json};

use super::CacheRequest;
use crate::reports::ALL_BRANCHES_ID;

/// How a range's ends are written.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Kind {
    /// `timestamptz` instants (`2026-10-01T21:00:00.000Z`), both ends inclusive.
    Instant,
    /// Calendar dates (`2026-10-01`), both ends inclusive.
    Date,
}

#[derive(Clone, Debug)]
enum Range {
    Instant(DateTime<Utc>, DateTime<Utc>),
    Date(String, String),
}

/// What a narrower request asks for.
pub(super) struct Want<'a> {
    query: &'a [(String, String)],
    range: Range,
    /// The zone the server cuts days in, when known for certain.
    zone: Option<&'a str>,
}

#[derive(Clone, Copy)]
enum Rule {
    /// One point per local day (or hour).
    Timeseries,
    /// Every row whose field lies in the range.
    Rows(&'static str),
    DrinksSummary,
}

pub(super) struct Deriver {
    matches: fn(&str) -> bool,
    /// The endpoint the wider answer comes from, when not the path's own.
    source: Option<&'static str>,
    kind: Kind,
    rule: Rule,
}

/// `/reports/branches/{id}/<tail>`'s branch id.
fn report_branch<'p>(path: &'p str, tail: &str) -> Option<&'p str> {
    let (id, rest) = path.strip_prefix("/reports/branches/")?.split_once('/')?;
    (!id.is_empty() && rest == tail).then_some(id)
}

fn is_timeseries(p: &str) -> bool {
    report_branch(p, "sales/timeseries").is_some()
}
fn is_tills(p: &str) -> bool {
    report_branch(p, "tills").is_some()
}
fn is_drinks(p: &str) -> bool {
    p == "/staff-pool/drinks"
}
fn is_drinks_summary(p: &str) -> bool {
    p == "/staff-pool/drinks/summary"
}
fn is_attendance(p: &str) -> bool {
    p == "/staff/attendance"
}

static DERIVERS: [Deriver; 5] = [
    // MadarRust `branch_sales_timeseries`: see `timeseries`.
    Deriver { matches: is_timeseries, source: None, kind: Kind::Instant, rule: Rule::Timeseries },
    // MadarRust `branch_till_sessions`: tills with `opened_at` in [from, to],
    // every figure the whole till's own, newest first; past 5000 the range is
    // refused, never cut, so an answer is the full list.
    Deriver { matches: is_tills, source: None, kind: Kind::Instant, rule: Rule::Rows("opened_at") },
    // MadarRust `staff_pool/record.rs` `list`: `business_date BETWEEN from AND
    // to`, every row the drink's own, no limit.
    Deriver { matches: is_drinks, source: None, kind: Kind::Date, rule: Rule::Rows("business_date") },
    Deriver {
        matches: is_drinks_summary,
        source: Some("/staff-pool/drinks"),
        kind: Kind::Date,
        rule: Rule::DrinksSummary,
    },
    // MadarRust `list_attendance`: `business_date BETWEEN from AND to`, every
    // row the record's own (`month_closed` is its own month's), no limit.
    // `ORDER BY business_date DESC, lower(name)`: rows tied on both come in no
    // set order from the server either.
    Deriver { matches: is_attendance, source: None, kind: Kind::Date, rule: Rule::Rows("business_date") },
];

fn deriver_for(path: &str) -> Option<&'static Deriver> {
    DERIVERS.iter().find(|d| (d.matches)(path))
}

/// Whether live answers to `path` are held for a deriver to narrow. A deriver
/// reading another endpoint (the drinks summary reads the drinks list) relies
/// on that endpoint having a deriver of its own.
pub(super) fn is_source(path: &str) -> bool {
    deriver_for(path).is_some()
}

pub(super) fn zone_branch(path: &str) -> Option<Option<String>> {
    let id = report_branch(path, "sales/timeseries")?;
    Some((id != ALL_BRANCHES_ID).then(|| id.to_string()))
}

/// The deriver for `req` and what it asks for; `None` when no deriver answers
/// its path or its range is not named properly.
pub(super) fn want<'a>(req: &'a CacheRequest, zone: Option<&'a str>) -> Option<(&'static Deriver, Want<'a>)> {
    let d = deriver_for(&req.path)?;
    let range = range_of(d.kind, &req.query)?;
    Some((d, Want { query: &req.query, range, zone }))
}

/// The only value of `name`, when it is given exactly once.
fn single<'q>(query: &'q [(String, String)], name: &str) -> Option<&'q str> {
    let mut values = query.iter().filter(|(k, _)| k == name);
    let v = values.next()?;
    values.next().is_none().then_some(v.1.as_str())
}

fn param<'q>(query: &'q [(String, String)], name: &str) -> Option<&'q str> {
    query.iter().find(|(k, _)| k == name).map(|(_, v)| v.as_str())
}

fn instant(s: &str) -> Option<DateTime<Utc>> {
    DateTime::parse_from_rfc3339(s).ok().map(|d| d.with_timezone(&Utc))
}

fn is_date(s: &str) -> bool {
    s.len() == 10
        && s.bytes()
            .enumerate()
            .all(|(i, b)| if i == 4 || i == 7 { b == b'-' } else { b.is_ascii_digit() })
}

fn range_of(kind: Kind, query: &[(String, String)]) -> Option<Range> {
    let (from, to) = (single(query, "from")?, single(query, "to")?);
    match kind {
        Kind::Instant => {
            let (a, b) = (instant(from)?, instant(to)?);
            (b >= a).then_some(Range::Instant(a, b))
        }
        Kind::Date => {
            (is_date(from) && is_date(to) && to >= from).then(|| Range::Date(from.to_string(), to.to_string()))
        }
    }
}

/// Every parameter but the range, a name's values in order.
fn others(query: &[(String, String)]) -> BTreeMap<&str, Vec<&str>> {
    let mut out: BTreeMap<&str, Vec<&str>> = BTreeMap::new();
    for (k, v) in query {
        if k != "from" && k != "to" {
            out.entry(k).or_default().push(v);
        }
    }
    out
}

impl Deriver {
    pub(super) fn source_of<'p>(&self, path: &'p str) -> &'p str {
        self.source.unwrap_or(path)
    }

    /// Whether `wider` (another request's query) names a range covering
    /// `want`'s with every other parameter the same.
    pub(super) fn covers(&self, wider: &[(String, String)], want: &Want<'_>) -> bool {
        let Some(r) = range_of(self.kind, wider) else {
            return false;
        };
        others(wider) == others(want.query)
            && match (&r, &want.range) {
                (Range::Instant(a, b), Range::Instant(x, y)) => a <= x && b >= y,
                (Range::Date(a, b), Range::Date(x, y)) => a <= x && b >= y,
                _ => false,
            }
    }

    /// The wider answer `body` narrowed to `want`, as JSON; `None` when this
    /// case is not provably exact. Every rule reads a list. A kept row is its
    /// bytes as the server sent them: re-encoding would move a long float's
    /// last digit.
    pub(super) fn derive(&self, body: &[u8], want: &Want<'_>) -> Option<Vec<u8>> {
        let raw: Vec<&RawValue> = serde_json::from_str(std::str::from_utf8(body).ok()?).ok()?;
        let rows = raw
            .iter()
            .map(|r| serde_json::from_str(r.get()))
            .collect::<Result<Vec<Value>, _>>()
            .ok()?;
        let kept = match self.rule {
            Rule::DrinksSummary => return serde_json::to_vec(&drinks_summary(&rows, want)?).ok(),
            Rule::Rows(field) => in_range(&rows, want, field, self.kind)?,
            Rule::Timeseries => timeseries(&rows, want)?,
        };
        let mut out = b"[".to_vec();
        for (i, r) in kept.into_iter().enumerate() {
            if i > 0 {
                out.push(b',');
            }
            out.extend_from_slice(raw[r].get().as_bytes());
        }
        out.push(b']');
        Some(out)
    }
}

/// The local days `from..=to` covers in `tz` when the range is exactly whole
/// days there: `from` is a local midnight and `to` the last millisecond before
/// one (the period picker's ranges), as madar-time draws days, DST included.
fn whole_local_days(from: DateTime<Utc>, to: DateTime<Utc>, tz: chrono_tz::Tz) -> Option<(String, String)> {
    let first = madar_time::business_date_of(tz, from);
    if madar_time::day_bounds(tz, first).0 != from {
        return None;
    }
    let end = to + Duration::milliseconds(1);
    let next = madar_time::business_date_of(tz, end);
    if madar_time::day_bounds(tz, next).0 != end {
        return None;
    }
    let last = next.pred_opt()?;
    (last >= first).then(|| (first.to_string(), last.to_string()))
}

/// Which rows (by index) have their `field` in `want`'s range; `None` when
/// a row is not an object carrying it.
fn in_range(rows: &[Value], want: &Want<'_>, field: &str, kind: Kind) -> Option<Vec<usize>> {
    let mut out = Vec::new();
    for (i, row) in rows.iter().enumerate() {
        let v = row.as_object()?.get(field)?.as_str()?;
        let inside = match (kind, &want.range) {
            (Kind::Instant, Range::Instant(from, to)) => {
                let at = instant(v)?;
                at >= *from && at <= *to
            }
            (Kind::Date, Range::Date(from, to)) => {
                if !is_date(v) {
                    return None;
                }
                v >= from.as_str() && v <= to.as_str()
            }
            _ => return None,
        };
        if inside {
            out.push(i);
        }
    }
    Some(out)
}

/// `GET /reports/branches/{id}/sales/timeseries` (MadarRust
/// `branch_sales_timeseries`): one point per local day (or hour) that had
/// orders, cut in the scope's zone (the branch's, every branch: the org's),
/// orders filtered `created_at >= from AND created_at <= to`, and every figure
/// of a point summed from that bucket's own orders (refunds are the order's
/// own, whenever made). A range that is whole local days in that zone is
/// exactly the points of those days. Monthly points are not cut by days:
/// never derived.
fn timeseries(points: &[Value], want: &Want<'_>) -> Option<Vec<usize>> {
    let g = param(want.query, "granularity").unwrap_or("daily");
    if g != "daily" && g != "hourly" {
        return None;
    }
    // The zone the caller named for this path's branch; never guessed.
    let tz: chrono_tz::Tz = want.zone?.parse().ok()?;
    let Range::Instant(from, to) = want.range else {
        return None;
    };
    let (first, last) = whole_local_days(from, to, tz)?;
    let mut out = Vec::new();
    for (i, p) in points.iter().enumerate() {
        let day = p.as_object()?.get("period")?.as_str()?.get(..10)?;
        if !is_date(day) {
            return None;
        }
        if day >= first.as_str() && day <= last.as_str() {
            out.push(i);
        }
    }
    Some(out)
}

fn int(v: Option<&Value>) -> i64 {
    match v {
        Some(Value::Number(n)) => n.as_i64().unwrap_or_else(|| n.as_f64().map_or(0, |f| f as i64)),
        _ => 0,
    }
}

fn present(v: Option<&Value>) -> Option<&Value> {
    v.filter(|v| !v.is_null())
}

/// Two JSON values equal as the dashboard reads them (5 and 5.0 are one
/// number).
fn same(a: &Value, b: Option<&Value>) -> bool {
    match (a, b) {
        (Value::Number(x), Some(Value::Number(y))) => x.as_f64() == y.as_f64(),
        (a, Some(b)) => a == b,
        (_, None) => false,
    }
}

/// `GET /staff-pool/drinks/summary` from `GET /staff-pool/drinks` over the same
/// or a wider range (MadarRust `staff_pool/record.rs`): both read the same
/// rows (`business_date BETWEEN from AND to`, the same branch and
/// `overspent_only`), and the summary is counts and `COALESCE(SUM(...), 0)`
/// over them.
fn drinks_summary(rows: &[Value], want: &Want<'_>) -> Option<Value> {
    let kept = in_range(rows, want, "business_date", Kind::Date)?;
    let (mut quantity, mut overspent, mut comp, mut extras, mut cost, mut mismatches, mut unpriced) =
        (0i64, 0i64, 0i64, 0i64, 0i64, 0i64, 0i64);
    for &i in &kept {
        let r = rows[i].as_object()?;
        quantity += int(r.get("quantity"));
        if r.get("overspent") == Some(&Value::Bool(true)) {
            overspent += 1;
        }
        comp += int(r.get("comp_minor"));
        extras += int(r.get("extras_minor"));
        cost += int(r.get("cost_minor"));
        let priced = present(r.get("comp_minor"));
        if present(r.get("comp_minor_reported")).is_some_and(|reported| !same(reported, priced)) {
            mismatches += 1;
        }
        if priced.is_none() {
            unpriced += 1;
        }
    }
    Some(json!({
        "drinks": kept.len(),
        "quantity": quantity,
        "overspent": overspent,
        "comp_minor": comp,
        "extras_minor": extras,
        "cost_minor": cost,
        "comp_mismatches": mismatches,
        "unpriced": unpriced,
    }))
}
