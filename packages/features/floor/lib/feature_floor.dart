/// Madar POS — floor plan and reservations: the to-scale dine-in table
/// map (live free/held/seated/dirty states, settle jumps) and the host
/// board (seat / notify bookings).
///
/// Pixel-and-behavior port of the Kotlin natives' FloorPlanScreen.kt over
/// the shared Rust core. All state flows from `floorProvider`;
/// `FloorPlanScreen` is paramless per the screen contract.
library;

export 'src/floor_plan_screen.dart' show FloorPlanScreen;
export 'src/floor_provider.dart' show FloorNotifier, FloorState, floorProvider;
