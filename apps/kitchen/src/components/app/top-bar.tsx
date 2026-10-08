import type { ReactNode } from "react";
import { Pressable, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTranslation } from "react-i18next";
import { ChefHat, LogOut, Router, Settings, Wifi, WifiOff } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { useNet } from "@/lib/net";
import { radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Txt } from "@/components/ui/text";

/**
 * The chrome: one ink bar, dark in both themes (the dashboard's sidebar role).
 * Station · branch · live dot · open count · who's signed in · settings.
 */
export function TopBar({ title, subtitle, count, actions }: { title: string; subtitle: string; count?: number; actions?: ReactNode }) {
  const { t } = useTranslation();
  const c = useColors();
  const insets = useSafeAreaInsets();
  const net = useNet();
  const userName = useKitchen((s) => s.device.userName);
  const signOut = useKitchen((s) => s.signOut);
  const setK = useKitchen((s) => s.set);

  const netLook = {
    online: { Icon: Wifi, color: c.success, label: t("net.online") },
    lan: { Icon: Router, color: c.info, label: t("net.lan") },
    offline: { Icon: WifiOff, color: c.warning, label: t("net.offline") },
  }[net];

  return (
    <View style={{ backgroundColor: c.chrome, paddingTop: insets.top, borderBottomWidth: 1, borderBottomColor: c.chromeBorder }}>
      <View style={{ height: 72, flexDirection: "row", alignItems: "center", gap: space.md, paddingHorizontal: space.xl }}>
        <View style={{ width: 44, height: 44, borderRadius: radius.md, backgroundColor: c.kitchen, alignItems: "center", justifyContent: "center" }}>
          <ChefHat size={24} color="#FFFFFF" />
        </View>
        <View style={{ flexShrink: 1 }}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 10 }}>
            <Txt size={22} weight="bold" color={c.chromeForeground} numberOfLines={1}>{title}</Txt>
            {count !== undefined ? (
              <View style={{ backgroundColor: c.chromeRaised, borderRadius: radius.full, paddingHorizontal: 10, height: 26, justifyContent: "center" }}>
                <Txt size={15} mono weight="semibold" color={c.chromeForeground}>{count}</Txt>
              </View>
            ) : null}
          </View>
          <Txt size={13} color={c.chromeMuted} numberOfLines={1}>{subtitle}</Txt>
        </View>

        <View style={{ flex: 1 }} />

        <View style={{ flexDirection: "row", alignItems: "center", gap: 6, paddingHorizontal: 12, height: 36, borderRadius: radius.full, backgroundColor: c.chromeAccent }}>
          <netLook.Icon size={16} color={netLook.color} />
          <Txt size={14} weight="medium" color={c.chromeForeground}>{netLook.label}</Txt>
        </View>
        {actions}
        <Pressable
          onPress={signOut}
          accessibilityRole="button"
          accessibilityLabel={t("auth.switch")}
          style={({ pressed }) => ({ flexDirection: "row", alignItems: "center", gap: 8, height: 44, paddingHorizontal: 12, borderRadius: radius.md, backgroundColor: pressed ? c.chromeAccent : c.chromeRaised })}
        >
          <Txt size={15} weight="medium" color={c.chromeForeground} numberOfLines={1}>{userName?.split(" ")[0] ?? ""}</Txt>
          <LogOut size={18} color={c.chromeMuted} />
        </Pressable>
        <Button variant="chrome" size="icon" icon={Settings} label={t("settings.title")} onPress={() => setK("settingsOpen", true)} />
      </View>
    </View>
  );
}
