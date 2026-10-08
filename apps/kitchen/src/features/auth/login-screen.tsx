import { useRef, useState } from "react";
import { Animated, Pressable, View } from "react-native";
import { useTranslation } from "react-i18next";
import { Delete, Wrench } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { backend } from "@/data/backend";
import { radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/input";
import { Txt } from "@/components/ui/text";
import { DeviceFrame } from "@/components/app/device-frame";

const LEN = 6;

/**
 * Staff sign-in (DV-2): the POS teller login — name, then a 6-digit PIN that
 * submits itself, a shake on a refusal. A cook signs in at the start of a shift.
 */
export function LoginScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const device = useKitchen((s) => s.device);
  const signIn = useKitchen((s) => s.signIn);
  const resetDevice = useKitchen((s) => s.resetDevice);
  const storeError = useKitchen((s) => s.error);
  const [name, setName] = useState("");
  const [pin, setPin] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const shake = useRef(new Animated.Value(0)).current;

  const submit = async (code: string) => {
    setBusy(true);
    try {
      await signIn(name, code);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
      setPin("");
      Animated.sequence([10, -10, 8, -8, 4, 0].map((x) => Animated.timing(shake, { toValue: x, duration: 50, useNativeDriver: true }))).start();
    } finally {
      setBusy(false);
    }
  };

  const press = (d: string) => {
    if (busy) return;
    setError(null);
    const next = (pin + d).slice(0, LEN);
    setPin(next);
    if (next.length === LEN) void submit(next);
  };

  const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"];
  const shown = error ?? storeError;

  return (
    <DeviceFrame
      title={t("auth.title")}
      subtitle={`${device.branchName ?? ""} · ${t("auth.body")}`}
      width={440}
      trailing={<Button variant="chrome" icon={Wrench} onPress={resetDevice}>{t("auth.changeBranch")}</Button>}
    >
      <Field label={t("auth.name")} value={name} onChangeText={setName} autoCapitalize="words" autoCorrect={false} textContentType="name" />

      <View style={{ gap: space.md }}>
        <Txt size={14} weight="semibold">{t("auth.pin")}</Txt>
        <Animated.View style={{ flexDirection: "row", justifyContent: "center", gap: 14, transform: [{ translateX: shake }] }}>
          {Array.from({ length: LEN }, (_, i) => (
            <View key={i} style={{ width: 18, height: 18, borderRadius: 9, backgroundColor: i < pin.length ? (shown ? c.destructive : c.foreground) : "transparent", borderWidth: 2, borderColor: shown ? c.destructive : c.input }} />
          ))}
        </Animated.View>
        <Txt size={14} align="center" color={shown ? c.destructive : c.mutedForeground} style={{ minHeight: 20 }}>
          {shown ?? (busy ? t("auth.checking") : backend().mock ? t("auth.mockHint") : " ")}
        </Txt>
        <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.sm, direction: "ltr" }}>
          {keys.map((k, i) => (
            <Pressable
              key={i}
              disabled={!k || busy || !name.trim()}
              onPress={() => (k === "⌫" ? setPin(pin.slice(0, -1)) : press(k))}
              accessibilityRole="button"
              accessibilityLabel={k === "⌫" ? t("auth.delete") : k}
              style={({ pressed }) => ({
                width: "31.5%", height: 68, borderRadius: radius.lg, alignItems: "center", justifyContent: "center",
                backgroundColor: !k ? "transparent" : pressed ? c.accent : c.secondary,
                opacity: k && !name.trim() ? 0.5 : 1,
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
