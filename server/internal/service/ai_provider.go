package service

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"strconv"
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
		Tools:       newAICardGenerationToolRegistry(request),
		Chat:        s.createAIChatCompletion,
		Evaluator:   aiCardGenerationEvaluator{},
	})
	result, err := runtime.Run(aiAgentRunInput{
		SystemPrompt: "You are an autonomous flashcard generation agent. You lead the reasoning: choose useful tools only when they help, choose card types yourself, and create high-quality cards for the user's learning goal. Tools are capabilities, not a fixed pipeline. Product guardrails: respect web-search permission, keep source traceability, and use the provided card tools so final cards fit the app DSL. Return JSON only in the format {\"items\":[...cards...]} without markdown fences.",
		UserPrompt:   prompt,
		Context: aiAgentToolContext{
			GenerateRequest: request,
			Service:         s,
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
		cardCountLine = fmt.Sprintf("CardCount: auto\nTargetCardRange: 3-%d\nInstruction: You choose the appropriate number of atomic cards based on the material and goal; do not pad with duplicates.", effectiveAICardCount(request, facts, policy))
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
		"Topic: %s\nSourceName: %s\nLearningGoal: %s\nSource Document:\n%s\nDifficulty: %s\n%s\nAllowedCardTypes: %s\nStrategy: %s\nAllowedWebSearch: %t\nExamMode: %t\nStrictSource: %t\nLanguage: zh-CN\n%s\n%s\n%s\n%s",
		strings.TrimSpace(request.Topic),
		strings.TrimSpace(request.SourceName),
		strings.TrimSpace(request.LearningGoal),
		strings.TrimSpace(request.Context),
		strings.TrimSpace(request.Difficulty),
		cardCountLine,
		cardTypes,
		strategy,
		request.AllowWebSearch,
		request.ExamMode,
		effectiveStrictSource(request),
		agentAutonomyPromptRules(),
		sourceGroundingPromptRules(),
		policyPromptRules(policy),
		cardDSLPromptRules(),
	)
}

func agentAutonomyPromptRules() string {
	return strings.Join([]string{
		"ModelAutonomy:",
		"- You choose the best card type yourself for each knowledge point. Do not follow rigid mappings such as definitions always being basic cards or formulas always being cloze cards.",
		"- Tools are optional capabilities. Decide whether to retrieve source chunks, search the web, critique drafts, or directly create cards.",
		"- If ExamMode is true, think like an exam coach: include common traps, misconceptions, confusing pairs, and scenario-transfer questions when useful.",
		"- If web search is allowed, use search_web to discover useful sources and read_web_page to inspect selected pages when deeper evidence is needed; mark web-enhanced cards with source_location or notes.",
		"- If web search is not allowed, do not ask for or invent web evidence.",
	}, "\n")
}

func sourceGroundingPromptRules() string {
	return strings.Join([]string{
		"SourceGroundingRules:",
		"- When StrictSource is true: Only create cards from the Source Document above. Do not use outside knowledge, examples, prior chat context, Anki documentation, or generic app manuals.",
		"- When StrictSource is false and web search is allowed, you may add clearly source-labeled web-enhanced misconceptions or exam context.",
		"- If SourceName or Topic mentions an exam/domain such as 408, every card must test that domain, not unrelated software behavior such as Anki default decks.",
		"- Every card creation tool call must include source_excerpt copied or tightly paraphrased from the Source Document or labeled web evidence.",
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

func newAICardGenerationToolRegistry(request model.AIGenerateRequest) *aiAgentToolRegistry {
	registry := newAIAgentToolRegistry()
	_ = registry.Register(newAISourceRetrievalTool())
	if request.AllowWebSearch {
		_ = registry.Register(newAIWebSearchTool())
		_ = registry.Register(newAIWebPageReaderTool())
	}
	_ = registry.Register(newAICritiqueCardsTool())
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

func newAISourceRetrievalTool() aiAgentTool {
	return aiAgentTool{
		Name: "retrieve_source_chunks",
		Spec: openAIChatTool{
			Type: "function",
			Function: openAIFunctionSpec{
				Name:        "retrieve_source_chunks",
				Description: "Retrieve relevant chunks from the user's Source Document. Use this when you want more grounded evidence before deciding card content.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"query":      map[string]any{"type": "string", "description": "What to look for in the Source Document."},
						"max_chunks": map[string]any{"type": "integer", "description": "Maximum chunks to return."},
					},
					"required":             []string{"query"},
					"additionalProperties": false,
				},
			},
		},
		Execute: executeAISourceRetrievalTool,
	}
}

func newAIWebSearchTool() aiAgentTool {
	return aiAgentTool{
		Name: "search_web",
		Spec: openAIChatTool{
			Type: "function",
			Function: openAIFunctionSpec{
				Name:        "search_web",
				Description: "Search the web through Brave Search for exam context, common traps, misconceptions, or missing background. Only available when the user allows web search.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"query":       map[string]any{"type": "string", "description": "Search query."},
						"intent":      map[string]any{"type": "string", "description": "Why this search helps card generation."},
						"max_results": map[string]any{"type": "integer", "description": "Maximum results to return. Defaults to 8 and is capped at 20."},
						"country":     map[string]any{"type": "string", "description": "Brave country code. Defaults to CN."},
						"search_lang": map[string]any{"type": "string", "description": "Brave search language. Defaults to zh."},
						"freshness":   map[string]any{"type": "string", "description": "Optional freshness filter: pd, pw, pm, or py."},
					},
					"required":             []string{"query"},
					"additionalProperties": false,
				},
			},
		},
		Execute: executeAIWebSearchTool,
	}
}

func newAIWebPageReaderTool() aiAgentTool {
	return aiAgentTool{
		Name: "read_web_page",
		Spec: openAIChatTool{
			Type: "function",
			Function: openAIFunctionSpec{
				Name:        "read_web_page",
				Description: "Read a web page selected from search results through Jina Reader and return Markdown/text content for deeper evidence.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"url":       map[string]any{"type": "string", "description": "Absolute http(s) URL to read."},
						"max_chars": map[string]any{"type": "integer", "description": "Maximum characters to return."},
					},
					"required":             []string{"url"},
					"additionalProperties": false,
				},
			},
		},
		Execute: executeAIWebPageReaderTool,
	}
}

