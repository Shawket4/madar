import { View } from "react-native";
import { useTranslation } from "react-i18next";
import { Layers, LogOut, Plus, RefreshCw, RotateCcw, Wrench } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { backend } from "@/data/backend";
import type { MockTools } from "@/data/mock-backend";
import type { NetState } from "@/data/types";
import { space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button, Segmented } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Txt } from "@/components/ui/text";
import { SectionHeader } from "@/components/app/section-header";
import { useNet } from "@/lib/net";

/** Per-device settings (KB-5, APP-6, APP-7) and the device's binding. */
export function SettingsSheet() {
  const { t } = useTranslation();
  const c = useColors();
  const s = useKitchen();
  const net = useNet();
  const close = () => s.set("settingsOpen", false);
  const tools = (backend() as { tools?: MockTools }).tools;

  const device = s.device;
  const where = device.mode === "expo" ? t("expo.title") : device.sectionIds.map((id) => s.sections.find((x) => x.id === id)?.name ?? "…").join(" · ");

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
      <Txt size={15}>{`${device.branchName ?? ""} · ${where}`}</Txt>
      <Txt size={13} muted>{t("settings.signedInAs", { name: device.userName ?? "—" })} · {t("net.pending", { count: device.pending })}</Txt>
      <View style={{ flexDirection: "row", gap: space.sm, flexWrap: "wrap" }}>
        <Button variant="outline" icon={RefreshCw} onPress={() => void backend().syncNow().then(s.refresh, (e) => s.set("error", String(e?.message ?? e)))}>{t("settings.syncNow")}</Button>
        <Button variant="outline" icon={Layers} onPress={s.changeSections}>{t("settings.changeSections")}</Button>
        <Button variant="outline" icon={LogOut} onPress={s.signOut}>{t("auth.signOut", { name: device.userName ?? "" })}</Button>
      </View>
      <Button variant="ghost" icon={Wrench} onPress={s.resetDevice} style={{ alignSelf: "flex-start" }}>{t("settings.resetDevice")}</Button>

      {tools ? (
        <>
          <View style={{ height: 1, backgroundColor: c.border }} />
          <SectionHeader title={t("mock.title")} />
          <Txt size={14} muted>{t("mock.body")}</Txt>
          <Row label={t("mock.network")}>
            <Segmented<NetState> value={net} onChange={(v) => { tools.setNet(v); void s.refresh(); }} options={[{ value: "online", label: t("net.online") }, { value: "lan", label: t("net.lan") }, { value: "offline", label: t("net.offline") }]} />
          </Row>
          <View style={{ flexDirection: "row", gap: space.sm, flexWrap: "wrap" }}>
            <Button variant="secondary" icon={Plus} onPress={() => { tools.sendTestOrder(); close(); }}>{t("mock.sendOrder")}</Button>
            <Button variant="secondary" icon={RotateCcw} onPress={() => { tools.reset(); close(); }}>{t("mock.reset")}</Button>
          </View>
        </>
      ) : null}
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
