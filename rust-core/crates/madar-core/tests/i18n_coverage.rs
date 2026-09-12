//! Regression guard for `src/i18n.rs`'s two string tables (`en` / `ar`).
//!
//! This exists because the localisation gap that prompted this test was never
//! a translation typo — it was keys silently missing from one table (or
//! both), which `tr` swallows by handing the raw key back to the screen
//! (`order.subtotal` rendered verbatim). `en`/`ar` themselves are private, so
//! this integration test parses the same `"key" => value` shape straight out
//! of the source (mirroring the crate's own inline coverage test in
//! `src/i18n.rs`) and cross-checks it through the public `tr` API.
//!
//! Run: `cd rust-core && cargo test -p madar-core --test i18n_coverage`

use std::collections::BTreeSet;

const I18N_SRC: &str = include_str!("../src/i18n.rs");

/// Extract the `"key" =>` literals from one `fn`'s body in the source. We
/// slice between the function's signature and the next top-level `fn ` so a
/// dispatch arm elsewhere in the file (e.g. `tr`'s `"ar" => ar(key)`) can't
/// leak in.
fn keys_in_fn<'a>(src: &'a str, fn_sig: &str) -> BTreeSet<&'a str> {
    let start = src
        .find(fn_sig)
        .unwrap_or_else(|| panic!("function signature not found: {fn_sig}"));
    let after = &src[start + fn_sig.len()..];
    let end = after.find("\nfn ").unwrap_or(after.len());
    let body = &after[..end];

    let mut keys = BTreeSet::new();
    for line in body.lines() {
        let t = line.trim_start();
        if let Some(rest) = t.strip_prefix('"') {
            if let Some(close) = rest.find('"') {
                let key = &rest[..close];
                let tail = rest[close + 1..].trim_start();
                if tail.starts_with("=>") {
                    keys.insert(key);
                }
            }
        }
    }
    keys
}

fn en_keys() -> BTreeSet<&'static str> {
    keys_in_fn(I18N_SRC, "fn en(key: &str) -> Option<&'static str> {")
}

fn ar_keys() -> BTreeSet<&'static str> {
    keys_in_fn(I18N_SRC, "fn ar(key: &str) -> Option<&'static str> {")
}

/// A value that is legitimately identical in `en` and `ar` — not a sign that
/// nobody translated it. Keep this list short and justified per entry.
const ALLOWED_IDENTICAL: &[&str] = &[
    // A phone-number format hint ("01x xxxx xxxx"): digits and placeholder
    // letters, not language content.
    "loyalty.phone_placeholder",
];

#[test]
fn sanity_parser_found_a_realistic_number_of_keys() {
    // Guards the parser itself: if a refactor of i18n.rs changes the table
    // shape enough that `keys_in_fn` stops matching, these two coverage
    // tests would otherwise pass vacuously on empty sets.
    let en = en_keys();
    let ar = ar_keys();
    assert!(en.len() > 200, "parser found too few EN keys: {}", en.len());
    assert!(ar.len() > 200, "parser found too few AR keys: {}", ar.len());
}

#[test]
fn every_en_key_has_an_ar_translation() {
    let en = en_keys();
    let ar = ar_keys();
    let missing: Vec<&str> = en.difference(&ar).copied().collect();
    assert!(
        missing.is_empty(),
        "Dart calls `bridge.tr(key: ...)` for these keys and they resolve in \
         EN but not AR — an Arabic device would render the raw key on \
         screen. Add them to `ar()` in i18n.rs: {missing:?}"
    );
}

#[test]
fn every_ar_key_has_an_en_translation() {
    let en = en_keys();
    let ar = ar_keys();
    let orphans: Vec<&str> = ar.difference(&en).copied().collect();
    assert!(
        orphans.is_empty(),
        "keys present in AR but absent from EN — unreachable via `tr` for an \
         en/unknown locale, and likely a stale or mistyped key: {orphans:?}"
    );
}

#[test]
fn no_ar_value_is_an_unreviewed_copy_of_its_en_value() {
    // A key whose AR string is byte-identical to its EN string is very
    // likely untranslated English masquerading as Arabic — exactly the
    // "not really MENA Arabic" complaint this pass was asked to fix. Genuine
    // exceptions (a fixed placeholder pattern, a currency code, a brand
    // name) go in `ALLOWED_IDENTICAL` with a one-line reason, not a silent
    // skip.
    let en = en_keys();
    let mut unreviewed = Vec::new();
    for key in en {
        if ALLOWED_IDENTICAL.contains(&key) {
            continue;
        }
        let en_val = madar_core::i18n::tr("en", key);
        let ar_val = madar_core::i18n::tr("ar", key);
        if en_val == ar_val {
            unreviewed.push(key);
        }
    }
    assert!(
        unreviewed.is_empty(),
        "these keys have an AR value identical to their EN value — either \
         translate them or add them to ALLOWED_IDENTICAL with a reason: \
         {unreviewed:?}"
    );
}

#[test]
fn every_en_key_resolves_through_the_public_tr_api() {
    // Round-trips every parsed EN key through `tr` for both locales: an en
    // resolution must not degrade to the bare key (that would mean the
    // parser and the real table disagree, or the key is somehow orphaned),
    // and the ar resolution must be non-empty.
    for key in en_keys() {
        let en_val = madar_core::i18n::tr("en", key);
        assert_ne!(en_val, key, "EN key {key} resolved to itself (missing)");
        let ar_val = madar_core::i18n::tr("ar", key);
        assert!(!ar_val.is_empty(), "AR value for {key} is empty");
    }
}
