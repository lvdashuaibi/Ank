package service

import (
	"encoding/json"
	"errors"
	"math"
	"net/http"
	"net/http/httptest"
	"sort"
	"strings"
	"testing"
	"time"
	"unicode/utf8"

	"go.uber.org/zap"

	"github.com/ank/flashcard-server/internal/config"
	"github.com/ank/flashcard-server/internal/model"
	"github.com/ank/flashcard-server/internal/pkg/fsrs"
	"github.com/ank/flashcard-server/internal/repository"
)

func newTestAppService(t *testing.T) *AppService {
	t.Helper()
	return NewAppService(config.Config{JWTSecret: "test-secret"}, repository.NewMemoryStore(), zap.NewNop())
}

func registerTestUser(t *testing.T, service *AppService, email string) model.User {
	t.Helper()
	user, _, err := service.Register(email, "Password123", "tester")
	if err != nil {
		t.Fatalf("register user: %v", err)
	}
	return user
}

func firstDeckID(t *testing.T, service *AppService, userID string) string {
	t.Helper()
	decks := service.ListDecks(userID)
	if len(decks) == 0 {
		t.Fatalf("expected at least one deck for user %s", userID)
	}
	return decks[0].ID
}

func TestCreateCardIsIdempotentByClientID(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "idempotent@example.com")
	deckID := firstDeckID(t, service, user.ID)

	card1, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "client-1",
		Title:    "Question",
		Content:  "Prompt",
	})
	if err != nil {
		t.Fatalf("first create card: %v", err)
	}

	card2, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "client-1",
		Title:    "Question changed",
		Content:  "Prompt changed",
	})
	if err != nil {
		t.Fatalf("second create card: %v", err)
	}

	if card1.ID != card2.ID {
		t.Fatalf("expected same card id for repeated client_id, got %s and %s", card1.ID, card2.ID)
	}

	cards := service.ListCards(user.ID, deckID)
	if len(cards) != 1 {
		t.Fatalf("expected one card after idempotent create, got %d", len(cards))
	}
}

func TestCreateCardRequiresOwnedDeck(t *testing.T) {
	service := newTestAppService(t)
	user1 := registerTestUser(t, service, "owner@example.com")
	user2 := registerTestUser(t, service, "other@example.com")
	deckID := firstDeckID(t, service, user1.ID)

	_, err := service.CreateCard(user2.ID, deckID, model.Card{
		ClientID: "client-2",
		Title:    "Question",
		Content:  "Prompt",
	})
	if !errors.Is(err, repository.ErrNotFound) {
		t.Fatalf("expected ErrNotFound when creating card in foreign deck, got %v", err)
	}
}

func TestCreateCardBuildsLegacyFrontBackFromContent(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "content-create@example.com")
	deckID := firstDeckID(t, service, user.ID)

	card, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "content-create-client",
		Title:    " 题目 ",
		Content:  "正面内容\n\n@answer\n反面内容\n@end",
	})
	if err != nil {
		t.Fatalf("create card with content: %v", err)
	}

	if card.Title != "题目" {
		t.Fatalf("expected trimmed title, got %q", card.Title)
	}
	if card.Content != "正面内容\n\n@answer\n反面内容\n@end" {
		t.Fatalf("expected content to be preserved, got %q", card.Content)
	}
	if card.Front != "正面内容" {
		t.Fatalf("expected front to be derived from content, got %q", card.Front)
	}
	if card.Back != "反面内容" {
		t.Fatalf("expected back to be derived from content, got %q", card.Back)
	}
}

func TestUpdateCardBuildsLegacyFrontBackFromContent(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "content-update@example.com")
	deckID := firstDeckID(t, service, user.ID)

	created, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "content-update-client",
		Title:    "旧题目",
		Content:  "旧正面",
	})
	if err != nil {
		t.Fatalf("create seed card: %v", err)
	}

	updated, err := service.UpdateCard(user.ID, created.ID, model.Card{
		ClientID: created.ClientID,
		Title:    "新题目",
		Content:  "新的正面\n\n@answer\n新的反面\n@end",
	})
	if err != nil {
		t.Fatalf("update card with content: %v", err)
	}

	if updated.Title != "新题目" {
		t.Fatalf("expected updated title, got %q", updated.Title)
	}
	if updated.Front != "新的正面" {
		t.Fatalf("expected updated front from content, got %q", updated.Front)
	}
	if updated.Back != "新的反面" {
		t.Fatalf("expected updated back from content, got %q", updated.Back)
	}
}

func TestSyncPushReturnsPerOperationResults(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "sync@example.com")
	deckID := firstDeckID(t, service, user.ID)

	response := service.SyncPush(user.ID, model.SyncPushRequest{
		Operations: []model.SyncOperation{
			{
				ID:   "op-success",
				Type: "create_card",
				Payload: map[string]interface{}{
					"deck_id":   deckID,
					"client_id": "sync-client-1",
					"title":     "Question",
					"content":   "Prompt",
				},
			},
			{
				ID:      "op-fail",
				Type:    "create_card",
				Payload: map[string]interface{}{},
			},
		},
	})

	if response.AppliedCount != 1 {
		t.Fatalf("expected AppliedCount to be 1, got %d", response.AppliedCount)
	}
	if response.FailedCount != 1 {
		t.Fatalf("expected FailedCount to be 1, got %d", response.FailedCount)
	}
	if len(response.Results) != 2 {
		t.Fatalf("expected 2 sync results, got %d", len(response.Results))
	}
	if response.Results[0].OperationID != "op-success" || !response.Results[0].Applied {
		t.Fatalf("expected first result to mark op-success applied, got %+v", response.Results[0])
	}
	if response.Results[1].OperationID != "op-fail" || response.Results[1].Applied {
		t.Fatalf("expected second result to mark op-fail failed, got %+v", response.Results[1])
	}
	if response.Results[1].Error == "" {
		t.Fatalf("expected failed result to contain error")
	}
}

