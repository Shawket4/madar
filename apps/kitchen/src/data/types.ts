/*
 * Kitchen types. `Ticket`, `Line`, `Branch`, `Section` and `DeviceState` are
 * the binding's own shapes (rust-core/crates/madar-kitchen-ffi, generated into
 * modules/madar-kitchen-core) so the native and mock backends are
 * interchangeable. `KitchenPart` is what the screens draw: one section's share
 * of a ticket (spec OF-1).
 */

export type SourceType = "dine_in" | "takeaway" | "online";
export type NetState = "online" | "lan" | "offline";
export type DeviceMode = "sections" | "expo";
export type Route = "setup" | "login" | "sections" | "board";

export interface Branch {
  id: string;
  name: string;
}

/** A kitchen section — `kitchen_stations` row (KS-1). */
export interface Section {
  id: string;
  name: string;
  isDefault: boolean;
  isActive: boolean;
}

/** Binding `Line`: names arrive localized by the core. */
export interface Line {
  id: string;
  name: string;
  qty: number;
  sizeLabel?: string;
  modifiers: string[];
  notes?: string;
  stationId?: string;
  stationName?: string;
  bumped: boolean;
  comboName?: string;
}

/** Binding `Ticket`: one fired round. */
export interface Ticket {
  id: string;
  kitchenRef?: string;
  tableLabel?: string;
  roundNumber: number;
  /** `order` (counter) | `open_ticket` (waiter) | `online` (mock; not on the server yet, OF-6) */
  sourceType: string;
  /** firing | ready | voided */
  status: string;
  createdAt: string;
  items: Line[];
}

export interface DeviceState {
  route: Route;
  branchId?: string;
  branchName?: string;
  mode: DeviceMode;
  sectionIds: string[];
  userName?: string;
  userRole?: string;
  pending: number;
}

export interface KitchenLine extends Line {
  /** SPEC OF-5: struck through, never removed. The server doesn't send voids yet. */
  voided: boolean;
}

/** One section's part of a ticket (OF-1). */
export interface KitchenPart {
  /** `${ticketId}:${sectionId}` */
  id: string;
  orderId: string;
  /** Order number shown large. */
  kitchenRef: string;
  sectionId: string;
  sourceType: SourceType;
  tableLabel?: string;
  /** SPEC OF-2: not in the kitchen feed yet. */
  waiter?: string;
  roundNumber: number;
  /** ISO time the round was fired. */
  createdAt: string;
  /** SPEC OF-2: the order note; not in the kitchen feed yet. */
  note?: string;
  items: KitchenLine[];
  /** Every line bumped. */
  done: boolean;
}
