import assert from "node:assert/strict";
import test from "node:test";

import { createNamePolicy } from "../src/namePolicy.js";
import { monthlyPeriod } from "../src/utils.js";

test("sanitizes whitespace", () => {
  assert.equal(createNamePolicy().sanitize("  Ivy   Park  "), "Ivy Park");
});

test("blocks normalized profanity", () => {
  assert.throws(() => createNamePolicy().sanitize("f.u.c.k"));
});

test("creates a monthly period", () => {
  assert.equal(monthlyPeriod(new Date("2026-06-23T00:00:00Z")), "2026-06");
});
