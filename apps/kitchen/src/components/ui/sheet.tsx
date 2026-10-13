import type { ReactNode } from "react";
import { Modal, Pressable, ScrollView, View } from "react-native";
import { X } from "lucide-react-native";

import { radius, space, wash } from "@/theme/tokens";
import { useColors, useIsRtl } from "@/theme/use-theme";
import { Button } from "./button";
import { Txt } from "./text";

/** A centred dialog card (the dashboard's Dialog). Tap outside or ✕ to close. */
export function Sheet({ open, onClose, title, subtitle, width = 520, children }: {
  open: boolean;
  onClose?: () => void;
  title: string;
  subtitle?: string;
  width?: number;
  children: ReactNode;
}) {
  const c = useColors();
  const rtl = useIsRtl();
  return (
    <Modal visible={open} transparent animationType="fade" onRequestClose={onClose} supportedOrientations={["portrait", "landscape"]}>
      <View style={{ flex: 1, direction: rtl ? "rtl" : "ltr", alignItems: "center", justifyContent: "center", padding: space.lg }}>
        <Pressable style={{ position: "absolute", inset: 0, backgroundColor: wash("#000000", 0.55) }} onPress={onClose} accessibilityLabel="close" />
        <View style={{ width: "100%", maxWidth: width, maxHeight: "92%", backgroundColor: c.card, borderRadius: radius.xl, borderWidth: 1, borderColor: c.border, overflow: "hidden" }}>
          <View style={{ flexDirection: "row", alignItems: "flex-start", gap: space.md, padding: space.xl, paddingBottom: space.md }}>
            <View style={{ flex: 1 }}>
              <Txt size={22} weight="bold">{title}</Txt>
              {subtitle ? <Txt size={14} muted style={{ marginTop: 2 }}>{subtitle}</Txt> : null}
            </View>
            {onClose ? <Button variant="ghost" size="icon" icon={X} label="close" onPress={onClose} /> : null}
          </View>
          <ScrollView contentContainerStyle={{ padding: space.xl, paddingTop: space.sm, gap: space.lg }}>{children}</ScrollView>
        </View>
      </View>
    </Modal>
  );
}
