package service

import (
	"encoding/json"
	"strings"
	"testing"

	"github.com/ank/flashcard-server/internal/model"
)

func TestAIAgentRuntimeUsesRegistryForNewToolsWithoutRuntimeChanges(t *testing.T) {
	registry := newAIAgentToolRegistry()
	if err := registry.Register(aiAgentTool{
		Name: "create_true_false_card",
		Spec: aiCardGenerationTool(
			"create_true_false_card",
			"Create a true/false flashcard.",
			[]string{"title", "statement", "is_true"},
		),
		Execute: func(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
			var args struct {
				Title     string `json:"title"`
				Statement string `json:"statement"`
				IsTrue    bool   `json:"is_true"`
			}
			if err := json.Unmarshal(arguments, &args); err != nil {
				return aiAgentToolResult{}, err
			}
			answer := "错误"
			if args.IsTrue {
				answer = "正确"
			}
			card := model.AIGeneratedCard{
				Title:    args.Title,
				Content:  composeCardContent(args.Statement, answer),
				CardType: "true_false",
				Tags:     []string{"测试工具"},
			}
			return aiAgentToolResult{
				Content: toolResultJSON(map[string]any{"ok": true, "title": args.Title}),
				Cards:   []model.AIGeneratedCard{card},
			}, nil
		},
	}); err != nil {
		t.Fatalf("register extension tool: %v", err)
	}

	callCount := 0
	runtime := newAIAgentRuntime(aiAgentRuntimeConfig{
		Model:       "test-model",
		MaxTurns:    2,
		Temperature: 0.1,
		ToolChoice:  "auto",
		Tools:       registry,
		Planner: aiAgentPlannerFunc(func(input aiAgentRunInput) []openAIChatMessage {
			return []openAIChatMessage{
				{Role: "system", Content: "custom planner"},
				{Role: "user", Content: input.UserPrompt},
			}
		}),
		Chat: func(request openAIChatRequest) (openAIChatResponse, error) {
			callCount++
			if request.Messages[0].Content != "custom planner" {
				t.Fatalf("expected runtime to use custom planner, got %+v", request.Messages)
			}
			if callCount == 1 {
				if len(request.Tools) != 1 || request.Tools[0].Function.Name != "create_true_false_card" {
					t.Fatalf("expected runtime to expose registered tool, got %+v", request.Tools)
				}
				return openAIChatResponse{Choices: []struct {
					Message openAIChatMessage `json:"message"`
				}{{
					Message: openAIChatMessage{
						Role: "assistant",
						ToolCalls: []openAIToolCall{{
							ID:   "call-true-false",
							Type: "function",
							Function: openAIToolFunction{
								Name:      "create_true_false_card",
								Arguments: `{"title":"教育目的判断","statement":"教育目的规定人才培养方向。","is_true":true}`,
							},
						}},
					},
				}}}, nil
			}
			if len(request.Messages) < 4 || request.Messages[len(request.Messages)-1].Role != "tool" {
				t.Fatalf("expected second request to include tool result message, got %+v", request.Messages)
			}
			return openAIChatResponse{Choices: []struct {
				Message openAIChatMessage `json:"message"`
			}{{
				Message: openAIChatMessage{Role: "assistant", Content: `{"items":[]}`},
			}}}, nil
		},
		Evaluator: aiCardGenerationEvaluator{},
	})

	result, err := runtime.Run(aiAgentRunInput{
		SystemPrompt: "system",
		UserPrompt:   "user",
		Context: aiAgentToolContext{
			GenerateRequest: model.AIGenerateRequest{Topic: "教育学原理"},
		},
	})
	if err != nil {
		t.Fatalf("run agent runtime: %v", err)
	}
	if callCount != 2 {
		t.Fatalf("expected two model turns, got %d", callCount)
	}
	if len(result.Cards) != 1 || result.Cards[0].CardType != "true_false" {
		t.Fatalf("expected extension tool card, got %+v", result.Cards)
	}
	if len(result.Steps) < 3 {
		t.Fatalf("expected assistant, tool, and final assistant trace steps, got %+v", result.Steps)
	}
	if !strings.Contains(result.Steps[1].Summary, "create_true_false_card") {
		t.Fatalf("expected tool trace summary, got %+v", result.Steps)
	}
}

func TestAIAgentToolRegistryRejectsDuplicateAndUnknownTools(t *testing.T) {
	registry := newAIAgentToolRegistry()
	tool := aiAgentTool{
		Name: "noop",
		Spec: aiCardGenerationTool("noop", "No-op tool.", []string{}),
		Execute: func(ctx aiAgentToolContext, arguments json.RawMessage) (aiAgentToolResult, error) {
			return aiAgentToolResult{Content: `{"ok":true}`}, nil
		},
	}
	if err := registry.Register(tool); err != nil {
		t.Fatalf("register noop: %v", err)
	}
	if err := registry.Register(tool); err == nil {
		t.Fatal("expected duplicate tool registration to fail")
	}
	_, err := registry.Execute(openAIToolCall{
		ID: "missing",
		Function: openAIToolFunction{
			Name:      "missing_tool",
			Arguments: `{}`,
		},
	}, aiAgentToolContext{})
	if err == nil {
		t.Fatal("expected unknown tool execution to fail")
	}
}
