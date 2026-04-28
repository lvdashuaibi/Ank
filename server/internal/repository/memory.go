package repository

import (
	"errors"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"

	"github.com/ank/flashcard-server/internal/model"
)

var ErrNotFound = errors.New("not found")

type MemoryStore struct {
	mu         sync.RWMutex
	users      map[string]model.User
	decks      map[string]model.Deck
	cards      map[string]model.Card
	reviewLogs []model.ReviewLog
}

func NewMemoryStore() *MemoryStore {
	return &MemoryStore{
		users:      make(map[string]model.User),
		decks:      make(map[string]model.Deck),
		cards:      make(map[string]model.Card),
		reviewLogs: make([]model.ReviewLog, 0),
	}
}

func (s *MemoryStore) CreateUser(user model.User) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.users[user.ID] = user
	return nil
}

func (s *MemoryStore) FindUserByEmail(email string) (model.User, bool) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, user := range s.users {
		if user.Email == email {
			return user, true
		}
	}
	return model.User{}, false
}

func (s *MemoryStore) GetUser(id string) (model.User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	user, ok := s.users[id]
	if !ok {
		return model.User{}, ErrNotFound
	}
	return user, nil
}

func (s *MemoryStore) ListDecks(userID string) []model.Deck {
	s.mu.RLock()
	defer s.mu.RUnlock()
	decks := make([]model.Deck, 0)
	for _, deck := range s.decks {
		if deck.UserID == userID {
			decks = append(decks, deck)
		}
	}
	sort.Slice(decks, func(i, j int) bool {
		return decks[i].CreatedAt.Before(decks[j].CreatedAt)
	})
	return decks
}

func (s *MemoryStore) CreateDeck(deck model.Deck) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.decks[deck.ID] = deck
	return nil
}

func (s *MemoryStore) GetDeck(userID, deckID string) (model.Deck, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	deck, ok := s.decks[deckID]
	if !ok || deck.UserID != userID {
		return model.Deck{}, ErrNotFound
	}
	return deck, nil
}

func (s *MemoryStore) UpdateDeck(deck model.Deck) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.decks[deck.ID] = deck
	return nil
}

func (s *MemoryStore) DeleteDeck(userID, deckID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	deck, ok := s.decks[deckID]
	if !ok || deck.UserID != userID {
		return ErrNotFound
	}
	deletedCardIDs := make(map[string]struct{})
	delete(s.decks, deckID)
	for id, card := range s.cards {
		if card.DeckID == deckID {
			delete(s.cards, id)
			deletedCardIDs[id] = struct{}{}
		}
	}
	s.reviewLogs = filterReviewLogs(s.reviewLogs, func(log model.ReviewLog) bool {
		_, exists := deletedCardIDs[log.CardID]
		return !exists
	})
	return nil
}

func (s *MemoryStore) ListCards(userID, deckID string) []model.Card {
	s.mu.RLock()
	defer s.mu.RUnlock()
	cards := make([]model.Card, 0)
	for _, card := range s.cards {
		if card.UserID == userID && card.DeckID == deckID {
			cards = append(cards, card)
		}
	}
	sort.Slice(cards, func(i, j int) bool {
		return cards[i].CreatedAt.Before(cards[j].CreatedAt)
	})
	return cards
}

func (s *MemoryStore) GetCard(userID, cardID string) (model.Card, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	card, ok := s.cards[cardID]
	if !ok || card.UserID != userID {
		return model.Card{}, ErrNotFound
	}
	return card, nil
}

func (s *MemoryStore) GetCardByClientID(userID, clientID string) (model.Card, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	for _, card := range s.cards {
		if card.UserID == userID && card.ClientID == clientID {
			return card, nil
		}
	}
	return model.Card{}, ErrNotFound
}

func (s *MemoryStore) CreateCard(card model.Card) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cards[card.ID] = card
	return nil
}

func (s *MemoryStore) UpdateCard(card model.Card) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.cards[card.ID] = card
	return nil
}

func (s *MemoryStore) DeleteCard(userID, cardID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	card, ok := s.cards[cardID]
	if !ok || card.UserID != userID {
		return ErrNotFound
	}
	delete(s.cards, cardID)
	s.reviewLogs = filterReviewLogs(s.reviewLogs, func(log model.ReviewLog) bool {
		return log.CardID != cardID
	})
	return nil
}

func (s *MemoryStore) ListDueCards(userID string, deckID string, now time.Time) []model.Card {
	s.mu.RLock()
	defer s.mu.RUnlock()
	cards := make([]model.Card, 0)
	for _, card := range s.cards {
		if card.UserID != userID {
			continue
		}
		if deckID != "" && card.DeckID != deckID {
			continue
		}
		if !card.State.DueDate.After(now) {
			cards = append(cards, card)
		}
	}
	sort.Slice(cards, func(i, j int) bool {
		return cards[i].State.DueDate.Before(cards[j].State.DueDate)
	})
	return cards
}

func (s *MemoryStore) AppendReviewLog(log model.ReviewLog) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.reviewLogs = append(s.reviewLogs, log)
	return nil
}

func (s *MemoryStore) Close() error {
	return nil
}

func NewID() string {
	return uuid.NewString()
}

func filterReviewLogs(
	items []model.ReviewLog,
	keep func(model.ReviewLog) bool,
) []model.ReviewLog {
	if len(items) == 0 {
		return items
	}
	filtered := make([]model.ReviewLog, 0, len(items))
	for _, item := range items {
		if keep(item) {
			filtered = append(filtered, item)
		}
	}
	return filtered
}
