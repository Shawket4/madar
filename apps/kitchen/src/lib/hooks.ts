import { useEffect, useState } from "react";

import { useKitchen } from "@/data/store";

/** A clock that ticks every `ms`. Ages re-tint and count on it. */
export function useNow(ms = 1000): number {
  const [now, setNow] = useState(Date.now);
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), ms);
    return () => clearInterval(id);
  }, [ms]);
  return now;
}

/** Picks the name for the current language from a `{ name, nameAr }` row. */
export function useLocalName(): (row: { name: string; nameAr: string }) => string {
  const ar = useKitchen((s) => s.lang) === "ar";
  return (row) => (ar ? row.nameAr : row.name);
}

/** Fire time, Latin digits in both languages (APP-7); 12/24h follows the device (APP-8). */
export function formatClock(iso: string): string {
  return new Date(iso).toLocaleTimeString(undefined, { hour: "numeric", minute: "2-digit", numberingSystem: "latn" });
}
