/// <reference types="node" />
// Run: npm test (node --test, no framework).
import { test } from "node:test";
import assert from "node:assert/strict";

import type { KitchenPart } from "../../data/types.ts";
import { ageTone, allDay, boardParts, formatAge, orderReady, partStatus, recallable } from "./logic.ts";

const NOW = Date.parse("2026-10-08T12:00:00Z");
const ago = (min: number) => new Date(NOW - min * 60_000).toISOString();

function part(over: Partial<KitchenPart> = {}): KitchenPart {
  return {
    id: "p", orderId: "o", kitchenRef: "1", sectionId: "s1", sourceType: "dine_in", waiter: "w",
    roundNumber: 1, createdAt: ago(1), bumpedAt: null, bumpedBy: null,
    items: [
      { id: "a", name: "Kofta", nameAr: "كفتة", qty: 2, modifiers: [], bumped: false, voided: false },
      { id: "b", name: "Salad", nameAr: "سلطة", qty: 1, modifiers: [], bumped: false, voided: false },
    ],
    ...over,
  };
}

test("age tone steps at 5 and 10 minutes", () => {
  assert.equal(ageTone(part({ createdAt: ago(4.9) }), NOW), "fresh");
  assert.equal(ageTone(part({ createdAt: ago(5) }), NOW), "amber");
  assert.equal(ageTone(part({ createdAt: ago(10) }), NOW), "red");
  assert.equal(ageTone(part({ createdAt: ago(30), bumpedAt: ago(0) }), NOW), "done");
});

test("formatAge", () => {
  assert.equal(formatAge(65_000), "1:05");
  assert.equal(formatAge(3_725_000), "1:02:05");
});

test("board: own sections, oldest first, bumped parts leave after the linger", () => {
  const ps = [
    part({ id: "new", createdAt: ago(1) }),
    part({ id: "old", createdAt: ago(9) }),
    part({ id: "other", sectionId: "s2" }),
    part({ id: "gone", bumpedAt: ago(1) }),
  ];
  assert.deepEqual(boardParts(ps, ["s1"], NOW).map((p) => p.id), ["old", "new"]);
  assert.deepEqual(recallable(ps, ["s1"], NOW).map((p) => p.id), ["gone"]);
  assert.deepEqual(recallable(ps, ["s1"], NOW + 11 * 60_000), []);
});

test("all-day counts waiting lines only", () => {
  const p = part();
  p.items[1].bumped = true;
  const q = part({ items: [{ ...p.items[0], qty: 3 }, { ...p.items[1], voided: true, bumped: false }] });
  assert.deepEqual(allDay([p, q]), [{ name: "Kofta", nameAr: "كفتة", qty: 5 }]);
});

test("expo: a void never holds an order back", () => {
  const p = part();
  assert.equal(partStatus(p), "waiting");
  p.items[0].bumped = true;
  assert.equal(partStatus(p), "cooking");
  p.items[1].voided = true;
  assert.equal(partStatus(p), "done");
  assert.equal(orderReady([p, part({ bumpedAt: ago(1) })]), true);
  assert.equal(orderReady([p, part()]), false);
});
