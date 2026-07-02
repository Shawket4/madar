/// Madar POS — floor plan and reservations: the to-scale dine-in table
/// map (live free/held/seated/dirty states, start-ticket + settle jumps)
/// and the host board (seat / notify bookings).
///
/// Pixel-and-behavior port of the Kotlin natives' FloorPlanScreen.kt over
/// the shared Rust core.
library;

export 'src/floor_controller.dart' show FloorController;
export 'src/floor_plan_screen.dart' show FloorPlanScreen;