func TestSyncCreateCardPreservesProvidedState(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "sync-state@example.com")
	deckID := firstDeckID(t, service, user.ID)

	response := service.SyncPush(user.ID, model.SyncPushRequest{
		Operations: []model.SyncOperation{
			{
				ID:   "op-state",
				Type: "create_card",
				Payload: map[string]interface{}{
					"deck_id":   deckID,
					"client_id": "sync-state-client",
					"title":     "Question",
					"content":   "Prompt",
					"state": map[string]interface{}{
						"state":          2,
						"difficulty":     5.5,
						"stability":      12.0,
						"retrievability": 0.9,
						"due_date":       "2030-01-02T03:04:05Z",
						"last_review_at": "2030-01-01T03:04:05Z",
						"reps":           3,
						"lapses":         1,
						"elapsed_days":   2.0,
						"scheduled_days": 5.0,
					},
				},
			},
		},
	})

	if response.AppliedCount != 1 || response.FailedCount != 0 {
		t.Fatalf("expected stateful create to succeed, got %+v", response)
	}

	cards := service.ListCards(user.ID, deckID)
	if len(cards) != 1 {
		t.Fatalf("expected one card after sync create, got %d", len(cards))
	}
	if cards[0].State.State != 2 {
		t.Fatalf("expected synced state to be preserved, got %d", cards[0].State.State)
	}
	if cards[0].State.Reps != 3 {
		t.Fatalf("expected synced reps to be preserved, got %d", cards[0].State.Reps)
	}
	if cards[0].State.DueDate.IsZero() {
		t.Fatalf("expected synced due date to be preserved")
	}
}

func TestSyncPullSanitizesInvalidFSRSValues(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "sync-pull-sanitize@example.com")
	deckID := firstDeckID(t, service, user.ID)

	_, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "sanitize-client",
		Title:    "Question",
		Content:  "Prompt",
		State: model.FSRSState{
			State:          2,
			Difficulty:     math.NaN(),
			Stability:      math.Inf(1),
			Retrievability: math.NaN(),
			DueDate:        time.Time{},
			ElapsedDays:    math.NaN(),
			ScheduledDays:  math.Inf(-1),
		},
	})
	if err != nil {
		t.Fatalf("create invalid card: %v", err)
	}

	response := service.SyncPull(user.ID)
	if len(response.Cards) != 1 {
		t.Fatalf("expected one card in sync pull, got %d", len(response.Cards))
	}
	if _, err := json.Marshal(response); err != nil {
		t.Fatalf("expected sync pull response to be JSON serializable, got %v", err)
	}
	card := response.Cards[0]
	if math.IsNaN(card.State.Difficulty) || math.IsInf(card.State.Difficulty, 0) {
		t.Fatalf("difficulty should be sanitized, got %v", card.State.Difficulty)
	}
	if math.IsNaN(card.State.Stability) || math.IsInf(card.State.Stability, 0) {
		t.Fatalf("stability should be sanitized, got %v", card.State.Stability)
	}
}

func TestReviewDoesNotProduceNaNForOverdueCards(t *testing.T) {
	engine := fsrs.NewEngine()
	now := time.Now()
	state := model.FSRSState{
		State:        2,
		Difficulty:   5,
		Stability:    1,
		LastReviewAt: now.Add(-10 * 24 * time.Hour),
		DueDate:      now.Add(-9 * 24 * time.Hour),
	}

	next := engine.Review(state, fsrs.Good, now)
	if math.IsNaN(next.Stability) || math.IsInf(next.Stability, 0) {
		t.Fatalf("expected finite stability, got %v", next.Stability)
	}
	if math.IsNaN(next.Retrievability) || math.IsInf(next.Retrievability, 0) {
		t.Fatalf("expected finite retrievability, got %v", next.Retrievability)
	}
}

