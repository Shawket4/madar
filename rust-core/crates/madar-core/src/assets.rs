//! Content-addressed assets (TILLS_CONTRACT §11.7, §11.10): `<assets dir>/<hash>.<ext>`
//! plus the `asset_files` table. No manifest: the needed set is derived from the
//! hash fields of synced rows (`image_hash`, `logo_hash` → tile `webp`;
//! `animation_hash` → `lottie.zst`). Missing = needed − on disk; unused = on disk −
//! needed, deleted only after a round saved its new files, never while a
//! protected row (one with an active outbox op) still references it.

use std::collections::{BTreeMap, HashSet};
use std::io::Read;
use std::path::{Path, PathBuf};
use std::sync::Mutex;

use rusqlite::params;
use sha2::{Digest, Sha256};

use crate::error::{CoreError, CoreResult};
use crate::store::Store;
use crate::MadarCore;

#[cfg_attr(feature = "uniffi-ffi", derive(uniffi::Record))]
#[derive(Clone, Debug, PartialEq, Eq, Default)]
pub struct AssetSyncView {
    pub needed: u32,
    pub missing: u32,
    pub downloading: bool,
    pub bytes_done: u64,
    pub bytes_total: u64,
    pub last_error: Option<String>,
}

/// Download progress shared by the running round (one device = one round).
static PROGRESS: Mutex<(bool, u64, u64, Option<String>)> = Mutex::new((false, 0, 0, None));

pub(crate) const EXT_IMAGE: &str = "webp";
pub(crate) const EXT_ANIMATION: &str = "lottie.zst";
const TOPUP_CHUNK: usize = 500;

fn is_hash(s: &str) -> bool {
    s.len() == 64 && s.bytes().all(|b| b.is_ascii_hexdigit() && !b.is_ascii_uppercase())
}

fn sha256_hex(bytes: &[u8]) -> String {
    let d = Sha256::digest(bytes);
    d.iter().map(|b| format!("{b:02x}")).collect()
}

fn err(detail: impl Into<String>) -> CoreError {
    CoreError::Internal {
        detail: detail.into(),
    }
}

// ── derivation (pure) ───────────────────────────────────────────────────────

/// Collect `hash -> ext` from every hash field anywhere in a row's JSON.
pub(crate) fn hashes_in(v: &serde_json::Value, out: &mut BTreeMap<String, String>) {
    match v {
        serde_json::Value::Object(m) => {
            for (k, val) in m {
                if let Some(h) = val.as_str().filter(|h| is_hash(h)) {
                    match k.as_str() {
                        "image_hash" | "logo_hash" => {
                            out.insert(h.to_string(), EXT_IMAGE.into());
                        }
                        "animation_hash" => {
                            out.insert(h.to_string(), EXT_ANIMATION.into());
                        }
                        _ => {}
                    }
                } else {
                    hashes_in(val, out);
                }
            }
        }
        serde_json::Value::Array(a) => a.iter().for_each(|x| hashes_in(x, out)),
        _ => {}
    }
}

/// Needed assets for a branch: every hash referenced by its synced rows.
pub(crate) fn needed(store: &Store, branch: &str) -> BTreeMap<String, String> {
    let mut out = BTreeMap::new();
    for (_, _, data) in all_rows(store, branch) {
        hashes_in(&data, &mut out);
    }
    out
}

fn all_rows(store: &Store, branch: &str) -> Vec<(String, String, serde_json::Value)> {
    store
        .with_conn(|c| {
            let mut st = c.prepare("SELECT type, id, data FROM sync_rows WHERE branch_id=?1")?;
            let rows = st
                .query_map([branch], |r| {
                    Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?, r.get::<_, String>(2)?))
                })?
                .collect::<Result<Vec<_>, _>>()?;
            Ok(rows)
        })
        .unwrap_or_default()
        .into_iter()
        .filter_map(|(t, i, d)| serde_json::from_str(&d).ok().map(|v| (t, i, v)))
        .collect()
}

