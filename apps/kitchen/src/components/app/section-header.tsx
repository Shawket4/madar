import type { ReactNode } from "react";
import { View } from "react-native";

import { radius } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";

/** A section's label (POS SPEC §7, dashboard SectionHeader): sentence case, optional count chip and trailing slot. */
export function SectionHeader({ title, count, trailing }: { title: string; count?: number; trailing?: ReactNode }) {
  const c = useColors();
  return (
    <View style={{ flexDirection: "row", alignItems: "center", justifyContent: "space-between", gap: 12, minHeight: 32 }}>
      <View style={{ flexDirection: "row", alignItems: "center", gap: 8, flexShrink: 1 }}>
        <Txt size={16} weight="semibold" numberOfLines={1}>{title}</Txt>
        {count !== undefined ? (
          <View style={{ backgroundColor: c.secondary, borderRadius: radius.full, paddingHorizontal: 7 }}>
            <Txt size={13} mono muted>{count}</Txt>
          </View>
        ) : null}
      </View>
      {trailing}
    </View>
  );
}
