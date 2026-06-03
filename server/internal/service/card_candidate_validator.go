package service

import (
	"math"
	"strings"
	"unicode/utf8"

	"github.com/ank/flashcard-server/internal/model"
)

func attachQualityReports(items []model.AIGeneratedCard, policy model.GenerationPolicy) []model.AIGeneratedCard {
	seenPrompts := make(map[string]struct{}, len(items))
	out := make([]model.AIGeneratedCard, 0, len(items))
	for _, item := range items {
		report := validateGeneratedCard(item, policy, seenPrompts)
		item.QualityReport = &report
		out = append(out, item)
	}
	return out
}

func validateGeneratedCard(item model.AIGeneratedCard, policy model.GenerationPolicy, seenPrompts map[string]struct{}) model.AICardQualityReport {
	prompt, answer := splitCardContent(item.Content)
	if prompt == "" {
		prompt = item.Front
	}
	if answer == "" {
		answer = item.Back
	}
	violations := make([]model.AIQualityViolation, 0)

	answerLen := utf8.RuneCountInString(strings.TrimSpace(answer))
	if policy.MaxAnswerChars > 0 && answerLen > policy.MaxAnswerChars {
		violations = append(violations, model.AIQualityViolation{
			Code:     "answer_too_long",
			Message:  "答案超过当前规则允许长度，建议压缩为更短、可自评的表达。",
			Severity: "warning",
		})
	}
	if strings.EqualFold(policy.AtomicityLevel, "strict") && looksMultiConcept(prompt) {
		violations = append(violations, model.AIQualityViolation{
			Code:     "possibly_not_atomic",
			Message:  "题干可能同时考察多个概念，建议拆成更小的原子卡。",
			Severity: "warning",
		})
	}
	if strings.TrimSpace(answer) == "" {
		violations = append(violations, model.AIQualityViolation{
			Code:     "missing_answer",
			Message:  "卡片缺少答案，复习时难以自评。",
			Severity: "error",
		})
	}
	key := strings.ToLower(strings.Join(strings.Fields(prompt), " "))
	if key != "" {
		if _, exists := seenPrompts[key]; exists {
			violations = append(violations, model.AIQualityViolation{
				Code:     "duplicate_prompt",
				Message:  "题干与已有候选高度重复。",
				Severity: "warning",
			})
		}
		seenPrompts[key] = struct{}{}
	}

	score := 1.0 - float64(len(violations))*0.22
	score = math.Max(0.1, math.Min(1.0, score))
	badges := []string{"一卡一知识点", "可自评"}
	if len(violations) == 0 {
		badges = append(badges, "已通过规则检查")
	} else {
		badges = append(badges, "需要检查")
	}
	return model.AICardQualityReport{
		Score:      score,
		Badges:     badges,
		Violations: violations,
		Repairable: len(violations) > 0,
	}
}

func looksMultiConcept(prompt string) bool {
	prompt = strings.TrimSpace(prompt)
	if prompt == "" {
		return false
	}
	markers := []string{"分别", "和", "以及", "与", "、", "/", "及其", "包括哪些"}
	for _, marker := range markers {
		if strings.Contains(prompt, marker) {
			return true
		}
	}
	return false
}
