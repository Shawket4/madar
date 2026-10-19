/*
 * KB-5: the new-order chime. One player, made on first use; it rings with the
 * iPad's silent switch on, because a kitchen screen is never meant to be quiet.
 */
import { createAudioPlayer, setAudioModeAsync } from "expo-audio";

let player: ReturnType<typeof createAudioPlayer> | null = null;

export function playChime(): void {
  try {
    if (!player) {
      void setAudioModeAsync({ playsInSilentMode: true }).catch(() => {});
      player = createAudioPlayer(require("../../assets/chime.wav"));
    }
    void player.seekTo(0);
    player.play();
  } catch {
    // No audio on this device: the board still shows the order.
  }
}
