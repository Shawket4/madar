/* The settings file beside the kitchen's data. A failure only costs the defaults. */
import { File, Paths } from "expo-file-system";

import { parsePrefs, type Prefs } from "@/data/prefs";

const file = () => new File(Paths.document, "kitchen-prefs.json");

export function loadPrefs(): Partial<Prefs> {
  try {
    const f = file();
    return f.exists ? parsePrefs(f.textSync()) : {};
  } catch {
    return {};
  }
}

export function savePrefs(p: Prefs): void {
  try {
    file().write(JSON.stringify(p));
  } catch {
    // Not saved: the next launch starts from the defaults.
  }
}
