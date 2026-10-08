/// <reference types="node" />
// Run: npm test (node --test, no framework).
import { test } from "node:test";
import assert from "node:assert/strict";

import type { Ticket } from "../../data/types.ts";
import { ageTone, allDay, boardParts, formatAge, orderReady, partStatus, recallable, toParts } from "./logic.ts";

const NOW = Date.parse("2026-10-08T12:00:00Z");
const ago = (min: number) => new Date(NOW - min * 60_000).toISOString();

function ticket(over: Partial<Ticket> = {}): Ticket {
  return {
    id: "t1", kitchenRef: "41", tableLabel: "T4", roundNumber: 1, sourceType: "open_ticket", status: "firing",
    createdAt: ago(1),
    items: [
      { id: "a", name: "Kofta", qty: 2, modifiers: [], stationId: "grill", bumped: false },
      { id: "b", name: "Salad", qty: 1, modifiers: [], stationId: "cold", bumped: false },
      { id: "c", name: "Bread", qty: 1, modifiers: [], bumped: false },
    ],
    ...over,
  };
}

test("a ticket splits by section; an unrouted line goes to the default (KS-4)", () => {
  const parts = toParts([ticket()], "grill");
  assert.deepEqual(parts.map((p) => [p.sectionId, p.items.map((l) => l.id)]), [["grill", ["a", "c"]], ["cold", ["b"]]]);
  assert.equal(parts[0].sourceType, "dine_in");
  assert.equal(toParts([ticket({ tableLabel: undefined, sourceType: "order" })], "grill")[0].sourceType, "takeaway");
  assert.equal(toParts([ticket({ tableLabel: undefined })], "grill")[0].sourceType, "dine_in");
  assert.equal(toParts([ticket({ kitchenRef: "T-DOWNTO-261008-0042" })], "grill")[0].kitchenRef, "42");
  assert.deepEqual(toParts([ticket({ status: "voided" })], "grill"), []);
});

test("age tone steps at 5 and 10 minutes", () => {
  const at = (min: number) => toParts([ticket({ createdAt: ago(min) })], "grill")[0];
  assert.equal(ageTone(at(4.9), NOW), "fresh");
  assert.equal(ageTone(at(5), NOW), "amber");
  assert.equal(ageTone(at(10), NOW), "red");
});

test("formatAge", () => {
  assert.equal(formatAge(65_000), "1:05");
  assert.equal(formatAge(3_725_000), "1:02:05");
});

test("board: own sections, oldest first; a finished part lingers only if finished here", () => {
  const done = ticket({ id: "t3", items: [{ id: "x", name: "Kofta", qty: 1, modifiers: [], stationId: "grill", bumped: true }] });
  const parts = toParts([ticket({ id: "t2", createdAt: ago(0.5) }), ticket({ createdAt: ago(9) }), done], "grill");
  assert.deepEqual(boardParts(parts, ["grill"], NOW, {}).map((p) => p.orderId), ["t1", "t2"]);
  assert.deepEqual(boardParts(parts, ["grill"], NOW, { "t3:grill": NOW - 1000 }).map((p) => p.orderId), ["t1", "t3", "t2"]);
  assert.deepEqual(recallable(parts, ["grill"]).map((p) => p.orderId), ["t3"]);
});

test("all-day counts waiting lines only", () => {
  const t = ticket();
  t.items[2].bumped = true;
  assert.deepEqual(allDay(toParts([t, ticket({ id: "t2" })], "grill")), [
    { name: "Kofta", qty: 4 }, { name: "Bread", qty: 1 }, { name: "Salad", qty: 2 },
  ].sort((a, b) => b.qty - a.qty || a.name.localeCompare(b.name)));
});

test("expo: waiting, cooking, done, ready", () => {
  const t = ticket();
  const [grill, cold] = toParts([t], "grill");
  assert.equal(partStatus(grill), "waiting");
  t.items[0].bumped = true;
  assert.equal(partStatus(toParts([t], "grill")[0]), "cooking");
  t.items.forEach((l) => (l.bumped = true));
  assert.equal(orderReady(toParts([t], "grill")), true);
  assert.equal(orderReady([grill, cold]), false);
});
