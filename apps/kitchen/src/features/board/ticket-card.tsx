import { Pressable, View } from "react-native";
import { useTranslation } from "react-i18next";
import type { TFunction } from "i18next";
import { Check, Globe, ShoppingBag, Utensils, type LucideIcon } from "lucide-react-native";

import type { KitchenLine, KitchenPart, SourceType } from "@/data/types";
import { kitchen, mix, radius, space, wash, type Palette } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Txt } from "@/components/ui/text";
import { StatusPill } from "@/components/app/status-pill";
import { formatClock, useLocalName } from "@/lib/hooks";
import { ageMs, ageTone, formatAge, type AgeTone } from "./logic";

export const SOURCE_ICON: Record<SourceType, LucideIcon> = { dine_in: Utensils, takeaway: ShoppingBag, online: Globe };

/** Header tint by age (KB-3). Solid fills: read from across the kitchen, not up close. */
function headerLook(c: Palette, tone: AgeTone): { bg: string; fg: string; sub: string } {
  switch (tone) {
    case "fresh": return { bg: c.secondary, fg: c.foreground, sub: c.mutedForeground };
    case "amber": return { bg: c.warning, fg: c.warningForeground, sub: wash(c.warningForeground, 0.8) };
    case "red": return { bg: c.destructive, fg: c.destructiveForeground, sub: wash(c.destructiveForeground, 0.8) };
    case "done": return { bg: c.success, fg: c.successForeground, sub: wash(c.successForeground, 0.8) };
  }
}

export function sourceLabel(t: TFunction, p: { sourceType: SourceType; tableLabel?: string }): string {
  if (p.sourceType === "dine_in") return t("source.table", { table: p.tableLabel ?? "—" });
  return t(`source.${p.sourceType}`);
}

export function TicketCard({ part, now, width, sectionName, onLine, onBumpAll }: {
  part: KitchenPart;
  /** Shown when the device covers several sections (KB-1). */
  sectionName?: string;
  now: number;
  width: number;
  onLine: (line: KitchenLine) => void;
  onBumpAll: () => void;
}) {
  const { t } = useTranslation();
  const c = useColors();
  const tone = ageTone(part, now);
  const h = headerLook(c, tone);
  const SourceIcon = SOURCE_ICON[part.sourceType];
  const done = tone === "done";

  return (
    <View
      style={{
        width,
        backgroundColor: c.card,
        borderRadius: radius.xl,
        borderWidth: done || tone === "red" ? 3 : 1,
        borderColor: done ? c.success : tone === "red" ? c.destructive : c.border,
        overflow: "hidden",
      }}
    >
      {/* Header: order number largest, then type · waiter, age on the end side. */}
      <View style={{ backgroundColor: h.bg, paddingHorizontal: space.lg, paddingVertical: space.md, gap: 4 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: space.sm }}>
          <Txt size={kitchen.orderNumber} mono weight="bold" color={h.fg} style={{ flexShrink: 1 }}>#{part.kitchenRef}</Txt>
          <View style={{ flex: 1 }} />
          {done ? (
            <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
              <Check size={22} color={h.fg} strokeWidth={3} />
              <Txt size={18} weight="bold" color={h.fg}>{t("board.done")}</Txt>
            </View>
          ) : (
            <Txt size={kitchen.age} mono weight="bold" color={h.fg}>{formatAge(ageMs(part.createdAt, now))}</Txt>
          )}
        </View>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 6 }}>
          <SourceIcon size={16} color={h.fg} />
          <Txt size={15} weight="semibold" color={h.fg}>{sourceLabel(t, part)}</Txt>
          <Txt size={14} color={h.sub} numberOfLines={1} style={{ flexShrink: 1 }}>· {part.waiter} · {formatClock(part.createdAt)}</Txt>
        </View>
      </View>

      {sectionName ? (
        <View style={{ paddingHorizontal: space.lg, paddingVertical: 6, backgroundColor: c.muted, borderBottomWidth: 1, borderBottomColor: c.border }}>
          <Txt size={13} weight="semibold" muted>{sectionName}</Txt>
        </View>
      ) : null}

      {part.roundNumber > 1 ? (
        <View style={{ paddingHorizontal: space.lg, paddingTop: space.md }}>
          <StatusPill tone="info" size="md">{t("board.addition", { round: part.roundNumber })}</StatusPill>
        </View>
      ) : null}

      {part.note ? (
        <View style={{ marginHorizontal: space.lg, marginTop: space.md, padding: space.md, borderRadius: radius.md, backgroundColor: wash(c.warning, 0.14) }}>
          <Txt size={15} weight="medium" color={mix(c.warning, c.foreground, 0.55)}>{part.note}</Txt>
        </View>
      ) : null}

      <View style={{ paddingVertical: space.sm }}>
        {part.items.map((l, i) => (
          <LineRow key={l.id} line={l} first={i === 0} onPress={() => onLine(l)} />
        ))}
      </View>

      {!done ? (
        <View style={{ padding: space.md, paddingTop: 0 }}>
          <Button size="lg" variant="default" icon={Check} onPress={onBumpAll}>{t("board.bumpAll")}</Button>
        </View>
      ) : null}
    </View>
  );
}

function LineRow({ line: l, first, onPress }: { line: KitchenLine; first: boolean; onPress: () => void }) {
  const { t } = useTranslation();
  const c = useColors();
  const name = useLocalName();
  const off = l.bumped || l.voided;
  return (
    <Pressable
      onPress={onPress}
      disabled={l.voided}
      accessibilityRole="checkbox"
      accessibilityState={{ checked: l.bumped, disabled: l.voided }}
      style={({ pressed }) => ({
        flexDirection: "row",
        alignItems: "flex-start",
        gap: space.md,
        minHeight: kitchen.touch,
        paddingHorizontal: space.lg,
        paddingVertical: space.sm + 2,
        borderTopWidth: first ? 0 : 1,
        borderTopColor: c.border,
        backgroundColor: pressed ? c.accent : "transparent",
      })}
    >
      <View
        style={{
          width: 30, height: 30, marginTop: 1, borderRadius: radius.sm, alignItems: "center", justifyContent: "center",
          borderWidth: l.bumped ? 0 : 2, borderColor: c.input, backgroundColor: l.bumped ? c.success : "transparent",
        }}
      >
        {l.bumped ? <Check size={20} color={c.successForeground} strokeWidth={3} /> : null}
      </View>
      <Txt size={kitchen.itemName} mono weight="bold" muted={off} strike={off} style={{ minWidth: 34 }}>{l.qty}×</Txt>
      <View style={{ flex: 1, gap: 2 }}>
        <View style={{ flexDirection: "row", alignItems: "center", gap: 8, flexWrap: "wrap" }}>
          <Txt size={kitchen.itemName} weight="semibold" muted={off} strike={off}>
            {name(l)}{l.sizeLabel ? ` · ${l.sizeLabel}` : ""}
          </Txt>
          {l.voided ? <StatusPill tone="danger" size="sm">{t("board.void")}</StatusPill> : null}
        </View>
        {l.modifiers.length ? <Txt size={15} muted strike={off}>{l.modifiers.join(" · ")}</Txt> : null}
        {l.notes ? <Txt size={15} weight="semibold" color={mix(c.warning, c.foreground, 0.55)} strike={off}>{l.notes}</Txt> : null}
      </View>
    </Pressable>
  );
}
