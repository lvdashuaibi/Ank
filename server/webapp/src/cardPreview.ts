export type CardPreview = {
  title: string;
  front: string;
  back: string;
  tags: string[];
  studyEnabled: boolean;
  source: "saved" | "draft";
};

export type PreviewCardInput = {
  title?: string;
  content?: string;
  front?: string;
  back?: string;
  tags?: string[];
  study_enabled?: boolean;
};

export type PreviewDraftInput = {
  title?: string;
  content?: string;
  front?: string;
  back?: string;
  tags?: string[];
};

export function cardToPreview(card: PreviewCardInput): CardPreview {
  return {
    title: card.title || card.front || "未命名卡片",
    front: previewFront(card.content, card.front),
    back: card.back || answerOf(card.content),
    tags: card.tags || [],
    studyEnabled: card.study_enabled ?? true,
    source: "saved",
  };
}

export function draftToPreview(draft?: PreviewDraftInput): CardPreview | null {
  if (!draft) return null;
  return {
    title: draft.title || "AI 草稿",
    front: previewFront(draft.content, draft.front),
    back: draft.back || answerOf(draft.content),
    tags: draft.tags || ["AI生成"],
    studyEnabled: true,
    source: "draft",
  };
}

export function previewFront(content = "", front = "") {
  const contentPrompt = promptOf(content);
  if (hasChoiceBlock(contentPrompt)) {
    return readablePrompt(contentPrompt);
  }
  return readablePrompt(front || contentPrompt);
}

export function readablePrompt(prompt = "") {
  const trimmed = prompt.trim();
  const single = parseChoiceBlock(trimmed, "single-choice");
  if (single) return single;
  const multi = parseChoiceBlock(trimmed, "multi-choice");
  if (multi) return multi;
  return trimmed;
}

function hasChoiceBlock(prompt: string) {
  return prompt.includes("{single-choice}") || prompt.includes("{multi-choice}");
}

function parseChoiceBlock(prompt: string, blockName: string) {
  if (!prompt.includes(`{${blockName}}`)) return "";
  const lines = prompt.split("\n").map((line) => line.trim()).filter(Boolean);
  const question = lines.find((line) => line.startsWith("Q:"))?.replace(/^Q:\s*/, "") || "";
  const options = lines
    .filter((line) => line.startsWith("*") || line.startsWith("-"))
    .map((line) => `${line.startsWith("*") ? "●" : "○"} ${line.slice(1).trim()}`);
  return [question, "", ...options].join("\n").trim();
}

export function promptOf(content = "") {
  return content.split("@answer")[0].trim();
}

export function answerOf(content = "") {
  const match = content.match(/@answer\s*([\s\S]*?)\s*@end/);
  return match?.[1]?.trim() || "";
}
