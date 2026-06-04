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
	Tools       []openAIChatTool    `json:"tools,omitempty"`
	ToolChoice  string              `json:"tool_choice,omitempty"`
}

type openAIChatMessage struct {
	Role       string           `json:"role"`
	Content    string           `json:"content"`
	ToolCalls  []openAIToolCall `json:"tool_calls,omitempty"`
	ToolCallID string           `json:"tool_call_id,omitempty"`
}

type openAIToolCall struct {
	ID       string             `json:"id"`
	Type     string             `json:"type"`
	Function openAIToolFunction `json:"function"`
}

type openAIToolFunction struct {
	Name      string `json:"name"`
	Arguments string `json:"arguments"`
}

type openAIChatTool struct {
	Type     string             `json:"type"`
	Function openAIFunctionSpec `json:"function"`
}

type openAIFunctionSpec struct {
	Name        string         `json:"name"`
	Description string         `json:"description"`
	Parameters  map[string]any `json:"parameters"`
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
	runtime := newAIAgentRuntime(aiAgentRuntimeConfig{
		Model:       s.config.AIModel,
		MaxTurns:    4,
		Temperature: 0.7,
		ToolChoice:  "auto",
		Tools:       newAICardGenerationToolRegistry(),
		Chat:        s.createAIChatCompletion,
		Evaluator:   aiCardGenerationEvaluator{},
	})
	result, err := runtime.Run(aiAgentRunInput{
		SystemPrompt: "You are a flashcard generation agent. Prefer calling the provided card creation tools for every card, then return JSON only in the format {\"items\":[...cards...]} without markdown fences. All choice cards must use the app's implemented Card DSL.",
		UserPrompt:   prompt,
		Context: aiAgentToolContext{
			GenerateRequest: request,
		},
	})
	if err != nil {
		return nil, err
	}
	return normalizeGeneratedCards(result.Cards), nil
}

func (s *AppService) createAIChatCompletion(payload openAIChatRequest) (openAIChatResponse, error) {
	data, err := json.Marshal(payload)
	if err != nil {
		return openAIChatResponse{}, err
	}
	req, err := http.NewRequest(http.MethodPost, strings.TrimRight(s.config.AIBaseURL, "/")+"/chat/completions", bytes.NewReader(data))
	if err != nil {
		return openAIChatResponse{}, err
	}
	req.Header.Set("Content-Type", "application/json")
	req.Header.Set("Authorization", "Bearer "+s.config.AIAPIKey)

	client := &http.Client{Timeout: 90 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return openAIChatResponse{}, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return openAIChatResponse{}, fmt.Errorf("external ai returned status %d", resp.StatusCode)
	}

	var chatResp openAIChatResponse
	if err := json.NewDecoder(resp.Body).Decode(&chatResp); err != nil {
		return openAIChatResponse{}, err
	}
	return chatResp, nil
}

func buildAIPrompt(request model.AIGenerateRequest) string {
	policy := effectiveGenerationPolicy(request)
	facts := extractAtomicFacts(request.Context, request.Topic)
	cardCountLine := fmt.Sprintf("CardCount: %d", effectiveAICardCount(request, facts, policy))
	if request.CardCount <= 0 {
		cardCountLine = fmt.Sprintf("CardCount: auto\nTargetCardRange: 3-%d\nInstruction: Choose the appropriate number of atomic cards based on source granularity; do not pad with duplicates.", effectiveAICardCount(request, facts, policy))
	}
	cardTypes := strings.Join(policy.PreferredCardTypes, ", ")
	if strings.TrimSpace(cardTypes) == "" {
		cardTypes = "basic, single_choice, multi_choice, cloze"
	}
	strategy := strings.TrimSpace(request.Strategy)
	if strategy == "" {
		strategy = "fsrs_friendly"
	}
	return fmt.Sprintf(
		"Topic: %s\nSourceName: %s\nSource Document:\n%s\nDifficulty: %s\n%s\nAllowedCardTypes: %s\nStrategy: %s\nLanguage: zh-CN\n%s\n%s\n%s",
		strings.TrimSpace(request.Topic),
		strings.TrimSpace(request.SourceName),
		strings.TrimSpace(request.Context),
		strings.TrimSpace(request.Difficulty),
		cardCountLine,
		cardTypes,
		strategy,
		sourceGroundingPromptRules(),
		policyPromptRules(policy),
		cardDSLPromptRules(),
	)
}

