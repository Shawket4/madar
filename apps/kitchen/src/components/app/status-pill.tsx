import type { ReactNode } from "react";
import { View } from "react-native";
import { Circle, CircleCheck, CircleDashed, CircleX, Info, TriangleAlert, type LucideIcon } from "lucide-react-native";

import { mix, radius, wash, type Palette } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";

/**
 * A status — glyph + label, never colour alone (POS SPEC §10). Same tones as
 * the dashboard's StatusPill: text is the tone pulled toward the foreground so
 * it clears AA on its own wash in both themes.
 */
export type StatusTone = "neutral" | "accent" | "success" | "warning" | "danger" | "info";

const GLYPH: Record<StatusTone, LucideIcon> = {
  neutral: Circle,
  accent: CircleDashed,
  success: CircleCheck,
  warning: TriangleAlert,
  danger: CircleX,
  info: Info,
};

export function toneColors(c: Palette, tone: StatusTone): { bg: string; fg: string } {
  switch (tone) {
    case "neutral": return { bg: c.secondary, fg: c.mutedForeground };
    case "accent": return { bg: c.accent, fg: c.foreground };
    case "success": return { bg: wash(c.success, 0.14), fg: mix(c.success, c.foreground, 0.6) };
    case "warning": return { bg: wash(c.warning, 0.16), fg: mix(c.warning, c.foreground, 0.55) };
    case "danger": return { bg: wash(c.destructive, 0.14), fg: mix(c.destructive, c.foreground, 0.6) };
    case "info": return { bg: wash(c.info, 0.14), fg: mix(c.info, c.foreground, 0.6) };
  }
}

export function StatusPill({ tone = "neutral", icon, size = "md", children }: {
  tone?: StatusTone;
  icon?: LucideIcon;
  size?: "sm" | "md" | "lg";
  children: ReactNode;
}) {
  const c = useColors();
  const { bg, fg } = toneColors(c, tone);
  const Glyph = icon ?? GLYPH[tone];
  const s = { sm: { h: 22, t: 12, i: 12 }, md: { h: 28, t: 14, i: 15 }, lg: { h: 34, t: 16, i: 18 } }[size];
  return (
    <View style={{ flexDirection: "row", alignItems: "center", gap: 5, height: s.h, paddingStart: 8, paddingEnd: 10, borderRadius: radius.full, backgroundColor: bg, alignSelf: "flex-start" }}>
      <Glyph size={s.i} color={fg} strokeWidth={2.25} />
      <Txt size={s.t} weight="semibold" color={fg} numberOfLines={1}>{children}</Txt>
    </View>
  );
}
