# Builds madar-frb-dashboard via Cargokit on Windows.
#
# The crate path is resolved TEXTUALLY through the flutter ephemeral plugin
# symlink, so it has to be counted rather than written the obvious way:
#
#   <repo>/apps/<app>/windows/flutter/ephemeral/.plugin_symlinks/<plugin>/windows
#
# is eight levels below <repo>. It used to be eight levels followed by
# `madar/`, which assumed the checkout's PARENT held a folder of that name --
# true only on the machine it was written on (`~/Desktop/madar`). Anywhere
# else, CI included, it resolved to `<repo>/madar/rust-core/...` and cargokit
# died with a PathNotFoundException that MSBuild reported only as
# `MSB8066 ... exited with code -1`.
cmake_minimum_required(VERSION 3.14)

set(PROJECT_NAME "rust_bridge_dashboard")
project(${PROJECT_NAME} LANGUAGES CXX)

include("../cargokit/cmake/cargokit.cmake")
apply_cargokit(${PROJECT_NAME} ../../../../../../../../rust-core/crates/madar-frb-dashboard madar_frb_dashboard "")

set(rust_bridge_dashboard_bundled_libraries
  "${${PROJECT_NAME}_cargokit_lib}"
  PARENT_SCOPE
)
