import type { ReactNode } from "react";
import { View } from "react-native";
import type { LucideIcon } from "lucide-react-native";

import { radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";

/** Empty content (POS SPEC §11, dashboard EmptyState): badge glyph, title that says what will appear, optional action. */
export function EmptyState({ icon: Icon, title, description, action, tone }: {
  icon?: LucideIcon;
  title: string;
  description?: string;
  action?: ReactNode;
  /** Tint the badge (the board's all-clear is success). */
  tone?: { bg: string; fg: string };
}) {
  const c = useColors();
  return (
    <View style={{ alignItems: "center", justifyContent: "center", gap: space.md, paddingVertical: 56, paddingHorizontal: space.xl, borderRadius: radius.xl, borderWidth: 1, borderColor: c.border, backgroundColor: c.card }}>
      {Icon ? (
        <View style={{ width: 64, height: 64, borderRadius: 32, alignItems: "center", justifyContent: "center", backgroundColor: tone?.bg ?? c.secondary }}>
          <Icon size={28} color={tone?.fg ?? c.mutedForeground} />
        </View>
      ) : null}
      <Txt size={20} weight="semibold" align="center">{title}</Txt>
      {description ? <Txt size={15} muted align="center" style={{ maxWidth: 420 }}>{description}</Txt> : null}
      {action}
    </View>
  );
}