/// Hashes on disk (`asset_files`).
pub(crate) fn on_disk(store: &Store) -> BTreeMap<String, String> {
    store
        .with_conn(|c| {
            let mut st = c.prepare("SELECT hash, ext FROM asset_files")?;
            let rows = st
                .query_map([], |r| Ok((r.get::<_, String>(0)?, r.get::<_, String>(1)?)))?
                .collect::<Result<BTreeMap<_, _>, _>>()?;
            Ok(rows)
        })
        .unwrap_or_default()
}

pub(crate) fn missing(store: &Store, branch: &str) -> BTreeMap<String, String> {
    let have = on_disk(store);
    needed(store, branch)
        .into_iter()
        .filter(|(h, _)| !have.contains_key(h))
        .collect()
}

/// Hashes referenced by rows that have an active outbox op (§10.3 A3). Their
/// files are never evicted even when the current rows no longer need them.
pub(crate) fn protected_hashes(store: &Store, branch: &str) -> HashSet<String> {
    let keys: HashSet<(String, String)> = store
        .list_active()
        .unwrap_or_default()
        .into_iter()
        .filter_map(|i| Some((i.entity_type?, i.entity_id?)))
        .collect();
    let mut out = BTreeMap::new();
    for (t, id, data) in all_rows(store, branch) {
        if keys.contains(&(t, id)) {
            hashes_in(&data, &mut out);
        }
    }
    out.into_keys().collect()
}

pub(crate) fn unused(store: &Store, branch: &str) -> Vec<String> {
    let need = needed(store, branch);
    let keep = protected_hashes(store, branch);
    on_disk(store)
        .into_keys()
        .filter(|h| !need.contains_key(h) && !keep.contains(h))
        .collect()
}

// ── files ───────────────────────────────────────────────────────────────────

pub(crate) fn file_name(hash: &str, ext: &str) -> String {
    format!("{hash}.{ext}")
}

/// Write one verified file atomically (tmp + rename) and record it. Returns
/// `false` (nothing written) when the bytes do not hash to `hash`.
pub(crate) fn save_verified(
    store: &Store,
    dir: &Path,
    hash: &str,
    ext: &str,
    bytes: &[u8],
) -> CoreResult<bool> {
    if !is_hash(hash) || sha256_hex(bytes) != hash {
        return Ok(false);
    }
    std::fs::create_dir_all(dir).map_err(|e| err(format!("assets dir: {e}")))?;
    let dest = dir.join(file_name(hash, ext));
    let tmp = dir.join(format!(".{hash}.tmp"));
    std::fs::write(&tmp, bytes).map_err(|e| err(format!("write: {e}")))?;
    std::fs::rename(&tmp, &dest).map_err(|e| err(format!("rename: {e}")))?;
    store.with_conn(|c| {
        c.execute(
            "INSERT INTO asset_files(hash, ext, bytes, verified_at) VALUES(?1,?2,?3,?4)
             ON CONFLICT(hash) DO UPDATE SET ext=excluded.ext, bytes=excluded.bytes, verified_at=excluded.verified_at",
            params![hash, ext, bytes.len() as i64, chrono::Utc::now().to_rfc3339()],
        )?;
        Ok(())
    })?;
    Ok(true)
}

/// Delete the given hashes' files + rows (and any decompressed cache).
pub(crate) fn evict(store: &Store, dir: &Path, hashes: &[String]) -> CoreResult<u32> {
    let disk = on_disk(store);
    let mut n = 0;
    for h in hashes {
        if let Some(ext) = disk.get(h) {
            let _ = std::fs::remove_file(dir.join(file_name(h, ext)));
            let _ = std::fs::remove_file(dir.join("cache").join(format!("{h}.json")));
            store.with_conn(|c| {
                c.execute("DELETE FROM asset_files WHERE hash=?1", [h])?;
                Ok(())
            })?;
            n += 1;
        }
    }
    Ok(n)
}

