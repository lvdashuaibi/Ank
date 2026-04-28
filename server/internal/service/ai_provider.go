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
				Role: "system",
				Content: "You generate high-quality flashcards. Return JSON only in the format {\"items\":[{\"front\":\"...\",\"back\":\"...\",\"tags\":[\"...\"],\"note\":\"...\"}]} without markdown fences.",
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
	return generated.Items, nil
}

func buildAIPrompt(request model.AIGenerateRequest) string {
	cardCount := request.CardCount
	if cardCount <= 0 {
		cardCount = 3
	}
	return fmt.Sprintf(
		"Topic: %s\nContext: %s\nDifficulty: %s\nCardCount: %d\nLanguage: zh-CN\nPlease generate concise but useful flashcards for a spaced repetition app.",
		strings.TrimSpace(request.Topic),
		strings.TrimSpace(request.Context),
		strings.TrimSpace(request.Difficulty),
		cardCount,
	)
}

func hasExternalAIConfig(cfg *config.Config) bool {
	if cfg == nil {
		return false
	}
	return strings.TrimSpace(cfg.AIBaseURL) != "" && strings.TrimSpace(cfg.AIAPIKey) != ""
}
