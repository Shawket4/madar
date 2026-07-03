# Builds madar-frb via Cargokit on Windows. NOTE: path is resolved through the
# flutter ephemeral plugin symlink (8 levels up to Desktop/), and this target
# can only be build-verified on a Windows machine.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "rust_bridge")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../../../../../../../madar/rust-core/crates/madar-frb madar_frb "")

set(rust_bridge_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
