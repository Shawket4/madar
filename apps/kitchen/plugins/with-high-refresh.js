// Android high refresh rate (90/120/144 Hz), on every prebuild (android/ is
// generated). Adds HighRefreshRate.kt (plugins/HighRefreshRate.kt.txt, the same
// logic as the Flutter apps: highest-Hz mode at the CURRENT resolution, never a
// resolution change, all guarded, no-op below API 23) and hooks MainActivity:
// start() in onCreate (applies + registers a DisplayManager listener), apply()
// in onResume, stop() in onDestroy.
const fs = require("fs");
const path = require("path");
const { withDangerousMod, withMainActivity } = require("expo/config-plugins");

const MARK = "HighRefreshRate";

function patch(src) {
  if (src.includes(`${MARK}(this)`)) return src;
  if (!/super\.onCreate\([^)]*\)/.test(src) || !/class MainActivity\b[^{]*\{/.test(src)) {
    throw new Error("with-high-refresh: MainActivity.kt no longer matches the expected template");
  }
  src = src.replace(/(\n[ \t]*)(super\.onCreate\([^)]*\))/, `$1$2$1highRefreshRate.start()`);
  src = src.replace(
    /(class MainActivity\b[^{]*\{\n)/,
    `$1  private val highRefreshRate = ${MARK}(this)\n\n`,
  );
  // Lifecycle hooks go right before the main-component accessor.
  const hooks = `  override fun onResume() {
    super.onResume()
    highRefreshRate.apply()
  }

  override fun onDestroy() {
    highRefreshRate.stop()
    super.onDestroy()
  }

`;
  const anchor = /(  \/\*\*\n(?:   \*.*\n)*?   \*\/\n)?  override fun getMainComponentName/;
  if (!anchor.test(src)) throw new Error("with-high-refresh: getMainComponentName not found");
  return src.replace(anchor, (m) => hooks + m);
}

module.exports = function withHighRefresh(config) {
  config = withDangerousMod(config, [
    "android",
    (c) => {
      const pkg = c.android?.package;
      if (!pkg) throw new Error("with-high-refresh: android.package is not set in app.json");
      const dir = path.join(c.modRequest.platformProjectRoot, "app/src/main/java", ...pkg.split("."));
      fs.mkdirSync(dir, { recursive: true });
      const tpl = fs.readFileSync(path.join(__dirname, "HighRefreshRate.kt.txt"), "utf8");
      fs.writeFileSync(path.join(dir, `${MARK}.kt`), tpl.replace("__PACKAGE__", pkg));
      return c;
    },
  ]);
  return withMainActivity(config, (c) => {
    if (c.modResults.language !== "kt") throw new Error("with-high-refresh: MainActivity is not Kotlin");
    c.modResults.contents = patch(c.modResults.contents);
    return c;
  });
};