/// Unpack a (bundle or top-up) ustar: `index.json` first, then `<hash>.<ext>`.
/// Every entry is hash-verified; corrupt ones are discarded. Returns
/// `(saved, rejected, index_missing)`.
pub(crate) fn unpack_tar(
    store: &Store,
    dir: &Path,
    tar: &[u8],
) -> CoreResult<(Vec<String>, Vec<String>, Vec<String>)> {
    let mut saved = Vec::new();
    let mut rejected = Vec::new();
    let mut index_missing = Vec::new();
    let mut off = 0usize;
    while off + 512 <= tar.len() {
        let hdr = &tar[off..off + 512];
        if hdr.iter().all(|b| *b == 0) {
            break;
        }
        let name = String::from_utf8_lossy(&hdr[..100])
            .trim_end_matches('\0')
            .to_string();
        let size_txt = String::from_utf8_lossy(&hdr[124..136]);
        let size = usize::from_str_radix(size_txt.trim_matches(|c: char| c == '\0' || c == ' '), 8)
            .map_err(|_| err("tar: bad size"))?;
        let start = off + 512;
        let end = start + size;
        if end > tar.len() {
            return Err(err("tar: truncated"));
        }
        let body = &tar[start..end];
        let typeflag = hdr[156];
        if typeflag == b'0' || typeflag == 0 {
            if name == "index.json" {
                if let Ok(v) = serde_json::from_slice::<serde_json::Value>(body) {
                    if let Some(m) = v.get("missing").and_then(|m| m.as_array()) {
                        index_missing = m
                            .iter()
                            .filter_map(|x| x.as_str().map(str::to_string))
                            .collect();
                    }
                }
            } else if let Some((hash, ext)) = name.split_once('.') {
                if save_verified(store, dir, hash, ext, body)? {
                    saved.push(hash.to_string());
                } else {
                    rejected.push(hash.to_string());
                }
            }
        }
        off = start + size.div_ceil(512) * 512;
    }
    Ok((saved, rejected, index_missing))
}

/// Resumable download: `fetch(offset)` returns the next chunk from `offset`
/// (empty = end). Bytes land in `partial_path`; the received count is kept in kv
/// `assets:bundle_partial:<file_name>` so a restart resumes. Returns the whole
/// body once its sha256 matches `sha256` (partial state cleared); a mismatch
/// discards the partial so the next round starts over.
pub(crate) async fn download_resumable<F, Fut>(
    store: &Store,
    file_name: &str,
    partial_path: &Path,
    sha256: &str,
    mut fetch: F,
) -> CoreResult<Vec<u8>>
where
    F: FnMut(u64) -> Fut,
    Fut: std::future::Future<Output = CoreResult<Vec<u8>>>,
{
    let key = format!("assets:bundle_partial:{file_name}");
    let mut done: u64 = store
        .kv_get(&key)?
        .and_then(|v| v.parse().ok())
        .unwrap_or(0);
    let on_disk = std::fs::metadata(partial_path).map(|m| m.len()).unwrap_or(0);
    if on_disk < done {
        done = on_disk; // never trust a count the file does not back
    }
    if let Some(p) = partial_path.parent() {
        std::fs::create_dir_all(p).map_err(|e| err(format!("dir: {e}")))?;
    }
    {
        let f = std::fs::OpenOptions::new()
            .create(true)
            .write(true)
            .truncate(false)
            .open(partial_path)
            .map_err(|e| err(format!("open: {e}")))?;
        f.set_len(done).map_err(|e| err(format!("truncate: {e}")))?;
    }
    loop {
        let chunk = fetch(done).await?;
        if chunk.is_empty() {
            break;
        }
        use std::io::Write;
        let mut f = std::fs::OpenOptions::new()
            .append(true)
            .open(partial_path)
            .map_err(|e| err(format!("open: {e}")))?;
        f.write_all(&chunk).map_err(|e| err(format!("append: {e}")))?;
        done += chunk.len() as u64;
        store.kv_put(&key, &done.to_string())?;
        if let Ok(mut p) = PROGRESS.lock() {
            p.1 = done;
        }
    }
    let body = std::fs::read(partial_path).map_err(|e| err(format!("read: {e}")))?;
    let _ = std::fs::remove_file(partial_path);
    store.kv_delete(&key)?;
    if sha256_hex(&body) != sha256.to_ascii_lowercase() {
        return Err(err("bundle sha256 mismatch"));
    }
    Ok(body)
}

