import { useState } from "react";
import { ScrollView, View, useWindowDimensions } from "react-native";
import { useTranslation } from "react-i18next";
import { BellRing, HandPlatter, Printer, Soup } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import * as mock from "@/data/mock";
import type { KitchenPart, Order } from "@/data/types";
import { kitchen, radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Txt } from "@/components/ui/text";
import { EmptyState } from "@/components/app/empty-state";
import { NetBanner } from "@/components/app/net-banner";
import { SectionHeader } from "@/components/app/section-header";
import { StatusPill, type StatusTone } from "@/components/app/status-pill";
import { TopBar } from "@/components/app/top-bar";
import { useLocalName, useNow } from "@/lib/hooks";
import { ageMs, formatAge, orderReady, partStatus, type PartStatus } from "@/features/board/logic";
import { SOURCE_ICON, sourceLabel } from "@/features/board/ticket-card";

const STATUS_TONE: Record<PartStatus, StatusTone> = { waiting: "neutral", cooking: "accent", done: "success" };

/** Expo / pass (EX-1..5): whole orders, each section's part as waiting, cooking or done. */
export function ExpoScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const now = useNow(1000);
  const { width } = useWindowDimensions();
  const device = useKitchen((s) => s.device)!;
  const orders = useKitchen((s) => s.orders);
  const parts = useKitchen((s) => s.parts);

  const live = orders
    .filter((o) => !o.handedOffAt)
    .map((o) => ({ o, ps: parts.filter((p) => p.orderId === o.id) }))
    .filter((x) => x.ps.length)
    .sort((a, b) => firstFire(a.ps) - firstFire(b.ps));
  const ready = live.filter((x) => orderReady(x.ps));
  const cooking = live.filter((x) => !orderReady(x.ps));
  const branch = mock.branches.find((b) => b.id === device.branchId)!;
  const wide = width >= 900;

  return (
    <View style={{ flex: 1, backgroundColor: c.background }}>
      <TopBar title={t("expo.title")} subtitle={`${name(branch)} · ${t("expo.subtitle")}`} count={live.length} />
      <NetBanner />
      <View style={{ flex: 1, flexDirection: wide ? "row" : "column" }}>
        <Lane title={t("expo.cooking")} count={cooking.length} flex={wide ? 2 : 1}>
          {cooking.length === 0 ? <EmptyState icon={Soup} title={t("expo.cookingEmpty")} /> : null}
          <Grid>{cooking.map((x) => <OrderCard key={x.o.id} order={x.o} parts={x.ps} now={now} />)}</Grid>
        </Lane>
        <View style={{ width: wide ? 1 : undefined, height: wide ? undefined : 1, backgroundColor: c.border }} />
        <Lane title={t("expo.ready")} count={ready.length} flex={1} tint>
          {ready.length === 0 ? <EmptyState icon={HandPlatter} title={t("expo.readyEmpty")} description={t("expo.readyEmptyBody")} /> : null}
          <Grid>{ready.map((x) => <OrderCard key={x.o.id} order={x.o} parts={x.ps} now={now} />)}</Grid>
        </Lane>
      </View>
    </View>
  );
}

const firstFire = (ps: KitchenPart[]) => Math.min(...ps.map((p) => Date.parse(p.createdAt)));

function Lane({ title, count, flex, tint, children }: { title: string; count: number; flex: number; tint?: boolean; children: React.ReactNode }) {
  const c = useColors();
  return (
    <View style={{ flex, backgroundColor: tint ? c.muted : c.background }}>
      <ScrollView contentContainerStyle={{ padding: space.lg, gap: space.md }}>
        <SectionHeader title={title} count={count} />
        {children}
      </ScrollView>
    </View>
  );
}

function Grid({ children }: { children: React.ReactNode }) {
  const [w, setW] = useState(0);
  const cols = Math.max(1, Math.floor((w + space.lg) / (kitchen.columnMin + space.lg)));
  const cardW = (w - space.lg * (cols - 1)) / cols;
  return (
    <View onLayout={(e) => setW(e.nativeEvent.layout.width)} style={{ flexDirection: "row", flexWrap: "wrap", gap: space.lg, alignItems: "flex-start" }}>
      {w > 0 ? (Array.isArray(children) ? children : [children]).map((ch, i) => <View key={i} style={{ width: cardW }}>{ch}</View>) : null}
    </View>
  );
}

function OrderCard({ order, parts, now }: { order: Order; parts: KitchenPart[]; now: number }) {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const handOff = useKitchen((s) => s.handOff);
  const guard = useKitchen((s) => s.guard);
  const ready = orderReady(parts);
  const Icon = SOURCE_ICON[order.sourceType];
  const age = now - firstFire(parts);
  const late = age >= 10 * 60_000;

  return (
    <View style={{ backgroundColor: c.card, borderRadius: radius.xl, borderWidth: ready ? 3 : 1, borderColor: ready ? c.success : c.border, padding: space.lg, gap: space.md }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: space.sm }}>
        <Txt size={kitchen.orderNumber} mono weight="bold">#{order.kitchenRef}</Txt>
        <View style={{ flex: 1 }} />
        <Txt size={kitchen.age - 2} mono weight="bold" color={late && !ready ? c.destructive : c.mutedForeground}>{formatAge(ageMs(new Date(firstFire(parts)).toISOString(), now))}</Txt>
      </View>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
        <Icon size={16} color={c.mutedForeground} />
        <Txt size={15} weight="semibold">{sourceLabel(t, order)}</Txt>
        <Txt size={14} muted>· {order.waiter}</Txt>
      </View>

      <View style={{ gap: 6 }}>
        {parts.map((p) => {
          const st = partStatus(p);
          const section = mock.sections.find((s) => s.id === p.sectionId)!;
          const lines = p.items.filter((l) => !l.voided);
          return (
            <View key={p.id} style={{ flexDirection: "row", alignItems: "center", gap: space.sm, minHeight: 36 }}>
              <Txt size={16} weight="medium" style={{ flex: 1 }} numberOfLines={1}>
                {name(section)}{p.roundNumber > 1 ? ` · ${t("expo.round", { round: p.roundNumber })}` : ""}
              </Txt>
              <Txt size={14} mono muted>{lines.filter((l) => l.bumped).length}/{lines.length}</Txt>
              <StatusPill tone={STATUS_TONE[st]} size="md">{t(`expo.status.${st}`)}</StatusPill>
            </View>
          );
        })}
      </View>

      {ready ? (
        <View style={{ gap: space.sm }}>
          <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
            <BellRing size={16} color={c.success} />
            <Txt size={14} weight="medium" color={c.success}>{t("expo.waiterAlerted", { name: order.waiter })}</Txt>
          </View>
          <View style={{ flexDirection: "row", gap: space.sm }}>
            <Button size="lg" variant="success" icon={HandPlatter} grow onPress={() => guard(() => handOff(order.id))}>{t("expo.handOff")}</Button>
            <Button size="icon-lg" variant="outline" icon={Printer} label={t("expo.reprint")} />
          </View>
        </View>
      ) : (
        <Button size="default" variant="ghost" icon={Printer} style={{ alignSelf: "flex-start" }}>{t("expo.reprint")}</Button>
      )}
    </View>
  );
}
