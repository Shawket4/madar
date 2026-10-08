#!/usr/bin/env node
// Generate dashboard_core's navigation data from the web dashboard's own
// config, by EVALUATING it (not by reading it with regexes):
//
//   - src/config/nav.ts            NAV, the module-tagged extra routes
//   - src/features/settings/settings-nav.ts   SETTINGS_NAV
//   - the 25 redirect-only route files under src/routes/_app/**
//
// esbuild (from MadarDashboard/node_modules) bundles each into a temp dir with
// the Lucide icon imports stubbed to their names and TanStack Router's
// createFileRoute/redirect stubbed to capture what a redirect does. A probe
// query string is sent through each redirect to learn which parameters it
// keeps.
//
//   node tool/gen_dashboard_nav.mjs [--web <dir>]     write lib/src/generated/nav.dart
//   node tool/gen_dashboard_nav.mjs --json            print the evaluated web data (for the parity test)
//   node tool/gen_dashboard_nav.mjs --check           exit 1 when nav.dart is stale
//
// The web repo is read-only: nothing is written inside it.
import { execFileSync } from "node:child_process";
import { createRequire } from "node:module";
import { existsSync, mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync, mkdirSync, statSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join, relative, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const OUT = join(ROOT, "packages", "dashboard_core", "lib", "src", "generated", "nav.dart");
const argv = process.argv.slice(2);
const webAt = argv.indexOf("--web");
const WEB = resolve(webAt >= 0 ? argv[webAt + 1] : "/Users/shawket/Desktop/Madar/MadarDashboard");
const JSON_MODE = argv.includes("--json");
const CHECK = argv.includes("--check");

const require = createRequire(join(WEB, "package.json"));
const esbuild = require("esbuild");

/**
 * Lucide icon -> MadarIcon catalog name (design_system/lib/src/icons.dart).
 * Every icon the two nav files use must be here; the generator refuses an
 * unmapped one so a new web icon is a conscious choice.
 */
const ICONS = {
  Armchair: "table",
  ArrowLeftRight: "arrow.up.arrow.down",
  BadgePercent: "percent",
  Boxes: "shippingbox",
  Building2: "building.2",
  CalendarClock: "calendar",
  CalendarRange: "calendar.days",
  ChefHat: "fork.knife",
  ClipboardList: "list.bullet.rectangle",
  Coins: "banknote",
  Contact: "person.fill",
  CreditCard: "creditcard",
  CupSoda: "cat.drink",
  FileBarChart: "chart.pie",
  Home: "house",
  Image: "camera",
  Inbox: "tray",
  Languages: "globe",
  Layers: "layers",
  LayoutDashboard: "square.grid.2x2",
  Link2: "link",
  ListChecks: "list.bullet",
  MessageCircle: "text.bubble",
  Package: "shippingbox",
  Palette: "sun.max",
  Plug: "link",
  QrCode: "qrcode",
  Receipt: "receipt",
  Sandwich: "cat.lunch",
  Scale: "building.columns",
  Settings: "gearshape",
  Settings2: "gearshape",
  Shapes: "square.grid.2x2.fill",
  ShoppingCart: "cart",
  SlidersHorizontal: "slider.horizontal.3",
  Star: "star",
  Store: "storefront",
  Tablet: "iphone",
  Telescope: "sparkles",
  TicketPercent: "percent",
  Trash2: "trash",
  TrendingUp: "arrow.up.right",
  Truck: "bicycle",
  UserRound: "person",
  Users: "person.2",
  Utensils: "fork.knife",
  Wallet: "wallet",
  UtensilsCrossed: "fork.knife",
};

const kebab = (s) => s.replace(/([a-z0-9])([A-Z])/g, "$1-$2").replace(/([A-Za-z])(\d)/g, "$1-$2").toLowerCase();

function resolveTs(base) {
  for (const ext of ["", ".ts", ".tsx", "/index.ts", "/index.tsx", ".js"]) {
    const p = base + ext;
    if (existsSync(p) && statSync(p).isFile()) return p;
  }
  throw new Error(`cannot resolve ${base}`);
}

const STUBS = {
  // Every named import resolves to its own name: `Armchair` -> "Armchair".
  "lucide-react": Object.keys(require("lucide-react"))
    .filter((k) => /^[A-Za-z_$][\w$]*$/.test(k) && k !== "default")
    .map((k) => `export const ${k} = ${JSON.stringify(k)};`)
    .join("\n"),
  "@tanstack/react-router": `
    export const createFileRoute = (path) => (opts) => ({ path, opts });
    export const redirect = (r) => r;
    export const Outlet = () => null;`,
};

/** Expose nav.ts's private route table to the generator (in the bundle only). */
const NAV_EXTRA = `\nexport { EXTRA_MODULE_ROUTES as __EXTRA_MODULE_ROUTES, MODULE_ROUTES as __MODULE_ROUTES };\n`;

async function bundle(contents, tmp, name) {
  const outfile = join(tmp, `${name}.mjs`);
  await esbuild.build({
    stdin: { contents, resolveDir: join(WEB, "src"), loader: "ts" },
    bundle: true,
    format: "esm",
    platform: "node",
    outfile,
    logLevel: "error",
    plugins: [
      {
        name: "web-stubs",
        setup(b) {
          b.onResolve({ filter: /.*/ }, (a) => {
            if (STUBS[a.path] !== undefined) return { path: a.path, namespace: "stub" };
            if (a.path.startsWith("@/")) return { path: resolveTs(join(WEB, "src", a.path.slice(2))) };
            return undefined;
          });
          b.onLoad({ filter: /.*/, namespace: "stub" }, (a) => ({ contents: STUBS[a.path], loader: "js" }));
          b.onLoad({ filter: /src[\\/]config[\\/]nav\.ts$/ }, (a) => ({
            contents: readFileSync(a.path, "utf8") + NAV_EXTRA,
            loader: "ts",
          }));
        },
      },
    ],
  });
  return import(pathToFileURL(outfile).href);
}

function walk(dir, out = []) {
  for (const e of readdirSync(dir, { withFileTypes: true })) {
    const p = join(dir, e.name);
    if (e.isDirectory()) walk(p, out);
    else if (/\.tsx?$/.test(e.name)) out.push(p);
  }
  return out.sort();
}

const PROBE = { user: "probe-user", edit: "probe-edit", branches: "probe-branches", branchId: "probe-branch", preset: "7d", zzz: "probe-other" };

async function evaluate() {
  const tmp = mkdtempSync(join(tmpdir(), "fdash-nav-"));
  try {
    const nav = await bundle(
      `export { NAV, __EXTRA_MODULE_ROUTES, __MODULE_ROUTES } from "@/config/nav";
       export { SETTINGS_NAV } from "@/features/settings/settings-nav";`,
      tmp,
      "nav",
    );

    const routeFiles = walk(join(WEB, "src", "routes", "_app")).filter((f) => {
      const s = readFileSync(f, "utf8");
      return /throw redirect\(/.test(s) && !/\bcomponent\s*:/.test(s);
    });
    const redirects = [];
    let n = 0;
    for (const f of routeFiles) {
      const rel = relative(join(WEB, "src", "routes"), f).split("\\").join("/");
      const m = await bundle(`export { Route } from ${JSON.stringify(f)};`, tmp, `route${n++}`);
      const { path, opts } = m.Route;
      const validated = opts.validateSearch ? opts.validateSearch({ ...PROBE }) : { ...PROBE };
      let thrown;
      try {
        opts.beforeLoad({ search: validated, location: { href: "/probe", pathname: "/probe" }, params: {} });
      } catch (e) {
        thrown = e;
      }
      if (!thrown || typeof thrown.to !== "string") throw new Error(`${rel}: beforeLoad did not redirect`);
      let query = "none";
      let keys = [];
      if (thrown.search !== undefined) {
        const kept = Object.keys(thrown.search).filter((k) => thrown.search[k] !== undefined);
        if (kept.length === Object.keys(PROBE).length) query = "all";
        else {
          query = "keys";
          keys = kept;
        }
      }
      const from = path.replace(/^\/_app/, "").replace(/\/$/, "") || "/";
      redirects.push({ from, to: thrown.to, query, keys, replace: !!thrown.replace, source: rel });
    }
    if (redirects.length !== 25) throw new Error(`expected the web's 25 redirect-only routes, found ${redirects.length}`);
    return {
      nav: nav.NAV,
      settings: nav.SETTINGS_NAV,
      extraModuleRoutes: nav.__EXTRA_MODULE_ROUTES,
      moduleRoutes: nav.__MODULE_ROUTES,
      redirects,
    };
  } finally {
    rmSync(tmp, { recursive: true, force: true });
  }
}

const dstr = (s) => (s == null ? "null" : `'${String(s).replace(/\\/g, "\\\\").replace(/'/g, "\\'").replace(/\$/g, "\\$").replace(/\n/g, "\\n")}'`);
const dlist = (xs) => `<String>[${xs.map(dstr).join(", ")}]`;

function icon(name, where) {
  const mapped = ICONS[name];
  if (!mapped) throw new Error(`${where}: Lucide icon "${name}" has no MadarIcon mapping in tool/gen_dashboard_nav.mjs`);
  return mapped;
}

function leaf(l, indent) {
  const parts = [
    `to: ${dstr(l.to)}`,
    `labelKey: ${dstr(l.labelKey)}`,
    `fallback: ${dstr(l.fallback)}`,
    `icon: ${dstr(icon(l.icon, l.to))}`,
    `lucide: ${dstr(kebab(l.icon))}`,
  ];
  if (l.caps) parts.push(`caps: ${dlist(l.caps)}`);
  if (l.module) parts.push(`module: ${dstr(l.module)}`);
  if (l.superAdminOnly) parts.push("superAdminOnly: true");
  if (l.setup) parts.push("setup: true");
  return `${indent}NavLeaf(${parts.join(", ")}),`;
}

function toDart(d) {
  const o = [];
  const w = (s) => o.push(s);
  w("// GENERATED by tool/gen_dashboard_nav.mjs from MadarDashboard src/config/nav.ts,");
  w("// src/features/settings/settings-nav.ts and the redirect-only route files under");
  w("// src/routes/_app. DO NOT EDIT: re-run the tool.");
  w("// ignore_for_file: type=lint");
  w("");
  w("import 'package:dashboard_core/src/routes/nav.dart';");
  w("");
  w("/// The sidebar (`NAV`).");
  w("const List<NavGroup> dashNav = <NavGroup>[");
  for (const g of d.nav) {
    w(`  NavGroup(labelKey: ${dstr(g.labelKey)}, fallback: ${dstr(g.fallback)}, entries: <NavEntry>[`);
    for (const e of g.entries) {
      if (e.children) {
        w(`    NavParent(labelKey: ${dstr(e.labelKey)}, fallback: ${dstr(e.fallback)}, icon: ${dstr(icon(e.icon, e.basePath))}, lucide: ${dstr(kebab(e.icon))}, basePath: ${dstr(e.basePath)}, children: <NavLeaf>[`);
        for (const c of e.children) w(leaf(c, "      "));
        w("    ]),");
      } else {
        w(leaf(e, "    "));
      }
    }
    w("  ]),");
  }
  w("];");
  w("");
  w("/// Settings panes, in order (`SETTINGS_NAV`).");
  w("const List<SettingsNavGroup> settingsNav = <SettingsNavGroup>[");
  for (const g of d.settings) {
    w(`  SettingsNavGroup(labelKey: ${dstr(g.labelKey)}, fallback: ${dstr(g.fallback)}, items: <SettingsNavLeaf>[`);
    for (const i of g.items) {
      const parts = [
        `to: ${dstr(i.to)}`,
        `labelKey: ${dstr(i.labelKey)}`,
        `fallback: ${dstr(i.fallback)}`,
        `descKey: ${dstr(i.descKey)}`,
        `desc: ${dstr(i.desc)}`,
        `icon: ${dstr(icon(i.icon, i.to))}`,
        `lucide: ${dstr(kebab(i.icon))}`,
      ];
      if (i.caps) parts.push(`caps: ${dlist(i.caps)}`);
      if (i.module) parts.push(`module: ${dstr(i.module)}`);
      if (i.superAdminOnly) parts.push("superAdminOnly: true");
      w(`    SettingsNavLeaf(${parts.join(", ")}),`);
    }
    w("  ]),");
  }
  w("];");
  w("");
  w("/// Pages that belong to a module but have no nav leaf (`EXTRA_MODULE_ROUTES`).");
  w("const List<(String, String)> extraModuleRoutes = <(String, String)>[");
  for (const [p, m] of d.extraModuleRoutes) w(`  (${dstr(p)}, ${dstr(m)}),`);
  w("];");
  w("");
  w("/// The settings language pane's icon (`LANGUAGE_ICON`).");
  w(`const String languageIcon = ${dstr(ICONS.Languages)};`);
  w("");
  w("/// The web's redirect-only routes: old paths and where they land now.");
  w("const List<LegacyRedirect> legacyRedirects = <LegacyRedirect>[");
  for (const r of d.redirects) {
    const parts = [`from: ${dstr(r.from)}`, `to: ${dstr(r.to)}`, `source: ${dstr(r.source)}`];
    if (r.query !== "none") parts.push(`query: RedirectQuery.${r.query}`);
    if (r.keys.length) parts.push(`keys: ${dlist(r.keys)}`);
    if (r.replace) parts.push("replace: true");
    w(`  LegacyRedirect(${parts.join(", ")}),`);
  }
  w("];");
  return o.join("\n") + "\n";
}

/** The text as `dart format` writes it (the repo's CI checks formatting). */
function dartFormat(text) {
  const dir = mkdtempSync(join(tmpdir(), "fdash-nav-fmt-"));
  try {
    const p = join(dir, "nav.dart");
    writeFileSync(p, text);
    execFileSync("dart", ["format", "--language-version=3.11", p], { stdio: "ignore" });
    return readFileSync(p, "utf8");
  } catch {
    return text;
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

const data = await evaluate();
if (JSON_MODE) {
  process.stdout.write(JSON.stringify({ ...data, icons: ICONS }) + "\n");
} else {
  const text = dartFormat(toDart(data));
  const current = existsSync(OUT) ? readFileSync(OUT, "utf8") : null;
  if (current !== text) {
    if (CHECK) {
      console.error(`stale: ${OUT} (run node tool/gen_dashboard_nav.mjs)`);
      process.exit(1);
    }
    mkdirSync(dirname(OUT), { recursive: true });
    writeFileSync(OUT, text);
    console.log(`wrote ${relative(ROOT, OUT)}`);
  }
}
