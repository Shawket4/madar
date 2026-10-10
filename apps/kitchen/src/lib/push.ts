import { PermissionsAndroid, Platform } from "react-native";
import {
  AuthorizationStatus,
  getMessaging,
  getToken,
  onMessage,
  onTokenRefresh,
  requestPermission,
  setBackgroundMessageHandler,
} from "@react-native-firebase/messaging";

import type { Backend } from "@/data/backend";

/*
 * Firebase Cloud Messaging, the third way new work reaches a kitchen screen
 * (after the branch LAN and the live stream). The server pushes only a screen
 * whose stream is down (`push::kitchen` in MadarRust), so a push means "you
 * may have missed something": the board just re-reads. Policy and words live
 * on the server; this is registration and a nudge, nothing more.
 */

let started = false;

/** Ask once, register the token (and every refresh), re-read on a push. */
export async function startPush(backend: Backend, locale: string, onPush: () => void): Promise<void> {
  if (started) return;
  started = true;
  try {
    const m = getMessaging();
    if (Platform.OS === "android" && Number(Platform.Version) >= 33) {
      await PermissionsAndroid.request(PermissionsAndroid.PERMISSIONS.POST_NOTIFICATIONS);
    }
    const status = await requestPermission(m);
    if (status === AuthorizationStatus.DENIED) return;
    const send = (token: string) => void backend.setPushToken(token, locale, Platform.OS).catch(() => {});
    send(await getToken(m));
    onTokenRefresh(m, send);
    onMessage(m, () => onPush());
  } catch {
    // No Google services (a simulator without them) or offline: retried on the next launch.
    started = false;
  }
}

/**
 * Required at startup by Firebase. The OS draws the notification itself; the
 * board catches up from the stream or the next read when the app opens.
 */
export function registerBackgroundPush(): void {
  setBackgroundMessageHandler(getMessaging(), async () => {});
}
