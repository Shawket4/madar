//! Every key the app ASKS for must exist here.
//!
//! `tr` falls back to returning the key itself, so a key that was never added
//! renders `order.remove_line` on a real screen in front of a real customer.
//! Nothing catches that: the parity test next door only proves `en` and `ar`
//! agree with each other, which a key missing from BOTH satisfies perfectly.
//!
//! Worse, five Dart tables (`charge_strings`, `kds_strings`, `history_strings`,
//! `queue_strings`, `words.dart`) carry their own English+Arabic fallbacks and
//! serve them through `trOr`, so a key missing from the core does not even show
//! as a raw key — it shows as untranslated English to an Arabic teller, which
//! is the exact complaint that keeps coming back.
//!
//! So this reads the Dart sources and fails on any key they ask for that this
//! crate cannot answer, in either locale. It is the only test that can see the
//! gap, because it is the only one that looks at both sides.

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

/// The Flutter workspace, from this crate's manifest.
fn dart_root() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .ancestors()
        .nth(3)
        .expect("crates/madar-core is three deep under the repo root")
        .to_path_buf()
}

fn dart_files(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for e in entries.flatten() {
        let p = e.path();
        let name = e.file_name();
        let name = name.to_string_lossy();
        if p.is_dir() {
            // Generated bindings carry no authored strings, and a test file
            // may legitimately assert on a key that does not exist.
            if matches!(
                name.as_ref(),
                "test"
                    | "build"
                    | ".dart_tool"
                    | "generated"
                    | "rust_bridge_dashboard"
                    | "rust_bridge_staff"
                    | "cargokit"
            ) {
                continue;
            }
            dart_files(&p, out);
        } else if name.ends_with(".dart") && !name.ends_with("_test.dart") {
            out.push(p);
        }
    }
}

/// Keys asked for with a STRING LITERAL. A key built at runtime
/// (`'delivery.${o.status}'`) cannot be checked here and is skipped — those
/// are covered by the enum-ish tests in i18n.rs itself.
fn keys_in(src: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    // `tr(key: 'x')`, `trOr(('x', 'y'))`, and the (key, fallback) records the
    // Dart string tables are written as.
    for (idx, _) in src.match_indices('\'') {
        let rest = &src[idx + 1..];
        let Some(end) = rest.find('\'') else { continue };
        let lit = &rest[..end];
        if lit.len() < 3 || lit.len() > 64 {
            continue;
        }
        // A key is `family.name` in lower snake: never a sentence, never a
        // path, never interpolated.
        if !lit.contains('.') || lit.contains(' ') || lit.contains('$') || lit.contains('/') {
            continue;
        }
        if !lit
            .chars()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '.' || c == '_')
        {
            continue;
        }
        // An identifier, not a word: `debugLabel: 'kds.stack'`,
        // `ValueKey('bill.table_actions')`.
        let before = src[..idx].trim_end();
        if before.ends_with("debugLabel:") || before.ends_with("Key(") {
            continue;
        }
        // Two or three dotted segments, each non-empty.
        let parts: Vec<&str> = lit.split('.').collect();
        if parts.len() < 2 || parts.len() > 3 || parts.iter().any(|p| p.is_empty()) {
            continue;
        }
        out.insert(lit.to_string());
    }
    out
}

/// The source with `//` / `///` comment lines removed.
fn strip_line_comments(src: &str) -> String {
    src.lines()
        .filter(|l| !l.trim_start().starts_with("//"))
        .collect::<Vec<_>>()
        .join("\n")
}

/// The families this crate owns. A dotted literal outside them is something
/// else entirely — a filename, a version, a package id — and asserting on it
/// would make this test fail for reasons that have nothing to do with strings.
fn is_ours(key: &str) -> bool {
    let family = key.split('.').next().unwrap_or_default();
    madar_core::i18n::tr("en", &format!("{family}.__probe__")) != format!("{family}.__probe__")
        || KNOWN_FAMILIES.contains(&family)
}

const POS_DART_ROOTS: &[&str] = &["packages", "apps/madar"];

