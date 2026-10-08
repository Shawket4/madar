import { useState } from "react";
import { View } from "react-native";
import { useTranslation } from "react-i18next";
import { LogIn, Store } from "lucide-react-native";

import { useKitchen } from "@/data/store";
import { backend } from "@/data/backend";
import type { Branch } from "@/data/types";
import { space } from "@/theme/tokens";
import { useColors } from "@/theme/use-theme";
import { Button } from "@/components/ui/button";
import { Field } from "@/components/ui/input";
import { Txt } from "@/components/ui/text";
import { Choice } from "@/components/app/choice";
import { DeviceFrame } from "@/components/app/device-frame";
import { SectionHeader } from "@/components/app/section-header";

/**
 * Device setup (DV-1): a manager signs in with their Madar email, then binds
 * this device to a branch. The manager is signed out again; cooks sign in next.
 */
export function SetupScreen() {
  const { t } = useTranslation();
  const c = useColors();
  const managerLogin = useKitchen((s) => s.managerLogin);
  const chooseBranch = useKitchen((s) => s.chooseBranch);
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [branches, setBranches] = useState<Branch[] | null>(null);

  const signIn = async () => {
    setBusy(true);
    setError(null);
    try {
      setBranches(await managerLogin(email, password));
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    } finally {
      setBusy(false);
    }
  };

  const pick = (b: Branch) => {
    try {
      chooseBranch(b);
    } catch (e) {
      setError(e instanceof Error ? e.message : String(e));
    }
  };

  return (
    <DeviceFrame title={t("setup.title")} subtitle={t("setup.subtitle")} width={560}>
      {!branches ? (
        <View style={{ gap: space.lg }}>
          <Field label={t("setup.email")} value={email} onChangeText={setEmail} autoCapitalize="none" autoComplete="email" keyboardType="email-address" textContentType="username" />
          <Field label={t("setup.password")} value={password} onChangeText={setPassword} secureTextEntry textContentType="password" onSubmitEditing={signIn} />
          {error ? <Txt size={15} color={c.destructive}>{error}</Txt> : null}
          <Button size="lg" icon={LogIn} disabled={busy || !email || !password} onPress={signIn}>{busy ? t("setup.signingIn") : t("setup.managerSignIn")}</Button>
        </View>
      ) : (
        <View style={{ gap: space.md }}>
          <SectionHeader title={t("setup.branch")} count={branches.length} />
          {branches.length === 0 ? <Txt size={15} muted>{t("setup.noBranches")}</Txt> : null}
          <View style={{ flexDirection: "row", flexWrap: "wrap", gap: space.md }}>
            {branches.map((b) => <Choice key={b.id} on={false} onPress={() => pick(b)} icon={Store} title={b.name} />)}
          </View>
          {error ? <Txt size={15} color={c.destructive}>{error}</Txt> : null}
        </View>
      )}
      {backend().mock ? <Txt size={13} muted align="center">{t("setup.mockNote")}</Txt> : null}
    </DeviceFrame>
  );
}
