package service

import (
	"fmt"
	"strings"

	"github.com/ank/flashcard-server/internal/model"
)

func defaultGenerationPolicy() model.GenerationPolicy {
	return model.GenerationPolicy{
		Name:                    "通用精读拆卡",
		Description:             "适合课程讲义、教材章节和知识点笔记的默认拆卡规则。",
		AtomicityLevel:          "strict",
		AnswerStyle:             "one_sentence",
		MaxAnswerChars:          80,
		PreferredCardTypes:      []string{"basic", "cloze", "single_choice"},
		AllowDefinitionCards:    true,
		AllowComparisonCards:    true,
		AllowExampleCards:       true,
		AllowMisconceptionCards: true,
		SplitStrategy:           "by_heading",
		CoverageMode:            "balanced",
		MaxCardsPerChunk:        6,
		MaxCardsTotal:           20,
		RequireSourceExcerpt:    true,
		RequireSourceLocation:   true,
		DedupeLevel:             "medium",
		RepairMode:              "violations_only",
	}
}

func effectiveGenerationPolicy(request model.AIGenerateRequest) model.GenerationPolicy {
	policy := defaultGenerationPolicy()
	if request.Policy != nil {
		mergeGenerationPolicy(&policy, *request.Policy)
	}
	if len(request.CardTypes) > 0 && (request.Policy == nil || len(request.Policy.PreferredCardTypes) == 0) {
		policy.PreferredCardTypes = compactStrings(request.CardTypes)
	}
	if policy.MaxCardsTotal <= 0 {
		policy.MaxCardsTotal = 20
	}
	if request.CardCount > 0 && request.CardCount < policy.MaxCardsTotal {
		policy.MaxCardsTotal = request.CardCount
	}
	if policy.MaxCardsPerChunk <= 0 {
		policy.MaxCardsPerChunk = 6
	}
	if policy.MaxAnswerChars <= 0 {
		policy.MaxAnswerChars = 80
	}
	if policy.MaxAnswerChars < 12 {
		policy.MaxAnswerChars = 12
	}
	if policy.MaxAnswerChars > 600 {
		policy.MaxAnswerChars = 600
	}
	if strings.TrimSpace(policy.AtomicityLevel) == "" {
		policy.AtomicityLevel = "strict"
	}
	if strings.TrimSpace(policy.AnswerStyle) == "" {
		policy.AnswerStyle = "one_sentence"
	}
	if strings.TrimSpace(policy.SplitStrategy) == "" {
		policy.SplitStrategy = "by_heading"
	}
	if strings.TrimSpace(policy.CoverageMode) == "" {
		policy.CoverageMode = "balanced"
	}
	if strings.TrimSpace(policy.DedupeLevel) == "" {
		policy.DedupeLevel = "medium"
	}
	if strings.TrimSpace(policy.RepairMode) == "" {
		policy.RepairMode = "violations_only"
	}
	return policy
}

func mergeGenerationPolicy(target *model.GenerationPolicy, override model.GenerationPolicy) {
	if strings.TrimSpace(override.ID) != "" {
		target.ID = strings.TrimSpace(override.ID)
	}
	if strings.TrimSpace(override.UserID) != "" {
		target.UserID = strings.TrimSpace(override.UserID)
	}
	if strings.TrimSpace(override.Name) != "" {
		target.Name = strings.TrimSpace(override.Name)
	}
	if strings.TrimSpace(override.Description) != "" {
		target.Description = strings.TrimSpace(override.Description)
	}
	if strings.TrimSpace(override.Subject) != "" {
		target.Subject = strings.TrimSpace(override.Subject)
	}
	if strings.TrimSpace(override.Audience) != "" {
		target.Audience = strings.TrimSpace(override.Audience)
	}
	if strings.TrimSpace(override.AtomicityLevel) != "" {
		target.AtomicityLevel = strings.TrimSpace(override.AtomicityLevel)
	}
	if strings.TrimSpace(override.AnswerStyle) != "" {
		target.AnswerStyle = strings.TrimSpace(override.AnswerStyle)
	}
	if override.MaxAnswerChars > 0 {
		target.MaxAnswerChars = override.MaxAnswerChars
	}
	if len(override.PreferredCardTypes) > 0 {
		target.PreferredCardTypes = compactStrings(override.PreferredCardTypes)
	}
	target.AllowDefinitionCards = override.AllowDefinitionCards || target.AllowDefinitionCards
	target.AllowComparisonCards = override.AllowComparisonCards || target.AllowComparisonCards
	target.AllowExampleCards = override.AllowExampleCards || target.AllowExampleCards
	target.AllowMisconceptionCards = override.AllowMisconceptionCards || target.AllowMisconceptionCards
	if strings.TrimSpace(override.SplitStrategy) != "" {
		target.SplitStrategy = strings.TrimSpace(override.SplitStrategy)
	}
	if strings.TrimSpace(override.CoverageMode) != "" {
		target.CoverageMode = strings.TrimSpace(override.CoverageMode)
	}
	if override.MaxCardsPerChunk > 0 {
		target.MaxCardsPerChunk = override.MaxCardsPerChunk
	}
	if override.MaxCardsTotal > 0 {
		target.MaxCardsTotal = override.MaxCardsTotal
	}
	target.RequireSourceExcerpt = override.RequireSourceExcerpt || target.RequireSourceExcerpt
	target.RequireSourceLocation = override.RequireSourceLocation || target.RequireSourceLocation
	if strings.TrimSpace(override.DedupeLevel) != "" {
		target.DedupeLevel = strings.TrimSpace(override.DedupeLevel)
	}
	if strings.TrimSpace(override.RepairMode) != "" {
		target.RepairMode = strings.TrimSpace(override.RepairMode)
	}
	if strings.TrimSpace(override.CustomRules) != "" {
		target.CustomRules = strings.TrimSpace(override.CustomRules)
	}
}

func policyPromptRules(policy model.GenerationPolicy) string {
	return fmt.Sprintf(
		"GenerationPolicy: name=%s; atomicity=%s; answer_style=%s; max_answer_chars=%d; preferred_card_types=%s; split_strategy=%s; coverage=%s; custom_rules=%s. Rules: one card tests one atomic knowledge point; answers must be short and self-checkable; cloze blanks should hide short key terms only; choice distractors must be plausible; do not make broad essay cards; keep source traceability when source excerpts or locations are provided.",
		strings.TrimSpace(policy.Name),
		strings.TrimSpace(policy.AtomicityLevel),
		strings.TrimSpace(policy.AnswerStyle),
		policy.MaxAnswerChars,
		strings.Join(policy.PreferredCardTypes, ", "),
		strings.TrimSpace(policy.SplitStrategy),
		strings.TrimSpace(policy.CoverageMode),
		strings.TrimSpace(policy.CustomRules),
	)
}

func compactStrings(values []string) []string {
	out := make([]string, 0, len(values))
	seen := make(map[string]struct{}, len(values))
	for _, value := range values {
		value = strings.TrimSpace(value)
		if value == "" {
			continue
		}
		if _, ok := seen[value]; ok {
			continue
		}
		seen[value] = struct{}{}
		out = append(out, value)
	}
	return out
}