/// A `.lottie.zst` asset decompressed for the player, cached as
/// `<dir>/cache/<hash>.json` on first use.
pub(crate) fn lottie_json_path(dir: &Path, hash: &str) -> CoreResult<Option<PathBuf>> {
    let src = dir.join(file_name(hash, EXT_ANIMATION));
    if !src.exists() {
        return Ok(None);
    }
    let out = dir.join("cache").join(format!("{hash}.json"));
    if out.exists() {
        return Ok(Some(out));
    }
    let raw = std::fs::read(&src).map_err(|e| err(format!("read: {e}")))?;
    let mut dec = ruzstd::decoding::StreamingDecoder::new(&raw[..])
        .map_err(|e| err(format!("zstd: {e}")))?;
    let mut json = Vec::new();
    dec.read_to_end(&mut json)
        .map_err(|e| err(format!("zstd: {e}")))?;
    std::fs::create_dir_all(out.parent().unwrap()).map_err(|e| err(format!("dir: {e}")))?;
    let tmp = out.with_extension("tmp");
    std::fs::write(&tmp, &json).map_err(|e| err(format!("write: {e}")))?;
    std::fs::rename(&tmp, &out).map_err(|e| err(format!("rename: {e}")))?;
    Ok(Some(out))
}

// ── MadarCore ───────────────────────────────────────────────────────────────

impl MadarCore {
    pub(crate) fn assets_dir(&self) -> PathBuf {
        let db = Path::new(&self.config.db_path);
        match db.parent().filter(|_| !self.config.db_path.is_empty()) {
            Some(p) => p.join("assets"),
            None => std::env::temp_dir().join(format!("madar-assets-{}", self.lan_device_id())),
        }
    }

    fn asset_branch(&self) -> String {
        self.current_session()
            .and_then(|s| s.branch_id)
            .unwrap_or_default()
    }

    /// Local file for an asset hash (tile image, or the decompressed Lottie JSON).
    pub fn local_path_for_hash(&self, hash: String) -> Option<String> {
        let dir = self.assets_dir();
        let ext = on_disk(&self.store).get(&hash)?.clone();
        if ext == EXT_ANIMATION {
            return lottie_json_path(&dir, &hash)
                .ok()
                .flatten()
                .map(|p| p.to_string_lossy().into_owned());
        }
        Some(dir.join(file_name(&hash, &ext)).to_string_lossy().into_owned())
    }

    pub(crate) fn asset_sync_view(&self) -> AssetSyncView {
        let branch = self.asset_branch();
        let p = PROGRESS.lock().map(|p| p.clone()).unwrap_or_default();
        AssetSyncView {
            needed: needed(&self.store, &branch).len() as u32,
            missing: missing(&self.store, &branch).len() as u32,
            downloading: p.0,
            bytes_done: p.1,
            bytes_total: p.2,
            last_error: p.3,
        }
    }

    async fn post_topup(&self, branch: &str, hashes: &[String]) -> CoreResult<Vec<u8>> {
        let cfg = self.api.config();
        let mut rb = cfg
            .client
            .post(format!("{}/sync/assets", cfg.base_path))
            .json(&serde_json::json!({ "branch_id": branch, "hashes": hashes }));
        if let Some(t) = cfg.bearer_access_token.clone() {
            rb = rb.bearer_auth(t);
        }
        let resp = rb.send().await.map_err(|e| crate::net::classify_reqwest(&e))?;
        let status = resp.status();
        let bytes = resp.bytes().await.map_err(|e| crate::net::classify_reqwest(&e))?;
        if !status.is_success() {
            return Err(crate::net::status_to_error(status.as_u16(), ""));
        }
        Ok(bytes.to_vec())
    }

