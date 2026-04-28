package service

import (
	"encoding/json"
	"errors"
	"math"
	"testing"
	"time"

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
			ClientID: id,
			Title:    id,
			Content:  id,
			State:    state,
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
