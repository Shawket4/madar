import type { Backend } from "./backend";
import { KitchenFailure } from "./backend";
import type { Branch, DeviceMode, Line, NetState, Section, Ticket } from "./types";

/*
 * The mock backend (APP-11): web, design review, demos. Same contract as the
 * core, in memory. Times are relative to load, so the board always shows a
 * spread of ages: fresh, amber (≥5 min) and red (≥10 min).
 *
 * Mock sign-in: any email/password for the manager; staff PINs 111111, 222222
 * (cooks) and 999999 (manager), any name.
 */

type Tr = [en: string, ar: string];

const BRANCHES: { id: string; name: Tr }[] = [
  { id: "b-zamalek", name: ["Zamalek", "الزمالك"] },
  { id: "b-maadi", name: ["Maadi", "المعادي"] },
];

const SECTIONS: { id: string; name: Tr; isDefault: boolean }[] = [
  { id: "s-grill", name: ["Grill", "المشويات"], isDefault: true },
  { id: "s-cold", name: ["Cold", "البارد"], isDefault: false },
  { id: "s-drinks", name: ["Drinks", "المشروبات"], isDefault: false },
  { id: "s-bakery", name: ["Bakery", "المخبوزات"], isDefault: false },
];

const STAFF: Record<string, { name: string; role: string }> = {
  "111111": { name: "Ahmed", role: "kitchen" },
  "222222": { name: "Mona", role: "kitchen" },
  "999999": { name: "Omar", role: "manager" },
};

const DISHES: Record<string, { name: Tr; section: string; mods?: Tr[][] }> = {
  mixedGrill: { name: ["Mixed grill", "مشويات مشكلة"], section: "s-grill", mods: [[["Well done", "مستوية جيدًا"]], [["Extra bread", "خبز إضافي"]]] },
  kofta: { name: ["Kofta", "كفتة"], section: "s-grill" },
  tawook: { name: ["Shish tawook", "شيش طاووق"], section: "s-grill" },
  burger: { name: ["Beef burger", "برجر لحم"], section: "s-grill", mods: [[["Medium", "متوسط"], ["No onion", "بدون بصل"]], [["Extra cheese", "جبنة إضافية"]]] },
  chicken: { name: ["Grilled chicken", "فراخ مشوية"], section: "s-grill" },
  tahini: { name: ["Tahini salad", "سلطة طحينة"], section: "s-cold" },
  green: { name: ["Green salad", "سلطة خضراء"], section: "s-cold" },
  baba: { name: ["Baba ghanoush", "بابا غنوج"], section: "s-cold" },
  fattoush: { name: ["Fattoush", "فتوش"], section: "s-cold" },
  lemonade: { name: ["Mint lemonade", "ليمون بالنعناع"], section: "s-drinks" },
  coffee: { name: ["Turkish coffee", "قهوة تركي"], section: "s-drinks", mods: [[["Medium sugar", "سكر مظبوط"]], [["No sugar", "سادة"]]] },
  mango: { name: ["Mango juice", "عصير مانجو"], section: "s-drinks" },
  latte: { name: ["Iced latte", "آيس لاتيه"], section: "s-drinks", mods: [[["Oat milk", "حليب شوفان"]], []] },
  feteer: { name: ["Feteer", "فطير"], section: "s-bakery" },
  sambousek: { name: ["Cheese sambousek", "سمبوسك جبنة"], section: "s-bakery" },
};

interface MockLine { id: string; dish: string; qty: number; mod: number; bumped: boolean; notes?: Tr; size?: Tr }
interface MockTicket { id: string; ref: number; table?: string; online?: boolean; round: number; at: number; lines: MockLine[] }

let seq = 0;
const id = (p: string) => `${p}-${++seq}`;

function fire(ref: number, minutesAgo: number, lines: [dish: string, qty: number, extra?: Partial<MockLine>][], o: { table?: string; online?: boolean; round?: number } = {}): MockTicket {
  return {
    id: id("t"),
    ref,
    table: o.table,
    online: o.online,
    round: o.round ?? 1,
    at: Date.now() - minutesAgo * 60_000,
    lines: lines.map(([dish, qty, extra]) => ({ id: id("l"), dish, qty, mod: seq % 2, bumped: false, ...extra })),
  };
}

function seed(): MockTicket[] {
  seq = 0;
  return [
    fire(1041, 12.5, [["mixedGrill", 2], ["tahini", 1], ["lemonade", 3, { bumped: true }]], { table: "T4" }),
    fire(1042, 7.2, [["burger", 2], ["latte", 1]]),
    fire(1043, 5.4, [["kofta", 1, { notes: ["Allergy: no nuts", "حساسية: بدون مكسرات"] }], ["tawook", 2, { bumped: true }], ["fattoush", 2], ["coffee", 2]], { table: "T12" }),
    fire(1044, 2.1, [["chicken", 1, { size: ["Half", "نصف"] }], ["baba", 1], ["feteer", 2]], { online: true }),
    fire(1045, 0.6, [["mixedGrill", 1], ["sambousek", 4], ["mango", 2]], { table: "T7" }),
    fire(1041, 1.3, [["kofta", 1], ["coffee", 1]], { table: "T4", round: 2 }),
    fire(1046, 4, [["burger", 1, { bumped: true }], ["mango", 1, { bumped: true }]], { table: "T2" }),
  ];
}

