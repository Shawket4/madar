import { useKitchen } from "@/data/store";
import { palettes, type Palette } from "./tokens";

/** The active palette. Dark by default (APP-6); light is a setting. */
export function useColors(): Palette {
  return palettes[useKitchen((s) => s.theme)];
}

/** Arabic first (APP-7). Layout mirrors through the root view's `direction`. */
export function useIsRtl(): boolean {
  return useKitchen((s) => s.lang) === "ar";
}
