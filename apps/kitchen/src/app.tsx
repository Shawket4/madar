import { useEffect } from "react";
import { ActivityIndicator, AppState, View } from "react-native";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { useFonts } from "expo-font";
import {
  IBMPlexSansArabic_400Regular,
  IBMPlexSansArabic_500Medium,
  IBMPlexSansArabic_600SemiBold,
  IBMPlexSansArabic_700Bold,
} from "@expo-google-fonts/ibm-plex-sans-arabic";
import { IBMPlexMono_500Medium, IBMPlexMono_600SemiBold } from "@expo-google-fonts/ibm-plex-mono";

import i18n from "@/i18n";
import { useKitchen } from "@/data/store";
import { useColors } from "@/theme/use-theme";
import { BoardScreen } from "@/features/board/board-screen";
import { ExpoScreen } from "@/features/expo/expo-screen";
import { SetupScreen } from "@/features/setup/setup-screen";
import { LoginScreen } from "@/features/auth/login-screen";
import { SectionsScreen } from "@/features/setup/sections-screen";
import { SettingsSheet } from "@/features/settings/settings-sheet";

/**
 * Madar Kitchen. A device, not a shell: a manager binds it to a branch once,
 * cooks sign in with their PIN, and it shows one board — a section's parts or
 * the expo — and nothing else. The route comes from the core.
 */
export default function App() {
  const [fontsLoaded] = useFonts({
    IBMPlexSansArabic_400Regular,
    IBMPlexSansArabic_500Medium,
    IBMPlexSansArabic_600SemiBold,
    IBMPlexSansArabic_700Bold,
    IBMPlexMono_500Medium,
    IBMPlexMono_600SemiBold,
  });
  const c = useColors();
  const lang = useKitchen((s) => s.lang);
  const device = useKitchen((s) => s.device);
  const boot = useKitchen((s) => s.boot);
  const refresh = useKitchen((s) => s.refresh);

  useEffect(() => { void i18n.changeLanguage(lang); }, [lang]);
  useEffect(() => { void boot(); }, [boot]);

  // The board re-reads local rows on every realtime event; this poll is the
  // fallback (and keeps the outbox count fresh), and keeps the section list
  // current while a device is being set up. Local reads, no network.
  useEffect(() => {
    if (device.route !== "board" && device.route !== "sections") return;
    const id = setInterval(() => void refresh(), 3000);
    const sub = AppState.addEventListener("change", (st) => st === "active" && void refresh());
    return () => { clearInterval(id); sub.remove(); };
  }, [device.route, refresh]);

  if (!fontsLoaded) {
    return (
      <View style={{ flex: 1, alignItems: "center", justifyContent: "center", backgroundColor: c.background }}>
        <ActivityIndicator color={c.foreground} />
      </View>
    );
  }

  return (
    <SafeAreaProvider>
      <StatusBar style="light" />
      {/* Arabic mirrors here, live, without the app restart I18nManager.forceRTL needs. */}
      <View key={lang} style={{ flex: 1, direction: lang === "ar" ? "rtl" : "ltr", backgroundColor: c.background }}>
        {device.route === "setup" ? <SetupScreen />
          : device.route === "login" ? <LoginScreen />
          : device.route === "sections" ? <SectionsScreen />
          : device.mode === "expo" ? <ExpoScreen /> : <BoardScreen />}
        {device.route === "board" ? <SettingsSheet /> : null}
      </View>
    </SafeAreaProvider>
  );
}
