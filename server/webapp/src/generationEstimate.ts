export type GenerationEstimateInput = {
  contextLength: number;
  fileSize?: number;
  cardCount?: number;
  hasFile: boolean;
  allowWebSearch: boolean;
  examMode: boolean;
};

export type GenerationEstimate = {
  seconds: number;
  label: string;
  shouldUseBackground: boolean;
  modeLabel: string;
};

export function estimateGeneration(input: GenerationEstimateInput): GenerationEstimate {
  const sourceWeight = Math.max(0, input.contextLength) + (input.hasFile ? Math.min(input.fileSize || 8000, 120000) / 8 : 0);
  const automaticCards = Math.max(input.hasFile ? 12 : 4, Math.ceil(sourceWeight / 520));
  const requestedCards = input.cardCount && input.cardCount > 0 ? input.cardCount : automaticCards;
  let seconds = 10 + requestedCards * 3 + Math.ceil(sourceWeight / 650);
  if (input.hasFile) seconds += 35;
  if (input.allowWebSearch) seconds += 25;
  if (input.examMode) seconds += 10;
  seconds = Math.min(Math.max(seconds, 8), 720);

  const shouldUseBackground = input.hasFile || input.allowWebSearch || seconds >= 45;
  return {
    seconds,
    label: formatEstimate(seconds),
    shouldUseBackground,
    modeLabel: shouldUseBackground ? "后台任务，完成后可取回" : "直接生成，稍后显示草稿",
  };
}

function formatEstimate(seconds: number) {
  if (seconds < 60) return `约 ${seconds} 秒`;
  const minutes = Math.ceil(seconds / 60);
  return `约 ${minutes} 分钟`;
}