func sourceGroundingPromptRules() string {
	return strings.Join([]string{
		"SourceGroundingRules:",
		"- Only create cards from the Source Document above. Do not use outside knowledge, examples, prior chat context, Anki documentation, or generic app manuals.",
		"- If SourceName or Topic mentions an exam/domain such as 408, every card must test that domain, not unrelated software behavior such as Anki default decks.",
		"- Every tool call must include source_excerpt copied or tightly paraphrased from the Source Document.",
		"- If the Source Document is empty or unrelated, return zero items with a warning instead of inventing cards.",
		"- Prefer terms that literally appear in the Source Document. 题干、答案和选项必须能从原文找到依据。",
	}, "\n")
}

func cardDSLPromptRules() string {
	return strings.Join([]string{
		"CardDSLRules:",
		"- basic/cloze cards may use normal prompt plus @answer ... @end.",
		"- single_choice must use exactly this implemented DSL block: {single-choice}\\nQ: 题干\\n* 正确选项\\n- 干扰项\\n- 干扰项\\n{/single-choice}.",
		"- multi_choice must use exactly this implemented DSL block: {multi-choice}\\nQ: 题干\\n* 正确选项\\n* 正确选项\\n- 干扰项\\n{/multi-choice}.",
		"- Do not write choice cards as ordinary A/B/C/D text. 不要把选择题写成 A/B/C/D 普通文本.",
		"- Put explanation or source note in @answer ... @end, not as the selectable option list.",
	}, "\n")
}

func stripJSONFence(content string) string {
	content = strings.TrimSpace(content)
	content = strings.TrimPrefix(content, "```json")
	content = strings.TrimPrefix(content, "```")
	content = strings.TrimSuffix(content, "```")
	return strings.TrimSpace(content)
}

func newAICardGenerationToolRegistry() *aiAgentToolRegistry {
	registry := newAIAgentToolRegistry()
	for _, tool := range []aiAgentTool{
		newAICardGenerationTool(
			"create_basic_card",
			"Create one atomic basic flashcard with a short self-checkable answer.",
			[]string{"title", "question", "answer"},
		),
		newAICardGenerationTool(
			"create_cloze_card",
			"Create one cloze flashcard. The question should contain {{...}} blanks around short key terms.",
			[]string{"title", "question", "answer"},
		),
		newAICardGenerationTool(
			"create_single_choice_card",
			"Create one single-choice flashcard. The service will convert arguments into implemented Card DSL.",
			[]string{"title", "question", "correct_answer", "distractors"},
		),
		newAICardGenerationTool(
			"create_multi_choice_card",
			"Create one multi-choice flashcard. The service will convert arguments into implemented Card DSL.",
			[]string{"title", "question", "correct_options", "distractors"},
		),
	} {
		_ = registry.Register(tool)
	}
	return registry
}

func newAICardGenerationTool(name, description string, required []string) aiAgentTool {
	return aiAgentTool{
		Name: name,
		Spec: aiCardGenerationTool(
			name,
			description,
			required,
		),
		Execute: func(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
			return executeAICardGenerationTool(name, ctx, arguments)
		},
	}
}

func aiCardGenerationTool(name, description string, required []string) openAIChatTool {
	properties := map[string]any{
		"title": map[string]any{
			"type":        "string",
			"description": "Short user-facing card title.",
		},
		"question": map[string]any{
			"type":        "string",
			"description": "The card prompt. It must test one atomic knowledge point.",
		},
		"answer": map[string]any{
			"type":        "string",
			"description": "Short answer, explanation, or self-check rubric.",
		},
		"correct_answer": map[string]any{
			"type":        "string",
			"description": "The only correct option for single-choice cards.",
		},
		"correct_options": map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "string",
			},
			"description": "All correct options for multi-choice cards.",
		},
		"distractors": map[string]any{
			"type": "array",
			"items": map[string]any{
				"type": "string",
			},
			"description": "Plausible but incorrect options.",
		},
		"knowledge_point": map[string]any{"type": "string"},
		"source_excerpt":  map[string]any{"type": "string"},
		"source_location": map[string]any{"type": "string"},
		"tags": map[string]any{
			"type":  "array",
			"items": map[string]any{"type": "string"},
		},
		"note": map[string]any{"type": "string"},
	}
	return openAIChatTool{
		Type: "function",
		Function: openAIFunctionSpec{
			Name:        name,
			Description: description,
			Parameters: map[string]any{
				"type":                 "object",
				"properties":           properties,
				"required":             required,
				"additionalProperties": false,
			},
		},
	}
}

