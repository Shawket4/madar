import { TextInput, View, type TextInputProps } from "react-native";

import { font, radius } from "@/theme/tokens";
import { useColors, useIsRtl } from "@/theme/use-theme";
import { Txt } from "./text";

/** The dashboard's Input + Label: a 52pt field with its label above. */
export function Field({ label, ...props }: TextInputProps & { label: string }) {
  const c = useColors();
  const rtl = useIsRtl();
  return (
    <View style={{ gap: 6 }}>
      <Txt size={14} weight="semibold">{label}</Txt>
      <TextInput
        placeholderTextColor={c.disabledForeground}
        {...props}
        style={{
          height: 52,
          paddingHorizontal: 14,
          borderRadius: radius.md,
          borderWidth: 1,
          borderColor: c.input,
          backgroundColor: c.card,
          color: c.foreground,
          fontFamily: font.regular,
          fontSize: 17,
          textAlign: rtl ? "right" : "left",
        }}
      />
    </View>
  );
}