func newAICritiqueCardsTool() aiAgentTool {
	return aiAgentTool{
		Name: "critique_cards",
		Spec: openAIChatTool{
			Type: "function",
			Function: openAIFunctionSpec{
				Name:        "critique_cards",
				Description: "Critique planned or generated cards for learning value, DSL fit, exam usefulness, ambiguity, duplicates, and missing misconceptions.",
				Parameters: map[string]any{
					"type": "object",
					"properties": map[string]any{
						"goal":  map[string]any{"type": "string", "description": "What quality dimension to critique."},
						"cards": map[string]any{"type": "array", "items": map[string]any{"type": "object"}},
					},
					"required":             []string{"goal"},
					"additionalProperties": false,
				},
			},
		},
		Execute: executeAICritiqueCardsTool,
	}
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

type aiSourceRetrievalArgs struct {
	Query     string `json:"query"`
	MaxChunks int    `json:"max_chunks"`
}

type aiWebSearchArgs struct {
	Query      string `json:"query"`
	Intent     string `json:"intent"`
	MaxResults int    `json:"max_results"`
	Count      int    `json:"count"`
	Country    string `json:"country"`
	SearchLang string `json:"search_lang"`
	Freshness  string `json:"freshness"`
}

type aiWebPageReadArgs struct {
	URL      string `json:"url"`
	MaxChars int    `json:"max_chars"`
}

type aiCritiqueCardsArgs struct {
	Goal  string                   `json:"goal"`
	Cards []map[string]interface{} `json:"cards"`
}

func executeAISourceRetrievalTool(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
	var args aiSourceRetrievalArgs
	if err := json.Unmarshal(arguments, &args); err != nil {
		return aiAgentToolResult{}, err
	}
	chunks := retrieveSourceChunks(ctx.GenerateRequest.Context, args.Query, args.MaxChunks)
	return aiAgentToolResult{
		Content: toolResultJSON(map[string]any{
			"ok":     true,
			"chunks": chunks,
		}),
	}, nil
}

func executeAIWebSearchTool(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
	if !ctx.GenerateRequest.AllowWebSearch {
		return aiAgentToolResult{}, fmt.Errorf("web search is not allowed for this request")
	}
	var args aiWebSearchArgs
	if err := json.Unmarshal(arguments, &args); err != nil {
		return aiAgentToolResult{}, err
	}
	if ctx.Service == nil {
		return aiAgentToolResult{}, fmt.Errorf("web search service is unavailable")
	}
	content, err := ctx.Service.performCachedBraveSearch(context.Background(), args)
	if err != nil {
		return aiAgentToolResult{}, err
	}
	return aiAgentToolResult{Content: content}, nil
}

func executeAIWebPageReaderTool(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
	if !ctx.GenerateRequest.AllowWebSearch {
		return aiAgentToolResult{}, fmt.Errorf("web page reading is not allowed for this request")
	}
	var args aiWebPageReadArgs
	if err := json.Unmarshal(arguments, &args); err != nil {
		return aiAgentToolResult{}, err
	}
	if ctx.Service == nil {
		return aiAgentToolResult{}, fmt.Errorf("web page reader service is unavailable")
	}
	content, err := ctx.Service.performCachedJinaRead(context.Background(), args)
	if err != nil {
		return aiAgentToolResult{}, err
	}
	return aiAgentToolResult{Content: content}, nil
}

func executeAICritiqueCardsTool(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
	var args aiCritiqueCardsArgs
	if err := json.Unmarshal(arguments, &args); err != nil {
		return aiAgentToolResult{}, err
	}
	notes := []string{
		"Prefer the most effective card type for each knowledge point; do not force all cards into one type.",
		"Choice cards should contain plausible distractors and a concise explanation in @answer.",
		"Cards should test one atomic idea and remain self-checkable.",
	}
	if ctx.GenerateRequest.ExamMode {
		notes = append(notes, "Exam mode is enabled: add traps, confusing pairs, and scenario transfer when they improve learning.")
	}
	if effectiveStrictSource(ctx.GenerateRequest) {
		notes = append(notes, "Strict source is enabled: every generated card must be grounded in the Source Document.")
	}
	return aiAgentToolResult{
		Content: toolResultJSON(map[string]any{
			"ok":    true,
			"goal":  strings.TrimSpace(args.Goal),
			"notes": notes,
		}),
	}, nil
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
	if !effectiveStrictSource(request) && request.AllowWebSearch {
		if sourceTextCovers(context, excerpt) || strings.TrimSpace(args.SourceLocation) != "" {
			return nil
		}
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

func effectiveStrictSource(request model.AIGenerateRequest) bool {
	if request.AllowWebSearch && !request.StrictSource {
		return false
	}
	if request.StrictSource {
		return true
	}
	return strings.TrimSpace(request.Context) != ""
}

func retrieveSourceChunks(source, query string, maxChunks int) []map[string]any {
	if maxChunks <= 0 || maxChunks > 8 {
		maxChunks = 4
	}
	facts := extractAtomicFacts(source, query)
	if len(facts) == 0 && strings.TrimSpace(source) != "" {
		facts = splitSourceIntoChunks(source)
	}
	queryTokens := significantTokens(query)
	type scoredChunk struct {
		text  string
		score int
		index int
	}
	scored := make([]scoredChunk, 0, len(facts))
	for index, fact := range facts {
		score := 0
		factTokens := significantTokens(fact)
		for token := range queryTokens {
			if _, ok := factTokens[token]; ok {
				score++
			}
		}
		scored = append(scored, scoredChunk{text: fact, score: score, index: index})
	}
	for i := 0; i < len(scored); i++ {
		for j := i + 1; j < len(scored); j++ {
			if scored[j].score > scored[i].score || (scored[j].score == scored[i].score && scored[j].index < scored[i].index) {
				scored[i], scored[j] = scored[j], scored[i]
			}
		}
	}
	out := make([]map[string]any, 0, maxChunks)
	for _, chunk := range scored {
		if strings.TrimSpace(chunk.text) == "" {
			continue
		}
		out = append(out, map[string]any{
			"text":  previewText(chunk.text, 500),
			"score": chunk.score,
			"index": chunk.index,
		})
		if len(out) >= maxChunks {
			break
		}
	}
	return out
}

func splitSourceIntoChunks(source string) []string {
	lines := strings.Split(source, "\n")
	chunks := make([]string, 0)
	var current strings.Builder
	for _, line := range lines {
		line = strings.TrimSpace(line)
		if line == "" {
			if strings.TrimSpace(current.String()) != "" {
				chunks = append(chunks, strings.TrimSpace(current.String()))
				current.Reset()
			}
			continue
		}
		if current.Len() > 0 {
			current.WriteString(" ")
		}
		current.WriteString(line)
		if len([]rune(current.String())) >= 360 {
			chunks = append(chunks, strings.TrimSpace(current.String()))
			current.Reset()
		}
	}
	if strings.TrimSpace(current.String()) != "" {
		chunks = append(chunks, strings.TrimSpace(current.String()))
	}
	return chunks
}

const (
	aiWebSearchCacheTTL = 6 * time.Hour
	aiWebReadCacheTTL   = 24 * time.Hour
)

func (s *AppService) performCachedBraveSearch(ctx context.Context, args aiWebSearchArgs) (string, error) {
	query := strings.TrimSpace(args.Query)
	if query == "" {
		return "", fmt.Errorf("search query is required")
	}
	count := normalizeBraveResultCount(args)
	country := firstNonEmpty(strings.TrimSpace(args.Country), strings.TrimSpace(s.config.BraveCountry), "CN")
	searchLang := firstNonEmpty(strings.TrimSpace(args.SearchLang), strings.TrimSpace(s.config.BraveSearchLang), "zh")
	freshness := normalizeBraveFreshness(args.Freshness)
	cacheKey := aiCacheKey("brave-search-v2", query, strconv.Itoa(count), country, searchLang, freshness)
	if s.cache != nil {
		if cached, ok := s.cache.Get(ctx, cacheKey); ok {
			return cached, nil
		}
	}

	searchResult, err := s.performBraveSearchWithFallbacks(ctx, query, count, country, searchLang, freshness)
	if err != nil {
		return "", err
	}
	content := toolResultJSON(map[string]any{
		"ok":            true,
		"intent":        strings.TrimSpace(args.Intent),
		"provider":      "brave",
		"query":         query,
		"country":       country,
		"search_lang":   searchLang,
		"freshness":     freshness,
		"fallback_used": searchResult.FallbackUsed,
		"attempts":      searchResult.Attempts,
		"next_tool":     "read_web_page",
		"next_hint":     "Call read_web_page with a result URL when source details are important.",
		"results":       searchResult.Results,
		"cached_until":  time.Now().Add(aiWebSearchCacheTTL).Format(time.RFC3339),
	})
	if s.cache != nil {
		s.cache.Set(ctx, cacheKey, content, aiWebSearchCacheTTL)
	}
	return content, nil
}

type aiBraveSearchAttempt struct {
	Query      string `json:"query"`
	Country    string `json:"country"`
	SearchLang string `json:"search_lang"`
	Results    int    `json:"results"`
}

type aiBraveSearchResult struct {
	Results      []map[string]string    `json:"results"`
	Attempts     []aiBraveSearchAttempt `json:"attempts"`
	FallbackUsed bool                   `json:"fallback_used"`
}

func (s *AppService) performBraveSearchWithFallbacks(ctx context.Context, query string, count int, country string, searchLang string, freshness string) (aiBraveSearchResult, error) {
	plans := buildBraveSearchFallbackPlans(query, country, searchLang)
	merged := make([]map[string]string, 0, count)
	seen := map[string]struct{}{}
	attempts := make([]aiBraveSearchAttempt, 0, len(plans))
	for index, plan := range plans {
		remaining := count - len(merged)
		if remaining <= 0 {
			break
		}
		results, err := s.performBraveSearch(ctx, plan.Query, count, plan.Country, plan.SearchLang, freshness)
		if err != nil {
			if index == 0 {
				return aiBraveSearchResult{}, err
			}
			continue
		}
		attempts = append(attempts, aiBraveSearchAttempt{
			Query:      plan.Query,
			Country:    plan.Country,
			SearchLang: plan.SearchLang,
			Results:    len(results),
		})
		for _, item := range results {
			key := firstNonEmpty(strings.TrimSpace(item["url"]), strings.TrimSpace(item["title"])+"|"+strings.TrimSpace(item["snippet"]))
			if key == "" {
				continue
			}
			if _, ok := seen[key]; ok {
				continue
			}
			seen[key] = struct{}{}
			merged = append(merged, item)
			if len(merged) >= count {
				break
			}
		}
		if len(merged) > 0 {
			break
		}
	}
	if len(merged) == 0 {
		merged = append(merged, map[string]string{
			"title":   query,
			"url":     "",
			"snippet": "No Brave web result was returned after localized and expanded fallback searches. Use the source document first or try a more explicit query.",
		})
	}
	return aiBraveSearchResult{
		Results:      merged,
		Attempts:     attempts,
		FallbackUsed: len(attempts) > 1,
	}, nil
}

type aiBraveSearchPlan struct {
	Query      string
	Country    string
	SearchLang string
}

func buildBraveSearchFallbackPlans(query string, country string, searchLang string) []aiBraveSearchPlan {
	plans := []aiBraveSearchPlan{{Query: query, Country: country, SearchLang: searchLang}}
	add := func(candidate aiBraveSearchPlan) {
		candidate.Query = strings.TrimSpace(candidate.Query)
		candidate.Country = firstNonEmpty(strings.TrimSpace(candidate.Country), "CN")
		candidate.SearchLang = firstNonEmpty(strings.TrimSpace(candidate.SearchLang), "zh")
		if candidate.Query == "" {
			return
		}
		for _, existing := range plans {
			if existing.Query == candidate.Query && existing.Country == candidate.Country && existing.SearchLang == candidate.SearchLang {
				return
			}
		}
		plans = append(plans, candidate)
	}
	add(aiBraveSearchPlan{Query: query, Country: "US", SearchLang: "en"})
	for _, expanded := range expandBraveSearchQuery(query) {
		add(aiBraveSearchPlan{Query: expanded, Country: "US", SearchLang: "en"})
		add(aiBraveSearchPlan{Query: expanded, Country: "CN", SearchLang: "zh"})
	}
	return plans
}

func expandBraveSearchQuery(query string) []string {
	lower := strings.ToLower(query)
	expanded := make([]string, 0, 3)
	if strings.Contains(lower, "amat") || (strings.Contains(lower, "cache") && strings.Contains(query, "访存")) {
		expanded = append(expanded,
			"average memory access time AMAT cache miss penalty",
			"408 平均访存时间 cache 缺失率 缺失代价",
		)
	}
	if strings.Contains(lower, "cache") && strings.Contains(query, "408") {
		expanded = append(expanded, "408 computer organization cache common mistakes")
	}
	return compactStrings(expanded)
}

func (s *AppService) performBraveSearch(ctx context.Context, query string, count int, country string, searchLang string, freshness string) ([]map[string]string, error) {
	if s.config == nil || strings.TrimSpace(s.config.BraveAPIKey) == "" {
		return nil, fmt.Errorf("Brave Search API key is not configured")
	}
	endpoint := firstNonEmpty(strings.TrimSpace(s.config.BraveSearchURL), "https://api.search.brave.com/res/v1/web/search")
	parsed, err := url.Parse(endpoint)
	if err != nil {
		return nil, err
	}
	values := parsed.Query()
	values.Set("q", query)
	values.Set("count", strconv.Itoa(count))
	values.Set("country", country)
	values.Set("search_lang", searchLang)
	values.Set("result_filter", "web")
	if freshness != "" {
		values.Set("freshness", freshness)
	}
	parsed.RawQuery = values.Encode()

	req, err := http.NewRequestWithContext(ctx, http.MethodGet, parsed.String(), nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("X-Subscription-Token", s.config.BraveAPIKey)
	req.Header.Set("Accept", "application/json")

	client := s.aiWebHTTPClient(12 * time.Second)
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return nil, fmt.Errorf("Brave Search returned status %d", resp.StatusCode)
	}
	var body struct {
		Web struct {
			Results []struct {
				Title         string   `json:"title"`
				URL           string   `json:"url"`
				Description   string   `json:"description"`
				ExtraSnippets []string `json:"extra_snippets"`
			} `json:"results"`
		} `json:"web"`
	}
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		return nil, err
	}
	results := make([]map[string]string, 0, count)
	for _, item := range body.Web.Results {
		snippet := strings.TrimSpace(item.Description)
		if snippet == "" && len(item.ExtraSnippets) > 0 {
			snippet = strings.Join(compactStrings(item.ExtraSnippets), " ")
		}
		results = append(results, map[string]string{
			"title":   firstNonEmpty(strings.TrimSpace(item.Title), previewText(snippet, 40), query),
			"url":     strings.TrimSpace(item.URL),
			"snippet": previewText(snippet, 220),
		})
		if len(results) >= count {
			break
		}
	}
	return results, nil
}

func (s *AppService) performCachedJinaRead(ctx context.Context, args aiWebPageReadArgs) (string, error) {
	targetURL := strings.TrimSpace(args.URL)
	if targetURL == "" {
		return "", fmt.Errorf("url is required")
	}
	maxChars := args.MaxChars
	if maxChars <= 0 {
		maxChars = 12000
	}
	if maxChars < 1000 {
		maxChars = 1000
	}
	if maxChars > 30000 {
		maxChars = 30000
	}
	cacheKey := aiCacheKey("jina-read", targetURL, strconv.Itoa(maxChars))
	if s.cache != nil {
		if cached, ok := s.cache.Get(ctx, cacheKey); ok {
			return cached, nil
		}
	}

	content, err := s.performJinaRead(ctx, targetURL, maxChars)
	if err != nil {
		return "", err
	}
	result := toolResultJSON(map[string]any{
		"ok":           true,
		"provider":     "jina",
		"url":          targetURL,
		"content":      content,
		"cached_until": time.Now().Add(aiWebReadCacheTTL).Format(time.RFC3339),
	})
	if s.cache != nil {
		s.cache.Set(ctx, cacheKey, result, aiWebReadCacheTTL)
	}
	return result, nil
}

func (s *AppService) performJinaRead(ctx context.Context, targetURL string, maxChars int) (string, error) {
	if _, err := validateReadableWebURL(targetURL); err != nil {
		return "", err
	}
	baseURL := "https://r.jina.ai"
	if s.config != nil {
		baseURL = firstNonEmpty(strings.TrimSpace(s.config.JinaReaderURL), baseURL)
	}
	endpoint := strings.TrimRight(baseURL, "/") + "/" + targetURL
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return "", err
	}
	if s.config != nil && strings.TrimSpace(s.config.JinaAPIKey) != "" {
		req.Header.Set("Authorization", "Bearer "+s.config.JinaAPIKey)
	}
	client := s.aiWebHTTPClient(20 * time.Second)
	resp, err := client.Do(req)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()
	if resp.StatusCode >= 400 {
		return "", fmt.Errorf("Jina Reader returned status %d", resp.StatusCode)
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, int64(maxChars*4)))
	if err != nil {
		return "", err
	}
	return previewText(string(data), maxChars), nil
}

