package handler

import (
	"net/http"
	"net/http/httptest"
	"regexp"
	"strings"
	"testing"

	"go.uber.org/zap"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/repository"
	"github.com/ank/flashcard-server/internal/service"
)

func TestRouterServesEmbeddedWebConsole(t *testing.T) {
	services := service.NewAppService(
		config.Config{JWTSecret: "test-secret"},
		repository.NewMemoryStore(),
		zap.NewNop(),
	)
	router := NewRouter(config.Config{Port: "8080"}, services, zap.NewNop())

	response := httptest.NewRecorder()
	request := httptest.NewRequest(http.MethodGet, "/", nil)
	router.ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected web console status 200, got %d", response.Code)
	}
	if !strings.Contains(response.Body.String(), "Ank Web Console") {
		t.Fatalf("expected embedded web console html, got %q", response.Body.String())
	}
}

func TestRouterServesEmbeddedWebConsoleAssets(t *testing.T) {
	services := service.NewAppService(
		config.Config{JWTSecret: "test-secret"},
		repository.NewMemoryStore(),
		zap.NewNop(),
	)
	router := NewRouter(config.Config{Port: "8080"}, services, zap.NewNop())

	index := httptest.NewRecorder()
	router.ServeHTTP(index, httptest.NewRequest(http.MethodGet, "/", nil))
	if index.Code != http.StatusOK {
		t.Fatalf("expected web console status 200, got %d", index.Code)
	}

	matches := regexp.MustCompile(`/(assets/[^"']+)`).FindAllStringSubmatch(index.Body.String(), -1)
	if len(matches) == 0 {
		t.Fatalf("expected index to reference bundled assets, got %q", index.Body.String())
	}
	for _, match := range matches {
		response := httptest.NewRecorder()
		router.ServeHTTP(response, httptest.NewRequest(http.MethodGet, "/"+match[1], nil))
		if response.Code != http.StatusOK {
			t.Fatalf("expected embedded asset %s status 200, got %d", match[1], response.Code)
		}
	}
}
