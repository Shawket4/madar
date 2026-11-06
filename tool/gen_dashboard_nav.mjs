#!/usr/bin/env node
// Generate dashboard_core's navigation data from the web dashboard's own
// config, by EVALUATING it (not by reading it with regexes):
//
//   - src/config/nav.ts            NAV, the module-tagged extra routes
//   - src/features/settings/settings-nav.ts   SETTINGS_NAV
//   - the 28 redirect-only route files under src/routes/_app/**
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

/**
 * Web pages the Flutter dashboard has no page for yet: left out of the
 * generated nav (sidebar leaves and settings panes, a path or everything under
 * it), its module routes, the redirects that land on them and the --json the
 * parity test reads, so the nav never offers a dead link. Remove an entry
 * when its page lands.
 *   /settings/plan  Settings > Plan (web 2026-10-13, Free plan); owner call 2026-10-19.
 *   /rewards        Rewards by Madar (web 656ef339, 2026-10-23): not ported yet.
 */
const WEB_ONLY = ["/settings/plan", "/rewards"];
const webOnly = (p) => WEB_ONLY.some((w) => p === w || p.startsWith(`${w}/`));

/**
 * Flutter pages the web has moved on from, kept in the Flutter nav where they
 * were until what replaced them is ported: each entry as the web last had it,
 * put back after `after` in its group, and its web redirect dropped (it would
 * land on a WEB_ONLY page). Remove an entry when its replacement lands.
 *   /settings/loyalty  the web moved Loyalty into Rewards by Madar (/rewards/*,
 *                      656ef339, 2026-10-23); Flutter keeps its Loyalty pane.
 */
const FLUTTER_KEEPS = [
  {
    to: "/settings/loyalty",
    nav: {
      group: "nav.setup",
      after: "/branch-setup",
      leaf: { caps: ["loyalty.use", "loyalty.members.list"], module: "pos", to: "/settings/loyalty", labelKey: "nav.loyalty", fallback: "Loyalty", icon: "Star" },
    },
    settings: {
      group: "settings.groupChannels",
      after: "/settings/bookings",
      item: {
        to: "/settings/loyalty",
        module: "pos",
        caps: ["loyalty.use", "loyalty.members.list"],
        labelKey: "nav.loyalty",
        fallback: "Loyalty",
        descKey: "settings.loyaltyDesc",
        desc: "Points or stamps, the rewards they buy, and who has joined.",
        icon: "Star",
      },
    },
  },
];
const flutterKeeps = (p) => FLUTTER_KEEPS.some((k) => k.to === p);

const navLeaves = (groups) => groups.flatMap((g) => g.entries.flatMap((e) => e.children ?? [e]));

/** [items] with [item] put back after the one at [after] (which must exist). */
function insertAfter(items, after, item, where) {
  const at = items.findIndex((i) => i.to === after);
  if (at < 0) throw new Error(`FLUTTER_KEEPS ${where}: no ${after} to put it after`);
  return [...items.slice(0, at + 1), item, ...items.slice(at + 1)];
}