func validateReadableWebURL(rawURL string) (*url.URL, error) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return nil, err
	}
	if parsed.Scheme != "http" && parsed.Scheme != "https" {
		return nil, fmt.Errorf("only http(s) URLs can be read")
	}
	if strings.TrimSpace(parsed.Host) == "" {
		return nil, fmt.Errorf("url host is required")
	}
	return parsed, nil
}

func normalizeBraveResultCount(args aiWebSearchArgs) int {
	count := args.MaxResults
	if args.Count > 0 {
		count = args.Count
	}
	if count <= 0 {
		return 8
	}
	if count > 20 {
		return 20
	}
	return count
}

func normalizeBraveFreshness(value string) string {
	switch strings.TrimSpace(value) {
	case "pd", "pw", "pm", "py":
		return strings.TrimSpace(value)
	default:
		return ""
	}
}

func (s *AppService) aiWebHTTPClient(timeout time.Duration) *http.Client {
	transport := http.DefaultTransport.(*http.Transport).Clone()
	if s != nil && s.config != nil && strings.TrimSpace(s.config.AIWebProxyURL) != "" {
		if proxyURL, err := url.Parse(strings.TrimSpace(s.config.AIWebProxyURL)); err == nil {
			transport.Proxy = http.ProxyURL(proxyURL)
		}
	}
	return &http.Client{
		Timeout:   timeout,
		Transport: transport,
	}
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
