import { Pressable, View } from "react-native";
import { Check, type LucideIcon } from "lucide-react-native";

import { radius, space, wash } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";
import { StatusPill } from "./status-pill";

/** A big selectable tile (setup: branch, mode, section). */
export function Choice({ on, onPress, icon: Icon, title, body, badge }: {
  on: boolean; onPress: () => void; icon: LucideIcon; title: string; body?: string; badge?: string;
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
        <Txt size={17} weight="semibold" numberOfLines={1} style={{ flexShrink: 1 }}>{title}</Txt>
        <View style={{ flex: 1 }} />
        {badge ? <StatusPill tone="accent" size="sm">{badge}</StatusPill> : null}
        {on ? <Check size={20} color={c.foreground} strokeWidth={3} /> : null}
      </View>
      {body ? <Txt size={14} muted>{body}</Txt> : null}
    </Pressable>
  );
}
