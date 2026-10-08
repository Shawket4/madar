import { useState } from "react";
import { Pressable, ScrollView, View } from "react-native";
import { useSafeAreaInsets } from "react-native-safe-area-context";
import { useTranslation } from "react-i18next";
import { Check, ChefHat, HandPlatter, Layers, Store } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import * as mock from "@/data/mock";
import type { DeviceMode } from "@/data/types";
import { radius, space, wash } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Txt } from "@/components/ui/text";
import { SectionHeader } from "@/components/app/section-header";
import { StatusPill } from "@/components/app/status-pill";
import { useLocalName } from "@/lib/hooks";

/** Device setup (DV-1, KB-1, EX-1): branch, then section(s) or expo. A manager confirms. */
export function SetupScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const insets = useSafeAreaInsets();
  const configure = useKitchen((s) => s.configure);
  const setK = useKitchen((s) => s.set);

  const [branchId, setBranch] = useState(mock.branches[0].id);
  const [mode, setMode] = useState<DeviceMode>("sections");
  const [sectionIds, setSections] = useState<string[]>([mock.sections[0].id]);

  const toggle = (id: string) => setSections((xs) => (xs.includes(id) ? xs.filter((x) => x !== id) : [...xs, id]));
  const ok = mode === "expo" || sectionIds.length > 0;

  const confirm = () => {
    setK("afterPin", () => configure({ branchId, mode, sectionIds: mode === "expo" ? mock.sections.map((s) => s.id) : sectionIds }));
    setK("pinFor", "manager");
  };

  return (
    <View style={{ flex: 1, backgroundColor: c.background }}>
      <View style={{ backgroundColor: c.chrome, paddingTop: insets.top }}>
        <View style={{ height: 72, flexDirection: "row", alignItems: "center", gap: space.md, paddingHorizontal: space.xl }}>
          <View style={{ width: 44, height: 44, borderRadius: radius.md, backgroundColor: c.kitchen, alignItems: "center", justifyContent: "center" }}>
            <ChefHat size={24} color="#FFFFFF" />
          </View>
          <Txt size={22} weight="bold" color={c.chromeForeground}>{t("app.name")}</Txt>
        </View>
      </View>
      <ScrollView contentContainerStyle={{ padding: space.xl, alignItems: "center" }}>
        <View style={{ width: "100%", maxWidth: 720, gap: space.xl }}>
          <View style={{ gap: 4 }}>
            <Txt size={28} weight="bold">{t("setup.title")}</Txt>
            <Txt size={15} muted>{t("setup.subtitle")}</Txt>
          </View>

          <View style={{ gap: space.md }}>
            <SectionHeader title={t("setup.branch")} />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.md }}>
              {mock.branches.map((b) => (
                <Choice key={b.id} on={b.id === branchId} onPress={() => setBranch(b.id)} icon={Store} title={name(b)} />
              ))}
            </View>
          </View>

          <View style={{ gap: space.md }}>
            <SectionHeader title={t("setup.mode")} />
            <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.md }}>
              <Choice on={mode === "sections"} onPress={() => setMode("sections")} icon={Layers} title={t("setup.modeSections")} body={t("setup.modeSectionsBody")} />
              <Choice on={mode === "expo"} onPress={() => setMode("expo")} icon={HandPlatter} title={t("setup.modeExpo")} body={t("setup.modeExpoBody")} />
            </View>
          </View>

          {mode === "sections" ? (
            <View style={{ gap: space.md }}>
              <SectionHeader title={t("setup.sections")} count={sectionIds.length} />
              <Txt size={14} muted>{t("setup.sectionsHint")}</Txt>
              <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.md }}>
                {mock.sections.map((s) => (
                  <Choice key={s.id} on={sectionIds.includes(s.id)} onPress={() => toggle(s.id)} icon={ChefHat} title={name(s)}
                    badge={s.isDefault ? t("setup.default") : undefined} />
                ))}
              </View>
            </View>
          ) : null}

          <Button size="lg" disabled={!ok} onPress={confirm}>{t("setup.confirm")}</Button>
          <Txt size={13} muted align="center">{t("setup.note")}</Txt>
        </View>
      </ScrollView>
    </View>
  );
}

function Choice({ on, onPress, icon: Icon, title, body, badge }: {
  on: boolean; onPress: () => void; icon: typeof Store; title: string; body?: string; badge?: string;
}) {
  const c = useColors();
  return (
    <Pressable
      onPress={onPress}
      accessibilityRole="button"
      accessibilityState={{ selected: on }}
      style={({ pressed }) => ({
        flexGrow: 1, flexBasis: 200, minHeight: 72, padding: space.lg, gap: 6, borderRadius: radius.lg,
        borderWidth: on ? 2 : 1, borderColor: on ? c.foreground : c.border,
        backgroundColor: on ? wash(c.foreground, 0.05) : pressed ? c.accent : c.card,
      })}
    >
      <View style={{ flexDirection: "row", alignItems: "center", gap: space.sm }}>
        <Icon size={20} color={on ? c.foreground : c.mutedForeground} />
        <Txt size={17} weight="semibold" style={{ flex: 1 }}>{title}</Txt>
        {badge ? <StatusPill tone="accent" size="sm">{badge}</StatusPill> : null}
        {on ? <Check size={20} color={c.foreground} strokeWidth={3} /> : null}
      </View>
      {body ? <Txt size={14} muted>{body}</Txt> : null}
    </Pressable>
  );
}
