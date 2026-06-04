import assert from "node:assert/strict";
import test from "node:test";
import { estimateGeneration } from "../.tmp-test/generationEstimate.js";

test("short plain text can generate directly", () => {
  const estimate = estimateGeneration({
    contextLength: 180,
    cardCount: 4,
    hasFile: false,
    allowWebSearch: false,
    examMode: false,
  });

  assert.equal(estimate.shouldUseBackground, false);
  assert.equal(estimate.modeLabel, "直接生成，稍后显示草稿");
  assert.match(estimate.label, /秒/);
});

test("file import uses background generation", () => {
  const estimate = estimateGeneration({
    contextLength: 1200,
    hasFile: true,
    allowWebSearch: false,
    examMode: false,
  });

  assert.equal(estimate.shouldUseBackground, true);
  assert.equal(estimate.modeLabel, "后台任务，完成后可取回");
});

test("web enhanced exam generation uses background and increases estimate", () => {
  const plain = estimateGeneration({
    contextLength: 1200,
    hasFile: false,
    allowWebSearch: false,
    examMode: false,
  });
  const enhanced = estimateGeneration({
    contextLength: 1200,
    hasFile: false,
    allowWebSearch: true,
    examMode: true,
  });

  assert.equal(enhanced.shouldUseBackground, true);
  assert.ok(enhanced.seconds > plain.seconds);
});
