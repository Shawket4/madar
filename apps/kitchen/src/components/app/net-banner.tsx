import { View } from "react-native";
import { useTranslation } from "react-i18next";
import { Router, WifiOff } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";
import { toneColors } from "./status-pill";

/** KB-7: offline or LAN-only, and how many bumps wait to sync. Nothing when online. */
export function NetBanner() {
  const { t } = useTranslation();
  const c = useColors();
  const net = useKitchen((s) => s.net);
  const pending = useKitchen((s) => s.pending);
  if (net === "online") return null;
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
