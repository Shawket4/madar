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
            if matches!(name.as_ref(), "test" | "build" | ".dart_tool" | "generated") {
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
        // Two or three dotted segments, each non-empty.
        let parts: Vec<&str> = lit.split('.').collect();
        if parts.len() < 2 || parts.len() > 3 || parts.iter().any(|p| p.is_empty()) {
            continue;
        }
        out.insert(lit.to_string());
    }
    out
}

/// The families this crate owns. A dotted literal outside them is something
/// else entirely — a filename, a version, a package id — and asserting on it
/// would make this test fail for reasons that have nothing to do with strings.
fn is_ours(key: &str) -> bool {
    let family = key.split('.').next().unwrap_or_default();
    madar_core::i18n::tr("en", &format!("{family}.__probe__")) != format!("{family}.__probe__")
        || KNOWN_FAMILIES.contains(&family)
}

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
];

#[test]
fn every_key_the_app_asks_for_exists_in_both_locales() {
    let root = dart_root();
    let mut files = Vec::new();
    for sub in ["packages", "apps"] {
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
        // Only files that actually localize; this keeps a stray dotted literal
        // in an unrelated file from being read as a key.
        if !src.contains("tr(key:") && !src.contains("trOr(") && !src.contains("(en:") {
            continue;
        }
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
