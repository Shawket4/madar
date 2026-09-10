/// Small shared pieces the incoming feature reuses across its two tabs —
/// the action button + text field (the natives' MadarButton /
/// MadarTextField), the hairline, and the card shell metrics.
library;

// Native metrics (IncomingScreen.kt / DeliveryScreen.kt / WaiterScreen.kt /
// Components.kt) that fall between the 4-pt Space steps — kept verbatim so
// the Flutter chrome measures identically to the Kotlin/Swift natives.

/// Board cards center under this cap (natives: widthIn(max = 620.dp)).
const double kBoardCardMaxWidth = 620;

/// Delivery card status strip height (natives: 50.dp).
const double kDeliveryStripHeight = 50;

/// Ticket card status strip height (natives: 56.dp).
const double kTicketStripHeight = 56;

/// Status dot diameter in the strip (natives: 8.dp).
const double kStatusDot = 8;

/// Person tone-tile on the delivery card (natives: 40.dp).
const double kPersonTile = 40;

/// Person tone-tile on the ticket card (natives: 34.dp).
const double kPersonTileSm = 34;

/// The ⋯ overflow button side (natives: 34.dp).
const double kMenuButton = 34;

/// Money hero pill vertical inset (natives: 7.dp).
const double kMoneyPillVPad = 7;