func TestDueCardsPrioritizesLearningAndAppliesDeckLimits(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "due-queue@example.com")
	defaultDeckID := firstDeckID(t, service, user.ID)

	deck, err := service.UpdateDeck(user.ID, defaultDeckID, model.Deck{
		Name:             "默认牌组",
		Description:      "queue test",
		Color:            "#4ECDC4",
		Icon:             "📚",
		NewCardsPerDay:   1,
		MaxReviewsPerDay: 2,
	})
	if err != nil {
		t.Fatalf("update deck limits: %v", err)
	}

	now := time.Now().UTC()
	mustCreate := func(id string, state model.FSRSState, createdAt time.Time) {
		card, err := service.CreateCard(user.ID, deck.ID, model.Card{
			ClientID:     id,
			Title:        id,
			Content:      id,
			StudyEnabled: true,
			State:        state,
		})
		if err != nil {
			t.Fatalf("create card %s: %v", id, err)
		}
		stored, err := service.store.GetCard(user.ID, card.ID)
		if err != nil {
			t.Fatalf("get stored card %s: %v", id, err)
		}
		stored.CreatedAt = createdAt
		if err := service.store.UpdateCard(stored); err != nil {
			t.Fatalf("update stored card %s: %v", id, err)
		}
	}

	mustCreate("learning", model.FSRSState{
		State:        1,
		DueDate:      now.Add(-2 * time.Minute),
		LastReviewAt: now.Add(-10 * time.Minute),
		Stability:    3,
		Difficulty:   5,
	}, now.Add(-6*time.Hour))
	mustCreate("review-2", model.FSRSState{
		State:        2,
		DueDate:      now.Add(-1 * time.Hour),
		LastReviewAt: now.Add(-24 * time.Hour),
		Stability:    5,
		Difficulty:   5,
	}, now.Add(-5*time.Hour))
	mustCreate("review-1", model.FSRSState{
		State:        2,
		DueDate:      now.Add(-2 * time.Hour),
		LastReviewAt: now.Add(-48 * time.Hour),
		Stability:    5,
		Difficulty:   5,
	}, now.Add(-4*time.Hour))
	mustCreate("review-3", model.FSRSState{
		State:        2,
		DueDate:      now.Add(-30 * time.Minute),
		LastReviewAt: now.Add(-72 * time.Hour),
		Stability:    5,
		Difficulty:   5,
	}, now.Add(-3*time.Hour))
	mustCreate("new-1", model.FSRSState{
		State:   0,
		DueDate: now.Add(-1 * time.Minute),
	}, now.Add(-48*time.Hour))
	mustCreate("new-2", model.FSRSState{
		State:   0,
		DueDate: now.Add(-1 * time.Minute),
	}, now.Add(-24*time.Hour))

	queue := service.DueCards(user.ID, deck.ID)
	if len(queue) != 4 {
		t.Fatalf("expected limited queue length 4, got %d", len(queue))
	}
	got := []string{queue[0].Title, queue[1].Title, queue[2].Title, queue[3].Title}
	want := []string{"learning", "review-1", "review-2", "new-1"}
	for i := range want {
		if got[i] != want[i] {
			t.Fatalf("unexpected queue order at %d: got %v want %v", i, got, want)
		}
	}
}

func TestSubmitReviewRejectsInvalidRating(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "invalid-rating@example.com")
	deckID := firstDeckID(t, service, user.ID)

	card, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "invalid-rating-card",
		Title:    "Question",
		Content:  "Prompt",
	})
	if err != nil {
		t.Fatalf("create card: %v", err)
	}

	if _, err := service.SubmitReview(user.ID, card.ID, 0, 0); !errors.Is(err, ErrInvalidReviewRating) {
		t.Fatalf("expected ErrInvalidReviewRating, got %v", err)
	}
}

func TestSyncPushSubmitReviewUsesOccurredAt(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "sync-review-time@example.com")
	deckID := firstDeckID(t, service, user.ID)

	card, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID: "sync-review-time-card",
		Title:    "Question",
		Content:  "Prompt",
	})
	if err != nil {
		t.Fatalf("create card: %v", err)
	}

	reviewedAt := time.Date(2026, 4, 23, 9, 30, 0, 0, time.UTC)
	response := service.SyncPush(user.ID, model.SyncPushRequest{
		Operations: []model.SyncOperation{
			{
				ID:         "review-op-1",
				Type:       "submit_review",
				OccurredAt: reviewedAt,
				Payload: map[string]interface{}{
					"card_id": card.ID,
					"rating":  int(fsrs.Good),
				},
			},
		},
	})

	if response.AppliedCount != 1 || response.FailedCount != 0 {
		t.Fatalf("expected sync review to succeed, got %+v", response)
	}

	updated, err := service.GetCard(user.ID, card.ID)
	if err != nil {
		t.Fatalf("get updated card: %v", err)
	}
	if !updated.State.LastReviewAt.Equal(reviewedAt) {
		t.Fatalf("expected last_review_at to use occurred_at, got %s want %s", updated.State.LastReviewAt, reviewedAt)
	}
	if !updated.UpdatedAt.Equal(reviewedAt) {
		t.Fatalf("expected updated_at to use occurred_at, got %s want %s", updated.UpdatedAt, reviewedAt)
	}
}

func TestDueCardsExcludeCardsNotInStudyList(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "study-toggle@example.com")
	deckID := firstDeckID(t, service, user.ID)

	if _, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID:     "study-off",
		Title:        "Not in review",
		Content:      "Prompt",
		StudyEnabled: false,
	}); err != nil {
		t.Fatalf("create non-study card: %v", err)
	}
	if _, err := service.CreateCard(user.ID, deckID, model.Card{
		ClientID:     "study-on",
		Title:        "In review",
		Content:      "Prompt",
		StudyEnabled: true,
	}); err != nil {
		t.Fatalf("create study card: %v", err)
	}

	queue := service.DueCards(user.ID, deckID)
	if len(queue) != 1 {
		t.Fatalf("expected exactly one due card in study list, got %d", len(queue))
	}
	if queue[0].ClientID != "study-on" {
		t.Fatalf("expected study-enabled card to remain, got %+v", queue[0])
	}
}

