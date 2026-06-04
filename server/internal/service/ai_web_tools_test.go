package service

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/model"
	"github.com/ank/flashcard-server/internal/repository"
	"go.uber.org/zap"
)

func TestSearchWebToolUsesBraveAPIAndCache(t *testing.T) {
	requestCount := 0
	brave := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestCount++
		if got := r.Header.Get("X-Subscription-Token"); got != "brave-test-key" {
			t.Fatalf("expected Brave token header, got %q", got)
		}
		if got := r.Header.Get("Accept"); got != "application/json" {
			t.Fatalf("expected json accept header, got %q", got)
		}
		query := r.URL.Query()
		if query.Get("q") != "408 cache AMAT 易错点" {
			t.Fatalf("unexpected query: %s", r.URL.RawQuery)
		}
		if query.Get("count") != "3" || query.Get("country") != "CN" || query.Get("search_lang") != "zh" || query.Get("result_filter") != "web" {
			t.Fatalf("unexpected Brave params: %s", r.URL.RawQuery)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"web": map[string]any{
				"results": []map[string]string{
					{
						"title":       "Cache AMAT 易错点",
						"url":         "https://example.com/cache-amat",
						"description": "平均访存时间常见混淆点。",
					},
				},
			},
		})
	}))
	defer brave.Close()

	service := NewAppService(config.Config{
		JWTSecret:      "test-secret",
		BraveAPIKey:    "brave-test-key",
		BraveSearchURL: brave.URL,
	}, repository.NewMemoryStore(), zap.NewNop())
	registry := newAICardGenerationToolRegistry(model.AIGenerateRequest{AllowWebSearch: true})
	call := openAIToolCall{Function: openAIToolFunction{
		Name:      "search_web",
		Arguments: `{"query":"408 cache AMAT 易错点","max_results":3}`,
	}}

	first, err := registry.Execute(call, aiAgentToolContext{GenerateRequest: model.AIGenerateRequest{AllowWebSearch: true}, Service: service})
	if err != nil {
		t.Fatalf("execute first search: %v", err)
	}
	if !strings.Contains(first.Content, "Cache AMAT 易错点") || !strings.Contains(first.Content, "https://example.com/cache-amat") {
		t.Fatalf("expected Brave result content, got %s", first.Content)
	}

	second, err := registry.Execute(call, aiAgentToolContext{GenerateRequest: model.AIGenerateRequest{AllowWebSearch: true}, Service: service})
	if err != nil {
		t.Fatalf("execute cached search: %v", err)
	}
	if second.Content != first.Content {
		t.Fatalf("expected cached content to match first content")
	}
	if requestCount != 1 {
		t.Fatalf("expected Brave API to be called once due to cache, got %d", requestCount)
	}
}

func TestReadWebPageToolUsesJinaReader(t *testing.T) {
	jina := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if got := r.Header.Get("Authorization"); got != "Bearer jina-test-key" {
			t.Fatalf("expected Jina auth header, got %q", got)
		}
		if !strings.Contains(r.URL.Path, "https://example.com/cache-amat") {
			t.Fatalf("expected encoded target URL in path, got %q", r.URL.Path)
		}
		_, _ = w.Write([]byte("# Cache AMAT\n\n平均访存时间 = 命中时间 + 缺失率 x 缺失代价。"))
	}))
	defer jina.Close()

	service := NewAppService(config.Config{
		JWTSecret:     "test-secret",
		JinaAPIKey:    "jina-test-key",
		JinaReaderURL: jina.URL,
	}, repository.NewMemoryStore(), zap.NewNop())
	registry := newAICardGenerationToolRegistry(model.AIGenerateRequest{AllowWebSearch: true})
	result, err := registry.Execute(openAIToolCall{Function: openAIToolFunction{
		Name:      "read_web_page",
		Arguments: `{"url":"https://example.com/cache-amat"}`,
	}}, aiAgentToolContext{GenerateRequest: model.AIGenerateRequest{AllowWebSearch: true}, Service: service})
	if err != nil {
		t.Fatalf("execute read_web_page: %v", err)
	}
	if !strings.Contains(result.Content, "Cache AMAT") || !strings.Contains(result.Content, "缺失代价") {
		t.Fatalf("expected Jina markdown in tool result, got %s", result.Content)
	}
}

func TestWebSearchToolUsesConfiguredProxy(t *testing.T) {
	proxyHits := 0
	proxy := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		proxyHits++
		if !strings.Contains(r.URL.String(), "brave.example.test/search") {
			t.Fatalf("expected proxied Brave URL, got %q", r.URL.String())
		}
		if got := r.Header.Get("X-Subscription-Token"); got != "brave-test-key" {
			t.Fatalf("expected Brave token through proxy, got %q", got)
		}
		_ = json.NewEncoder(w).Encode(map[string]any{
			"web": map[string]any{
				"results": []map[string]string{
					{
						"title":       "Proxy Brave Result",
						"url":         "https://example.com/proxy",
						"description": "The search was served through a configured proxy.",
					},
				},
			},
		})
	}))
	defer proxy.Close()

	service := NewAppService(config.Config{
		JWTSecret:      "test-secret",
		BraveAPIKey:    "brave-test-key",
		BraveSearchURL: "http://brave.example.test/search",
		AIWebProxyURL:  proxy.URL,
	}, repository.NewMemoryStore(), zap.NewNop())
	registry := newAICardGenerationToolRegistry(model.AIGenerateRequest{AllowWebSearch: true})
	result, err := registry.Execute(openAIToolCall{Function: openAIToolFunction{
		Name:      "search_web",
		Arguments: `{"query":"proxy smoke","max_results":1}`,
	}}, aiAgentToolContext{GenerateRequest: model.AIGenerateRequest{AllowWebSearch: true}, Service: service})
	if err != nil {
		t.Fatalf("execute proxied search: %v", err)
	}
	if !strings.Contains(result.Content, "Proxy Brave Result") {
		t.Fatalf("expected proxied Brave result, got %s", result.Content)
	}
	if proxyHits != 1 {
		t.Fatalf("expected proxy to be used once, got %d", proxyHits)
	}
}
