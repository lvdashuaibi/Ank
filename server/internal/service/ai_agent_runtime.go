package service

import (
	"encoding/json"
	"fmt"
	"strings"

	"github.com/ank/flashcard-server/internal/model"
)

type aiAgentToolContext struct {
	GenerateRequest model.AIGenerateRequest
	Service         *AppService
}

type aiAgentToolResult struct {
	Content string
	Cards   []model.AIGeneratedCard
}

type aiAgentTool struct {
	Name    string
	Spec    openAIChatTool
	Execute func(aiAgentToolContext, json.RawMessage) (aiAgentToolResult, error)
}

type aiAgentToolRegistry struct {
	tools map[string]aiAgentTool
	order []string
}

func newAIAgentToolRegistry() *aiAgentToolRegistry {
	return &aiAgentToolRegistry{tools: map[string]aiAgentTool{}, order: []string{}}
}

func (r *aiAgentToolRegistry) Register(tool aiAgentTool) error {
	name := strings.TrimSpace(tool.Name)
	if name == "" {
		return fmt.Errorf("agent tool name is required")
	}
	if tool.Execute == nil {
		return fmt.Errorf("agent tool %s is missing executor", name)
	}
	if _, exists := r.tools[name]; exists {
		return fmt.Errorf("agent tool %s already registered", name)
	}
	if strings.TrimSpace(tool.Spec.Function.Name) == "" {
		tool.Spec.Function.Name = name
	}
	r.tools[name] = tool
	r.order = append(r.order, name)
	return nil
}

func (r *aiAgentToolRegistry) Specs() []openAIChatTool {
	specs := make([]openAIChatTool, 0, len(r.order))
	for _, name := range r.order {
		specs = append(specs, r.tools[name].Spec)
	}
	return specs
}

func (r *aiAgentToolRegistry) Execute(call openAIToolCall, ctx aiAgentToolContext) (aiAgentToolResult, error) {
	name := strings.TrimSpace(call.Function.Name)
	tool, ok := r.tools[name]
	if !ok {
		return aiAgentToolResult{}, fmt.Errorf("unknown agent tool %s", name)
	}
	return tool.Execute(ctx, json.RawMessage(call.Function.Arguments))
}

type aiAgentRuntimeConfig struct {
	Model       string
	MaxTurns    int
	Temperature float64
	ToolChoice  string
	Tools       *aiAgentToolRegistry
	Planner     aiAgentPlanner
	Chat        func(openAIChatRequest) (openAIChatResponse, error)
	Evaluator   aiAgentEvaluator
}

type aiAgentRuntime struct {
	config aiAgentRuntimeConfig
}

func newAIAgentRuntime(config aiAgentRuntimeConfig) *aiAgentRuntime {
	if config.MaxTurns <= 0 {
		config.MaxTurns = 4
	}
	if config.ToolChoice == "" {
		config.ToolChoice = "auto"
	}
	if config.Planner == nil {
		config.Planner = staticAIAgentPlanner{}
	}
	if config.Evaluator == nil {
		config.Evaluator = aiCardGenerationEvaluator{}
	}
	return &aiAgentRuntime{config: config}
}

type aiAgentRunInput struct {
	SystemPrompt string
	UserPrompt   string
	Context      aiAgentToolContext
}

type aiAgentPlanner interface {
	Plan(aiAgentRunInput) []openAIChatMessage
}

type aiAgentPlannerFunc func(aiAgentRunInput) []openAIChatMessage

func (f aiAgentPlannerFunc) Plan(input aiAgentRunInput) []openAIChatMessage {
	return f(input)
}

type staticAIAgentPlanner struct{}

func (staticAIAgentPlanner) Plan(input aiAgentRunInput) []openAIChatMessage {
	return []openAIChatMessage{
		{Role: "system", Content: input.SystemPrompt},
		{Role: "user", Content: input.UserPrompt},
	}
}

type aiAgentRunResult struct {
	Messages     []openAIChatMessage
	Steps        []aiAgentTraceStep
	Cards        []model.AIGeneratedCard
	FinalContent string
}

type aiAgentTraceStep struct {
	Turn       int
	Kind       string
	ToolName   string
	ToolCallID string
	Status     string
	Summary    string
}

type aiAgentEvaluator interface {
	Evaluate(message openAIChatMessage, accumulatedCards []model.AIGeneratedCard) (aiAgentEvaluation, error)
}

type aiAgentEvaluation struct {
	Cards        []model.AIGeneratedCard
	FinalContent string
}

