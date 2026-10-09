import Zeroconf, { type Service } from "react-native-zeroconf";

import type { LanAdvert, LanBackend } from "@/data/backend";

/*
 * Native Bonjour for the core's LAN relay — a port of the POS's
 * apps/madar/lib/app/lan_bonjour.dart.
 *
 * iOS blocks the core's own mDNS multicast and UDP beacon without Apple's
 * restricted multicast entitlement, so a tablet would never find a peer. The
 * system's Bonjour needs only the NSBonjourServices + NSLocalNetworkUsageDescription
 * Info.plist keys. This advertises `_madar._tcp` with the same TXT keys as the
 * POS, browses, and hands each resolved peer to the core, which filters by
 * branch and skips this device. Sequencing only; no decision lives here.
 */

const TYPE = "madar";
const PROTOCOL = "tcp";
/** Below the core's 12 s peer TTL. */
const RENOTE_MS = 4000;

export class LanBonjour {
  private zc: Zeroconf | null = null;
  private advertised: string | null = null;
  private publishedName: string | null = null;
  private peers = new Map<string, Service>();
  private renote: ReturnType<typeof setInterval> | null = null;

  constructor(private readonly lan: LanBackend) {}

  /** Start (or refresh) advertising and browsing for the running relay. Safe to call often. */
  async ensure(): Promise<void> {
    const advert = this.lan.lanAdvert();
    if (!advert) return this.stop();
    const zc = (this.zc ??= this.browse());
    const key = JSON.stringify(advert);
    if (key !== this.advertised) await this.advertise(zc, advert, key);
  }

  stop(): void {
    if (this.renote) clearInterval(this.renote);
    this.renote = null;
    this.peers.clear();
    const zc = this.zc;
    this.zc = null;
    if (!zc) return;
    try {
      if (this.publishedName) zc.unpublishService(this.publishedName);
      zc.stop();
      zc.removeDeviceListeners();
    } catch {
      // Already gone.
    }
    this.publishedName = null;
    this.advertised = null;
  }

  private browse(): Zeroconf {
    const zc = new Zeroconf();
    zc.on("resolved", (s) => {
      this.peers.set(s.name, s);
      this.note(s);
    });
    // Stop re-noting; the core's TTL drops the peer within seconds.
    zc.on("remove", (name) => this.peers.delete(name));
    zc.on("error", () => {});
    zc.scan({ type: TYPE, protocol: PROTOCOL, domain: "local." });
    this.renote = setInterval(() => this.peers.forEach((s) => this.note(s)), RENOTE_MS);
    return zc;
  }

  private async advertise(zc: Zeroconf, a: LanAdvert, key: string) {
    if (this.publishedName) {
      try {
        zc.unpublishService(this.publishedName);
      } catch {}
    }
    try {
      // Same name scheme as the POS's native advert, distinct from the core's own mDNS instance.
      const published = await zc.publishService({
        type: TYPE,
        protocol: PROTOCOL,
        domain: "local.",
        name: `madar-n-${a.deviceId}`,
        port: a.tcpPort,
        txt: {
          device_id: a.deviceId,
          branch_id: a.branchId,
          role: a.role,
          station_id: a.stationId ?? "",
          device_code: a.deviceCode ?? "",
          tcp_port: String(a.tcpPort),
        },
      });
      this.publishedName = published.name;
      this.advertised = key;
    } catch {
      // The OS refused (no permission): a manual hub still works.
      this.publishedName = null;
      this.advertised = null;
    }
  }

  private note(s: Service) {
    const deviceId = s.txt?.device_id ?? "";
    const host = s.ipv4?.[0] ?? s.ipv6?.find((a) => !a.toLowerCase().startsWith("fe80")) ?? null;
    if (!host || !deviceId) return;
    const port = Number(s.txt?.tcp_port) || s.port;
    try {
      this.lan.lanNotePeer({
        deviceId,
        branchId: s.txt?.branch_id ?? "",
        host,
        port,
        role: s.txt?.role ?? "",
        stationId: s.txt?.station_id || undefined,
        deviceCode: s.txt?.device_code || undefined,
      });
    } catch {
      // The relay stopped between events; the next ensure() restarts us.
    }
  }
}
