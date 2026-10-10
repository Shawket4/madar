/// The business rules the dashboard shows, computed by madar-shared's crates
/// through the core (`rust-core/crates/madar-frb-dashboard/src/api/rules.rs`):
/// the copy the POS and the backend run. The dashboard's Dart computes none of
/// them; it calls these.
library;

export 'src/generated/api/rules.dart';
