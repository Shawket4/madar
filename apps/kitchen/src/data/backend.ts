import { Platform } from "react-native";

import type { Branch, DeviceMode, DeviceState, Section, Ticket } from "./types";

/**
 * Everything the app asks of the kitchen side. Two implementations:
 * `native-backend` (the Rust core through modules/madar-kitchen-core — the
 * real thing) and `mock-backend` (web, and `EXPO_PUBLIC_MOCK=1`, APP-11).
 */
export interface Backend extends LanBackend {
  readonly mock: boolean;
  state(): DeviceState;
  /**
   * Device setup (DV-1), the only sign-in a kitchen does: the activation code
   * made for this screen in the dashboard's branch plan. No person, no account.
   */
  activate(code: string): Promise<Branch>;
  /** Re-mint the screen's session from its device credential when it is due. */
  ensureSession(): Promise<void>;
  /** Firebase's token, for the push that reaches a screen off the LAN and stream. */
  setPushToken(token: string, locale: string, platform: string): Promise<void>;
  stations(): Promise<Section[]>;
  setSections(mode: DeviceMode, sectionIds: string[]): void;
  clearSections(): void;
  resetDevice(): void;
  /** Every open ticket in the branch, local reads (no network). */
  tickets(): Promise<Ticket[]>;
  bump(lineId: string): Promise<void>;
  unbump(lineId: string): Promise<void>;
  syncNow(): Promise<void>;
  startRealtime(l: { onChange(): void; onConnection(connected: boolean): void; onPing(): void }): Promise<void>;
  stopRealtime(): void;
  setLocale(locale: string): void;
}

export interface LanAdvert {
  deviceId: string;
  branchId: string;
  role: string;
  stationId?: string;
  deviceCode?: string;
  tcpPort: number;
}

export interface LanStatus {
  running: boolean;
  peerCount: number;
  lastError?: string;
}

/** The core's LAN relay (spec LN-1..5): fires from a POS on the same network, no internet needed. */
export interface LanBackend {
  /** Start after a sign-in; needs the branch's LAN key from an online sign-in. */
  lanStart(): Promise<void>;
  lanStop(): void;
  lanStatus(): LanStatus;
  lanAdvert(): LanAdvert | undefined;
  lanNotePeer(p: Omit<LanAdvert, "tcpPort"> & { host: string; port: number }): boolean;
}

/** A refusal or failure, already worded for a person. */
export class KitchenFailure extends Error {
  constructor(message: string, readonly offline = false) {
    super(message);
  }
}

export const useMock = Platform.OS === "web" || process.env.EXPO_PUBLIC_MOCK === "1";

let instance: Backend | null = null;

export function backend(): Backend {
  if (!instance) {
    // Required lazily so the web bundle never loads the native module.
    instance = useMock ? require("./mock-backend").mockBackend() : require("./native-backend").nativeBackend();
  }
  return instance!;
}
