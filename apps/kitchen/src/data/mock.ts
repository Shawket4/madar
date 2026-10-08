import type { Branch, KitchenLine, KitchenPart, Order, Section, SourceType, Staff } from "./types";

/*
 * Seeded mock data (APP-11). Times are relative to load so the board always
 * shows a spread of ages: fresh, amber (≥5 min) and red (≥10 min).
 */

export const branches: Branch[] = [
  { id: "b-zamalek", name: "Zamalek", nameAr: "الزمالك" },
  { id: "b-maadi", name: "Maadi", nameAr: "المعادي" },
];

export const sections: Section[] = [
  { id: "s-grill", name: "Grill", nameAr: "المشويات", isDefault: true },
  { id: "s-cold", name: "Cold", nameAr: "البارد", isDefault: false },
  { id: "s-drinks", name: "Drinks", nameAr: "المشروبات", isDefault: false },
  { id: "s-bakery", name: "Bakery", nameAr: "المخبوزات", isDefault: false },
];

export const staff: Staff[] = [
  { id: "u-ahmed", name: "Ahmed Saeed", role: "cook", pin: "111111" },
  { id: "u-mona", name: "Mona Fathy", role: "cook", pin: "222222" },
  { id: "u-omar", name: "Omar Nabil", role: "manager", pin: "999999" },
];

type Dish = [en: string, ar: string, sectionId: string];
const DISHES: Dish[] = [
  ["Mixed grill", "مشويات مشكلة", "s-grill"],
  ["Kofta", "كفتة", "s-grill"],
  ["Shish tawook", "شيش طاووق", "s-grill"],
  ["Beef burger", "برجر لحم", "s-grill"],
  ["Grilled chicken", "فراخ مشوية", "s-grill"],
  ["Tahini salad", "سلطة طحينة", "s-cold"],
  ["Green salad", "سلطة خضراء", "s-cold"],
  ["Baba ghanoush", "بابا غنوج", "s-cold"],
  ["Fattoush", "فتوش", "s-cold"],
  ["Mint lemonade", "ليمون بالنعناع", "s-drinks"],
  ["Turkish coffee", "قهوة تركي", "s-drinks"],
  ["Mango juice", "عصير مانجو", "s-drinks"],
  ["Iced latte", "آيس لاتيه", "s-drinks"],
  ["Feteer", "فطير", "s-bakery"],
  ["Cheese sambousek", "سمبوسك جبنة", "s-bakery"],
];

const MODS: Record<string, string[][]> = {
  "Mixed grill": [["Well done"], ["Extra bread"], []],
  "Beef burger": [["Medium", "No onion"], ["Extra cheese"], []],
  "Turkish coffee": [["Medium sugar"], ["No sugar"]],
  "Iced latte": [["Oat milk"], []],
};

const WAITERS = ["Karim", "Yara", "Hassan", "Nour"];

let seq = 0;
const id = (p: string) => `${p}-${++seq}`;

function line(d: Dish, qty: number, extra: Partial<KitchenLine> = {}): KitchenLine {
  const mods = MODS[d[0]];
  return {
    id: id("l"),
    name: d[0],
    nameAr: d[1],
    qty,
    modifiers: mods ? mods[seq % mods.length] : [],
    bumped: false,
    voided: false,
    ...extra,
  };
}

/** Splits an order's lines by section — the server's job (OF-1), faked here. */
function fire(
  order: Order,
  dishes: { d: Dish; qty: number; extra?: Partial<KitchenLine> }[],
  minutesAgo: number,
  round = 1,
  note?: string,
): KitchenPart[] {
  const bySection = new Map<string, KitchenLine[]>();
  for (const { d, qty, extra } of dishes) {
    const list = bySection.get(d[2]) ?? [];
    list.push(line(d, qty, extra));
    bySection.set(d[2], list);
  }
  const createdAt = new Date(Date.now() - minutesAgo * 60_000 - (seq % 50) * 1000).toISOString();
  return [...bySection].map(([sectionId, items]) => ({
    id: id("p"),
    orderId: order.id,
    kitchenRef: order.kitchenRef,
    sectionId,
    sourceType: order.sourceType,
    tableLabel: order.tableLabel,
    waiter: order.waiter,
    roundNumber: round,
    createdAt,
    note,
    items,
    bumpedAt: null,
    bumpedBy: null,
  }));
}