func TestDeckSpecificDueCardsRespectRandomReviewOrder(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "random-order@example.com")
	deckID := firstDeckID(t, service, user.ID)

	deck, err := service.GetDeck(user.ID, deckID)
	if err != nil {
		t.Fatalf("get deck: %v", err)
	}
	if _, err := service.UpdateDeck(user.ID, deck.ID, model.Deck{
		Name:             deck.Name,
		Description:      deck.Description,
		Color:            deck.Color,
		Icon:             deck.Icon,
		ReviewOrder:      ReviewOrderRandom,
		NewCardsPerDay:   deck.NewCardsPerDay,
		MaxReviewsPerDay: deck.MaxReviewsPerDay,
	}); err != nil {
		t.Fatalf("update deck order: %v", err)
	}

	for _, clientID := range []string{"card-a", "card-b", "card-c"} {
		if _, err := service.CreateCard(user.ID, deckID, model.Card{
			ClientID:     clientID,
			Title:        clientID,
			Content:      "Prompt",
			StudyEnabled: true,
		}); err != nil {
			t.Fatalf("create %s: %v", clientID, err)
		}
	}

	queue := service.DueCards(user.ID, deckID)
	if len(queue) != 3 {
		t.Fatalf("expected three due cards, got %d", len(queue))
	}

	got := []string{queue[0].ClientID, queue[1].ClientID, queue[2].ClientID}
	expected := append([]model.Card(nil), queue...)
	dayKey := reviewDayKey(time.Now())
	sort.Slice(expected, func(i, j int) bool {
		return stableReviewOrderValue(deckID, dayKey, "new", expected[i].ID) <
			stableReviewOrderValue(deckID, dayKey, "new", expected[j].ID)
	})
	want := []string{expected[0].ClientID, expected[1].ClientID, expected[2].ClientID}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("unexpected random order at %d: got %v want %v", index, got, want)
		}
	}
}

func TestDeleteFolderKeepsDecksAndClearsFolderID(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "folder-delete@example.com")

	folder, err := service.CreateFolder(user.ID, model.Folder{Name: "语言学习"})
	if err != nil {
		t.Fatalf("create folder: %v", err)
	}

	deck, err := service.CreateDeck(user.ID, model.Deck{
		Name:             "英语",
		Description:      "Deck in folder",
		Color:            "#4ECDC4",
		Icon:             "📚",
		FolderID:         folder.ID,
		ReviewOrder:      ReviewOrderSequential,
		NewCardsPerDay:   20,
		MaxReviewsPerDay: 200,
	})
	if err != nil {
		t.Fatalf("create deck in folder: %v", err)
	}

	if err := service.DeleteFolder(user.ID, folder.ID); err != nil {
		t.Fatalf("delete folder: %v", err)
	}

	updatedDeck, err := service.GetDeck(user.ID, deck.ID)
	if err != nil {
		t.Fatalf("get deck after folder delete: %v", err)
	}
	if updatedDeck.FolderID != "" {
		t.Fatalf("expected folder id to be cleared, got %q", updatedDeck.FolderID)
	}

	decks := service.ListDecks(user.ID)
	if len(decks) < 2 {
		t.Fatalf("expected default deck plus retained deck, got %d", len(decks))
	}
}

func TestGenerateCardsAppliesPolicyAndReportsQuality(t *testing.T) {
	service := newTestAppService(t)

	response := service.GenerateCards(model.AIGenerateRequest{
		Topic:      "教育学原理",
		Context:    "教育学研究教育现象、教育问题和教育规律。教育目的、教育制度和教师专业发展都需要拆成独立知识点。",
		CardCount:  3,
		Difficulty: "medium",
		Policy: &model.GenerationPolicy{
			Name:               "教育学精读",
			AtomicityLevel:     "strict",
			AnswerStyle:        "one_sentence",
			MaxAnswerChars:     24,
			PreferredCardTypes: []string{"basic", "cloze"},
			CoverageMode:       "balanced",
			SplitStrategy:      "by_heading",
			RepairMode:         "violations_only",
			CustomRules:        "避免宽泛论述题，优先拆成可自评的概念卡。",
		},
	})

	if response.Policy == nil {
		t.Fatalf("expected response to include effective policy snapshot")
	}
	if response.Policy.Name != "教育学精读" {
		t.Fatalf("expected custom policy name, got %q", response.Policy.Name)
	}
	if response.Policy.MaxAnswerChars != 24 {
		t.Fatalf("expected custom max answer chars, got %d", response.Policy.MaxAnswerChars)
	}
	if len(response.Items) == 0 {
		t.Fatalf("expected generated cards")
	}
	for _, item := range response.Items {
		if item.QualityReport == nil {
			t.Fatalf("expected quality report for card %q", item.Title)
		}
		if item.QualityReport.Score <= 0 {
			t.Fatalf("expected positive quality score for card %q, got %.2f", item.Title, item.QualityReport.Score)
		}
	}
}

func TestGenerateCardsRepairsFallbackOutputToPolicy(t *testing.T) {
	service := newTestAppService(t)

	response := service.GenerateCards(model.AIGenerateRequest{
		Topic:      "教育学原理",
		Context:    "教育目的规定人才培养方向；教学原则指导教学设计；反馈帮助学生修正学习；迁移强调知识在新情境中的应用。",
		CardCount:  6,
		Difficulty: "medium",
		Policy: &model.GenerationPolicy{
			AtomicityLevel: "strict",
			AnswerStyle:    "one_sentence",
			MaxAnswerChars: 36,
		},
	})

	if len(response.Items) != 6 {
		t.Fatalf("expected 6 cards, got %d", len(response.Items))
	}
	seenPrompts := map[string]struct{}{}
	for _, item := range response.Items {
		prompt, answer := splitCardContent(item.Content)
		if prompt == "" {
			t.Fatalf("expected prompt for card %+v", item)
		}
		key := strings.ToLower(strings.Join(strings.Fields(prompt), " "))
		if _, exists := seenPrompts[key]; exists {
			t.Fatalf("expected fallback generator to avoid duplicate prompt %q", prompt)
		}
		seenPrompts[key] = struct{}{}
		if got := utf8.RuneCountInString(strings.TrimSpace(answer)); got > 36 {
			t.Fatalf("expected answer <= 36 chars, got %d: %q", got, answer)
		}
		if item.QualityReport == nil {
			t.Fatalf("expected quality report for card %q", item.Title)
		}
		for _, violation := range item.QualityReport.Violations {
			if violation.Code == "answer_too_long" || violation.Code == "duplicate_prompt" {
				t.Fatalf("expected repair to avoid %s for card %q", violation.Code, item.Title)
			}
		}
	}
}

