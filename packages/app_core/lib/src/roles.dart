/// What a signed-in person does, as far as the screens need to branch on it —
/// derived from their effective capabilities (`bridge.can`), never the role
/// name, so an owner's custom role behaves the way its grants say.
library;

import 'package:app_core/src/generated/capabilities.dart';

/// A capability check, usually `(c) => bridge.can(cap: c)`.
typedef CanFn = bool Function(String cap);

/// Whether this person takes money at a till (rings up and charges, or opens a
/// drawer). Someone who does not works tables only: their cart fires a ticket
/// and the bill's Settle is not offered.
bool takesMoney(CanFn can) => can(Cap.paymentsTake) || can(Cap.tillOpen);

/// Whether this person only works the kitchen screen (no selling, no tables).
bool isKitchenOnly(CanFn can) =>
    can(Cap.kitchenDisplayRead) &&
    !can(Cap.ordersCreate) &&
    !can(Cap.ticketsOpen);
