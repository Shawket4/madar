/*
 * Board rules, pure. The real ones live in madar-core `kds.rs` (APP-2); these
 * mirror them for the mock so the design behaves, and go once the binding lands.
 */
import type { KitchenLine, KitchenPart } from "../../data/types.ts";

export type AgeTone = "fresh" | "amber" | "red" | "done";

/** Per branch (KB-3); per section is an open question. */
export const AMBER_MIN = 5;
export const RED_MIN = 10;
/** Bumped parts can be recalled for this long (KB-4). */
export const RECALL_MIN = 10;
/** A finished card stays on the board, green, this long before it leaves. */
export const DONE_LINGER_MS = 2500;

export function ageMs(createdAt: string, now: number): number {
  return Math.max(0, now - Date.parse(createdAt));
}

/** "7:05", "12:40", "1:02:09" — mono, counting up. */
export function formatAge(ms: number): string {
  const s = Math.floor(ms / 1000);
  const h = Math.floor(s / 3600);
  const m = Math.floor((s % 3600) / 60);
  const ss = String(s % 60).padStart(2, "0");
  return h ? `${h}:${String(m).padStart(2, "0")}:${ss}` : `${m}:${ss}`;
}

export function ageTone(part: KitchenPart, now: number): AgeTone {
  if (part.bumpedAt) return "done";
  const min = ageMs(part.createdAt, now) / 60_000;
  return min >= RED_MIN ? "red" : min >= AMBER_MIN ? "amber" : "fresh";
}

const live = (l: KitchenLine) => !l.voided;

/** Every line that still counts is bumped. */
export function isComplete(part: KitchenPart): boolean {
  const lines = part.items.filter(live);
  return lines.length > 0 && lines.every((l) => l.bumped);
}

/** What the board shows: open parts, plus ones just finished (green) for a moment. Oldest first (KB-2). */
export function boardParts(parts: KitchenPart[], sectionIds: string[], now: number): KitchenPart[] {
  return parts
    .filter((p) => sectionIds.includes(p.sectionId))
    .filter((p) => !p.bumpedAt || now - Date.parse(p.bumpedAt) < DONE_LINGER_MS)
    .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
}

export function recallable(parts: KitchenPart[], sectionIds: string[], now: number): KitchenPart[] {
  return parts
    .filter((p) => sectionIds.includes(p.sectionId) && p.bumpedAt)
    .filter((p) => now - Date.parse(p.bumpedAt!) < RECALL_MIN * 60_000)
    .sort((a, b) => Date.parse(b.bumpedAt!) - Date.parse(a.bumpedAt!));
}

/** All-day strip (KB-6): waiting quantity per item, most first. */
export function allDay(parts: KitchenPart[]): { name: string; nameAr: string; qty: number }[] {
  const m = new Map<string, { name: string; nameAr: string; qty: number }>();
  for (const p of parts) {
    if (p.bumpedAt) continue;
    for (const l of p.items) {
      if (l.bumped || l.voided) continue;
      const e = m.get(l.name) ?? { name: l.name, nameAr: l.nameAr, qty: 0 };
      e.qty += l.qty;
      m.set(l.name, e);
    }
  }
  return [...m.values()].sort((a, b) => b.qty - a.qty || a.name.localeCompare(b.name));
}

export type PartStatus = "waiting" | "cooking" | "done";

/** Expo (EX-1): a section's part is waiting (nothing bumped), cooking (some) or done. */
export function partStatus(part: KitchenPart): PartStatus {
  if (part.bumpedAt || isComplete(part)) return "done";
  return part.items.some((l) => l.bumped && !l.voided) ? "cooking" : "waiting";
}

/** EX-2: ready when every part of the order is done. */
export function orderReady(parts: KitchenPart[]): boolean {
  return parts.length > 0 && parts.every((p) => partStatus(p) === "done");
}