func TestGenerateCardsFallbackChoiceDistractorsStayDomainNeutral(t *testing.T) {
	service := newTestAppService(t)

	response := service.GenerateCards(model.AIGenerateRequest{
		Topic:      "408 计算机组成原理：Cache 与平均访存时间",
		Context:    "Cache 是位于 CPU 和主存之间的高速小容量存储器，用于利用程序访问的时间局部性和空间局部性。Cache 命中率表示访问能在 Cache 中找到所需数据的比例。平均访存时间 AMAT = 命中时间 + 缺失率 × 缺失代价，其中缺失率 = 1 - 命中率。提高命中率或降低缺失代价都可以改善存储系统性能。",
		CardCount:  4,
		Difficulty: "medium",
		Policy: &model.GenerationPolicy{
			PreferredCardTypes: []string{"single_choice", "multi_choice"},
		},
	})

	if len(response.Items) != 4 {
		t.Fatalf("expected 4 generated cards, got %d", len(response.Items))
	}
	joined := ""
	for _, item := range response.Items {
		joined += item.Content + "\n"
		if !strings.Contains(item.Content, "{single-choice}") && !strings.Contains(item.Content, "{multi-choice}") {
			t.Fatalf("expected choice DSL, got %q", item.Content)
		}
	}
	for _, forbidden := range []string{"学习反馈", "最终排名", "教育", "Anki", "默认牌组"} {
		if strings.Contains(joined, forbidden) {
			t.Fatalf("expected 408 fallback choices to avoid unrelated term %q, got:\n%s", forbidden, joined)
		}
	}
}

func TestGenerateCardsUsesLegacyCardTypesWhenPolicyDoesNotOverride(t *testing.T) {
	service := newTestAppService(t)

	response := service.GenerateCards(model.AIGenerateRequest{
		Topic:      "教育学原理",
		Context:    "教育制度是教育活动组织运行的制度体系。",
		CardCount:  2,
		Difficulty: "medium",
		CardTypes:  []string{"multi_choice"},
	})

	if len(response.Items) == 0 {
		t.Fatalf("expected generated cards")
	}
	for _, item := range response.Items {
		if item.CardType != "multi_choice" {
			t.Fatalf("expected legacy card_types to drive output, got %q", item.CardType)
		}
		if !strings.Contains(item.Content, "{multi-choice}") {
			t.Fatalf("expected multi choice cards to use interactive DSL, got %q", item.Content)
		}
		if !strings.Contains(item.Content, "* ") {
			t.Fatalf("expected multi choice DSL to mark correct options, got %q", item.Content)
		}
	}
}

func TestBuildAIPromptRequiresImplementedChoiceDSL(t *testing.T) {
	prompt := buildAIPrompt(model.AIGenerateRequest{
		Topic:     "教育学原理",
		Context:   "形成性评价强调及时反馈。",
		CardCount: 2,
		Policy: &model.GenerationPolicy{
			PreferredCardTypes: []string{"single_choice", "multi_choice"},
		},
	})

	for _, expected := range []string{
		"{single-choice}",
		"{multi-choice}",
		"* 正确选项",
		"- 干扰项",
		"不要把选择题写成 A/B/C/D 普通文本",
	} {
		if !strings.Contains(prompt, expected) {
			t.Fatalf("expected prompt to include %q, got:\n%s", expected, prompt)
		}
	}
}

