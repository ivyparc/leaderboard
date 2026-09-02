import assert from "node:assert/strict";
import test from "node:test";

import {
  formatDurationScore,
  isBetterScore,
  normalizeScoreOrder,
} from "../src/utils.js";

test("normalizes score order", () => {
  assert.equal(normalizeScoreOrder("lower"), "lower");
  assert.equal(normalizeScoreOrder("higher"), "higher");
  assert.equal(normalizeScoreOrder("anything"), "higher");
});

test("compares higher and lower scores", () => {
  assert.equal(isBetterScore(12, undefined), true);
  assert.equal(isBetterScore(12, 10, "higher"), true);
  assert.equal(isBetterScore(8, 10, "higher"), false);
  assert.equal(isBetterScore(8, 10, "lower"), true);
  assert.equal(isBetterScore(12, 10, "lower"), false);
});

test("formats duration scores as mm:ss", () => {
  assert.equal(formatDurationScore(0), "00:00");
  assert.equal(formatDurationScore(231), "03:51");
  assert.equal(formatDurationScore(623), "10:23");
});
