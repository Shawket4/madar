import { create } from "zustand";

import type { ColorScheme } from "@/theme/tokens";
import { backend, KitchenFailure, type LanStatus } from "./backend";
import type { LanBonjour } from "@/lib/lan-bonjour";
import type { Branch, DeviceMode, DeviceState, KitchenLine, KitchenPart, Section, Ticket } from "./types";
import { toParts } from "@/features/board/logic";

/*
 * The device's state. The truth lives behind `backend()` — madar-core on a
 * device, the mock on web — and this store holds the last read of it plus the
 * screen state. Every write goes to the backend (outbox first in the core) and
 * the board re-reads; a refused write is said out loud, never swallowed.
 */

export type Lang = "ar" | "en";

interface KitchenState {
  device: DeviceState;
  sections: Section[];
  tickets: Ticket[];
  parts: KitchenPart[];
  /** When this device finished a part, so it lingers green for a moment. */
  finishedAt: Record<string, number>;
  /** Expo hand-offs (EX-4). Device-local: the server has no hand-off yet. */
  handedOff: Record<string, true>;
  connected: boolean;
  /** The LAN relay (LN-1..5): running, and how many peers it can reach. */
  lan: LanStatus;
  /** The last refused or failed action, shown in a banner until dismissed. */
  error: string | null;
  theme: ColorScheme;
  lang: Lang;
  chime: boolean;
  settingsOpen: boolean;
  recallOpen: boolean;

  boot(): Promise<void>;
  refresh(): Promise<void>;
  managerLogin(email: string, password: string): Promise<Branch[]>;
  chooseBranch(b: Branch): void;
  signIn(name: string, pin: string): Promise<void>;
  signOut(): void;
  chooseSections(mode: DeviceMode, ids: string[]): void;
  changeSections(): void;
  resetDevice(): void;
  toggleLine(part: KitchenPart, line: KitchenLine): Promise<void>;
  bumpPart(part: KitchenPart): Promise<void>;
  recall(part: KitchenPart): Promise<void>;
  handOff(orderId: string): void;
  set<K extends "theme" | "lang" | "chime" | "settingsOpen" | "recallOpen" | "error">(k: K, v: KitchenState[K]): void;
}

const say = (e: unknown) => (e instanceof KitchenFailure || e instanceof Error ? e.message : String(e));

/** Native Bonjour for the relay; none on web or in the mock. */
let bonjour: LanBonjour | null = null;
let lastLanTry = 0;
const LAN_RETRY_MS = 30_000;