    async fn get_range(&self, url: &str, from: u64) -> CoreResult<Vec<u8>> {
        let cfg = self.api.config();
        let full = if url.starts_with("http") {
            url.to_string()
        } else {
            format!("{}{}", cfg.base_path, url)
        };
        let mut rb = cfg
            .client
            .get(full)
            .header("Range", format!("bytes={from}-{}", from + 4 * 1024 * 1024 - 1));
        if let Some(t) = cfg.bearer_access_token.clone() {
            rb = rb.bearer_auth(t);
        }
        let resp = rb.send().await.map_err(|e| crate::net::classify_reqwest(&e))?;
        match resp.status().as_u16() {
            416 => Ok(Vec::new()),
            s if (200..300).contains(&s) => {
                let whole = s == 200;
                let b = resp.bytes().await.map_err(|e| crate::net::classify_reqwest(&e))?;
                // A server ignoring Range sends everything: only take what is new.
                Ok(if whole {
                    b.get(from as usize..).map(|x| x.to_vec()).unwrap_or_default()
                } else {
                    b.to_vec()
                })
            }
            s => Err(crate::net::status_to_error(s, "")),
        }
    }

    async fn topup_missing(&self, branch: &str, dir: &Path) -> CoreResult<()> {
        let want: Vec<String> = missing(&self.store, branch).into_keys().collect();
        let retry_key = "assets:missing_retry_at";
        let skip: HashSet<String> = self
            .store
            .kv_get(retry_key)?
            .and_then(|v| serde_json::from_str::<BTreeMap<String, i64>>(&v).ok())
            .unwrap_or_default()
            .into_iter()
            .filter(|(_, at)| *at > chrono::Utc::now().timestamp())
            .map(|(h, _)| h)
            .collect();
        let want: Vec<String> = want.into_iter().filter(|h| !skip.contains(h)).collect();
        let mut later = BTreeMap::new();
        for chunk in want.chunks(TOPUP_CHUNK) {
            let tar = self.post_topup(branch, chunk).await?;
            let (_, _, server_missing) = unpack_tar(&self.store, dir, &tar)?;
            for h in server_missing {
                later.insert(h, chrono::Utc::now().timestamp() + 3600);
            }
        }
        if !later.is_empty() {
            self.store
                .kv_put(retry_key, &serde_json::to_string(&later).unwrap_or_default())?;
        }
        Ok(())
    }

    /// After a pull: base bundle (full pulls) → top-up → evict unused.
    pub(crate) async fn sync_assets_after_pull(
        &self,
        bundle: Option<(String, i64, u64, String)>,
    ) -> CoreResult<()> {
        let branch = self.asset_branch();
        if branch.is_empty() {
            return Ok(());
        }
        let dir = self.assets_dir();
        if let Ok(mut p) = PROGRESS.lock() {
            *p = (true, 0, bundle.as_ref().map(|b| b.2).unwrap_or(0), None);
        }
        let res: CoreResult<()> = async {
            if let Some((url, _seq, _bytes, sha)) = bundle {
                if !missing(&self.store, &branch).is_empty() {
                    let name = url.rsplit('/').next().unwrap_or("bundle.tar").to_string();
                    let partial = dir.join(format!(".{name}.part"));
                    let body = download_resumable(&self.store, &name, &partial, &sha, |off| {
                        self.get_range(&url, off)
                    })
                    .await?;
                    unpack_tar(&self.store, &dir, &body)?;
                }
            }
            self.topup_missing(&branch, &dir).await?;
            // Only now, with this round's files saved, drop what nothing uses.
            let gone = unused(&self.store, &branch);
            evict(&self.store, &dir, &gone)?;
            Ok(())
        }
        .await;
        if let Ok(mut p) = PROGRESS.lock() {
            p.0 = false;
            p.3 = res.as_ref().err().map(|e| e.to_string());
        }
        // The menu snapshot resolves pictures from these files; drop it so the
        // next read sees what this round delivered, and tell the boards.
        self.invalidate_catalog_cache();
        self.store.emit_changes([crate::changes::CATALOG]);
        res
    }

