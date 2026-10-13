/// <reference types="node" />
// AT-6: Arabic and English stay complete. Plural suffixes are matched by stem.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const load = (l: string) => JSON.parse(readFileSync(new URL(`./locales/${l}.json`, import.meta.url), "utf8"));
const keys = (o: Record<string, unknown>, p = ""): string[] =>
  Object.entries(o).flatMap(([k, v]) => (typeof v === "object" ? keys(v as Record<string, unknown>, `${p}${k}.`) : [`${p}${k}`.replace(/_(zero|one|two|few|many|other)$/, "")]));

test("en and ar have the same keys", () => {
  assert.deepEqual([...new Set(keys(load("ar")))].sort(), [...new Set(keys(load("en")))].sort());
});
