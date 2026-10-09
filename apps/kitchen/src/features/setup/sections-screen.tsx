import { useState } from "react";
import { View } from "react-native";
import { useTranslation } from "react-i18next";
import { ChefHat, HandPlatter, Layers, LogOut } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import type { DeviceMode } from "@/data/types";
import { space } from "@/theme/tokens";
import { Button } from "@/components/ui/button";
import { Txt } from "@/components/ui/text";
import { Choice } from "@/components/app/choice";
import { DeviceFrame } from "@/components/app/device-frame";
import { ErrorBanner } from "@/components/app/error-banner";
import { SectionHeader } from "@/components/app/section-header";

/** What this screen shows (KB-1, EX-1): one or more sections, or the expo. */
export function SectionsScreen() {
  const { t } = useTranslation();
  const sections = useKitchen((s) => s.sections);
  const device = useKitchen((s) => s.device);
  const choose = useKitchen((s) => s.chooseSections);
  const signOut = useKitchen((s) => s.signOut);
  const [mode, setMode] = useState<DeviceMode>("sections");
  const [ids, setIds] = useState<string[]>([]);

  const toggle = (id: string) => setIds((xs) => (xs.includes(id) ? xs.filter((x) => x !== id) : [...xs, id]));
  const active = sections.filter((s) => s.isActive);
  const ok = mode === "expo" ? active.length > 0 : ids.length > 0;

  return (
    <View style={{ flex: 1 }}>
      <ErrorBanner />
      <DeviceFrame
        title={t("setup.sectionsTitle")}
        subtitle={`${device.branchName ?? ""} · ${t("setup.sectionsSubtitle")}`}
        trailing={<Button variant="chrome" icon={LogOut} onPress={signOut}>{device.userName ?? ""}</Button>}
      >
        <View style={{ gap: space.md }}>
          <SectionHeader title={t("setup.mode")} />
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.md }}>
            <Choice on={mode === "sections"} onPress={() => setMode("sections")} icon={Layers} title={t("setup.modeSections")} body={t("setup.modeSectionsBody")} />
            <Choice on={mode === "expo"} onPress={() => setMode("expo")} icon={HandPlatter} title={t("setup.modeExpo")} body={t("setup.modeExpoBody")} />
          </View>
        </View>

        {mode === "sections" ? (
          <View style={{ gap: space.md }}>
            <SectionHeader title={t("setup.sections")} count={ids.length} />
            <Txt size={14} muted>{active.length ? t("setup.sectionsHint") : t("setup.noSections")}</Txt>
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.md }}>
              {active.map((s) => (
                <Choice key={s.id} on={ids.includes(s.id)} onPress={() => toggle(s.id)} icon={ChefHat} title={s.name} badge={s.isDefault ? t("setup.default") : undefined} />
              ))}
            </View>
          </View>
        ) : null}

        <Button size="lg" disabled={!ok} onPress={() => choose(mode, ids)}>{t("setup.confirm")}</Button>
      </DeviceFrame>
    </View>
  );
}