type aiCardToolArgs struct {
	Title          string   `json:"title"`
	Question       string   `json:"question"`
	Answer         string   `json:"answer"`
	CorrectAnswer  string   `json:"correct_answer"`
	CorrectOptions []string `json:"correct_options"`
	Distractors    []string `json:"distractors"`
	KnowledgePoint string   `json:"knowledge_point"`
	SourceExcerpt  string   `json:"source_excerpt"`
	SourceLocation string   `json:"source_location"`
	Tags           []string `json:"tags"`
	Note           string   `json:"note"`
}

func executeAICardGenerationTool(toolName string, ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
	var args aiCardToolArgs
	if err := json.Unmarshal(arguments, &args); err != nil {
		return aiAgentToolResult{}, err
	}
	if err := validateSourceGrounding(ctx.GenerateRequest, args); err != nil {
		return aiAgentToolResult{}, err
	}

	cardType := "basic"
	content := ""
	answer := strings.TrimSpace(args.Answer)
	question := strings.TrimSpace(args.Question)
	switch toolName {
	case "create_basic_card":
		cardType = "basic"
		content = composeCardContent(question, answer)
	case "create_cloze_card":
		cardType = "cloze"
		content = composeCardContent(question, answer)
	case "create_single_choice_card":
		cardType = "single_choice"
		correct := firstNonEmpty(args.CorrectAnswer, firstString(args.CorrectOptions), answer)
		content = composeSingleChoiceCardContent(question, correct, args.Distractors, firstNonEmpty(answer, correct))
	case "create_multi_choice_card":
		cardType = "multi_choice"
		correct := compactStrings(args.CorrectOptions)
		if len(correct) == 0 && strings.TrimSpace(args.CorrectAnswer) != "" {
			correct = []string{strings.TrimSpace(args.CorrectAnswer)}
		}
		content = composeMultiChoiceCardContent(question, correct, args.Distractors, firstNonEmpty(answer, strings.Join(correct, "；")))
	default:
		return aiAgentToolResult{}, fmt.Errorf("unknown card generation tool: %s", toolName)
	}
	card := completeAIGeneratedToolCard(model.AIGeneratedCard{
		Title:          strings.TrimSpace(args.Title),
		Content:        content,
		CardType:       cardType,
		KnowledgePoint: strings.TrimSpace(args.KnowledgePoint),
		SourceExcerpt:  strings.TrimSpace(args.SourceExcerpt),
		SourceLocation: strings.TrimSpace(args.SourceLocation),
		Tags:           compactStrings(args.Tags),
		Note:           strings.TrimSpace(args.Note),
	}, ctx.GenerateRequest)
	return aiAgentToolResult{
		Content: toolResultJSON(map[string]any{"ok": true, "card": card}),
		Cards:   []model.AIGeneratedCard{card},
	}, nil
}

func validateSourceGrounding(request model.AIGenerateRequest, args aiCardToolArgs) error {
	context := strings.TrimSpace(request.Context)
	if context == "" {
		return nil
	}
	excerpt := strings.TrimSpace(args.SourceExcerpt)
	if excerpt == "" {
		return fmt.Errorf("source_excerpt is required when Source Document is provided")
	}
	if sourceTextCovers(context, excerpt) {
		return nil
	}
	evidence := strings.Join([]string{
		args.Title,
		args.Question,
		args.Answer,
		args.CorrectAnswer,
		strings.Join(args.CorrectOptions, " "),
		strings.Join(args.Distractors, " "),
		args.KnowledgePoint,
	}, " ")
	if sourceTextCovers(context, evidence) {
		return nil
	}
	return fmt.Errorf("source_excerpt is not grounded in Source Document")
}

func sourceTextCovers(source, candidate string) bool {
	sourceTokens := significantTokens(source)
	candidateTokens := significantTokens(candidate)
	if len(candidateTokens) == 0 {
		return false
	}
	matched := 0
	for token := range candidateTokens {
		if _, ok := sourceTokens[token]; ok {
			matched++
		}
	}
	if matched >= 2 {
		return true
	}
	if len(candidateTokens) <= 2 && matched == len(candidateTokens) {
		return true
	}
	return false
}

