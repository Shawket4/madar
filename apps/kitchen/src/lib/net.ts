import { backend } from "@/data/backend";
import type { MockTools } from "@/data/mock-backend";
import { useKitchen } from "@/data/store";
import type { NetState } from "@/data/types";

/**
 * Online / LAN-only / offline (KB-7). On a device this is the realtime
 * stream's state; the LAN-only case needs the core's LAN relay to report it
 * (LN-*), so today a device shows online or offline. The mock fakes all three.
 */
export function useNet(): NetState {
  const connected = useKitchen((s) => s.connected);
  useKitchen((s) => s.device); // re-read when the backend changes
  const b = backend() as { mock: boolean; tools?: MockTools };
  if (b.mock && b.tools) return b.tools.net;
  return connected ? "online" : "offline";
}
