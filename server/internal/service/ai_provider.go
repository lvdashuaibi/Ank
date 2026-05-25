package service

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/model"
)

type openAIChatRequest struct {
	Model       string              `json:"model"`
	Messages    []openAIChatMessage `json:"messages"`
	Temperature float64             `json:"temperature"`
}

type openAIChatMessage struct {
	Role    string `json:"role"`
	Content string `json:"content"`
}

type openAIChatResponse struct {
	Choices []struct {
		Message openAIChatMessage `json:"message"`
	} `json:"choices"`
}

func (s *AppService) tryGenerateCardsWithExternalAI(request model.AIGenerateRequest) ([]model.AIGeneratedCard, error) {
	if s.config == nil || strings.TrimSpace(s.config.AIBaseURL) == "" || strings.TrimSpace(s.config.AIAPIKey) == "" {
		return nil, fmt.Errorf("external ai not configured")
	}

	prompt := buildAIPrompt(request)
	payload := openAIChatRequest{
		Model: s.config.AIModel,
		Messages: []openAIChatMessage{
			{
				Role:    "system",
				Content: "You generate high-quality flashcards for a spaced repetition app. Return JSON only in the format {\"items\":[{\"title\":\"...\",\"content\":\"Card DSL...\",\"front\":\"...\",\"back\":\"...\",\"card_type\":\"basic|single_choice|multi_choice|cloze\",\"knowledge_point\":\"...\",\"source_excerpt\":\"...\",\"tags\":[\"...\"],\"note\":\"...\"}]} without markdown fences.",
			},
			{
				Role:    "user",
				Content: prompt,
			},
		},
		Temperature: 0.7,
	}

	data, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}

	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(s.config.AIBaseURL, "/")+"/chat/completions", bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.config.AIAPIKey)

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("external ai returned status %d", resp.StatusCode)
	}

	var chatResp openAIChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return nil, err
	}
	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("external ai returned no choices")
	}

	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var generated model.AIGenerateResponse
	if err := json.Unmarshal([]byte(content), &generated); err != nil {
		return nil, err
	}
	return normalizeGeneratedCards(generated.Items), nil
}

func buildAIPrompt(request model.AIGenerateRequest) string {
	cardCount := request.CardCount
	if cardCount <= 0 {
		cardCount = 3
	}
	cardTypes := strings.Join(request.CardTypes, ", ")
	if strings.TrimSpace(cardTypes) == "" {
		cardTypes = "basic, single_choice, multi_choice, cloze"
	}
	strategy := strings.TrimSpace(request.Strategy)
	if strategy == "" {
		strategy = "fsrs_friendly"
	}
	return fmt.Sprintf(
		"Topic: %s\nSourceName: %s\nContext: %s\nDifficulty: %s\nCardCount: %d\nAllowedCardTypes: %s\nStrategy: %s\nLanguage: zh-CN\nRules: one card tests one atomic knowledge point; answers must be short and self-checkable; cloze blanks should hide short key terms only; choice distractors must be plausible; do not make broad essay cards; prefer Card DSL content with @answer blocks when useful.",
		strings.TrimSpace(request.Topic),
		strings.TrimSpace(request.SourceName),
		strings.TrimSpace(request.Context),
		strings.TrimSpace(request.Difficulty),
		cardCount,
		cardTypes,
		strategy,
	)
}

func (s *AppService) tryRewriteCardWithExternalAI(request model.AIRewriteCardRequest) ([]model.AIRewriteCandidate, error) {
	if s.config == nil || strings.TrimSpace(s.config.AIBaseURL) == "" || strings.TrimSpace(s.config.AIAPIKey) == "" {
		return nil, fmt.Errorf("external ai not configured")
	}

	payload := openAIChatRequest{
		Model: s.config.AIModel,
		Messages: []openAIChatMessage{
			{
				Role:    "system",
				Content: "You rewrite flashcards for a spaced repetition app. Return JSON only in the format {\"candidates\":[{\"title\":\"...\",\"content\":\"Card DSL...\",\"change_summary\":\"...\",\"quality_notes\":[\"...\"]}]} without markdown fences.",
			},
			{
				Role: "user",
				Content: fmt.Sprintf(
					"Title: %s\nContent:\n%s\nRewriteType: %s\nInstruction: %s\nLanguage: zh-CN\nRules: preserve factual meaning; one card should test one atomic point; answer must be self-checkable; use Card DSL; do not auto-schedule FSRS.",
					strings.TrimSpace(request.Title),
					strings.TrimSpace(request.Content),
					strings.TrimSpace(request.RewriteType),
					strings.TrimSpace(request.Instruction),
				),
			},
		},
		Temperature: 0.45,
	}
	data, err := json.Marshal(payload)
	if err != nil {
		return nil, err
	}
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(s.config.AIBaseURL, "/")+"/chat/completions", bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.config.AIAPIKey)

	client := &http.Client{Timeout: 20 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("external ai returned status %d", resp.StatusCode)
	}

	var chatResp openAIChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return nil, err
	}
	if len(chatResp.Choices) == 0 {
		return nil, fmt.Errorf("external ai returned no choices")
	}
	content := strings.TrimSpace(chatResp.Choices[0].Message.Content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	content = strings.TrimSpace(content)

	var rewritten model.AIRewriteCardResponse
	if err := json.Unmarshal([]byte(content), &rewritten); err != nil {
		return nil, err
	}
	for i := range rewritten.Candidates {
		if strings.TrimSpace(rewritten.Candidates[i].Content) == "" {
			rewritten.Candidates[i].Content = composeCardContent(rewritten.Candidates[i].Title, "")
		}
	}
	return rewritten.Candidates, nil
}

func normalizeGeneratedCards(items []model.AIGeneratedCard) []model.AIGeneratedCard {
	normalized := make([]model.AIGeneratedCard, 0, len(items))
	for _, item := range items {
		item.Title = strings.TrimSpace(item.Title)
		item.Content = strings.TrimSpace(item.Content)
		item.Front = strings.TrimSpace(item.Front)
		item.Back = strings.TrimSpace(item.Back)
		if item.Content == "" {
			item.Content = composeCardContent(item.Front, item.Back)
		}
		if item.Title == "" {
			item.Title = firstNonEmpty(firstLine(item.Front), firstLine(item.Content))
		}
		if strings.TrimSpace(item.CardType) == "" {
			item.CardType = "basic"
		}
		normalized = append(normalized, item)
	}
	return normalized
}

func hasExternalAIConfig(cfg *config.Config) bool {
	if cfg == nil {
		return false
	}
	return strings.TrimSpace(cfg.AIBaseURL) != "" && strings.TrimSpace(cfg.AIAPIKey) != ""
}
