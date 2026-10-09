/*
 * Board rules, pure. Bump, outbox and the feed live in madar-core; what's here
 * is how one device draws that feed — split by section (OF-1), aged (KB-3),
 * counted (KB-6). Moves into the core with the multi-section binding (APP-2).
 */
import type { KitchenLine, KitchenPart, SourceType, Ticket } from "../../data/types.ts";

export type AgeTone = "fresh" | "amber" | "red" | "done";

/** Per branch (KB-3); per section is an open question. */
export const AMBER_MIN = 5;
export const RED_MIN = 10;
/** A card the cook just finished stays on the board, green, this long. */
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
  if (part.done) return "done";
  const min = ageMs(part.createdAt, now) / 60_000;
  return min >= RED_MIN ? "red" : min >= AMBER_MIN ? "amber" : "fresh";
}

/** A waiter's bill is dine-in (with or without a table yet); a counter order is takeaway. */
export function sourceOf(t: Pick<Ticket, "sourceType" | "tableLabel">): SourceType {
  if (t.sourceType === "online") return "online";
  return t.sourceType === "open_ticket" || t.tableLabel ? "dine_in" : "takeaway";
}

/** The number a cook calls out: the ref's last segment ("T-DOWNTO-261008-0042" → "42"). */
export function shortRef(ref: string | undefined, id: string): string {
  if (!ref) return id.slice(-4).toUpperCase();
  const tail = ref.split("-").pop() ?? ref;
  return /^\d+$/.test(tail) ? String(Number(tail)) : tail;
}

const live = (l: KitchenLine) => !l.voided;

/** Every line that still counts is bumped. */
export function isComplete(items: KitchenLine[]): boolean {
  const lines = items.filter(live);
  return lines.length > 0 && lines.every((l) => l.bumped);
}

/**
 * The feed → one part per (ticket, section). A line with no station goes to the
 * branch's default section (KS-4). Voided tickets never show.
 */
export function toParts(tickets: Ticket[], defaultSectionId: string | undefined): KitchenPart[] {
  const out: KitchenPart[] = [];
  for (const t of tickets) {
    if (t.status === "voided") continue;
    const bySection = new Map<string, KitchenLine[]>();
    for (const l of t.items) {
      const sid = l.stationId ?? defaultSectionId ?? "";
      const list = bySection.get(sid) ?? [];
      list.push({ ...l, voided: false });
      bySection.set(sid, list);
    }
    for (const [sectionId, items] of bySection) {
      out.push({
        id: `${t.id}:${sectionId}`,
        orderId: t.id,
        kitchenRef: shortRef(t.kitchenRef, t.id),
        sectionId,
        sourceType: sourceOf(t),
        tableLabel: t.tableLabel,
        roundNumber: t.roundNumber,
        createdAt: t.createdAt,
        items,
        done: isComplete(items),
      });
    }
  }
  return out;
}

/** The board: open parts for these sections, plus ones just finished here, oldest first (KB-2). */
export function boardParts(parts: KitchenPart[], sectionIds: string[], now: number, finishedAt: Record<string, number>): KitchenPart[] {
  return parts
    .filter((p) => sectionIds.includes(p.sectionId))
    .filter((p) => !p.done || now - (finishedAt[p.id] ?? 0) < DONE_LINGER_MS)
    .sort((a, b) => Date.parse(a.createdAt) - Date.parse(b.createdAt));
}

/** KB-4: finished parts still on an open ticket, newest first — the ones a cook can bring back. */
export function recallable(parts: KitchenPart[], sectionIds: string[]): KitchenPart[] {
  return parts
    .filter((p) => sectionIds.includes(p.sectionId) && p.done)
    .sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt));
}

/** All-day strip (KB-6): waiting quantity per item, most first. */
export function allDay(parts: KitchenPart[]): { name: string; qty: number }[] {
  const m = new Map<string, number>();
  for (const p of parts) {
    for (const l of p.items) {
      if (l.bumped || l.voided) continue;
      m.set(l.name, (m.get(l.name) ?? 0) + l.qty);
    }
  }
  return [...m].map(([name, qty]) => ({ name, qty })).sort((a, b) => b.qty - a.qty || a.name.localeCompare(b.name));
}

export type PartStatus = "waiting" | "cooking" | "done";

/** Expo (EX-1): a section's part is waiting (nothing bumped), cooking (some) or done. */
export function partStatus(part: KitchenPart): PartStatus {
  if (part.done) return "done";
  return part.items.some((l) => l.bumped && !l.voided) ? "cooking" : "waiting";
}

/** EX-2: ready when every part of the order is done. */
export function orderReady(parts: KitchenPart[]): boolean {
  return parts.length > 0 && parts.every((p) => p.done);
}
