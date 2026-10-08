import { create } from "zustand";

import type { ColorScheme } from "@/theme/tokens";
import * as mock from "./mock";
import type { DeviceConfig, KitchenPart, NetState, Order, Staff } from "./types";
import { isComplete } from "@/features/board/logic";

/*
 * The device's state. In mock mode (APP-11) this IS the data; once the core is
 * wired, tickets come from the binding (React Query over core reads) and the
 * actions become core calls — the screens keep the same hooks.
 */

export type Lang = "ar" | "en";

interface KitchenState {
  device: DeviceConfig | null;
  user: Staff | null;
  orders: Order[];
  parts: KitchenPart[];
  net: NetState;
  /** Bumps waiting to sync (KB-7). */
  pending: number;
  theme: ColorScheme;
  lang: Lang;
  chime: boolean;
  /** Overlays */
  pinFor: null | "bump" | "switch" | "manager";
  settingsOpen: boolean;
  recallOpen: boolean;
  /** Runs after a successful PIN, so a bump asked for while signed out still happens (DV-5). */
  afterPin: null | (() => void);

  configure(d: DeviceConfig): void;
  resetDevice(): void;
  signIn(u: Staff): void;
  /** Runs `fn` as the signed-in person, asking for a PIN first if nobody is. */
  guard(fn: () => void): void;
  signOut(): void;
  toggleLine(partId: string, lineId: string): void;
  bumpPart(partId: string): void;
  recall(partId: string): void;
  handOff(orderId: string): void;
  setNet(n: NetState): void;
  set<K extends "theme" | "lang" | "chime" | "pinFor" | "afterPin" | "settingsOpen" | "recallOpen">(k: K, v: KitchenState[K]): void;
  sendTestOrder(): void;
  resetMock(): void;
}

const now = () => new Date().toISOString();

export const useKitchen = create<KitchenState>((set, get) => {
  /** A write: applies locally, counts as pending while not online (outbox first, AT-2). */
  const write = (fn: (parts: KitchenPart[]) => KitchenPart[]) =>
    set((s) => ({ parts: fn(s.parts), pending: s.net === "online" ? s.pending : s.pending + 1 }));

  const patch = (partId: string, f: (p: KitchenPart) => KitchenPart) =>
    write((ps) => ps.map((p) => (p.id === partId ? f(p) : p)));

  return {
    device: null,
    user: null,
    ...mock.seed(),
    net: "online",
    pending: 0,
    theme: "dark",
    lang: "ar",
    chime: true,
    pinFor: null,
    settingsOpen: false,
    recallOpen: false,
    afterPin: null,

    configure: (device) => set({ device, user: null, pinFor: null }),
    resetDevice: () => set({ device: null, user: null, settingsOpen: false }),
    signIn: (user) => {
      const after = get().afterPin;
      set({ user, pinFor: null, afterPin: null });
      after?.();
    },
    guard: (fn) => (get().user ? fn() : set({ pinFor: "bump", afterPin: fn })),
    signOut: () => set({ user: null, settingsOpen: false }),

    toggleLine: (partId, lineId) =>
      patch(partId, (p) => {
        const items = p.items.map((l) => (l.id === lineId && !l.voided ? { ...l, bumped: !l.bumped } : l));
        const next = { ...p, items };
        const done = isComplete(next);
        return { ...next, bumpedAt: done ? now() : null, bumpedBy: done ? get().user?.id ?? null : null };
      }),
    bumpPart: (partId) =>
      patch(partId, (p) => ({
        ...p,
        items: p.items.map((l) => (l.voided ? l : { ...l, bumped: true })),
        bumpedAt: now(),
        bumpedBy: get().user?.id ?? null,
      })),
    recall: (partId) =>
      patch(partId, (p) => ({ ...p, items: p.items.map((l) => ({ ...l, bumped: false })), bumpedAt: null, bumpedBy: null })),
    handOff: (orderId) =>
      set((s) => ({ orders: s.orders.map((o) => (o.id === orderId ? { ...o, handedOffAt: now() } : o)) })),

    // Back online: the outbox drains (mocked as instant).
    setNet: (net) => set((s) => ({ net, pending: net === "online" ? 0 : s.pending })),
    set: (k, v) => set({ [k]: v } as Partial<KitchenState>),

    sendTestOrder: () => {
      const { order, parts } = mock.randomOrder();
      set((s) => ({ orders: [...s.orders, order], parts: [...s.parts, ...parts] }));
    },
    resetMock: () => set({ ...mock.seed(), pending: 0, settingsOpen: false }),
  };
});