export interface MockTools {
  net: NetState;
  setNet(n: NetState): void;
  sendTestOrder(): void;
  reset(): void;
}

export function mockBackend(): Backend & { tools: MockTools } {
  let tickets = seed();
  let branch: Branch | undefined;
  let manager = false;
  let user: { name: string; role: string } | undefined;
  let binding: { mode: DeviceMode; sectionIds: string[] } | undefined;
  let ar = true;
  let pending = 0;
  let nextRef = 1047;
  let listener: Parameters<Backend["startRealtime"]>[0] | undefined;
  const tr = (t: Tr) => (ar ? t[1] : t[0]);
  const changed = () => listener?.onChange();

  const tools: MockTools = {
    net: "online",
    setNet(n) {
      tools.net = n;
      if (n === "online") pending = 0; // the outbox drains on reconnect
      listener?.onConnection(n !== "offline");
      changed();
    },
    sendTestOrder() {
      const keys = Object.keys(DISHES).sort(() => Math.random() - 0.5).slice(0, 2 + Math.floor(Math.random() * 3));
      const kind = nextRef % 3;
      tickets.push(fire(nextRef++, 0, keys.map((k) => [k, 1 + Math.floor(Math.random() * 2)]), kind === 0 ? { table: `T${(nextRef % 15) + 1}` } : kind === 1 ? { online: true } : {}));
      listener?.onPing();
      changed();
    },
    reset() {
      tickets = seed();
      pending = 0;
      changed();
    },
  };

  const write = (lineId: string, bumped: boolean) => {
    if (!user) throw new KitchenFailure(ar ? "سجّل الدخول أولًا" : "Sign in first");
    for (const t of tickets) for (const l of t.lines) if (l.id === lineId) l.bumped = bumped;
    if (tools.net !== "online") pending++;
  };

  return {
    mock: true,
    tools,
    state() {
      return {
        route: !branch ? "setup" : !user ? "login" : !binding ? "sections" : "board",
        branchId: branch?.id,
        branchName: branch?.name,
        mode: binding?.mode ?? "sections",
        sectionIds: binding?.sectionIds ?? [],
        userName: user?.name,
        userRole: user?.role,
        pending,
      };
    },
    async managerLogin(email, password) {
      if (!email.includes("@") || !password) throw new KitchenFailure(ar ? "أدخل البريد وكلمة المرور" : "Enter your email and password");
      manager = true;
      return BRANCHES.map((b) => ({ id: b.id, name: tr(b.name) }));
    },
    chooseBranch(b) {
      if (!manager) throw new KitchenFailure("Manager sign-in required");
      branch = b;
      manager = false;
      binding = undefined;
    },
    async signIn(name, pin) {
      const who = STAFF[pin];
      if (!who) throw new KitchenFailure(ar ? "الاسم أو الرمز غير صحيح" : "Wrong name or PIN");
      user = { name: name.trim() || who.name, role: who.role };
    },
    signOut() {
      user = undefined;
    },
    async stations(): Promise<Section[]> {
      return SECTIONS.map((s) => ({ id: s.id, name: tr(s.name), isDefault: s.isDefault, isActive: true }));
    },
    setSections(mode, sectionIds) {
      binding = { mode, sectionIds };
    },
    clearSections() {
      binding = undefined;
    },
    resetDevice() {
      if (pending) throw new KitchenFailure(ar ? "هناك إنهاءات لم تُزامن بعد" : "Some bumps haven't synced yet");
      branch = undefined;
      user = undefined;
      binding = undefined;
    },
    async tickets(): Promise<Ticket[]> {
      return tickets.map((t) => ({
        id: t.id,
        kitchenRef: String(t.ref),
        tableLabel: t.table,
        roundNumber: t.round,
        sourceType: t.online ? "online" : t.table ? "open_ticket" : "order",
        status: t.lines.every((l) => l.bumped) ? "ready" : "firing",
        createdAt: new Date(t.at).toISOString(),
        items: t.lines.map((l): Line => {
          const d = DISHES[l.dish];
          const section = SECTIONS.find((s) => s.id === d.section)!;
          return {
            id: l.id,
            name: tr(d.name),
            qty: l.qty,
            sizeLabel: l.size && tr(l.size),
            modifiers: (d.mods?.[l.mod % d.mods.length] ?? []).map(tr),
            notes: l.notes && tr(l.notes),
            stationId: section.id,
            stationName: tr(section.name),
            bumped: l.bumped,
          };
        }),
      }));
    },
    async bump(lineId) {
      write(lineId, true);
    },
    async unbump(lineId) {
      write(lineId, false);
    },
    async syncNow() {},
    async startRealtime(l) {
      listener = l;
      l.onConnection(tools.net !== "offline");
    },
    stopRealtime() {
      listener = undefined;
    },
    setLocale(locale) {
      ar = locale.startsWith("ar");
    },
  };
}
