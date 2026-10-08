import { useState } from "react";
import { ScrollView, View } from "react-native";
import { useTranslation } from "react-i18next";
import { History, PartyPopper, RotateCcw } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import * as mock from "@/data/mock";
import { radius, space, wash, kitchen } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Txt } from "@/components/ui/text";
import { EmptyState } from "@/components/app/empty-state";
import { NetBanner } from "@/components/app/net-banner";
import { TopBar } from "@/components/app/top-bar";
import { toneColors } from "@/components/app/status-pill";
import { formatClock, useLocalName, useNow } from "@/lib/hooks";
import { allDay, boardParts, recallable } from "./logic";
import { sourceLabel, TicketCard } from "./ticket-card";

/** The section screen (KB-1..7): one or more sections' parts, oldest first. */
export function BoardScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const now = useNow(1000);
  const device = useKitchen((s) => s.device)!;
  const parts = useKitchen((s) => s.parts);
  const guard = useKitchen((s) => s.guard);
  const toggleLine = useKitchen((s) => s.toggleLine);
  const bumpPart = useKitchen((s) => s.bumpPart);
  const setK = useKitchen((s) => s.set);
  const [width, setWidth] = useState(0);

  const sectionIds = device.sectionIds;
  const shown = boardParts(parts, sectionIds, now);
  const recent = recallable(parts, sectionIds, now);
  const open = shown.filter((p) => !p.bumpedAt).length;
  const branch = mock.branches.find((b) => b.id === device.branchId)!;
  const title = sectionIds.map((id) => name(mock.sections.find((s) => s.id === id)!)).join(" · ");

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
        subtitle={`${name(branch)} · ${t(multi ? "board.sections" : "board.section")}`}
        count={open}
        actions={
          <Button variant="chrome" size="default" icon={History} onPress={() => setK("recallOpen", true)}>
            {recent.length ? t("board.recallCount", { count: recent.length }) : t("board.recall")}
          </Button>
        }
      />
      <NetBanner />
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
                    sectionName={multi ? name(mock.sections.find((x) => x.id === p.sectionId)!) : undefined}
                    onLine={(l) => guard(() => toggleLine(p.id, l.id))}
                    onBumpAll={() => guard(() => bumpPart(p.id))}
                  />
                ))}
              </View>
            ))}
          </View>
        )}
      </ScrollView>
      <RecallSheet sectionIds={sectionIds} now={now} />
    </View>
  );
}

/** KB-6: how many of each item are waiting in this section. */
function AllDayStrip() {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const device = useKitchen((s) => s.device)!;
  const parts = useKitchen((s) => s.parts);
  const counts = allDay(parts.filter((p) => device.sectionIds.includes(p.sectionId)));
  if (!counts.length) return null;
  return (
    <View style={{ flexDirection: "row", alignItems: "center", backgroundColor: c.card, borderBottomWidth: 1, borderBottomColor: c.border }}>
      <Txt size={13} weight="semibold" muted style={{ paddingStart: space.xl, paddingEnd: space.sm }}>{t("board.allDay")}</Txt>
      <ScrollView horizontal showsHorizontalScrollIndicator={false} contentContainerStyle={{ gap: space.sm, paddingVertical: space.sm, paddingEnd: space.xl }}>
        {counts.map((x) => (
          <View key={x.name} style={{ flexDirection: "row", alignItems: "center", gap: 8, height: 36, paddingHorizontal: 12, borderRadius: radius.full, backgroundColor: c.secondary }}>
            <Txt size={17} mono weight="bold">{x.qty}</Txt>
            <Txt size={15} weight="medium">{name(x)}</Txt>
          </View>
        ))}
      </ScrollView>
    </View>
  );
}

/** KB-4: the last bumped parts, recallable for 10 minutes. */
function RecallSheet({ sectionIds, now }: { sectionIds: string[]; now: number }) {
  const { t } = useTranslation();
  const c = useColors();
  const open = useKitchen((s) => s.recallOpen);
  const parts = useKitchen((s) => s.parts);
  const setK = useKitchen((s) => s.set);
  const recall = useKitchen((s) => s.recall);
  const guard = useKitchen((s) => s.guard);
  const list = recallable(parts, sectionIds, now);
  const who = (id: string | null) => mock.staff.find((s) => s.id === id)?.name.split(" ")[0] ?? "—";

  return (
    <Sheet open={open} onClose={() => setK("recallOpen", false)} title={t("recall.title")} subtitle={t("recall.subtitle")}>
      {list.length === 0 ? <Txt size={15} muted>{t("recall.empty")}</Txt> : null}
      {list.map((p) => (
        <View key={p.id} style={{ flexDirection: "row", alignItems: "center", gap: space.md, padding: space.md, borderRadius: radius.lg, borderWidth: 1, borderColor: c.border, backgroundColor: wash(c.success, 0.06) }}>
          <View style={{ flex: 1 }}>
            <Txt size={20} mono weight="bold">#{p.kitchenRef}</Txt>
            <Txt size={14} muted>
              {sourceLabel(t, p)} · {t("recall.bumpedBy", { name: who(p.bumpedBy), time: formatClock(p.bumpedAt!) })}
            </Txt>
          </View>
          <Button variant="outline" icon={RotateCcw} onPress={() => guard(() => recall(p.id))}>{t("recall.action")}</Button>
        </View>
      ))}
    </Sheet>
  );
}
