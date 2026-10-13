import { View } from "react-native";
import { X, CircleX } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Txt } from "@/components/ui/text";
import { toneColors } from "./status-pill";

/** A refused or failed action, in the core's own words — never swallowed. */
export function ErrorBanner() {
  const c = useColors();
  const error = useKitchen((s) => s.error);
  const setK = useKitchen((s) => s.set);
  if (!error) return null;
  const tone = toneColors(c, "danger");
  return (
    <View accessibilityRole="alert" style={{ flexDirection: "row", alignItems: "center", gap: space.md, paddingStart: space.xl, paddingEnd: space.sm, paddingVertical: space.xs, backgroundColor: tone.bg, borderBottomWidth: 1, borderBottomColor: c.border }}>
      <CircleX size={18} color={tone.fg} />
      <Txt size={15} weight="medium" color={tone.fg} style={{ flex: 1 }}>{error}</Txt>
      <Button variant="ghost" size="icon" icon={X} label="dismiss" onPress={() => setK("error", null)} />
    </View>
  );
}
