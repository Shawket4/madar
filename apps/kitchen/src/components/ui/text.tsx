import { Text, type TextProps, type TextStyle } from "react-native";

import { font } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";

type Weight = "regular" | "medium" | "semibold" | "bold";

export interface TxtProps extends TextProps {
  size?: number;
  weight?: Weight;
  /** Plex Mono, tabular — order numbers, ages, counts. */
  mono?: boolean;
  color?: string;
  muted?: boolean;
  strike?: boolean;
  align?: TextStyle["textAlign"];
}

/** The one text primitive. Line height is 1.3× for Arabic's taller marks. */
export function Txt({ size = 15, weight = "regular", mono, color, muted, strike, align, style, ...rest }: TxtProps) {
  const c = useColors();
  return (
    <Text
      {...rest}
      style={[
        {
          fontFamily: mono ? (weight === "bold" || weight === "semibold" ? font.monoBold : font.mono) : font[weight],
          fontSize: size,
          lineHeight: Math.round(size * 1.3),
          color: color ?? (muted ? c.mutedForeground : c.foreground),
          textAlign: align,
          fontVariant: mono ? ["tabular-nums"] : undefined,
          textDecorationLine: strike ? "line-through" : undefined,
        },
        style,
      ]}
    />
  );
}
