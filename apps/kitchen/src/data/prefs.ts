/*
 * This screen's own settings (theme, language, chime), kept across restarts.
 * Pure: the store reads and writes the file (`lib/prefs-file.ts`).
 */
export interface Prefs {
  theme: "light" | "dark";
  lang: "ar" | "en";
  chime: boolean;
}

/** What the saved file holds, keeping only values this build understands. */
export function parsePrefs(text: string | null | undefined): Partial<Prefs> {
  let raw: unknown;
  try {
    raw = JSON.parse(text ?? "");
  } catch {
    return {};
  }
  if (!raw || typeof raw !== "object") return {};
  const r = raw as Record<string, unknown>;
  const out: Partial<Prefs> = {};
  if (r.theme === "light" || r.theme === "dark") out.theme = r.theme;
  if (r.lang === "ar" || r.lang === "en") out.lang = r.lang;
  if (typeof r.chime === "boolean") out.chime = r.chime;
  return out;
}
