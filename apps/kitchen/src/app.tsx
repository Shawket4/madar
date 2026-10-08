import { useEffect } from "react";
import { ActivityIndicator, View } from "react-native";
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
import { PinSheet } from "@/features/auth/pin-sheet";
import { SettingsSheet } from "@/features/settings/settings-sheet";

/**
 * Madar Kitchen. A device, not a shell: setup once (manager), then one board —
 * a section's parts or the expo — and nothing else.
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

  useEffect(() => { void i18n.changeLanguage(lang); }, [lang]);

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
        {!device ? <SetupScreen /> : device.mode === "expo" ? <ExpoScreen /> : <BoardScreen />}
        <PinSheet />
        <SettingsSheet />
      </View>
    </SafeAreaProvider>
  );
}
