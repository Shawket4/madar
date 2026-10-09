import { Paths } from "expo-file-system";
import { KitchenCore, KitchenError, type KitchenListener } from "madar-kitchen-core";

import type { Backend } from "./backend";
import { KitchenFailure } from "./backend";
import type { DeviceMode, Route } from "./types";

/** The real backend: madar-core through the uniffi binding (APP-1). */

const API = process.env.EXPO_PUBLIC_MADAR_API ?? "https://api.madar-pos.cloud";
const ENV = process.env.EXPO_PUBLIC_MADAR_ENV ?? "prod";

/** A core error becomes a KitchenFailure carrying the core's own wording. */
async function call<T>(f: () => Promise<T> | T): Promise<T> {
  try {
    return await f();
  } catch (e) {
    if (KitchenError.instanceOf(e)) throw new KitchenFailure(e.inner.message, e.inner.offline);
    throw e;
  }
}

function sync<T>(f: () => T): T {
  try {
    return f();
  } catch (e) {
    if (KitchenError.instanceOf(e)) throw new KitchenFailure(e.inner.message, e.inner.offline);
    throw e;
  }
}

export function nativeBackend(): Backend {
  const dir = decodeURI(Paths.document.uri.replace(/^file:\/\//, "")) + "madar-kitchen";
  const core = new KitchenCore(dir, API, ENV, "ar");

  return {
    mock: false,
    state() {
      const s = core.state();
      return {
        route: s.route as Route,
        branchId: s.branchId,
        branchName: s.branchName,
        mode: s.mode as DeviceMode,
        sectionIds: s.sectionIds,
        userName: s.userName,
        userRole: s.userRole,
        pending: s.pending,
      };
    },
    managerLogin: (email, password) => call(() => core.managerLogin(email, password)),
    chooseBranch: (b) => sync(() => core.chooseBranch(b.id, b.name)),
    signIn: (name, pin) => call(() => core.signIn(name, pin)),
    signOut: () => sync(() => core.signOut()),
    stations: () => call(() => core.stations()),
    setSections: (mode, ids) => sync(() => core.setSections(mode, ids)),
    clearSections: () => sync(() => core.clearSections()),
    resetDevice: () => sync(() => core.resetDevice()),
    tickets: () => call(() => core.tickets(undefined)),
    bump: (id) => call(() => core.bump(id)),
    unbump: (id) => call(() => core.unbump(id)),
    syncNow: () => call(() => core.syncNow()),
    startRealtime: (l) => {
      const listener: KitchenListener = {
        onKitchenChange: () => l.onChange(),
        onConnection: (c) => l.onConnection(c),
        onPing: () => l.onPing(),
      };
      return call(() => core.startRealtime(listener));
    },
    stopRealtime: () => core.stopRealtime(),
    setLocale: (locale) => core.setLocale(locale),
  };
}
