export type GenerationEstimateInput = {
  contextLength: number;
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
  const requestedCards = input.cardCount && input.cardCount > 0 ? input.cardCount : 6;
  let seconds = 8 + requestedCards * 2 + Math.ceil(Math.max(0, input.contextLength) / 420);
  if (input.hasFile) seconds += 28;
  if (input.allowWebSearch) seconds += 18;
  if (input.examMode) seconds += 8;
  seconds = Math.min(Math.max(seconds, 8), 180);

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
