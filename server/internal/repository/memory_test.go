package repository

import (
	"testing"
	"time"

	"github.com/ank/flashcard-server/internal/model"
)

func TestMemoryStoreDeleteCardRemovesReviewLogs(t *testing.T) {
	store := NewMemoryStore()
	cardID := "card-1"

	if err := store.CreateCard(model.Card{
		ID:        cardID,
		UserID:    "user-1",
		DeckID:    "deck-1",
		CreatedAt: time.Now(),
		UpdatedAt: time.Now(),
	}); err != nil {
		t.Fatalf("create card: %v", err)
	}
	if err := store.AppendReviewLog(model.ReviewLog{ID: "log-1", CardID: cardID, UserID: "user-1"}); err != nil {
		t.Fatalf("append review log: %v", err)
	}

	if err := store.DeleteCard("user-1", cardID); err != nil {
		t.Fatalf("delete card: %v", err)
	}

	if len(store.reviewLogs) != 0 {
		t.Fatalf("expected review logs to be removed with card delete, got %d", len(store.reviewLogs))
	}
}

func TestMemoryStoreDeleteDeckRemovesCardsAndReviewLogs(t *testing.T) {
	store := NewMemoryStore()
	now := time.Now()

	if err := store.CreateDeck(model.Deck{
		ID:        "deck-1",
		UserID:    "user-1",
		Name:      "Deck",
		CreatedAt: now,
		UpdatedAt: now,
	}); err != nil {
		t.Fatalf("create deck: %v", err)
	}
	if err := store.CreateCard(model.Card{
		ID:        "card-1",
		UserID:    "user-1",
		DeckID:    "deck-1",
		CreatedAt: now,
		UpdatedAt: now,
	}); err != nil {
		t.Fatalf("create card: %v", err)
	}
	if err := store.AppendReviewLog(model.ReviewLog{ID: "log-1", CardID: "card-1", UserID: "user-1"}); err != nil {
		t.Fatalf("append review log: %v", err)
	}

	if err := store.DeleteDeck("user-1", "deck-1"); err != nil {
		t.Fatalf("delete deck: %v", err)
	}

	if len(store.cards) != 0 {
		t.Fatalf("expected cards to be removed with deck delete, got %d", len(store.cards))
	}
	if len(store.reviewLogs) != 0 {
		t.Fatalf("expected review logs to be removed with deck delete, got %d", len(store.reviewLogs))
	}
}