export const useKitchen = create<KitchenState>((set, get) => {
  /** Start the LAN relay and its Bonjour discovery; retried by refresh until it runs. */
  const startLan = async () => {
    lastLanTry = Date.now();
    try {
      await backend().lanStart();
      if (!backend().mock) {
        bonjour ??= new (require("@/lib/lan-bonjour").LanBonjour)(backend());
        await bonjour!.ensure();
      }
    } catch {
      // No LAN key yet (never signed in online here) or no network: the next refresh retries.
    }
    set({ lan: backend().lanStatus() });
  };

  const stopLan = () => {
    bonjour?.stop();
    backend().lanStop();
    set({ lan: { running: false, peerCount: 0 } });
  };

  const readState = () => set({ device: backend().state() });

  const defaultSection = () => get().sections.find((s) => s.isDefault)?.id ?? get().sections[0]?.id;

  /** Re-split the last tickets (after sections load, or an optimistic change). */
  const reparts = (tickets: Ticket[]) => set({ tickets, parts: toParts(tickets, defaultSection()) });

  const loadSections = async () => {
    try {
      set({ sections: await backend().stations() });
      reparts(get().tickets);
    } catch (e) {
      set({ error: say(e) });
    }
  };

  const startLive = async () => {
    await loadSections();
    try {
      await backend().startRealtime({
        onChange: () => void get().refresh(),
        onConnection: (connected) => set({ connected }),
        onPing: () => {}, // KB-5: no chime asset yet
      });
    } catch {
      // Offline at boot: the poll still reads local rows, and the core reconnects.
    }
    void backend().syncNow().catch(() => {});
    void startLan();
    await get().refresh();
  };

  /** Optimistic line change, then the core; a refusal re-reads and says why. */
  const writeLines = async (lineIds: string[], bumped: boolean, partId?: string) => {
    const ids = new Set(lineIds);
    reparts(get().tickets.map((t) => ({ ...t, items: t.items.map((l) => (ids.has(l.id) ? { ...l, bumped } : l)) })));
    if (partId && bumped && get().parts.find((p) => p.id === partId)?.done) {
      set((s) => ({ finishedAt: { ...s.finishedAt, [partId]: Date.now() } }));
    }
    try {
      for (const id of lineIds) await (bumped ? backend().bump(id) : backend().unbump(id));
    } catch (e) {
      set({ error: say(e) });
    }
    await get().refresh();
  };

  return {
    device: { route: "setup", mode: "sections", sectionIds: [], pending: 0 },
    sections: [],
    tickets: [],
    parts: [],
    finishedAt: {},
    handedOff: {},
    connected: true,
    lan: { running: false, peerCount: 0 },
    error: null,
    theme: "dark",
    lang: "ar",
    chime: true,
    settingsOpen: false,
    recallOpen: false,

    async boot() {
      backend().setLocale(get().lang);
      readState();
      const { route } = get().device;
      if (route === "board") await startLive();
      else if (route === "sections") {
        // Sections live in the branch settings the core syncs: pull once now,
        // and listen, so ones added in the dashboard meanwhile arrive too.
        await loadSections();
        void backend().syncNow().then(loadSections, () => {});
        void backend().startRealtime({ onChange: () => void loadSections(), onConnection: (connected) => set({ connected }), onPing: () => {} }).catch(() => {});
      }
    },

    async refresh() {
      readState();
      if (get().device.route === "sections") return loadSections();
      if (get().device.route !== "board") return;
      const lan = backend().lanStatus();
      set({ lan });
      if (!lan.running && Date.now() - lastLanTry > LAN_RETRY_MS) void startLan();
      else if (lan.running) void bonjour?.ensure();
      try {
        reparts(await backend().tickets());
      } catch (e) {
        set({ error: say(e) });
      }
    },

    managerLogin: (email, password) => backend().managerLogin(email, password),

    chooseBranch(b) {
      backend().chooseBranch(b);
      readState();
    },

    async signIn(name, pin) {
      await backend().signIn(name, pin);
      set({ error: null });
      await get().boot();
    },

    signOut() {
      stopLan();
      backend().stopRealtime();
      backend().signOut();
      set({ settingsOpen: false, tickets: [], parts: [] });
      readState();
    },

    chooseSections(mode, ids) {
      const def = defaultSection();
      // The core keeps one station; for expo that is the default section.
      backend().setSections(mode, mode === "expo" ? (def ? [def] : []) : ids);
      void get().boot();
    },

    changeSections() {
      stopLan();
      backend().stopRealtime();
      backend().clearSections();
      set({ settingsOpen: false });
      void get().boot();
    },

    resetDevice() {
      try {
        stopLan();
        backend().resetDevice();
        set({ settingsOpen: false, tickets: [], parts: [], sections: [] });
        readState();
      } catch (e) {
        set({ error: say(e), settingsOpen: false });
      }
    },

    toggleLine: (part, line) => writeLines([line.id], !line.bumped, part.id),

    bumpPart: (part) =>
      writeLines(part.items.filter((l) => !l.bumped && !l.voided).map((l) => l.id), true, part.id),

    recall: (part) => writeLines(part.items.filter((l) => l.bumped).map((l) => l.id), false),

    handOff: (orderId) => set((s) => ({ handedOff: { ...s.handedOff, [orderId]: true } })),

    set: (k, v) => {
      set({ [k]: v } as Partial<KitchenState>);
      if (k === "lang") {
        backend().setLocale(v as string);
        if (get().device.route === "board" || get().device.route === "sections") {
          void loadSections();
          void get().refresh();
        }
      }
    },
  };
});
