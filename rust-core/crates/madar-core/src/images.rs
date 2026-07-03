//! Core-owned catalog image cache — menu/bundle photos + the org logo.
//!
//! The core downloads every catalog image during `refresh_catalog` (after the
//! data mirror commits) and stores the bytes on disk under a directory derived
//! from the db path (`<db_dir>/images/`). The host then renders from LOCAL
//! paths surfaced on the existing views — so every photo is available offline
//! from the first refresh, including items the teller never scrolled to while
//! online, and the Dart side needs no network image stack at all.
//!
//! The FILENAME is the index: a hash of the source URL plus a sensible
//! extension. Existence on disk == cached; there is no DB table.
//! LIMITATION (accepted for V1): the same URL with changed bytes behind it is
//! never re-fetched — dashboards upload new images under new storage URLs in
//! practice, and a changed URL is a different file here.

use std::collections::HashSet;
use std::path::{Path, PathBuf};

use sha2::{Digest, Sha256};

/// Disk store for catalog images. `root == None` (in-memory db) disables it —
/// every operation becomes a cheap no-op and paths resolve to `None`.
pub(crate) struct ImageStore {
    root: Option<PathBuf>,
}

impl ImageStore {
    /// Derive the store root from the sqlite path (`<db_dir>/images/`).
    /// An empty `db_path` (in-memory store) disables the cache entirely.
    pub(crate) fn new(db_path: &str) -> Self {
        let root = if db_path.is_empty() {
            None
        } else {
            Path::new(db_path).parent().map(|d| d.join("images"))
        };
        Self { root }
    }

    /// Deterministic filename for a source URL — the filename IS the index.
    fn file_name(url: &str) -> String {
        let digest = Sha256::digest(url.as_bytes());
        let mut hex = String::with_capacity(24);
        for b in &digest[..12] {
            hex.push_str(&format!("{b:02x}"));
        }
        // Keep a recognizable image extension when the URL path carries one
        // (helps host-side decoders + humans poking at the dir).
        let path_part = url.split(['?', '#']).next().unwrap_or(url);
        let ext = Path::new(path_part)
            .extension()
            .and_then(|e| e.to_str())
            .map(str::to_ascii_lowercase)
            .filter(|e| matches!(e.as_str(), "png" | "jpg" | "jpeg" | "webp" | "gif"))
            .unwrap_or_else(|| "img".into());
        format!("{hex}.{ext}")
    }

    /// The on-disk path for `url` IF it has been downloaded — `None` when the
    /// store is disabled or the file isn't there yet.
    pub(crate) fn path_if_cached(&self, url: &str) -> Option<String> {
        let root = self.root.as_ref()?;
        let p = root.join(Self::file_name(url));
        if p.is_file() {
            Some(p.to_string_lossy().into_owned())
        } else {
            None
        }
    }

    /// Whether `url` is already on disk.
    pub(crate) fn is_cached(&self, url: &str) -> bool {
        self.path_if_cached(url).is_some()
    }

    /// Persist downloaded bytes ATOMICALLY: write to a temp file in the same
    /// directory, then rename over the final name — a crash mid-write can
    /// never leave a torn image where the host would read it.
    pub(crate) fn store(&self, url: &str, bytes: &[u8]) -> std::io::Result<()> {
        let Some(root) = self.root.as_ref() else {
            return Ok(());
        };
        std::fs::create_dir_all(root)?;
        let name = Self::file_name(url);
        let tmp = root.join(format!("{name}.tmp"));
        std::fs::write(&tmp, bytes)?;
        std::fs::rename(&tmp, root.join(name))
    }

    /// Delete cached files whose source URL no longer appears in the fresh
    /// catalog (orphans of deleted/replaced items) — plus any stray `.tmp`
    /// left by an interrupted download.
    pub(crate) fn evict_except(&self, keep_urls: &HashSet<String>) {
        let Some(root) = self.root.as_ref() else {
            return;
        };
        let keep: HashSet<String> = keep_urls.iter().map(|u| Self::file_name(u)).collect();
        let Ok(entries) = std::fs::read_dir(root) else {
            return;
        };
        for entry in entries.flatten() {
            let name = entry.file_name().to_string_lossy().into_owned();
            if name.ends_with(".tmp") || !keep.contains(&name) {
                let _ = std::fs::remove_file(entry.path());
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store() -> (ImageStore, PathBuf) {
        let dir = std::env::temp_dir().join(format!("madar-img-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let db = dir.join("madar.db");
        (ImageStore::new(&db.to_string_lossy()), dir)
    }

    #[test]
    fn file_name_is_stable_and_keeps_image_extensions() {
        let a = ImageStore::file_name("https://cdn.x/menu/latte.PNG?sig=abc");
        let b = ImageStore::file_name("https://cdn.x/menu/latte.PNG?sig=abc");
        assert_eq!(a, b, "same URL must always map to the same file");
        assert!(a.ends_with(".png"), "extension survives (lowercased): {a}");
        assert_ne!(
            a,
            ImageStore::file_name("https://cdn.x/menu/latte.PNG?sig=def"),
            "the query string is part of the identity (signed URLs differ)"
        );
        let odd = ImageStore::file_name("https://cdn.x/blob/8f3a");
        assert!(odd.ends_with(".img"), "no recognizable extension → .img");
    }

    #[test]
    fn in_memory_store_is_fully_disabled() {
        let store = ImageStore::new("");
        assert!(store.store("https://x/a.png", b"bytes").is_ok());
        assert_eq!(store.path_if_cached("https://x/a.png"), None);
        store.evict_except(&HashSet::new()); // must not panic
    }

    #[test]
    fn store_is_atomic_and_leaves_no_temp_files() {
        let (store, dir) = temp_store();
        store.store("https://cdn.x/a.png", b"IMAGE").unwrap();
        let path = store.path_if_cached("https://cdn.x/a.png").expect("cached");
        assert_eq!(std::fs::read(&path).unwrap(), b"IMAGE");
        let leftovers: Vec<_> = std::fs::read_dir(dir.join("images"))
            .unwrap()
            .flatten()
            .filter(|e| e.file_name().to_string_lossy().ends_with(".tmp"))
            .collect();
        assert!(leftovers.is_empty(), "no torn/temp file after a write");
    }

    #[test]
    fn eviction_drops_orphans_and_stray_temps_keeps_live_urls() {
        let (store, dir) = temp_store();
        store.store("https://cdn.x/keep.png", b"K").unwrap();
        store.store("https://cdn.x/gone.png", b"G").unwrap();
        // A stray .tmp from a simulated interrupted download.
        std::fs::write(dir.join("images").join("dead.png.tmp"), b"partial").unwrap();

        let keep: HashSet<String> = ["https://cdn.x/keep.png".to_string()].into();
        store.evict_except(&keep);

        assert!(store.is_cached("https://cdn.x/keep.png"), "live URL kept");
        assert!(!store.is_cached("https://cdn.x/gone.png"), "orphan evicted");
        assert!(
            !dir.join("images").join("dead.png.tmp").exists(),
            "stray temp cleaned"
        );
    }
}