const KNOWN_FAMILIES: &[&str] = &[
    "order",
    "cart",
    "charge",
    "checkout",
    "bill",
    "bills",
    "tables",
    "floor",
    "waiter",
    "ticket",
    "kds",
    "kitchen",
    "queue",
    "delivery",
    "history",
    "shift",
    "shifts",
    "till",
    "cash",
    "sync",
    "settings",
    "setup",
    "auth",
    "home",
    "chrome",
    "common",
    "err",
    "void",
    "drafts",
    "loyalty",
    "receipt",
    "search",
    "reservations",
    "booking",
    "bookings",
    "transfer",
    "sell",
    "print",
    "printing",
    "notif",
    "nav",
    "role",
    "toggle",
    "login",
    "brand",
    "me",
    "tender",
    "shifts",
    "combo",
    "meal",
    "deal",
];

#[test]
fn every_key_the_app_asks_for_exists_in_both_locales() {
    let root = dart_root();
    let mut files = Vec::new();
    // The POS side only: `apps/dashboard` and `apps/staff` carry their own
    // bundled JSON string tables (their `Strings.t`) and never ask this crate,
    // and their bridges' packages are excluded for the same reason.
    for sub in POS_DART_ROOTS {
        dart_files(&root.join(sub), &mut files);
    }
    assert!(
        files.len() > 100,
        "only found {} dart files under {} — the scanner is looking in the wrong place, \
         and a green run would mean nothing",
        files.len(),
        root.display()
    );

    let mut checked: BTreeSet<String> = BTreeSet::new();
    let mut missing: Vec<String> = Vec::new();
    for f in &files {
        let Ok(src) = std::fs::read_to_string(f) else {
            continue;
        };
        // Doc-comment examples (`/// t('history.load_failed')`) are prose.
        let src = strip_line_comments(&src);
        // Every file, not only the ones that spell `tr(key:`: a screen that
        // wraps the bridge in a local `t('…')` / `_tr('…')` / `_w('…')`
        // helper asks for keys just the same, and the old filter skipped
        // exactly those files — five missing keys hid behind it. `is_ours`
        // keeps an unrelated dotted literal (an icon name) out.
        for key in keys_in(&src) {
            if !is_ours(&key) {
                continue;
            }
            checked.insert(key.clone());
            for locale in ["en", "ar"] {
                if madar_core::i18n::tr(locale, &key) == key {
                    let rel = f.strip_prefix(&root).unwrap_or(f);
                    missing.push(format!("{key} ({locale}) · {}", rel.display()));
                }
            }
        }
    }
    // If this ever collapses the scanner has broken, and a green run would be
    // worth nothing — the app localizes roughly two hundred distinct keys.
    assert!(
        checked.len() > 150,
        "only matched {} keys across {} files — the scanner is broken",
        checked.len(),
        files.len()
    );
    missing.sort();
    missing.dedup();
    assert!(
        missing.is_empty(),
        "{} key(s) the app asks for are not in i18n.rs — each of these renders \
         either the raw key or untranslated English on a real screen:\n  {}",
        missing.len(),
        missing.join("\n  ")
    );
}

/// Keys the app BUILDS at runtime (`'ticket.status.$status'`). The scanner
/// above cannot see them, so each builder prefix is registered here with
/// every value the wire can carry, and each of those keys must exist in both
/// locales. A builder whose prefix is not registered fails the test: adding
/// `'foo.${x}'` in Dart without saying what `x` can be is how a raw key
/// reaches a screen.
const BUILT_KEYS: &[(&str, &[&str])] = &[
    (
        "ticket.status.",
        &["open", "ready", "settled", "voided", "queued"],
    ),
    // An add-on type with no words falls back to order.addon_other in Dart.
    (
        "order.addon_",
        &["milk_type", "coffee_type", "extra", "other"],
    ),
    (
        "delivery.status.",
        &[
            "received",
            "confirmed",
            "preparing",
            "ready",
            "out_for_delivery",
            "delivered",
            "cancelled",
            "rejected",
        ],
    ),
    (
        "delivery.action.",
        &[
            "confirmed",
            "preparing",
            "ready",
            "out_for_delivery",
            "delivered",
        ],
    ),
    ("delivery.mode_", &["auto", "open", "closed"]),
    // The order's delivery channel (`in_mall` | `outside` | `umbrella` | `pickup`).
    ("delivery.", &["in_mall", "outside", "umbrella", "pickup"]),
    (
        "role.",
        &[
            "waiter",
            "teller",
            "branch_manager",
            "org_admin",
            "super_admin",
            "kitchen",
        ],
    ),
    ("settings.routing_", &["kds", "till", "both", "off"]),
];