func significantTokens(value string) map[string]struct{} {
	tokens := map[string]struct{}{}
	var builder strings.Builder
	flush := func() {
		token := strings.ToLower(strings.TrimSpace(builder.String()))
		builder.Reset()
		if len([]rune(token)) >= 2 && !isStopToken(token) {
			tokens[token] = struct{}{}
		}
	}
	for _, r := range value {
		if (r >= 'a' && r <= 'z') || (r >= 'A' && r <= 'Z') || (r >= '0' && r <= '9') || (r >= '\u4e00' && r <= '\u9fff') {
			builder.WriteRune(r)
			continue
		}
		flush()
	}
	flush()
	return tokens
}

func isStopToken(token string) bool {
	switch token {
	case "什么", "为什么", "以下", "哪种", "哪个", "一个", "进行", "可以", "包括", "的是", "the", "and", "for", "with":
		return true
	default:
		return false
	}
}

func completeAIGeneratedToolCard(card model.AIGeneratedCard, request model.AIGenerateRequest) model.AIGeneratedCard {
	prompt, answer := splitCardContent(card.Content)
	if card.Title == "" {
		card.Title = firstNonEmpty(firstLine(prompt), strings.TrimSpace(request.Topic))
	}
	card.Front = prompt
	card.Back = answer
	if card.KnowledgePoint == "" {
		card.KnowledgePoint = strings.TrimSpace(request.Topic)
	}
	if card.SourceLocation == "" {
		card.SourceLocation = strings.TrimSpace(request.SourceName)
	}
	if card.SourceExcerpt == "" {
		card.SourceExcerpt = previewText(request.Context, 160)
	}
	if card.Difficulty == "" {
		card.Difficulty = strings.TrimSpace(request.Difficulty)
	}
	if len(card.Tags) == 0 {
		card.Tags = compactStrings([]string{"AI生成", request.Topic, request.Difficulty})
	}
	return card
}

func toolResultJSON(value map[string]any) string {
	data, err := json.Marshal(value)
	if err != nil {
		return `{"ok":false,"error":"tool result marshal failed"}`
	}
	return string(data)
}

func firstString(values []string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return strings.TrimSpace(value)
		}
	}
	return ""
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

	client := &http.Client{Timeout: 90 * time.Second}
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
		rewritten.Candidates[i] = normalizeRewriteCandidate(rewritten.Candidates[i])
	}
	return rewritten.Candidates, nil
}

func normalizeRewriteCandidate(candidate model.AIRewriteCandidate) model.AIRewriteCandidate {
	candidate.Title = strings.TrimSpace(candidate.Title)
	candidate.Content = strings.TrimSpace(candidate.Content)
	if candidate.Content == "" {
		candidate.Content = composeCardContent(candidate.Title, "")
		return candidate
	}

	prompt, answer := splitCardContent(candidate.Content)
	if !strings.Contains(candidate.Content, "@question") && strings.TrimSpace(prompt) != "" {
		candidate.Content = composeCardContent(prompt, answer)
		if candidate.Title == "" {
			candidate.Title = firstLine(prompt)
		}
		return candidate
	}

	if question, questionAnswer, ok := splitQuestionDslContent(candidate.Content); ok {
		candidate.Content = composeCardContent(question, questionAnswer)
		if candidate.Title == "" {
			candidate.Title = firstLine(question)
		}
		return candidate
	}

	candidate.Content = composeCardContent(firstNonEmpty(prompt, candidate.Title), answer)
	return candidate
}

func splitQuestionDslContent(content string) (string, string, bool) {
	lines := strings.Split(content, "\n")
	questionLines := make([]string, 0)
	answerLines := make([]string, 0)
	inQuestion := false
	sawQuestion := false
	questionClosed := false
	for _, line := range lines {
		trimmed := strings.TrimSpace(line)
		if !inQuestion && trimmed == "@question" {
			inQuestion = true
			sawQuestion = true
			continue
		}
		if inQuestion && trimmed == "@end" {
			inQuestion = false
			questionClosed = true
			continue
		}
		if inQuestion {
			questionLines = append(questionLines, line)
			continue
		}
		if questionClosed {
			if trimmed == "@answer" || trimmed == "@end" {
				continue
			}
			answerLines = append(answerLines, line)
		}
	}
	question := strings.TrimSpace(strings.Join(questionLines, "\n"))
	answer := strings.TrimSpace(strings.Join(answerLines, "\n"))
	return question, answer, sawQuestion && question != ""
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
