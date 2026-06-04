import assert from "node:assert/strict";
import test from "node:test";
import { cardToPreview, draftToPreview, readablePrompt } from "../.tmp-test/cardPreview.js";

const singleChoiceContent = `{single-choice}
Q: 平均访存时间 AMAT 的组成是什么？
* 命中时间 + 缺失率 × 缺失代价
- 缺失率 + 磁盘容量
- CPU 主频 × Cache 行大小
{/single-choice}

@answer
AMAT = 命中时间 + 缺失率 × 缺失代价。
@end`;

test("readablePrompt renders choice DSL as visual options", () => {
  const rendered = readablePrompt(singleChoiceContent.split("@answer")[0]);

  assert.match(rendered, /平均访存时间 AMAT/);
  assert.match(rendered, /● 命中时间 \+ 缺失率 × 缺失代价/);
  assert.match(rendered, /○ 缺失率 \+ 磁盘容量/);
  assert.doesNotMatch(rendered, /\{single-choice\}/);
});

test("draft preview prefers choice DSL from content over plain front", () => {
  const preview = draftToPreview({
    title: "Cache 选择题",
    front: "平均访存时间 AMAT 的组成是什么？",
    content: singleChoiceContent,
    back: "AMAT = 命中时间 + 缺失率 × 缺失代价。",
  });

  assert.ok(preview);
  assert.match(preview.front, /● 命中时间 \+ 缺失率 × 缺失代价/);
  assert.match(preview.front, /○ CPU 主频 × Cache 行大小/);
});

test("saved card preview prefers choice DSL from content over plain front", () => {
  const preview = cardToPreview({
    title: "Cache 选择题",
    front: "平均访存时间 AMAT 的组成是什么？",
    content: singleChoiceContent,
    back: "AMAT = 命中时间 + 缺失率 × 缺失代价。",
    tags: ["408"],
    study_enabled: true,
  });

  assert.match(preview.front, /● 命中时间 \+ 缺失率 × 缺失代价/);
  assert.match(preview.front, /○ 缺失率 \+ 磁盘容量/);
});
