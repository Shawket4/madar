import { backend } from "@/data/backend";
import type { MockTools } from "@/data/mock-backend";
import { useKitchen } from "@/data/store";
import type { NetState } from "@/data/types";

/**
 * Online / LAN-only / offline (KB-7). On a device: online while the realtime
 * stream is up; LAN only when it's down but the core's LAN relay has a peer
 * (a POS on the same network); offline otherwise. The mock fakes all three.
 */
export function useNet(): NetState {
  const connected = useKitchen((s) => s.connected);
  const lan = useKitchen((s) => s.lan);
  useKitchen((s) => s.device); // re-read when the backend changes
  const b = backend() as { mock: boolean; tools?: MockTools };
  if (b.mock && b.tools) return b.tools.net;
  if (connected) return "online";
  // No server, but a POS (or another screen) on this network still reaches us.
  return lan.running && lan.peerCount > 0 ? "lan" : "offline";
}
