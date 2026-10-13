import type { ReactNode } from "react";
import { KeyboardAvoidingView, Platform, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTranslation } from "react-i18next";
import { ChefHat } from "lucide-react-native";

import { radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";

/** The frame of the setup and sign-in screens: the ink bar, then one centred column. */
export function DeviceFrame({ title, subtitle, width = 720, trailing, children }: {
  title: string;
  subtitle?: string;
  width?: number;
  trailing?: ReactNode;
  children: ReactNode;
}) {
  const { t } = useTranslation();
  const c = useColors();
  const insets = useSafeAreaInsets();
  return (
    <View style={{ flex: 1, backgroundColor: c.background }}>
      <View style={{ backgroundColor: c.chrome, paddingTop: insets.top }}>
        <View style={{ height: 72, flexDirection: "row", alignItems: "center", gap: space.md, paddingHorizontal: space.xl }}>
          <View style={{ width: 44, height: 44, borderRadius: radius.md, backgroundColor: c.kitchen, alignItems: "center", justifyContent: "center" }}>
            <ChefHat size={24} color="#FFFFFF" />
          </View>
          <Txt size={22} weight="bold" color={c.chromeForeground} style={{ flex: 1 }}>{t("app.name")}</Txt>
          {trailing}
        </View>
      </View>
      <KeyboardAvoidingView style={{ flex: 1 }} behavior={Platform.OS === "ios" ? "padding" : undefined}>
        <ScrollView contentContainerStyle={{ padding: space.xl, alignItems: "center" }} keyboardShouldPersistTaps="handled">
          <View style={{ width: "100%", maxWidth: width, gap: space.xl }}>
            <View style={{ gap: 4 }}>
              <Txt size={28} weight="bold">{title}</Txt>
              {subtitle ? <Txt size={15} muted>{subtitle}</Txt> : null}
            </View>
            {children}
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
    </View>
  );
}