    /// Re-verify local files against their hashes, drop corrupt ones, top up.
    pub async fn repair_assets(&self) -> Result<AssetSyncView, CoreError> {
        let dir = self.assets_dir();
        let mut bad = Vec::new();
        for (h, ext) in on_disk(&self.store) {
            let ok = std::fs::read(dir.join(file_name(&h, &ext)))
                .map(|b| sha256_hex(&b) == h)
                .unwrap_or(false);
            if !ok {
                bad.push(h);
            }
        }
        evict(&self.store, &dir, &bad)?;
        let _ = self.store.kv_delete("assets:missing_retry_at");
        let _ = self.sync_assets_after_pull(None).await;
        Ok(self.asset_sync_view())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn tmpdir(tag: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("madar-assets-test-{tag}-{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&d).unwrap();
        d
    }

    fn put_row(store: &Store, ty: &str, id: &str, data: serde_json::Value) {
        store
            .with_conn(|c| {
                c.execute(
                    "INSERT OR REPLACE INTO sync_rows(type,id,branch_id,seq,data) VALUES(?1,?2,'B',1,?3)",
                    params![ty, id, data.to_string()],
                )?;
                Ok(())
            })
            .unwrap();
    }

    fn tar_of(entries: &[(&str, &[u8])]) -> Vec<u8> {
        let mut out = Vec::new();
        for (name, body) in entries {
            let mut h = [0u8; 512];
            h[..name.len()].copy_from_slice(name.as_bytes());
            h[100..107].copy_from_slice(b"0000644");
            let size = format!("{:011o}", body.len());
            h[124..135].copy_from_slice(size.as_bytes());
            h[156] = b'0';
            h[257..262].copy_from_slice(b"ustar");
            out.extend_from_slice(&h);
            out.extend_from_slice(body);
            out.resize(out.len().div_ceil(512) * 512, 0);
        }
        out.extend_from_slice(&[0u8; 1024]);
        out
    }

    #[test]
    fn needed_missing_unused_derived_from_rows() {
        let store = Store::open("").unwrap();
        let img = sha256_hex(b"img");
        let anim = sha256_hex(b"anim");
        let old = sha256_hex(b"old");
        put_row(&store, "menu_item", "m1", serde_json::json!({"image_hash": img,
            "recipe_steps": [{"animation_hash": anim}, {"animation_hash": null}]}));
        put_row(&store, "branch_settings", "B", serde_json::json!({"logo_hash": null}));
        let dir = tmpdir("derive");
        assert!(save_verified(&store, &dir, &img, EXT_IMAGE, b"img").unwrap());
        assert!(save_verified(&store, &dir, &old, EXT_IMAGE, b"old").unwrap());
        let need = needed(&store, "B");
        assert_eq!(need.get(&img).map(String::as_str), Some("webp"));
        assert_eq!(need.get(&anim).map(String::as_str), Some("lottie.zst"));
        assert_eq!(need.len(), 2);
        assert_eq!(missing(&store, "B").into_keys().collect::<Vec<_>>(), vec![anim]);
        assert_eq!(unused(&store, "B"), vec![old]);
    }

    #[test]
    fn topup_verifies_hash_and_rejects_corrupt() {
        let store = Store::open("").unwrap();
        let dir = tmpdir("topup");
        let good = sha256_hex(b"good");
        let bad = sha256_hex(b"expected");
        let idx = serde_json::json!({"files": [], "missing": ["ab"]}).to_string();
        let tar = tar_of(&[
            ("index.json", idx.as_bytes()),
            (&format!("{good}.webp"), b"good"),
            (&format!("{bad}.webp"), b"tampered"),
        ]);
        let (saved, rejected, miss) = unpack_tar(&store, &dir, &tar).unwrap();
        assert_eq!(saved, vec![good.clone()]);
        assert_eq!(rejected, vec![bad.clone()]);
        assert_eq!(miss, vec!["ab".to_string()]);
        assert!(dir.join(format!("{good}.webp")).exists());
        assert!(!dir.join(format!("{bad}.webp")).exists());
        assert!(!on_disk(&store).contains_key(&bad));
    }

    #[tokio::test]
    async fn bundle_download_resumes_from_partial() {
        let store = Store::open("").unwrap();
        let dir = tmpdir("resume");
        let body: Vec<u8> = (0..10_000u32).map(|i| (i % 251) as u8).collect();
        let sha = sha256_hex(&body);
        let part = dir.join("b.part");
        // First attempt dies after 4000 bytes.
        let b1 = body.clone();
        let r = download_resumable(&store, "b.tar", &part, &sha, |off| {
            let b1 = b1.clone();
            async move {
                if off >= 4000 {
                    return Err(err("connection reset"));
                }
                Ok(b1[off as usize..(off as usize + 2000)].to_vec())
            }
        })
        .await;
        assert!(r.is_err());
        assert_eq!(store.kv_get("assets:bundle_partial:b.tar").unwrap().as_deref(), Some("4000"));
        // Second attempt must ask from 4000, not 0.
        let asked = std::sync::Arc::new(Mutex::new(Vec::new()));
        let a2 = asked.clone();
        let b2 = body.clone();
        let got = download_resumable(&store, "b.tar", &part, &sha, move |off| {
            a2.lock().unwrap().push(off);
            let b2 = b2.clone();
            async move { Ok(b2[(off as usize).min(b2.len())..].iter().take(3000).copied().collect()) }
        })
        .await
        .unwrap();
        assert_eq!(asked.lock().unwrap()[0], 4000);
        assert_eq!(got, body);
        assert!(store.kv_get("assets:bundle_partial:b.tar").unwrap().is_none());
    }

    #[test]
    fn unused_deleted_only_after_new_saved() {
        let store = Store::open("").unwrap();
        let dir = tmpdir("evict");
        let old = sha256_hex(b"old");
        let new = sha256_hex(b"new");
        save_verified(&store, &dir, &old, EXT_IMAGE, b"old").unwrap();
        put_row(&store, "menu_item", "m1", serde_json::json!({"image_hash": new}));
        // The round: save the new file FIRST, then evict. Before saving, the old
        // file is still on disk (the item keeps a picture until the new one lands).
        assert!(dir.join(format!("{old}.webp")).exists());
        let tar = tar_of(&[(&format!("{new}.webp"), b"new")]);
        unpack_tar(&store, &dir, &tar).unwrap();
        let gone = unused(&store, "B");
        assert_eq!(gone, vec![old.clone()]);
        evict(&store, &dir, &gone).unwrap();
        assert!(dir.join(format!("{new}.webp")).exists());
        assert!(!dir.join(format!("{old}.webp")).exists());
    }

    #[test]
    fn protected_row_asset_not_deleted() {
        let store = Store::open("").unwrap();
        let dir = tmpdir("protect");
        let h = sha256_hex(b"pic");
        save_verified(&store, &dir, &h, EXT_IMAGE, b"pic").unwrap();
        // The row still names the hash, but only via a locally-changed row whose
        // op is queued; even if another row stops needing it, it is kept.
        put_row(&store, "discount", "d1", serde_json::json!({"image_hash": h}));
        store
            .enqueue(&crate::store::NewOutboxOp {
                id: "op1".into(),
                op_type: "x".into(),
                idempotency_key: "op1".into(),
                payload: "{}".into(),
                event_at: "t".into(),
                entity_type: Some("discount".into()),
                entity_id: Some("d1".into()),
                ..Default::default()
            })
            .unwrap();
        assert!(protected_hashes(&store, "B").contains(&h));
        assert!(unused(&store, "B").is_empty());
    }

    #[test]
    fn lottie_zst_decompressed_for_player() {
        let store = Store::open("").unwrap();
        let dir = tmpdir("lottie");
        let json = br#"{"v":"5.7","fr":30,"layers":[]}"#;
        let zst = ruzstd::encoding::compress_to_vec(
            &json[..],
            ruzstd::encoding::CompressionLevel::Fastest,
        );
        let h = sha256_hex(&zst);
        assert!(save_verified(&store, &dir, &h, EXT_ANIMATION, &zst).unwrap());
        let p = lottie_json_path(&dir, &h).unwrap().unwrap();
        assert_eq!(std::fs::read(&p).unwrap(), json.to_vec());
        assert!(p.ends_with(format!("cache/{h}.json")));
        // Evicting the asset removes its cache too.
        evict(&store, &dir, &[h.clone()]).unwrap();
        assert!(!p.exists());
    }
}
