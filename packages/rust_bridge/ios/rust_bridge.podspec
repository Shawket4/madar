Pod::Spec.new do |s|
  s.name             = 'rust_bridge'
  s.version          = '0.1.0'
  s.summary          = 'Madar POS Rust core FFI (madar-frb) built via Cargokit.'
  s.description      = <<-DESC
Builds the madar-frb Rust crate (flutter_rust_bridge wrapper over madar-core)
and links it into the app. No Objective-C/Swift sources beyond a forwarder.
                       DESC
  s.homepage         = 'https://madar.example'
  s.license          = { :type => 'UNLICENSED' }
  s.author           = { 'Madar' => 'dev@madar.example' }

  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.swift_version = '5.0'

  s.script_phase = {
    :name => 'Build Rust library',
    # args: relative path to the crate dir, rust library name
    :script => 'sh "$PODS_TARGET_SRCROOT/../cargokit/build_pod.sh" ../../../rust-core/crates/madar-frb madar_frb',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ["${BUILT_PRODUCTS_DIR}/libmadar_frb.a"],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libmadar_frb.a',
    # force_load pins EVERY object from the staticlib and a dylib exports all
    # public symbols by default — so nothing is dead-strippable. Exporting
    # ONLY the flutter_rust_bridge surface turns the rest into dead-strip
    # fodder (matches the Android cdylib link, several MB smaller).
    'EXPORTED_SYMBOLS_FILE' => '${PODS_TARGET_SRCROOT}/exports_apple.txt',
    'DEAD_CODE_STRIPPING' => 'YES',
  }
end