func TestExternalAIAgentLoopExecutesCardGenerationTool(t *testing.T) {
	callCount := 0
	fakeAI := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		callCount++
		var requestBody map[string]any
		if err := json.NewDecoder(r.Body).Decode(&requestBody); err != nil {
			t.Fatalf("decode chat request: %v", err)
		}
		if callCount == 1 {
			if _, ok := requestBody["tools"].([]any); !ok {
				t.Fatalf("expected first request to include tools, got %+v", requestBody)
			}
			_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"","tool_calls":[{"id":"call-1","type":"function","function":{"name":"create_single_choice_card","arguments":"{\"title\":\"形成性评估\",\"question\":\"形成性评估的主要作用是什么？\",\"correct_answer\":\"支持及时反馈\",\"distractors\":[\"提供最终等级\",\"确定课程目标\",\"定义学习者发展\"],\"answer\":\"形成性评估主要用于支持及时反馈。\",\"source_excerpt\":\"形成性评估强调及时反馈。\"}"}}]}}]}`))
			return
		}
		messages, ok := requestBody["messages"].([]any)
		if !ok || len(messages) < 3 {
			t.Fatalf("expected follow-up request to include tool result messages, got %+v", requestBody)
		}
		_, _ = w.Write([]byte(`{"choices":[{"message":{"role":"assistant","content":"{\"items\":[]}"}}]}`))
	}))
	defer fakeAI.Close()

	service := NewAppService(config.Config{
		JWTSecret: "test-secret",
		AIBaseURL: fakeAI.URL,
		AIAPIKey:  "test-key",
		AIModel:   "deepseek-v4-pro",
	}, repository.NewMemoryStore(), zap.NewNop())

	items, err := service.tryGenerateCardsWithExternalAI(model.AIGenerateRequest{
		Topic:     "教育学原理",
		Context:   "形成性评估强调及时反馈。",
		CardCount: 1,
	})
	if err != nil {
		t.Fatalf("generate with fake tool-calling AI: %v", err)
	}
	if callCount != 2 {
		t.Fatalf("expected agent loop to make two chat calls, got %d", callCount)
	}
	if len(items) != 1 {
		t.Fatalf("expected one tool-generated card, got %d", len(items))
	}
	if items[0].CardType != "single_choice" {
		t.Fatalf("expected single choice card, got %q", items[0].CardType)
	}
	if !strings.Contains(items[0].Content, "{single-choice}") || !strings.Contains(items[0].Content, "* 支持及时反馈") {
		t.Fatalf("expected implemented choice DSL, got %q", items[0].Content)
	}
}

func TestGenerateCardsFromMarkdownDocumentIncludesImageSummary(t *testing.T) {
	service := newTestAppService(t)
	doc, err := extractDocumentText("education.md", "text/markdown", []byte(strings.Join([]string{
		"# 教育目的",
		"",
		"教育目的规定人才培养方向。",
		"",
		"![教育目的结构图](images/aims.png)",
	}, "\n")))
	if err != nil {
		t.Fatalf("extract markdown: %v", err)
	}

	response := service.GenerateCardsFromDocument(model.AIGenerateRequest{
		Topic:      "教育学原理",
		CardCount:  2,
		Difficulty: "medium",
		Policy: &model.GenerationPolicy{
			AtomicityLevel:   "strict",
			AnswerStyle:      "one_sentence",
			MaxAnswerChars:   60,
			SplitStrategy:    "by_heading",
			MaxCardsPerChunk: 2,
			MaxCardsTotal:    2,
		},
	}, doc)

	if response.Document == nil {
		t.Fatal("expected document summary")
	}
	if response.Document.ImageCount != 1 {
		t.Fatalf("expected one image, got %+v", response.Document)
	}
	if len(response.Document.Images) != 1 || response.Document.Images[0].Source != "images/aims.png" {
		t.Fatalf("unexpected image summary: %+v", response.Document.Images)
	}
	if !strings.Contains(response.Document.TextPreview, "图片") {
		t.Fatalf("expected image placeholder in preview, got %q", response.Document.TextPreview)
	}
	if len(response.Items) == 0 {
		t.Fatal("expected generated cards")
	}
}

func TestGenerationPolicyServiceCRUD(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "policy@example.com")

	created, err := service.CreateGenerationPolicy(user.ID, model.GenerationPolicy{
		Name:               "教育学模板",
		AtomicityLevel:     "strict",
		MaxAnswerChars:     36,
		PreferredCardTypes: []string{"basic"},
	})
	if err != nil {
		t.Fatalf("create policy: %v", err)
	}
	if created.ID == "" || created.UserID != user.ID {
		t.Fatalf("expected created policy to include id and owner, got %+v", created)
	}

	updated, err := service.UpdateGenerationPolicy(user.ID, created.ID, model.GenerationPolicy{
		Name:               "教育学考试模板",
		AtomicityLevel:     "strict",
		MaxAnswerChars:     28,
		PreferredCardTypes: []string{"basic", "cloze"},
	})
	if err != nil {
		t.Fatalf("update policy: %v", err)
	}
	if updated.Name != "教育学考试模板" || updated.MaxAnswerChars != 28 {
		t.Fatalf("unexpected updated policy: %+v", updated)
	}
	items := service.ListGenerationPolicies(user.ID)
	if len(items) != 1 {
		t.Fatalf("expected one policy, got %d", len(items))
	}
	if err := service.DeleteGenerationPolicy(user.ID, created.ID); err != nil {
		t.Fatalf("delete policy: %v", err)
	}
	if len(service.ListGenerationPolicies(user.ID)) != 0 {
		t.Fatalf("expected deleted policy to be absent")
	}
}

func TestDocumentChunkerUsesMarkdownHeadings(t *testing.T) {
	policy := defaultGenerationPolicy()
	doc := extractedDocument{
		Title: "education.md",
		Text: strings.Join([]string{
			"# 第一章 教育与教育学",
			"",
			"教育是培养人的社会活动。教育学研究教育现象、教育问题和教育规律。",
			"",
			"## 教育的本质",
			"",
			"教育具有目的性、社会性和历史性，需要单独拆成可复习知识点。",
			"",
			"## 教育制度",
			"",
			"教育制度包括学校教育制度、管理制度和评价制度。",
		}, "\n"),
	}

	chunks := chunkDocument(doc, policy)
	if len(chunks) < 3 {
		t.Fatalf("expected heading-based chunks, got %d", len(chunks))
	}
	if chunks[0].HeadingPath != "第一章 教育与教育学" {
		t.Fatalf("unexpected first heading path: %q", chunks[0].HeadingPath)
	}
	if chunks[1].HeadingPath != "第一章 教育与教育学 / 教育的本质" {
		t.Fatalf("unexpected nested heading path: %q", chunks[1].HeadingPath)
	}
	if chunks[1].SourceLocation != "第一章 教育与教育学 / 教育的本质" {
		t.Fatalf("expected heading path as source location, got %q", chunks[1].SourceLocation)
	}
}

func TestRewriteSplitReturnsMultipleAtomicCandidates(t *testing.T) {
	service := newTestAppService(t)

	response := service.RewriteCardWithAI(model.AIRewriteCardRequest{
		Title:       "教育目的和教育制度",
		Content:     composeCardContent("教育目的和教育制度分别是什么？", "教育目的是教育活动预期培养人的质量规格；教育制度是规范教育活动组织运行的制度体系。"),
		RewriteType: "split",
		Instruction: "拆成两张原子卡，每张只考一个概念。",
	})

	if len(response.Candidates) < 2 {
		t.Fatalf("expected split rewrite to return multiple candidates, got %d", len(response.Candidates))
	}
	for _, candidate := range response.Candidates {
		if candidate.Title == "" || candidate.Content == "" {
			t.Fatalf("expected complete candidate, got %+v", candidate)
		}
	}
}

func TestNormalizeRewriteCandidateConvertsQuestionDsl(t *testing.T) {
	candidate := model.AIRewriteCandidate{
		Title: "教育原则中的教育目标",
		Content: strings.Join([]string{
			"@question",
			"在教育原则中，“教育目标”的含义是什么？",
			"@end",
			"教育目标指导学习者的发展。",
		}, "\n"),
	}

	normalized := normalizeRewriteCandidate(candidate)
	prompt, answer := splitCardContent(normalized.Content)

	if strings.Contains(prompt, "@question") || strings.Contains(prompt, "@end") {
		t.Fatalf("expected question DSL markers to be removed, got %q", prompt)
	}
	if prompt != "在教育原则中，“教育目标”的含义是什么？" {
		t.Fatalf("unexpected prompt: %q", prompt)
	}
	if answer != "教育目标指导学习者的发展。" {
		t.Fatalf("unexpected answer: %q", answer)
	}
}

func TestRewriteCardsWithAIBatchPreservesCardOrder(t *testing.T) {
	service := newTestAppService(t)

	response := service.RewriteCardsWithAI(model.AIRewriteBatchRequest{
		RewriteType: "simplify_answer",
		Instruction: "答案压缩成一句话",
		Policy:      &model.GenerationPolicy{Name: "批量整理", MaxAnswerChars: 20},
		Cards: []model.AIRewriteCardRequest{
			{
				CardID:  "card-1",
				Title:   "教育目的",
				Content: composeCardContent("教育目的是什么？", "教育目的是教育活动预期培养人的质量规格，体现社会要求和个体发展需要。"),
			},
			{
				CardID:  "card-2",
				Title:   "教育制度",
				Content: composeCardContent("教育制度是什么？", "教育制度是规范教育活动组织运行的制度体系。"),
			},
		},
	})

	if len(response.Results) != 2 {
		t.Fatalf("expected two batch rewrite results, got %d", len(response.Results))
	}
	if response.Results[0].CardID != "card-1" || len(response.Results[0].Candidates) == 0 {
		t.Fatalf("unexpected first batch result: %+v", response.Results[0])
	}
	if response.Results[1].CardID != "card-2" || len(response.Results[1].Candidates) == 0 {
		t.Fatalf("unexpected second batch result: %+v", response.Results[1])
	}
}

func TestChatCardsWithAIGeneratesDraftsFromConversation(t *testing.T) {
	service := newTestAppService(t)

	response := service.ChatCardsWithAI(model.AICardChatRequest{
		Topic:       "教育学原理",
		Instruction: "帮我做 3 张形成性评价的考试型卡片，选择题多一点。",
		CardCount:   3,
		Difficulty:  "medium",
		Messages: []model.AICardChatMessage{
			{Role: "user", Content: "希望答案短一点，适合背诵。"},
		},
		Policy: &model.GenerationPolicy{
			PreferredCardTypes: []string{"single_choice", "basic"},
			MaxAnswerChars:     60,
		},
	})

	if len(response.Items) != 3 {
		t.Fatalf("expected 3 generated chat drafts, got %d", len(response.Items))
	}
	if response.AssistantMessage == "" {
		t.Fatal("expected assistant message")
	}
	if !strings.Contains(response.Items[0].Content, "{single-choice}") {
		t.Fatalf("expected chat generation to preserve requested card type DSL, got %q", response.Items[0].Content)
	}
}

func TestChatCardsWithAIRefinesReferencedCardOnly(t *testing.T) {
	service := newTestAppService(t)
	items := []model.AIGeneratedCard{
		{
			Title:    "教育目的",
			Content:  composeCardContent("教育目的是什么？", "规定人才培养方向。"),
			CardType: "basic",
			Tags:     []string{"AI生成"},
		},
		{
			Title:    "教育制度",
			Content:  composeCardContent("教育制度是什么？", "教育活动组织运行的制度体系。"),
			CardType: "basic",
			Tags:     []string{"AI生成"},
		},
	}

	response := service.ChatCardsWithAI(model.AICardChatRequest{
		Topic:       "教育学原理",
		Instruction: "把答案改得更口语，但不要改题干。",
		Items:       items,
		Reference: &model.AICardReference{
			CardIndex: 1,
			Part:      "answer",
		},
	})

	if response.UpdatedIndex == nil || *response.UpdatedIndex != 1 {
		t.Fatalf("expected updated index 1, got %+v", response.UpdatedIndex)
	}
	if len(response.Items) != 2 {
		t.Fatalf("expected two cards after refinement, got %d", len(response.Items))
	}
	if response.Items[0].Content != items[0].Content {
		t.Fatalf("expected unreferenced card to remain unchanged")
	}
	if response.Items[1].Content == items[1].Content {
		t.Fatalf("expected referenced card to be refined")
	}
}

func TestGenerateCardsChoosesCardCountWhenUnspecified(t *testing.T) {
	service := newTestAppService(t)

	response := service.GenerateCards(model.AIGenerateRequest{
		Topic:      "教育学原理",
		Context:    "教育目的规定人才培养方向。教育制度规范教育活动运行。课程目标连接教学内容与评价。形成性评价支持及时反馈。德育过程强调知情意行统一。",
		CardCount:  0,
		Difficulty: "medium",
		Policy: &model.GenerationPolicy{
			MaxCardsTotal:      12,
			MaxCardsPerChunk:   6,
			PreferredCardTypes: []string{"basic"},
		},
	})

	if got := len(response.Items); got < 5 {
		t.Fatalf("expected unspecified count to follow source granularity, got %d", got)
	}
}

func TestChatCardsWithAISplitsSelectedCard(t *testing.T) {
	service := newTestAppService(t)
	items := []model.AIGeneratedCard{
		{
			Title:    "教育目的与教育制度",
			Content:  composeCardContent("教育目的和教育制度分别是什么？", "教育目的规定人才培养方向；教育制度规范教育活动运行；课程目标连接教学内容与评价。"),
			CardType: "basic",
			Tags:     []string{"AI生成"},
		},
	}

	response := service.ChatCardsWithAI(model.AICardChatRequest{
		Topic:           "教育学原理",
		Instruction:     "拆成更小的原子卡",
		Operation:       "split",
		Items:           items,
		SelectedIndexes: []int{0},
	})

	if len(response.Items) < 2 {
		t.Fatalf("expected split to create multiple cards, got %+v", response.Items)
	}
	if response.UpdatedIndex == nil || *response.UpdatedIndex != 0 {
		t.Fatalf("expected split to report first selected index, got %+v", response.UpdatedIndex)
	}
}

func TestChatCardsWithAIMergesSelectedCards(t *testing.T) {
	service := newTestAppService(t)
	items := []model.AIGeneratedCard{
		{
			Title:    "教育目的",
			Content:  composeCardContent("教育目的是什么？", "规定人才培养方向。"),
			CardType: "basic",
			Tags:     []string{"AI生成"},
		},
		{
			Title:    "教育制度",
			Content:  composeCardContent("教育制度是什么？", "规范教育活动运行。"),
			CardType: "basic",
			Tags:     []string{"AI生成"},
		},
	}

	response := service.ChatCardsWithAI(model.AICardChatRequest{
		Topic:           "教育学原理",
		Instruction:     "合并成一张对比卡",
		Operation:       "merge",
		Items:           items,
		SelectedIndexes: []int{0, 1},
	})

	if len(response.Items) != 1 {
		t.Fatalf("expected merge to replace selected cards with one card, got %d", len(response.Items))
	}
	if !strings.Contains(response.Items[0].Content, "教育目的") || !strings.Contains(response.Items[0].Content, "教育制度") {
		t.Fatalf("expected merged content to mention both cards, got %q", response.Items[0].Content)
	}
}

func TestCreateAIGenerationJobPersistsSucceededResult(t *testing.T) {
	service := newTestAppService(t)
	user := registerTestUser(t, service, "ai-job@example.com")

	job, err := service.CreateAIGenerationJob(user.ID, model.AIGenerateRequest{
		Topic:      "教育学原理",
		Context:    "教育目的规定教育活动要培养什么样的人。",
		CardCount:  2,
		Difficulty: "medium",
	})
	if err != nil {
		t.Fatalf("create generation job: %v", err)
	}
	if job.ID == "" || job.Status != "running" || job.Progress <= 0 {
		t.Fatalf("unexpected job state: %+v", job)
	}

	persisted := waitForAIGenerationJob(t, service, user.ID, job.ID)
	if persisted.Status != "succeeded" || persisted.Progress != 1 {
		t.Fatalf("expected completed job, got %+v", persisted)
	}
	if persisted.Result == nil || len(persisted.Result.Items) == 0 {
		t.Fatalf("expected persisted result, got %+v", persisted)
	}
	if jobs := service.ListAIGenerationJobs(user.ID); len(jobs) == 0 || jobs[0].ID != job.ID {
		t.Fatalf("expected job to be recoverable from list, got %+v", jobs)
	}
}

func waitForAIGenerationJob(t *testing.T, service *AppService, userID, jobID string) model.AIGenerationJob {
	t.Helper()
	deadline := time.After(2 * time.Second)
	ticker := time.NewTicker(10 * time.Millisecond)
	defer ticker.Stop()
	for {
		select {
		case <-deadline:
			job, _ := service.GetAIGenerationJob(userID, jobID)
			t.Fatalf("generation job did not complete: %+v", job)
		case <-ticker.C:
			job, err := service.GetAIGenerationJob(userID, jobID)
			if err != nil {
				t.Fatalf("get generation job: %v", err)
			}
			if job.Status == "succeeded" || job.Status == "failed" {
				return job
			}
		}
	}
}
