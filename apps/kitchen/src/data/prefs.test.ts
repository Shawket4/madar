/// <reference types="node" />
import { test } from "node:test";
import assert from "node:assert/strict";

import { parsePrefs } from "./prefs.ts";

test("saved settings come back; anything else is ignored", () => {
  assert.deepEqual(parsePrefs('{"theme":"light","lang":"en","chime":false}'), { theme: "light", lang: "en", chime: false });
  assert.deepEqual(parsePrefs('{"theme":"blue","lang":"fr","chime":"no","extra":1}'), {});
  assert.deepEqual(parsePrefs("not json"), {});
  assert.deepEqual(parsePrefs(null), {}, "first launch: the defaults");
});
