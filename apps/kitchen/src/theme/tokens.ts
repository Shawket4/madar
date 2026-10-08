/*
 * Madar design tokens — system v2, the same values as the dashboard
 * (MadarDashboard/src/styles/globals.css) and the POS
 * (packages/design_system/lib/src/tokens/colors.dart). Hex here, oklch there:
 * a change to one is a change to all three.
 *
 * The WORK SURFACE is paper (light) or deep slate (dark). The CHROME — the
 * kitchen's top bar — is ink in both themes, so the frame never changes colour
 * when the room does. Madar teal (`brand`) is for brand marks only.
 */

export type ColorScheme = "light" | "dark";

export interface Palette {
  background: string;
  foreground: string;
  card: string;
  primary: string;
  primaryForeground: string;
  secondary: string;
  muted: string;
  mutedForeground: string;
  accent: string;
  brand: string;
  brandForeground: string;
  /** The kitchen's product accent (KS spec APP-4). APP-5 is open: Madar teal stands in until the logo work lands. */
  kitchen: string;
  destructive: string;
  destructiveForeground: string;
  success: string;
  successForeground: string;
  warning: string;
  warningForeground: string;
  info: string;
  infoForeground: string;
  border: string;
  input: string;
  disabled: string;
  disabledForeground: string;
  chrome: string;
  chromeForeground: string;
  chromeMuted: string;
  chromeRaised: string;
  chromeAccent: string;
  chromeBorder: string;
}

export const palettes: Record<ColorScheme, Palette> = {
  light: {
    background: "#F1F3F3",
    foreground: "#101820",
    card: "#FFFFFF",
    primary: "#0D1A1E",
    primaryForeground: "#FFFFFF",
    secondary: "#E4E9EA",
    muted: "#EDF0F1",
    mutedForeground: "#4F5F66",
    accent: "#DDE4E6",
    brand: "#0F7A8A",
    brandForeground: "#FFFFFF",
    kitchen: "#0F7A8A",
    destructive: "#D0392C",
    destructiveForeground: "#FFFFFF",
    success: "#178A4C",
    successForeground: "#FFFFFF",
    warning: "#BF5F07",
    warningForeground: "#FFFFFF",
    info: "#2563C9",
    infoForeground: "#FFFFFF",
    border: "#DAE1E2",
    input: "#D1D9DB",
    disabled: "#E2E7E8",
    disabledForeground: "#8A979C",
    chrome: "#0D1A1E",
    chromeForeground: "#EAF0F1",
    chromeMuted: "#9DB0B6",
    chromeRaised: "#1E353B",
    chromeAccent: "#15272C",
    chromeBorder: "rgba(255,255,255,0.08)",
  },
  dark: {
    background: "#0F1A1E",
    foreground: "#EEF3F4",
    card: "#16252A",
    primary: "#D3DEE1",
    primaryForeground: "#0D1A1E",
    secondary: "#213238",
    muted: "#1D2D32",
    mutedForeground: "#B3C2C7",
    accent: "#26393F",
    brand: "#2AA7B8",
    brandForeground: "#0B2226",
    kitchen: "#2AA7B8",
    destructive: "#F26B5E",
    destructiveForeground: "#2A0F0C",
    success: "#3BCB7E",
    successForeground: "#0B2817",
    warning: "#F0A23F",
    warningForeground: "#2B1904",
    info: "#6EA3F5",
    infoForeground: "#0C1B33",
    border: "#243740",
    input: "#2C4048",
    disabled: "#1F3035",
    disabledForeground: "#7D9096",
    chrome: "#0A1417",
    chromeForeground: "#EAF0F1",
    chromeMuted: "#8FA4AB",
    chromeRaised: "#173036",
    chromeAccent: "#122126",
    chromeBorder: "rgba(255,255,255,0.07)",
  },
};

/** `a` mixed into `b` by `t` (0..1). The dashboard's `color-mix(in oklch, …)`, close enough in sRGB. */
export function mix(a: string, b: string, t: number): string {
  const p = (h: string) => [1, 3, 5].map((i) => parseInt(h.slice(i, i + 2), 16));
  const [x, y] = [p(a), p(b)];
  return "#" + x.map((v, i) => Math.round(v * t + y[i] * (1 - t)).toString(16).padStart(2, "0")).join("");
}

/** A tone's wash: the colour at `alpha` (0..1) as 8-digit hex. */
export function wash(hex: string, alpha: number): string {
  return hex + Math.round(alpha * 255).toString(16).padStart(2, "0");
}

/** Dashboard `--radius: 0.75rem` and its steps. */
export const radius = { sm: 8, md: 10, lg: 12, xl: 16, full: 999 } as const;

/** 4-pt spacing (POS SPEC). */
export const space = { xs: 4, sm: 8, md: 12, lg: 16, xl: 24, xxl: 32 } as const;

/**
 * IBM Plex Sans Arabic carries Latin too — one face, both scripts (dashboard
 * `--font-sans`). Plex Mono for figures that stack: order numbers, ages, counts.
 */
export const font = {
  regular: "IBMPlexSansArabic_400Regular",
  medium: "IBMPlexSansArabic_500Medium",
  semibold: "IBMPlexSansArabic_600SemiBold",
  bold: "IBMPlexSansArabic_700Bold",
  mono: "IBMPlexMono_500Medium",
  monoBold: "IBMPlexMono_600SemiBold",
} as const;

/** Kitchen legibility (APP-6): read from 2 m, hit with a wet or gloved hand. */
export const kitchen = {
  touch: 56,
  orderNumber: 30,
  itemName: 19,
  age: 22,
  columnMin: 300,
} as const;