function order(n: number, sourceType: SourceType, table?: string): Order {
  return {
    id: id("o"),
    kitchenRef: String(n),
    sourceType,
    tableLabel: table,
    waiter: sourceType === "online" ? "Online" : WAITERS[n % WAITERS.length],
    handedOffAt: null,
  };
}

const dish = (en: string) => DISHES.find((d) => d[0] === en)!;

export function seed(): { orders: Order[]; parts: KitchenPart[] } {
  seq = 0;
  const o1 = order(1041, "dine_in", "T4");
  const o2 = order(1042, "takeaway");
  const o3 = order(1043, "dine_in", "T12");
  const o4 = order(1044, "online");
  const o5 = order(1045, "dine_in", "T7");
  const o6 = order(1046, "dine_in", "T2");

  const parts = [
    ...fire(o1, [
      { d: dish("Mixed grill"), qty: 2 },
      { d: dish("Tahini salad"), qty: 1 },
      { d: dish("Mint lemonade"), qty: 3 },
    ], 12.5, 1, "Birthday table — bring the drinks first"),
    ...fire(o2, [
      { d: dish("Beef burger"), qty: 2 },
      { d: dish("Iced latte"), qty: 1 },
    ], 7.2),
    ...fire(o3, [
      { d: dish("Kofta"), qty: 1, extra: { notes: "Allergy: no nuts" } },
      { d: dish("Shish tawook"), qty: 2 },
      { d: dish("Fattoush"), qty: 2 },
      { d: dish("Green salad"), qty: 1, extra: { voided: true } },
      { d: dish("Turkish coffee"), qty: 2 },
    ], 5.4),
    ...fire(o4, [
      { d: dish("Grilled chicken"), qty: 1, extra: { sizeLabel: "Half" } },
      { d: dish("Baba ghanoush"), qty: 1 },
      { d: dish("Feteer"), qty: 2 },
    ], 2.1),
    ...fire(o5, [
      { d: dish("Mixed grill"), qty: 1 },
      { d: dish("Cheese sambousek"), qty: 4 },
      { d: dish("Mango juice"), qty: 2 },
    ], 0.6),
    // A second round on T4 (OF-4).
    ...fire(o1, [{ d: dish("Kofta"), qty: 1 }, { d: dish("Turkish coffee"), qty: 1 }], 1.3, 2),
    ...fire(o6, [{ d: dish("Beef burger"), qty: 1 }, { d: dish("Mango juice"), qty: 1 }], 4),
  ];
  // Some lines already bumped, so cooking / partly-done states show.
  parts.find((p) => p.orderId === o3.id && p.sectionId === "s-grill")!.items[1].bumped = true;
  const drinks1 = parts.find((p) => p.orderId === o1.id && p.sectionId === "s-drinks" && p.roundNumber === 1)!;
  drinks1.items.forEach((l) => (l.bumped = true));
  drinks1.bumpedAt = new Date(Date.now() - 9 * 60_000).toISOString();
  drinks1.bumpedBy = "u-mona";
  // T2 is fully bumped: ready on the expo, recallable on the board.
  for (const p of parts.filter((p) => p.orderId === o6.id)) {
    p.items.forEach((l) => (l.bumped = true));
    p.bumpedAt = new Date(Date.now() - 60_000).toISOString();
    p.bumpedBy = "u-ahmed";
  }

  return { orders: [o1, o2, o3, o4, o5, o6], parts };
}

let nextRef = 1047;
/** A new order for the "Send test order" tool. */
export function randomOrder(): { order: Order; parts: KitchenPart[] } {
  const types: SourceType[] = ["dine_in", "dine_in", "takeaway", "online"];
  const t = types[nextRef % types.length];
  const o = order(nextRef++, t, t === "dine_in" ? `T${(nextRef % 15) + 1}` : undefined);
  const picks = [...DISHES].sort(() => Math.random() - 0.5).slice(0, 2 + Math.floor(Math.random() * 3));
  return { order: o, parts: fire(o, picks.map((d) => ({ d, qty: 1 + Math.floor(Math.random() * 2) })), 0) };
}
