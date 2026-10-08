import { useState } from "react";
import { ScrollView, View } from "react-native";
import { useTranslation } from "react-i18next";
import { History, PartyPopper, RotateCcw } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { radius, space, wash, kitchen } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Txt } from "@/components/ui/text";
import { EmptyState } from "@/components/app/empty-state";
import { ErrorBanner } from "@/components/app/error-banner";
import { NetBanner } from "@/components/app/net-banner";
import { TopBar } from "@/components/app/top-bar";
import { toneColors } from "@/components/app/status-pill";
import { formatClock, useNow } from "@/lib/hooks";
import { allDay, boardParts, recallable } from "./logic";
import { sourceLabel, TicketCard } from "./ticket-card";

/** The section screen (KB-1..7): one or more sections' parts, oldest first. */
export function BoardScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const now = useNow(1000);
  const device = useKitchen((s) => s.device);
  const sections = useKitchen((s) => s.sections);
  const parts = useKitchen((s) => s.parts);
  const finishedAt = useKitchen((s) => s.finishedAt);
  const toggleLine = useKitchen((s) => s.toggleLine);
  const bumpPart = useKitchen((s) => s.bumpPart);
  const setK = useKitchen((s) => s.set);
  const [width, setWidth] = useState(0);

  const sectionIds = device.sectionIds;
  const mine = parts.filter((p) => sectionIds.includes(p.sectionId));
  const shown = boardParts(parts, sectionIds, now, finishedAt);
  const recent = recallable(parts, sectionIds);
  const open = mine.filter((p) => !p.done).length;
  const sectionName = (id: string) => sections.find((s) => s.id === id)?.name ?? "…";
  const title = sectionIds.map(sectionName).join(" · ");

  // Masonry by reading order: card i goes to column i % n, so the oldest run across the top.
  const gap = space.lg;
  const cols = Math.max(1, Math.min(6, Math.floor((width - gap) / (kitchen.columnMin + gap))));
  const colW = cols ? (width - gap * (cols + 1)) / cols : 0;
  const columns = Array.from({ length: cols }, (_, i) => shown.filter((_, j) => j % cols === i));
  const multi = sectionIds.length > 1;

  return (
    <View style={{ flex: 1, backgroundColor: c.background }}>
      <TopBar
        title={title}
        subtitle={`${device.branchName ?? ""} · ${t(multi ? "board.sections" : "board.section")}`}
        count={open}
        actions={
          <Button variant="chrome" size="default" icon={History} onPress={() => setK("recallOpen", true)}>
            {recent.length ? t("board.recallCount", { count: recent.length }) : t("board.recall")}
          </Button>
        }
      />
      <NetBanner />
      <ErrorBanner />
      <AllDayStrip />
      <ScrollView
        style={{ flex: 1 }}
        onLayout={(e) => setWidth(e.nativeEvent.layout.width)}
        contentContainerStyle={{ padding: gap, paddingTop: space.md, flexGrow: 1 }}
      >
        {shown.length === 0 ? (
          <View style={{ flex: 1, justifyContent: "center" }}>
            <EmptyState icon={PartyPopper} tone={toneColors(c, "success")} title={t("board.clearTitle")} description={t("board.clearBody")} />
          </View>
        ) : (
          <View style={{ flexDirection: "row", gap, alignItems: "flex-start" }}>
            {columns.map((col, i) => (
              <View key={i} style={{ gap, width: colW }}>
                {col.map((p) => (
                  <TicketCard
                    key={p.id}
                    part={p}
                    now={now}
                    width={colW}
                    sectionName={multi ? sectionName(p.sectionId) : undefined}
                    onLine={(l) => void toggleLine(p, l)}
                    onBumpAll={() => void bumpPart(p)}
                  />
                ))}
              </View>
            ))}
          </View>
        )}
      </ScrollView>
      <RecallSheet />
    </View>
  );
}

/** KB-6: how many of each item are waiting in this screen's sections. */
function AllDayStrip() {
  const { t } = useTranslation();
  const c = useColors();
  const sectionIds = useKitchen((s) => s.device.sectionIds);
  const parts = useKitchen((s) => s.parts);
  const counts = allDay(parts.filter((p) => sectionIds.includes(p.sectionId) && !p.done));
  if (!counts.length) return null;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", backgroundColor: c.card, borderBottomWidth: 1, borderBottomColor: c.border }}>
      <Txt size={13} weight="semibold" muted style={{ paddingStart: space.xl, paddingEnd: space.sm }}>{t("board.allDay")}</Txt>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space.sm, paddingVertical: space.sm, paddingEnd: space.xl }}>
        {counts.map((x) => (
          <View key={x.name} style={{ flexDirection: "row", alignItems: "center", gap: 8, height: 36, paddingHorizontal: 12, borderRadius: radius.full, backgroundColor: c.secondary }}>
            <Txt size={17} mono weight="bold">{x.qty}</Txt>
            <Txt size={15} weight="medium">{x.name}</Txt>
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

/** KB-4: finished parts still on an open ticket — bring one back if it was bumped by mistake. */
function RecallSheet() {
  const { t } = useTranslation();
  const c = useColors();
  const open = useKitchen((s) => s.recallOpen);
  const parts = useKitchen((s) => s.parts);
  const sectionIds = useKitchen((s) => s.device.sectionIds);
  const setK = useKitchen((s) => s.set);
  const recall = useKitchen((s) => s.recall);
  const list = recallable(parts, sectionIds);

  return (
    <Sheet open={open} onClose={() => setK("recallOpen", false)} title={t("recall.title")} subtitle={t("recall.subtitle")}>
      {list.length === 0 ? <Txt size={15} muted>{t("recall.empty")}</Txt> : null}
      {list.map((p) => (
        <View key={p.id} style={{ flexDirection: "row", alignItems: "center", gap: space.md, padding: space.md, borderRadius: radius.lg, borderWidth: 1, borderColor: c.border, backgroundColor: wash(c.success, 0.06) }}>
          <View style={{ flex: 1 }}>
            <Txt size={20} mono weight="bold">#{p.kitchenRef}</Txt>
            <Txt size={14} muted numberOfLines={1}>
              {sourceLabel(t, p)} · {formatClock(p.createdAt)} · {p.items.map((l) => `${l.qty}× ${l.name}`).join(", ")}
            </Txt>
          </View>
          <Button variant="outline" icon={RotateCcw} onPress={() => void recall(p)}>{t("recall.action")}</Button>
        </View>
      ))}
    </Sheet>
  );
}
