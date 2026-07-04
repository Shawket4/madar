//! Release-size link plumbing: export ONLY the flutter_rust_bridge surface
//! from the cdylib. The UniFFI scaffolding (the archived Kotlin/Swift
//! natives' FFI) would otherwise pin megabytes of dead code as exported
//! symbols; hidden, the linker garbage-collects it.

fn main() {
    let target_os = std::env::var("CARGO_CFG_TARGET_OS").unwrap_or_default();
    let dir = std::env::var("CARGO_MANIFEST_DIR").expect("manifest dir");
    match target_os.as_str() {
        "android" | "linux" => {
            println!("cargo:rustc-link-arg-cdylib=-Wl,--version-script={dir}/exports.map");
            println!("cargo:rustc-link-arg-cdylib=-Wl,--gc-sections");
        }
        "macos" => {
            println!("cargo:rustc-link-arg-cdylib=-Wl,-exported_symbols_list,{dir}/exports_apple.txt");
            println!("cargo:rustc-link-arg-cdylib=-Wl,-dead_strip");
        }
        // iOS links a STATICLIB into the app; export control happens at the
        // app link (Xcode's dead-strip), not here.
        _ => {}
    }
    println!("cargo:rerun-if-changed=exports.map");
    println!("cargo:rerun-if-changed=exports_apple.txt");
}
