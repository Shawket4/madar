import type { ReactNode } from "react";
import { Pressable, View, type StyleProp, type ViewStyle } from "react-native";
import type { LucideIcon } from "lucide-react-native";

import { kitchen, radius, wash, type Palette } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "./text";

/*
 * The dashboard's Button (src/components/ui/button.tsx): the same variants,
 * sized up for the kitchen — `lg` is the 56pt gloved-hand target (APP-6).
 */
export type ButtonVariant = "default" | "secondary" | "outline" | "ghost" | "destructive" | "success" | "chrome";
export type ButtonSize = "sm" | "default" | "lg" | "icon" | "icon-lg";

function look(c: Palette, v: ButtonVariant): { bg: string; fg: string; border?: string } {
  switch (v) {
    case "default": return { bg: c.primary, fg: c.primaryForeground };
    case "secondary": return { bg: c.secondary, fg: c.foreground };
    case "outline": return { bg: c.card, fg: c.foreground, border: c.input };
    case "ghost": return { bg: "transparent", fg: c.foreground };
    case "destructive": return { bg: c.destructive, fg: c.destructiveForeground };
    case "success": return { bg: c.success, fg: c.successForeground };
    // On the ink top bar.
    case "chrome": return { bg: c.chromeRaised, fg: c.chromeForeground };
  }
}

const SIZE: Record<ButtonSize, { h: number; px: number; text: number; icon: number }> = {
  sm: { h: 36, px: 12, text: 14, icon: 16 },
  default: { h: 44, px: 16, text: 15, icon: 18 },
  lg: { h: kitchen.touch, px: 20, text: 17, icon: 20 },
  icon: { h: 44, px: 0, text: 15, icon: 20 },
  "icon-lg": { h: kitchen.touch, px: 0, text: 15, icon: 22 },
};

export interface ButtonProps {
  children?: ReactNode;
  onPress?: () => void;
  variant?: ButtonVariant;
  size?: ButtonSize;
  icon?: LucideIcon;
  disabled?: boolean;
  /** Required for icon-only buttons. */
  label?: string;
  style?: StyleProp<ViewStyle>;
  grow?: boolean;
}

export function Button({ children, onPress, variant = "default", size = "default", icon: Icon, disabled, label, style, grow }: ButtonProps) {
  const c = useColors();
  const l = look(c, variant);
  const s = SIZE[size];
  const iconOnly = size === "icon" || size === "icon-lg";
  const fg = disabled ? c.disabledForeground : l.fg;
  return (
    <Pressable
      onPress={onPress}
      disabled={disabled}
      accessibilityRole="button"
      accessibilityLabel={label}
      style={({ pressed }) => [
        {
          height: s.h,
          width: iconOnly ? s.h : undefined,
          paddingHorizontal: s.px,
          borderRadius: radius.md,
          backgroundColor: disabled ? c.disabled : pressed && variant === "ghost" ? c.accent : l.bg,
          borderWidth: l.border ? 1 : 0,
          borderColor: l.border,
          flexDirection: "row",
          alignItems: "center",
          justifyContent: "center",
          gap: 8,
          flexGrow: grow ? 1 : 0,
          opacity: pressed && variant !== "ghost" ? 0.88 : 1,
          transform: [{ scale: pressed ? 0.98 : 1 }],
        },
        style,
      ]}
    >
      {Icon ? <Icon size={s.icon} color={fg} strokeWidth={2.25} /> : null}
      {children != null ? (
        typeof children === "string" ? <Txt size={s.text} weight="semibold" color={fg}>{children}</Txt> : <View>{children}</View>
      ) : null}
    </Pressable>
  );
}

/** A segmented control — the dashboard's Tabs list, as a picker. */
export function Segmented<T extends string>({ value, options, onChange }: { value: T; options: { value: T; label: string }[]; onChange: (v: T) => void }) {
  const c = useColors();
  return (
    <View style={{ flexDirection: "row", backgroundColor: c.secondary, borderRadius: radius.md, padding: 3, gap: 3 }}>
      {options.map((o) => {
        const on = o.value === value;
        return (
          <Pressable
            key={o.value}
            onPress={() => onChange(o.value)}
            accessibilityRole="button"
            accessibilityState={{ selected: on }}
            style={{ flex: 1, height: 40, borderRadius: radius.sm, alignItems: "center", justifyContent: "center", backgroundColor: on ? c.card : "transparent", borderWidth: on ? 1 : 0, borderColor: wash(c.foreground, 0.06) }}
          >
            <Txt size={14} weight={on ? "semibold" : "medium"} muted={!on}>{o.label}</Txt>
          </Pressable>
        );
      })}
    </View>
  );
}