/** The web's evaluated nav with WEB_ONLY taken out and FLUTTER_KEEPS put back. */
function forFlutter(web) {
  for (const p of WEB_ONLY) {
    const there =
      web.settings.some((g) => g.items.some((i) => webOnly(i.to) && (i.to === p || i.to.startsWith(`${p}/`)))) ||
      navLeaves(web.nav).some((l) => l.to === p || l.to.startsWith(`${p}/`));
    if (!there) throw new Error(`WEB_ONLY ${p} is no longer a web page: drop it from the list`);
  }
  let nav = web.nav
    .map((g) => ({
      ...g,
      entries: g.entries
        .map((e) => (e.children ? { ...e, children: e.children.filter((c) => !webOnly(c.to)) } : e))
        .filter((e) => (e.children ? e.children.length > 0 : !webOnly(e.to))),
    }))
    .filter((g) => g.entries.length > 0);
  let settings = web.settings.map((g) => ({ ...g, items: g.items.filter((i) => !webOnly(i.to)) }));
  for (const k of FLUTTER_KEEPS) {
    if (navLeaves(web.nav).some((l) => l.to === k.to) || web.settings.some((g) => g.items.some((i) => i.to === k.to))) {
      throw new Error(`FLUTTER_KEEPS ${k.to} is a web page again: drop it from the list`);
    }
    nav = nav.map((g) => (g.labelKey === k.nav.group ? { ...g, entries: insertAfter(g.entries, k.nav.after, k.nav.leaf, k.to) } : g));
    settings = settings.map((g) =>
      g.labelKey === k.settings.group ? { ...g, items: insertAfter(g.items, k.settings.after, k.settings.item, k.to) } : g,
    );
    if (!navLeaves(nav).some((l) => l.to === k.to)) throw new Error(`FLUTTER_KEEPS ${k.to}: no nav group ${k.nav.group}`);
    if (!settings.some((g) => g.items.some((i) => i.to === k.to))) {
      throw new Error(`FLUTTER_KEEPS ${k.to}: no settings group ${k.settings.group}`);
    }
  }
  const extraModuleRoutes = web.extraModuleRoutes.filter(([p]) => !webOnly(p));
  // The web's MODULE_ROUTES rule (nav.ts), over the nav Flutter shows.
  const moduleRoutesOf = (groups, extra) => [
    ...navLeaves(groups)
      .filter((l) => l.module && l.to !== "/")
      .map((l) => [l.to, l.module]),
    ...extra,
  ];
  if (JSON.stringify(moduleRoutesOf(web.nav, web.extraModuleRoutes)) !== JSON.stringify(web.moduleRoutes)) {
    throw new Error("the web's MODULE_ROUTES rule changed: update moduleRoutesOf in tool/gen_dashboard_nav.mjs");
  }
  return {
    nav,
    settings,
    extraModuleRoutes,
    moduleRoutes: moduleRoutesOf(nav, extraModuleRoutes),
    redirects: web.redirects.filter((r) => !webOnly(r.to) && !flutterKeeps(r.from)),
  };
}

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
  ClipboardCheck: "checkmark.seal",
  ClipboardList: "list.bullet.rectangle",
  Coins: "banknote",
  Contact: "person.fill",
  CreditCard: "creditcard",
  CupSoda: "cat.drink",
  FileBarChart: "chart.pie",
  Gem: "creditcard",
  Home: "house",
  Image: "camera",
  ImageIcon: "camera",
  Inbox: "tray",
  Languages: "globe",
  Layers: "layers",
  LayoutDashboard: "square.grid.2x2",
  Link2: "link",
  ListChecks: "list.bullet",
  MessageCircle: "text.bubble",
  Network: "network",
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
    // Vite's env object: nav.ts reads `env` (the Rewards host), whose schema
    // has a default for everything the nav needs.
    define: { "import.meta.env": "{}" },
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
      // A search value that is the probe's came through from the old URL; any
      // other value is the redirect's own (`search: { section: "codes" }`).
      const set = {};
      if (thrown.search !== undefined) {
        const given = Object.keys(thrown.search).filter((k) => thrown.search[k] !== undefined);
        const kept = given.filter((k) => thrown.search[k] === validated[k]);
        for (const k of given) if (!kept.includes(k)) set[k] = String(thrown.search[k]);
        if (kept.length === Object.keys(PROBE).length) query = "all";
        else if (kept.length) {
          query = "keys";
          keys = kept;
        }
      }
      const from = path.replace(/^\/_app/, "").replace(/\/$/, "") || "/";
      redirects.push({ from, to: thrown.to, query, keys, set, replace: !!thrown.replace, source: rel });
    }
    if (redirects.length !== 28) throw new Error(`expected the web's 28 redirect-only routes, found ${redirects.length}`);
    return forFlutter({
      nav: nav.NAV,
      settings: nav.SETTINGS_NAV,
      extraModuleRoutes: nav.__EXTRA_MODULE_ROUTES,
      moduleRoutes: nav.__MODULE_ROUTES,
      redirects,
    });
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
    const fixed = Object.entries(r.set);
    if (fixed.length) parts.push(`set: <String, String>{${fixed.map(([k, v]) => `${dstr(k)}: ${dstr(v)}`).join(", ")}}`);
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
