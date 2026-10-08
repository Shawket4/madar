import { useEffect, useRef, useState } from "react";
import { Animated, Pressable, View } from "react-native";
import { useTranslation } from "react-i18next";
import { Delete, LogOut } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import * as mock from "@/data/mock";
import { radius, space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Sheet } from "@/components/ui/sheet";
import { Txt } from "@/components/ui/text";

const LEN = 6;

/**
 * Staff PIN (DV-2): the POS teller login — 6 digits, auto-submit, a shake on
 * a wrong one. `manager` asks for a manager (DV-1: only a manager changes setup).
 */
export function PinSheet() {
  const { t } = useTranslation();
  const c = useColors();
  const pinFor = useKitchen((s) => s.pinFor);
  const user = useKitchen((s) => s.user);
  const signIn = useKitchen((s) => s.signIn);
  const signOut = useKitchen((s) => s.signOut);
  const setK = useKitchen((s) => s.set);
  const [pin, setPin] = useState("");
  const [error, setError] = useState(false);
  const shake = useRef(new Animated.Value(0)).current;

  useEffect(() => { setPin(""); setError(false); }, [pinFor]);

  const close = () => { setK("pinFor", null); setK("afterPin", null); };

  const submit = (code: string) => {
    const who = mock.staff.find((s) => s.pin === code && (pinFor !== "manager" || s.role === "manager"));
    if (who) return signIn(who);
    setError(true);
    setPin("");
    Animated.sequence([10, -10, 8, -8, 4, 0].map((x) => Animated.timing(shake, { toValue: x, duration: 50, useNativeDriver: true }))).start();
  };

  const press = (d: string) => {
    setError(false);
    const next = (pin + d).slice(0, LEN);
    setPin(next);
    if (next.length === LEN) setTimeout(() => submit(next), 120);
  };

  // Keep the last reason while the sheet fades out, so its title doesn't flip mid-fade.
  const last = useRef(pinFor);
  if (pinFor) last.current = pinFor;
  const why = last.current;
  const title = t(why === "manager" ? "auth.managerTitle" : why === "bump" ? "auth.bumpTitle" : "auth.switchTitle");
  const keys = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "", "0", "⌫"];

  return (
    <Sheet open={pinFor !== null} onClose={close} title={title} subtitle={t(why === "manager" ? "auth.managerBody" : "auth.body")} width={420}>
      <Animated.View style={{ flexDirection: "row", justifyContent: "center", gap: 14, transform: [{ translateX: shake }] }}>
        {Array.from({ length: LEN }, (_, i) => (
          <View key={i} style={{ width: 18, height: 18, borderRadius: 9, backgroundColor: i < pin.length ? (error ? c.destructive : c.foreground) : "transparent", borderWidth: 2, borderColor: error ? c.destructive : c.input }} />
        ))}
      </Animated.View>
      <Txt size={14} align="center" color={error ? c.destructive : c.mutedForeground} style={{ minHeight: 20 }}>
        {error ? t("auth.wrong") : t("auth.mockHint")}
      </Txt>

      <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.sm, direction: "ltr" }}>
        {keys.map((k, i) => (
          <Pressable
            key={i}
            disabled={!k}
            onPress={() => (k === "⌫" ? setPin(pin.slice(0, -1)) : press(k))}
            accessibilityRole="button"
            accessibilityLabel={k === "⌫" ? t("auth.delete") : k}
            style={({ pressed }) => ({
              width: "31.5%", height: 68, borderRadius: radius.lg, alignItems: "center", justifyContent: "center",
              backgroundColor: !k ? "transparent" : pressed ? c.accent : c.secondary,
            })}
          >
            {k === "⌫" ? <Delete size={26} color={c.foreground} /> : <Txt size={28} mono weight="semibold">{k}</Txt>}
          </Pressable>
        ))}
      </View>

      {pinFor === "switch" && user ? (
        <Button variant="outline" size="lg" icon={LogOut} onPress={() => { signOut(); close(); }}>
          {t("auth.signOut", { name: user.name.split(" ")[0] })}
        </Button>
      ) : null}
    </Sheet>
  );
}