func (r *aiAgentRuntime) Run(input aiAgentRunInput) (aiAgentRunResult, error) {
	if r.config.Chat == nil {
		return aiAgentRunResult{}, fmt.Errorf("agent runtime chat client is required")
	}
	messages := r.config.Planner.Plan(input)
	if len(messages) == 0 {
		return aiAgentRunResult{}, fmt.Errorf("agent planner returned no messages")
	}
	steps := make([]aiAgentTraceStep, 0)
	accumulatedCards := make([]model.AIGeneratedCard, 0)
	tools := []openAIChatTool(nil)
	if r.config.Tools != nil {
		tools = r.config.Tools.Specs()
	}

	for turn := 1; turn <= r.config.MaxTurns; turn++ {
		response, err := r.config.Chat(openAIChatRequest{
			Model:       r.config.Model,
			Messages:    messages,
			Temperature: r.config.Temperature,
			Tools:       tools,
			ToolChoice:  r.config.ToolChoice,
		})
		if err != nil {
			return aiAgentRunResult{}, err
		}
		if len(response.Choices) == 0 {
			return aiAgentRunResult{}, fmt.Errorf("agent model returned no choices")
		}

		message := response.Choices[0].Message
		messages = append(messages, message)
		steps = append(steps, aiAgentTraceStep{
			Turn:    turn,
			Kind:    "assistant",
			Status:  "ok",
			Summary: summarizeAgentMessage(message),
		})

		if len(message.ToolCalls) > 0 {
			if r.config.Tools == nil {
				return aiAgentRunResult{}, fmt.Errorf("agent requested tools but no registry is configured")
			}
			for _, call := range message.ToolCalls {
				result, err := r.config.Tools.Execute(call, input.Context)
				status := "ok"
				content := result.Content
				if err != nil {
					status = "error"
					content = toolResultJSON(map[string]any{"ok": false, "error": err.Error()})
				}
				if strings.TrimSpace(content) == "" {
					content = toolResultJSON(map[string]any{"ok": status == "ok"})
				}
				accumulatedCards = append(accumulatedCards, result.Cards...)
				messages = append(messages, openAIChatMessage{
					Role:       "tool",
					ToolCallID: firstNonEmpty(call.ID, call.Function.Name),
					Content:    content,
				})
				steps = append(steps, aiAgentTraceStep{
					Turn:       turn,
					Kind:       "tool",
					ToolName:   call.Function.Name,
					ToolCallID: firstNonEmpty(call.ID, call.Function.Name),
					Status:     status,
					Summary:    fmt.Sprintf("%s returned %d card(s)", call.Function.Name, len(result.Cards)),
				})
			}
			continue
		}

		evaluation, err := r.config.Evaluator.Evaluate(message, accumulatedCards)
		if err != nil {
			return aiAgentRunResult{}, err
		}
		return aiAgentRunResult{
			Messages:     messages,
			Steps:        steps,
			Cards:        evaluation.Cards,
			FinalContent: evaluation.FinalContent,
		}, nil
	}

	if len(accumulatedCards) > 0 {
		return aiAgentRunResult{
			Messages: messages,
			Steps:    steps,
			Cards:    accumulatedCards,
		}, nil
	}
	return aiAgentRunResult{}, fmt.Errorf("agent reached max turns without producing cards")
}

type aiCardGenerationEvaluator struct{}

func (aiCardGenerationEvaluator) Evaluate(message openAIChatMessage, accumulatedCards []model.AIGeneratedCard) (aiAgentEvaluation, error) {
	content := stripJSONFence(message.Content)
	var generated model.AIGenerateResponse
	if err := json.Unmarshal([]byte(content), &generated); err == nil && len(generated.Items) > 0 {
		return aiAgentEvaluation{
			Cards:        normalizeGeneratedCards(generated.Items),
			FinalContent: content,
		}, nil
	}
	if len(accumulatedCards) > 0 {
		return aiAgentEvaluation{
			Cards:        normalizeGeneratedCards(accumulatedCards),
			FinalContent: content,
		}, nil
	}
	return aiAgentEvaluation{}, fmt.Errorf("agent returned no usable cards")
}

func summarizeAgentMessage(message openAIChatMessage) string {
	if len(message.ToolCalls) > 0 {
		names := make([]string, 0, len(message.ToolCalls))
		for _, call := range message.ToolCalls {
			names = append(names, call.Function.Name)
		}
		return "requested tools: " + strings.Join(names, ", ")
	}
	return previewText(message.Content, 120)
}
