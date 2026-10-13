import { useRef, useState } from "react";
import { Animated, Pressable, View } from "react-native";
import { useTranslation } from "react-i18next";
import { Delete } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { backend } from "@/data/backend";
import { radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Txt } from "@/components/ui/text";
import { DeviceFrame } from "@/components/app/device-frame";

const LEN = 8;

/**
 * Device setup (DV-1), the only sign-in a kitchen ever does: the 8-digit code
 * a manager made for this screen in the dashboard's branch plan. It binds the
 * branch and the screen stays signed in from then on. No person, no account.
 */
export function SetupScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const activate = useKitchen((s) => s.activate);
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const shake = useRef(new Animated.Value(0)).current;

  const submit = async (value: string) => {
    setBusy(true);
    try {
      await activate(value);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setCode("");
      Animated.sequence([10, -10, 8, -8, 4, 0].map((x) => Animated.timing(shake, { toValue: x, duration: 50, useNativeDriver: true }))).start();
    } finally {
      setBusy(false);
    }
  };

  const press = (d: string) => {
    if (busy) return;
    setError(null);
    const next = (code + d).slice(0, LEN);
    setCode(next);
    if (next.length === LEN) void submit(next);
  };

  const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"];

  return (
    <DeviceFrame title={t("setup.title")} subtitle={t("setup.subtitle")} width={460}>
      <View style={{ gap: space.md }}>
        <Txt size={14} weight="semibold">{t("setup.code")}</Txt>
        <Animated.View style={{ flexDirection: "row", justifyContent: "center", gap: 10, transform: [{ translateX: shake }], direction: "ltr" }}>
          {Array.from({ length: LEN }, (_, i) => (
            <View key={i} style={{ width: 34, height: 44, borderRadius: radius.md, borderWidth: 2, borderColor: error ? c.destructive : i < code.length ? c.foreground : c.input, alignItems: "center", justifyContent: "center" }}>
              <Txt size={22} mono weight="semibold">{code[i] ?? ""}</Txt>
            </View>
          ))}
        </Animated.View>
        <Txt size={14} align="center" color={error ? c.destructive : c.mutedForeground} style={{ minHeight: 20 }}>
          {error ?? (busy ? t("setup.activating") : backend().mock ? t("setup.mockNote") : t("setup.codeHint"))}
        </Txt>
        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.sm, direction: "ltr" }}>
          {keys.map((k, i) => (
            <Pressable
              key={i}
              disabled={!k || busy}
              onPress={() => (k === "⌫" ? setCode(code.slice(0, -1)) : press(k))}
              accessibilityRole="button"
              accessibilityLabel={k === "⌫" ? t("setup.delete") : k}
              style={({ pressed }) => ({
                width: "31.5%", height: 68, borderRadius: radius.lg, alignItems: "center", justifyContent: "center",
                backgroundColor: !k ? "transparent" : pressed ? c.accent : c.secondary,
              })}
            >
              {k === "⌫" ? <Delete size={26} color={c.foreground} /> : <Txt size={28} mono weight="semibold">{k}</Txt>}
            </Pressable>
          ))}
        </View>
      </View>
    </DeviceFrame>
  );
}