/// `'family.prefix${…}'` / `'family.prefix$x'` literals: the part before `$`.
fn built_prefixes(src: &str) -> BTreeSet<String> {
    let mut out = BTreeSet::new();
    for (idx, _) in src.match_indices('\'') {
        let rest = &src[idx + 1..];
        let Some(dollar) = rest.find('$') else {
            continue;
        };
        let Some(end) = rest.find('\'') else { continue };
        if dollar > end {
            continue;
        }
        let prefix = &rest[..dollar];
        if prefix.len() < 3
            || !prefix.contains('.')
            || !prefix
                .chars()
                .all(|c| c.is_ascii_lowercase() || c == '.' || c == '_')
        {
            continue;
        }
        out.insert(prefix.to_string());
    }
    out
}

#[test]
fn every_key_the_app_builds_at_runtime_exists_in_both_locales() {
    let root = dart_root();
    let mut files = Vec::new();
    // The POS side only: `apps/dashboard` and `apps/staff` carry their own
    // bundled JSON string tables (their `Strings.t`) and never ask this crate,
    // and their bridges' packages are excluded for the same reason.
    for sub in POS_DART_ROOTS {
        dart_files(&root.join(sub), &mut files);
    }
    let mut seen = BTreeSet::new();
    let mut unregistered = Vec::new();
    for f in &files {
        let Ok(src) = std::fs::read_to_string(f) else {
            continue;
        };
        // Doc-comment examples (`/// t('history.load_failed')`) are prose.
        let src = strip_line_comments(&src);
        for prefix in built_prefixes(&src) {
            let family = prefix.split('.').next().unwrap_or_default();
            if !is_ours(&format!("{family}.x")) {
                continue;
            }
            // Only a builder that feeds `tr` — `'order.$x'` in an event-type
            // `startsWith` is not a key.
            let asks = src.contains(&format!("tr(key: '{prefix}$"))
                || src.contains(&format!("(key: '{prefix}$"));
            if !asks {
                continue;
            }
            seen.insert(prefix.clone());
            if !BUILT_KEYS.iter().any(|(p, _)| *p == prefix) {
                let rel = f.strip_prefix(&root).unwrap_or(f);
                unregistered.push(format!("{prefix}… · {}", rel.display()));
            }
        }
    }
    assert!(
        unregistered.is_empty(),
        "Dart builds keys from these prefixes, but BUILT_KEYS does not say what \
         can follow them — register every wire value:\n  {}",
        unregistered.join("\n  ")
    );
    assert!(
        seen.len() >= 5,
        "only saw {} key builders — the scanner is broken",
        seen.len()
    );

    let mut missing = Vec::new();
    for (prefix, values) in BUILT_KEYS {
        for v in *values {
            let key = format!("{prefix}{v}");
            for locale in ["en", "ar"] {
                if madar_core::i18n::tr(locale, &key) == key {
                    missing.push(format!("{key} ({locale})"));
                }
            }
        }
    }
    assert!(
        missing.is_empty(),
        "runtime-built keys missing from i18n.rs:\n  {}",
        missing.join("\n  ")
    );
}

/// `rust_bridge/lib/src/failure.dart` swaps the core's English refusal details
/// for keys. A detail reworded here would silently stop matching and go back
/// to English on screen, so every detail it lists must still be raised by
/// this crate, word for word.
#[test]
fn every_core_detail_the_app_translates_is_still_raised() {
    let root = dart_root();
    let failure = std::fs::read_to_string(root.join("packages/rust_bridge/lib/src/failure.dart"))
        .expect("failure.dart");
    let start = failure.find("coreDetailKeys = {").expect("the detail map");
    let body = &failure[start..failure[start..].find("};").map(|e| start + e).unwrap()];
    let mut core_src = String::new();
    let src_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("src");
    for e in std::fs::read_dir(&src_dir).unwrap().flatten() {
        if e.path().extension().is_some_and(|x| x == "rs") {
            core_src.push_str(&std::fs::read_to_string(e.path()).unwrap_or_default());
        }
    }
    let mut stale = Vec::new();
    let mut n = 0;
    for line in body.lines() {
        let t = line.trim();
        let Some(rest) = t.strip_prefix('\'') else {
            continue;
        };
        let Some(end) = rest.find("':") else { continue };
        let detail = rest[..end].replace("\\'", "'");
        n += 1;
        if !core_src.contains(&format!("\"{detail}\"")) {
            stale.push(detail);
        }
    }
    assert!(n > 10, "parsed only {n} details — the parser is broken");
    assert!(
        stale.is_empty(),
        "details no longer raised by the core: {stale:?}"
    );
}
