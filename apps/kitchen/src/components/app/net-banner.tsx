import { View } from "react-native";
import { useTranslation } from "react-i18next";
import { Router, WifiOff } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { useNet } from "@/lib/net";
import { space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";
import { toneColors } from "./status-pill";

/** KB-7: offline or LAN-only, and how many bumps wait to sync. Nothing when online. */
export function NetBanner() {
  const { t } = useTranslation();
  const c = useColors();
  const net = useNet();
  const pending = useKitchen((s) => s.device.pending);
  if (net === "online" && !pending) return null;
  if (net === "online") {
    // Back online with writes still draining: say so quietly.
    return (
      <View style={{ paddingHorizontal: space.xl, paddingVertical: 6, backgroundColor: c.muted, borderBottomWidth: 1, borderBottomColor: c.border }}>
        <Txt size={13} muted>{t("net.pending", { count: pending })}</Txt>
      </View>
    );
  }
  const tone = toneColors(c, net === "lan" ? "info" : "warning");
  const Icon = net === "lan" ? Router : WifiOff;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: space.md, paddingHorizontal: space.xl, paddingVertical: space.md, backgroundColor: tone.bg, borderBottomWidth: 1, borderBottomColor: c.border }}>
      <Icon size={20} color={tone.fg} />
      <View style={{ flex: 1 }}>
        <Txt size={15} weight="semibold" color={tone.fg}>{t(net === "lan" ? "net.lanTitle" : "net.offlineTitle")}</Txt>
        <Txt size={13} color={tone.fg}>{t(net === "lan" ? "net.lanBody" : "net.offlineBody")}</Txt>
      </View>
      {pending > 0 ? <Txt size={14} weight="semibold" color={tone.fg}>{t("net.pending", { count: pending })}</Txt> : null}
    </View>
  );
}
