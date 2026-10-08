import { View } from "react-native";
import { useTranslation } from "react-i18next";
import { LogOut, Plus, RotateCcw, Wrench } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import * as mock from "@/data/mock";
import type { NetState } from "@/data/types";
import { space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button, Segmented } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Txt } from "@/components/ui/text";
import { SectionHeader } from "@/components/app/section-header";
import { useLocalName } from "@/lib/hooks";

/** Per-device settings (KB-5, APP-6, APP-7). Setup changes need a manager (DV-1). */
export function SettingsSheet() {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const s = useKitchen();
  const close = () => s.set("settingsOpen", false);

  const changeSetup = () => {
    close();
    s.set("afterPin", s.resetDevice);
    s.set("pinFor", "manager");
  };

  const device = s.device;
  const where = device
    ? device.mode === "expo"
      ? t("expo.title")
      : device.sectionIds.map((id) => name(mock.sections.find((x) => x.id === id)!)).join(" · ")
    : "";

  return (
    <Sheet open={s.settingsOpen} onClose={close} title={t("settings.title")} width={560}>
      <Row label={t("settings.theme")}>
        <Segmented value={s.theme} onChange={(v) => s.set("theme", v)} options={[{ value: "dark", label: t("settings.dark") }, { value: "light", label: t("settings.light") }]} />
      </Row>
      <Row label={t("settings.language")}>
        <Segmented value={s.lang} onChange={(v) => s.set("lang", v)} options={[{ value: "ar", label: "العربية" }, { value: "en", label: "English" }]} />
      </Row>
      <Row label={t("settings.chime")} hint={t("settings.chimeHint")}>
        <Segmented value={s.chime ? "on" : "off"} onChange={(v) => s.set("chime", v === "on")} options={[{ value: "on", label: t("settings.on") }, { value: "off", label: t("settings.off") }]} />
      </Row>

      <View style={{ height: 1, backgroundColor: c.border }} />
      <SectionHeader title={t("settings.device")} />
      <Txt size={15}>{device ? `${name(mock.branches.find((b) => b.id === device.branchId)!)} · ${where}` : "—"}</Txt>
      <View style={{ flexDirection: "row", gap: space.sm, flexWrap: "wrap" }}>
        <Button variant="outline" icon={Wrench} onPress={changeSetup}>{t("settings.changeSetup")}</Button>
        {s.user ? <Button variant="outline" icon={LogOut} onPress={s.signOut}>{t("auth.signOut", { name: s.user.name.split(" ")[0] })}</Button> : null}
      </View>

      <View style={{ height: 1, backgroundColor: c.border }} />
      <SectionHeader title={t("mock.title")} />
      <Txt size={14} muted>{t("mock.body")}</Txt>
      <Row label={t("mock.network")}>
        <Segmented<NetState> value={s.net} onChange={s.setNet} options={[{ value: "online", label: t("net.online") }, { value: "lan", label: t("net.lan") }, { value: "offline", label: t("net.offline") }]} />
      </Row>
      <View style={{ flexDirection: "row", gap: space.sm, flexWrap: "wrap" }}>
        <Button variant="secondary" icon={Plus} onPress={() => { s.sendTestOrder(); close(); }}>{t("mock.sendOrder")}</Button>
        <Button variant="secondary" icon={RotateCcw} onPress={s.resetMock}>{t("mock.reset")}</Button>
      </View>
    </Sheet>
  );
}

function Row({ label, hint, children }: { label: string; hint?: string; children: React.ReactNode }) {
  return (
    <View style={{ gap: space.sm }}>
      <Txt size={15} weight="semibold">{label}</Txt>
      {hint ? <Txt size={13} muted>{hint}</Txt> : null}
      {children}
    </View>
  );
}
