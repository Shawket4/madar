/*
 * Kitchen view types. Field names follow madar-shared `madar-kitchen`
 * (`KdsStationView`, `KdsTicketView`, `KdsLineView`); fields marked SPEC are
 * what the target spec adds and the contract does not carry yet. Once the
 * uniffi binding exists these come from it (AT-7) and this file goes.
 */

export type SourceType = "dine_in" | "takeaway" | "online";
export type NetState = "online" | "lan" | "offline";
export type DeviceMode = "sections" | "expo";

export interface Branch {
  id: string;
  name: string;
  nameAr: string;
}

/** A kitchen section — `kitchen_stations` row (KS-1). */
export interface Section {
  id: string;
  name: string;
  nameAr: string;
  isDefault: boolean;
}

export interface KitchenLine {
  id: string;
  name: string;
  /** SPEC: the server localizes `name`; mock data carries both. */
  nameAr: string;
  qty: number;
  sizeLabel?: string;
  modifiers: string[];
  notes?: string;
  bumped: boolean;
  /** SPEC OF-5: struck through, never removed. */
  voided: boolean;
}

/** One section's part of an order (OF-1). */
export interface KitchenPart {
  id: string;
  orderId: string;
  /** Order number shown large. */
  kitchenRef: string;
  sectionId: string;
  sourceType: SourceType;
  tableLabel?: string;
  /** SPEC OF-2 */
  waiter: string;
  roundNumber: number;
  /** ISO time the round was fired. */
  createdAt: string;
  /** SPEC OF-2: the order note. */
  note?: string;
  items: KitchenLine[];
  /** Set when the part was bumped (KB-4); null while open. */
  bumpedAt: string | null;
  /** SPEC DV-3 */
  bumpedBy: string | null;
}

export interface Order {
  id: string;
  kitchenRef: string;
  sourceType: SourceType;
  tableLabel?: string;
  waiter: string;
  /** SPEC EX-4: set by the expo. */
  handedOffAt: string | null;
}

export interface Staff {
  id: string;
  name: string;
  role: "cook" | "manager";
  /** Mock only: the real PIN check is the core's teller login (DV-2). */
  pin: string;
}

export interface DeviceConfig {
  branchId: string;
  mode: DeviceMode;
  sectionIds: string[];
}
