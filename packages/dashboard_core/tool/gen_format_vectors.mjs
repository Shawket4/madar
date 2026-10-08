#!/usr/bin/env node
// Runs the web dashboard's own formatting code (src/lib/format.ts,
// src/data/scope/presets.ts, src/lib/excel.ts's date serial) under Node and
// writes what it answers for a fixed set of inputs to
// test/fixtures/format_vectors.json. The Dart port (lib/src/format) is tested
// against these, so "formats exactly like the web" is a checked claim.
//
//   node packages/dashboard_core/tool/gen_format_vectors.mjs [--web <MadarDashboard dir>]
//
// The web repo is read-only: this bundles from it into a temp dir and never
// writes inside it.
// The web's TZDate builds a wall-clock time through the HOST's local zone, so
// on a machine whose own zone has a DST gap at that moment (Cairo's spring
// midnight) it lands an hour off for every zone. That is an artefact of where
// the code runs, not a rule of the web; the vectors are taken on a UTC host.
process.env.TZ = "UTC";

import { createRequire } from "node:module";
import { mkdtempSync, writeFileSync, rmSync, existsSync } from "node:fs";
import { tmpdir } from "node:os";
import { join, dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const args = process.argv.slice(2);
const webIdx = args.indexOf("--web");
const WEB = resolve(webIdx >= 0 ? args[webIdx + 1] : "/Users/shawket/Desktop/Madar/MadarDashboard");
const OUT = join(here, "..", "test", "fixtures", "format_vectors.json");

const require = createRequire(join(WEB, "package.json"));
const esbuild = require("esbuild");

const STUBS = {
  "@/i18n": `
    const i18n = { resolvedLanguage: "en", language: "en",
      t: (k, o) => (typeof o === "string" ? o : (o && o.defaultValue) || k),
      getFixedT: () => (k, o) => (typeof o === "string" ? o : (o && o.defaultValue) || k) };
    export default i18n;`,
  "@/data/stores/app.store": `
    const state = { activeTimezone: "Africa/Cairo", setActiveTimezone(tz) { state.activeTimezone = tz; } };
    export const useAppStore = { getState: () => state };`,
  sonner: `export const toast = { error() {}, success() {}, loading() { return 1; } };`,
  "@/lib/download": `export function downloadBlob() {} export function downloadUrl() {}`,
};

const entry = `
  export * from "@/lib/format";
  export { rangeForPreset, dayBoundaryISO } from "@/data/scope/presets";
  export { toExcelDateSerial } from "@/lib/excel";
  export { default as i18n } from "@/i18n";
  export { useAppStore } from "@/data/stores/app.store";
`;

/** `@/x/y` → the .ts/.tsx file (or folder index) it names. */
function resolveTs(base) {
  for (const ext of ["", ".ts", ".tsx", "/index.ts", "/index.tsx", ".js"]) {
    if (existsSync(base + ext) && (ext !== "" || /\.[cm]?[jt]sx?$/.test(base))) return base + ext;
  }
  throw new Error(`cannot resolve ${base}`);
}

const tmp = mkdtempSync(join(tmpdir(), "fdash-vectors-"));
const outfile = join(tmp, "bundle.mjs");
try {
  await esbuild.build({
    stdin: { contents: entry, resolveDir: join(WEB, "src"), loader: "ts" },
    bundle: true,
    format: "esm",
    platform: "node",
    outfile,
    logLevel: "error",
    plugins: [
      {
        name: "stubs-and-alias",
        setup(b) {
          b.onResolve({ filter: /.*/ }, (a) => {
            if (STUBS[a.path] !== undefined) return { path: a.path, namespace: "stub" };
            if (a.path.startsWith("@/")) {
              return { path: resolveTs(join(WEB, "src", a.path.slice(2))) };
            }
            return undefined;
          });
          b.onLoad({ filter: /.*/, namespace: "stub" }, (a) => ({ contents: STUBS[a.path], loader: "js" }));
        },
      },
    ],
  });
  const m = await import(pathToFileURL(outfile).href);
  const setLang = (l) => {
    m.i18n.resolvedLanguage = l;
    m.i18n.language = l;
  };
  const setTz = (tz) => m.useAppStore.getState().setActiveTimezone(tz);

  const vectors = [];
  const add = (fn, lang, tz, argsList, call) => {
    for (const a of argsList) {
      setLang(lang);
      setTz(tz);
      let out;
      try {
        out = call(...a);
      } catch (e) {
        out = { error: String(e) };
      }
      vectors.push({ fn, lang, tz, args: a, out });
    }
  };

  const LANGS = ["en", "ar"];
  const TZS = ["Africa/Cairo", "America/New_York", "Asia/Riyadh", "UTC"];

  const moneyValues = [0, 1, 5, 49, 50, 99, 100, 1999, 123450, -5000, 123456, -1, 100000000, 12345678901, -0.4, 0.4, null];
  const moneyOpts = [
    undefined,
    { signed: true },
    { maxFractionDigits: 0 },
    { fractionDigits: 0 },
    { currency: false },
    { maxFractionDigits: 0, currency: false },
    { currency: false, fractionDigits: 0 },
    { signed: true, currency: false },
  ];
  const compactMoney = [0, 50, 4999, 99999, 100000, 123456, 1234567, 99999999, 123456789, 12345678900, 999999999999, -123456, -4, null];
  const numbers = [0, 1, 7, 1234, 1234.5678, -1234, 0.5, 12.345, 12.35, -0.0001, 1e21, null];
  const numberOpts = [
    undefined,
    { maximumFractionDigits: 1 },
    { maximumFractionDigits: 2 },
    { minimumFractionDigits: 1, maximumFractionDigits: 1 },
    { signDisplay: "exceptZero" },
    { signDisplay: "always" },
    { maximumFractionDigits: 0 },
  ];
  const compactNumbers = [0, 5, 999, 1000, 1049, 1050, 1500, 2234, 12345, 99950, 123456, 999999, 1000000, 2234567, 1e9, 1.5e12, -2234, 0.5, 12.34, null];
  const ratios = [0, 0.1234, 1, -0.05, 0.0005, 1.5, 0.12345, 0.99999, 12.3456];
  const instants = [
    "2026-09-12T15:02:00Z",
    "2026-09-12T21:30:00Z",
    "2026-01-01T00:00:00Z",
    "2026-03-08T07:30:00Z",
    "2026-06-30T10:05:09Z",
    "2025-12-31T21:30:00Z",
    "2026-11-05T12:00:00Z",
    "2026-02-05T23:59:59.999Z",
    "2026-07-04T11:00:00Z",
    "2026-05-05T09:09:00Z",
    "2026-08-15T16:45:00+03:00",
    "",
    null,
    "not-a-date",
  ];

  for (const lang of LANGS) {
    for (const o of moneyOpts) add("fmtMoney", lang, "Africa/Cairo", moneyValues.map((v) => [v, o ?? null]), (v, op) => m.fmtMoney(v, op ?? undefined));
    add("fmtMoneySigned", lang, "Africa/Cairo", moneyValues.map((v) => [v]), (v) => m.fmtMoneySigned(v));
    add("fmtMoneyCompact", lang, "Africa/Cairo", compactMoney.map((v) => [v]), (v) => m.fmtMoneyCompact(v));
    for (const o of numberOpts) add("fmtNumber", lang, "Africa/Cairo", numbers.map((v) => [v, o ?? null]), (v, op) => m.fmtNumber(v, op ?? undefined));
    add("fmtNumberCompact", lang, "Africa/Cairo", compactNumbers.map((v) => [v]), (v) => m.fmtNumberCompact(v));
    add("fmtPercent", lang, "Africa/Cairo", ratios.map((v) => [v]), (v) => m.fmtPercent(v));
    add("fmtShare", lang, "Africa/Cairo", [[1, 3], [0, 0], [5, 0], [2, 8], [-1, 4]], (a, b) => m.fmtShare(a, b));
    add("currencyLabel", lang, "Africa/Cairo", [[null], ["EGP"], ["SAR"], ["USD"], ["KWD"]], (c) => m.currencyLabel(c ?? undefined));
    for (const tz of TZS) {
      add("fmtDate", lang, tz, instants.map((v) => [v]), (v) => m.fmtDate(v));
      add("fmtTime", lang, tz, instants.map((v) => [v, null]), (v, z) => m.fmtTime(v, z));
      add("fmtDateTime", lang, tz, instants.map((v) => [v, null]), (v, z) => m.fmtDateTime(v, z));
      add("fmtDateTimeFull", lang, tz, instants.map((v) => [v]), (v) => m.fmtDateTimeFull(v));
      for (const g of ["hourly", "daily", "monthly", "peak_hours", "peak_days"]) {
        add("fmtPeriod", lang, tz, instants.filter((v) => v && v !== "not-a-date").map((v) => [v, g]), (v, gg) => m.fmtPeriod(v, gg));
      }
      const nows = ["2026-09-12T20:00:00Z", "2026-09-12T23:30:00Z", "2027-01-01T03:00:00Z"];
      for (const now of nows) {
        add("fmtStamp", lang, tz, instants.map((v) => [v, now]), (v, n) => m.fmtStamp(v, new Date(n)));
      }
    }
    // fmtTime / fmtDateTime with an explicit record tz.
    add("fmtTime", lang, "Africa/Cairo", instants.map((v) => [v, "America/New_York"]), (v, z) => m.fmtTime(v, z));
    add("fmtDateTime", lang, "Africa/Cairo", instants.map((v) => [v, "Asia/Riyadh"]), (v, z) => m.fmtDateTime(v, z));
    const ms = [0, -5, 59_999, 60_000, 42 * 60_000, 65 * 60_000, (27 * 60 + 5) * 60_000, 3 * 86_400_000 + 3_600_000, 99 * 86_400_000, NaN, Infinity];
    add("fmtElapsedMs", lang, "Africa/Cairo", ms.map((v) => [Number.isFinite(v) ? v : String(v)]), (v) => m.fmtElapsedMs(typeof v === "string" ? Number(v) : v));
    add("fmtDuration", lang, "Africa/Cairo", [
      ["2026-09-12T15:00:00Z", "2026-09-12T16:05:00Z"],
      ["2026-09-12T15:00:00Z", "2026-09-14T18:00:00Z"],
      [null, "2026-09-12T16:05:00Z"],
      ["nope", "2026-09-12T16:05:00Z"],
      ["2026-09-12T16:00:00Z", "2026-09-12T15:00:00Z"],
    ], (a, b) => m.fmtDuration(a, b));
    add("fmtHour", lang, "Africa/Cairo", [...Array(24).keys(), 24, -1, 25].map((h) => [h]), (h) => m.fmtHour(h));
    add("fmtWireTime", lang, "Africa/Cairo", [["00:05"], ["18:02"], ["9:30"], ["12:00"], ["23:59:59"], ["24:00"], ["12:60"], [""], ["nope"], ["07:00 extra"]], (s) => m.fmtWireTime(s));
  }
  add("initials", "en", "Africa/Cairo", [["Ahmad Ghazal"], ["  mariam  "], [""], ["سارة أحمد علي"], ["a b c"], ["élan vital"]], (s) => m.initials(s));
  add("fmtUnit", "en", "Africa/Cairo", [["g"], ["kg"], ["ml"], ["l"], ["pcs"], ["box"], [null], [""]], (s) => m.fmtUnit(s));
  add("rateOf", "en", "Africa/Cairo", [
    [{ value: 14, dtype: "percentage" }],
    [{ value: 14, value_rate: 0.14, dtype: "percentage" }],
    [{ value: 500, dtype: "fixed" }],
    [{ value: 500 }],
  ], (d) => m.rateOf(d));
  for (const tz of TZS) {
    add("cairoDateISO", "en", tz, [[2026, 2, 8, false], [2026, 2, 8, true], [2026, 0, 1, false], [2026, 11, 31, true], [2026, 9, 30, false], [2026, 3, 24, false], [2026, 3, 24, true], [2026, 9, 29, true], [2026, 9, 30, false], [2026, 10, 1, false], [2026, 1, 0, false], [2026, 0, -5, true], [2026, 12, 1, false]], (y, mo, d, e) => m.cairoDateISO(y, mo, d, e));
    add("cairoParts", "en", tz, [["2026-03-07T22:30:00Z"], ["2026-12-31T23:30:00Z"], ["2026-06-01T03:00:00Z"]], (s) => m.cairoParts(s));
    const presetNows = [Date.UTC(2026, 2, 8, 15), Date.UTC(2026, 2, 9, 15), Date.UTC(2026, 9, 31, 23, 30), Date.UTC(2026, 0, 1, 1), Date.UTC(2026, 10, 1, 5), Date.UTC(2026, 3, 24, 10), Date.UTC(2026, 3, 25, 10), Date.UTC(2026, 4, 20, 10), Date.UTC(2026, 9, 29, 10), Date.UTC(2026, 9, 30, 10), Date.UTC(2026, 10, 27, 10)];
    for (const p of ["today", "yesterday", "7d", "30d", "mtd"]) {
      add("rangeForPreset", "en", tz, presetNows.map((n) => [p, n]), (pp, n) => m.rangeForPreset(pp, tz, n));
    }
    add("toExcelDateSerial", "en", tz, instants.filter((v) => v && v !== "not-a-date").map((v) => [v]), (v) => m.toExcelDateSerial(new Date(v), tz));
  }

  writeFileSync(OUT, JSON.stringify({ generatedFrom: "MadarDashboard src/lib/format.ts, src/data/scope/presets.ts, src/lib/excel.ts", node: process.versions.node, icu: process.versions.icu, vectors }, null, 1) + "\n");
  console.log(`wrote ${vectors.length} vectors to ${OUT}`);
} finally {
  rmSync(tmp, { recursive: true, force: true });
}
